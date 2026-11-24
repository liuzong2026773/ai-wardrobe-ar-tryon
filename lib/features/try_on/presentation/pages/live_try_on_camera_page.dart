import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/image_storage_utils.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';
import '../../data/neon_stream_try_on_stub.dart';
import '../../domain/pose_landmarks_model.dart';
import '../../domain/try_on_engine_interface.dart';

final neonStreamTryOnEngineProvider =
    Provider.autoDispose<NeonStreamTryOnEngine>((ref) {
  final engine = NeonStreamTryOnEngine(smoothingAlpha: 0.35);
  ref.onDispose(() => engine.dispose());
  return engine;
});

class LiveTryOnCameraPage extends ConsumerStatefulWidget {
  final List<ClothingItem> initialItems;

  const LiveTryOnCameraPage({
    super.key,
    this.initialItems = const [],
  });

  @override
  ConsumerState<LiveTryOnCameraPage> createState() =>
      _LiveTryOnCameraPageState();
}

class _LiveTryOnCameraPageState extends ConsumerState<LiveTryOnCameraPage>
    with WidgetsBindingObserver {
  final GlobalKey _captureKey = GlobalKey();
  final List<ClothingItem> _selectedGarments = [];

  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;

  bool _isInitializing = true;
  bool _isProcessing = false; // 帧丢弃并发锁，防止积压保证 24~30 FPS 流畅度
  bool _isSavingSnapshot = false;
  bool _showSkeleton = false;
  String? _errorMessage;

  PoseLandmarks? _currentLandmarks;
  double _currentFps = 0.0;
  DateTime _lastFrameTime = DateTime.now();

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedGarments.addAll(widget.initialItems);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _startSelectedCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '未检测到可用摄像头';
        });
        return;
      }

      // 默认优先开启前置摄像头，提供试衣镜镜像体验
      final frontIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = frontIdx >= 0 ? frontIdx : 0;
      await _startSelectedCamera();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '摄像头初始化失败：$e\n请在系统设置中授予相机权限。';
        });
      }
    }
  }

  Future<void> _startSelectedCamera() async {
    if (_cameras.isEmpty) return;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    await _stopCamera();

    final camera = _cameras[_cameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.medium, // 平衡清晰度与 24~30 FPS 实时骨骼推理速度
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      ref.read(neonStreamTryOnEngineProvider).resetSmoothing();
      await controller.startImageStream(_onCameraImage);
      setState(() => _isInitializing = false);
    } catch (e) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '启动实时视频流失败：$e';
        });
      }
    }
  }

  Future<void> _stopCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      await controller.dispose();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _currentLandmarks = null);
    await _startSelectedCamera();
  }

  /// 实时帧回调：使用 _isProcessing 并发锁自动丢弃来不及处理的帧
  Future<void> _onCameraImage(CameraImage image) async {
    if (_isProcessing || !mounted) return;
    _isProcessing = true;

    try {
      final camera = _cameras[_cameraIndex];
      final rotationDeg = _computeRotationDegrees(camera);
      final converted = _extractFrameBytes(image);
      if (converted == null) return;

      final engine = ref.read(neonStreamTryOnEngineProvider);
      final landmarks = await engine.detectPose(
        TryOnFrame(
          bytes: converted.$1,
          width: image.width,
          height: image.height,
          isVideoStreamFrame: true,
          rotationDegrees: rotationDeg,
          bytesPerRow: converted.$2,
          pixelFormat: Platform.isAndroid ? 'nv21' : 'bgra8888',
          isFrontCamera: camera.lensDirection == CameraLensDirection.front,
        ),
      );

      final now = DateTime.now();
      final dtMs = now.difference(_lastFrameTime).inMilliseconds;
      _lastFrameTime = now;
      final instantFps = dtMs > 0 ? (1000.0 / dtMs).clamp(1.0, 60.0) : 30.0;

      if (mounted) {
        setState(() {
          _currentLandmarks = landmarks;
          _currentFps = _currentFps == 0
              ? instantFps
              : (_currentFps * 0.8 + instantFps * 0.2);
        });
      }
    } catch (_) {
      // 单帧推理异常直接丢弃，不影响后续实时流
    } finally {
      _isProcessing = false;
    }
  }

  int _computeRotationDegrees(CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) return sensorOrientation;

    final deviceDeg =
        _orientations[_controller?.value.deviceOrientation] ?? 0;
    if (camera.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceDeg) % 360;
    }
    return (sensorOrientation - deviceDeg + 360) % 360;
  }

  /// 兼容 Android NV21 单平面、YUV420 三平面转 NV21 及 iOS BGRA8888
  (Uint8List, int)? _extractFrameBytes(CameraImage image) {
    if (image.planes.isEmpty) return null;

    if (Platform.isIOS) {
      return (image.planes.first.bytes, image.planes.first.bytesPerRow);
    }

    // Android 若 CameraX 直接返回 NV21 单平面
    if (image.planes.length == 1) {
      return (image.planes.first.bytes, image.planes.first.bytesPerRow);
    }

    // Android 若返回 3 平面 YUV420_888，则安全组装为标准 NV21
    if (image.planes.length == 3) {
      final width = image.width;
      final height = image.height;
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final nv21 = Uint8List(width * height + (width * height) ~/ 2);
      int dstIdx = 0;

      for (int row = 0; row < height; row++) {
        final rowStart = row * yPlane.bytesPerRow;
        nv21.setRange(dstIdx, dstIdx + width, yPlane.bytes, rowStart);
        dstIdx += width;
      }

      final uvHeight = height ~/ 2;
      final uvWidth = width ~/ 2;
      final uPixelStride = uPlane.bytesPerPixel ?? 1;
      final vPixelStride = vPlane.bytesPerPixel ?? 1;

      for (int row = 0; row < uvHeight; row++) {
        final uRowStart = row * uPlane.bytesPerRow;
        final vRowStart = row * vPlane.bytesPerRow;
        for (int col = 0; col < uvWidth; col++) {
          final vIdx = vRowStart + col * vPixelStride;
          final uIdx = uRowStart + col * uPixelStride;
          if (dstIdx + 1 < nv21.length &&
              vIdx < vPlane.bytes.length &&
              uIdx < uPlane.bytes.length) {
            nv21[dstIdx++] = vPlane.bytes[vIdx];
            nv21[dstIdx++] = uPlane.bytes[uIdx];
          }
        }
      }
      return (nv21, width);
    }
    return null;
  }

  /// 一键截取当前实时试穿画面并保存至本地沙盒
  Future<void> _captureAndSaveSnapshot() async {
    if (_isSavingSnapshot) return;
    setState(() => _isSavingSnapshot = true);
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final savedPath = await ImageStorageUtils.saveImageBytes(
        pngBytes,
        subDir: 'try_on_snapshots',
        extension: 'png',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('试穿效果已保存至本地：$savedPath'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截图保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSnapshot = false);
    }
  }

  int _layerOrder(String category) {
    return switch (category) {
      'bottom' => 1,
      'dress' => 2,
      'top' => 3,
      'outerwear' => 4,
      _ => 5,
    };
  }

  void _toggleGarment(ClothingItem item) {
    setState(() {
      final existsIdx = _selectedGarments.indexWhere((e) => e.id == item.id);
      if (existsIdx >= 0) {
        _selectedGarments.removeAt(existsIdx);
      } else {
        // 同品类自动替换，方便一键试穿切换
        _selectedGarments.removeWhere((e) => e.category == item.category);
        _selectedGarments.add(item);
      }
    });
  }

  File _resolveGarmentFile(ClothingItem item) {
    final alphaPath =
        item.cutoutImgPath.replaceAll('cutout_white', 'cutout_alpha');
    final alphaFile = File(alphaPath);
    if (alphaFile.existsSync()) return alphaFile;
    return File(item.cutoutImgPath);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wardrobeAsync = ref.watch(filteredWardrobeItemsProvider);
    final engine = ref.watch(neonStreamTryOnEngineProvider);
    final bool isFront = _cameras.isNotEmpty &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

    final orderedGarments = List<ClothingItem>.from(_selectedGarments)
      ..sort((a, b) => _layerOrder(a.category).compareTo(_layerOrder(b.category)));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 主体实时试衣镜区域
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    key: _captureKey,
                    child: _buildCameraAndOverlay(
                      engine: engine,
                      isFront: isFront,
                      orderedGarments: orderedGarments,
                    ),
                  ),

                  // 顶部悬浮控制栏
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _currentLandmarks != null
                                    ? Icons.accessibility_new_rounded
                                    : Icons.search_rounded,
                                color: _currentLandmarks != null
                                    ? Colors.greenAccent
                                    : Colors.amberAccent,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _currentLandmarks != null
                                    ? 'AR追踪中 · ${_currentFps.round()} FPS'
                                    : '请站在镜头前露出上半身/全身',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        _CircleIconBtn(
                          icon: _showSkeleton
                              ? Icons.scatter_plot_rounded
                              : Icons.scatter_plot_outlined,
                          tooltip: '显示/隐藏骨骼点',
                          onTap: () =>
                              setState(() => _showSkeleton = !_showSkeleton),
                        ),
                        const SizedBox(width: 8),
                        if (_cameras.length > 1)
                          _CircleIconBtn(
                            icon: Icons.cameraswitch_rounded,
                            tooltip: '切换前后摄像头',
                            onTap: _switchCamera,
                          ),
                      ],
                    ),
                  ),

                  // 右下角一键截图按钮
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      heroTag: 'ar_snapshot_btn',
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.textPrimary,
                      onPressed:
                          _isSavingSnapshot ? null : _captureAndSaveSnapshot,
                      icon: _isSavingSnapshot
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_rounded, size: 20),
                      label: const Text(
                        '截图保存',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 底部横向衣橱快捷切换栏
            Container(
              color: AppTheme.cardWhite,
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Text(
                          'AR 实时换装 (${_selectedGarments.length} 件)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (_selectedGarments.isNotEmpty)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _selectedGarments.clear()),
                            child: const Text(
                              '清空',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 86,
                    child: wardrobeAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('加载失败: $e')),
                      data: (items) {
                        if (items.isEmpty) {
                          return const Center(
                            child: Text(
                              '衣橱暂无单品，请先在「衣橱」页入库衣物',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, idx) {
                            final item = items[idx];
                            final selected = _selectedGarments
                                .any((e) => e.id == item.id);
                            return GestureDetector(
                              onTap: () => _toggleGarment(item),
                              child: Container(
                                width: 72,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? AppTheme.accentCharcoal
                                        : AppTheme.dividerColor,
                                    width: selected ? 2.2 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Image.file(
                                        File(item.cutoutImgPath),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraAndOverlay({
    required NeonStreamTryOnEngine engine,
    required bool isFront,
    required List<ClothingItem> orderedGarments,
  }) {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('正在启动实时试衣镜...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_errorMessage != null || _controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage ?? '摄像头不可用',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final landmarks = _currentLandmarks;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 前置摄像头镜像预览
              Transform.flip(
                flipX: isFront,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.previewSize?.height ??
                        previewSize.width,
                    height: _controller!.value.previewSize?.width ??
                        previewSize.height,
                    child: CameraPreview(_controller!),
                  ),
                ),
              ),

              // 实时衣物仿射/透视变形叠加层
              if (landmarks != null)
                ...orderedGarments.map((item) {
                  final transform = engine.computeOverlayTransform(
                    category: item.category,
                    landmarks: landmarks,
                    previewSize: previewSize,
                    mirrorX: isFront,
                  );
                  return Positioned(
                    left: transform.center.dx - transform.width / 2,
                    top: transform.center.dy - transform.height / 2,
                    width: transform.width,
                    height: transform.height,
                    child: IgnorePointer(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: transform.matrix,
                        child: Image.file(
                          _resolveGarmentFile(item),
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  );
                }),

              // 可选骨骼关键点调试层（肩/肘/胯/膝）
              if (_showSkeleton && landmarks != null)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _PoseSkeletonPainter(
                      landmarks: landmarks,
                      mirrorX: isFront,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CircleIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _PoseSkeletonPainter extends CustomPainter {
  final PoseLandmarks landmarks;
  final bool mirrorX;

  _PoseSkeletonPainter({
    required this.landmarks,
    required this.mirrorX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / (landmarks.imageWidth > 0 ? landmarks.imageWidth : 1);
    final sy =
        size.height / (landmarks.imageHeight > 0 ? landmarks.imageHeight : 1);

    Offset toCanvas(BodyPoint p) {
      final x = p.x * sx;
      final y = p.y * sy;
      return Offset(mirrorX ? (size.width - x) : x, y);
    }

    final linePaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final ls = toCanvas(landmarks.leftShoulder);
    final rs = toCanvas(landmarks.rightShoulder);
    final le = toCanvas(landmarks.leftElbow);
    final re = toCanvas(landmarks.rightElbow);
    final lh = toCanvas(landmarks.leftHip);
    final rh = toCanvas(landmarks.rightHip);
    final lk = toCanvas(landmarks.leftKnee);
    final rk = toCanvas(landmarks.rightKnee);

    canvas.drawLine(ls, rs, linePaint);
    canvas.drawLine(ls, le, linePaint);
    canvas.drawLine(rs, re, linePaint);
    canvas.drawLine(ls, lh, linePaint);
    canvas.drawLine(rs, rh, linePaint);
    canvas.drawLine(lh, rh, linePaint);
    canvas.drawLine(lh, lk, linePaint);
    canvas.drawLine(rh, rk, linePaint);

    for (final pt in [ls, rs, le, re, lh, rh, lk, rk]) {
      canvas.drawCircle(pt, 4.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PoseSkeletonPainter oldDelegate) =>
      oldDelegate.landmarks != landmarks || oldDelegate.mirrorX != mirrorX;
}
