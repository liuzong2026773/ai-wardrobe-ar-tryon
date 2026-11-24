import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path_provider/path_provider.dart';
import '../data/app_database.dart';
import '../services/pose_service.dart';
import '../widgets/garment_overlay_painter.dart';

/// 核心:实时试衣镜
/// 前置镜像预览 + startImageStream + 并发帧丢弃锁(同一时间只处理一帧,保证 24-30 FPS)
/// + Pose 33 点 + EMA 平滑 + 躯干四边形贴合 + 底部横向换衣 + 一键拍照保存
class TryonMirrorScreen extends StatefulWidget {
  final AppDatabase db;
  const TryonMirrorScreen({super.key, required this.db});
  @override State<TryonMirrorScreen> createState() => _TryonMirrorScreenState();
}

class _TryonMirrorScreenState extends State<TryonMirrorScreen> {
  CameraController? _controller;
  final _pose = PoseService();
  bool _processing = false; // 帧丢弃锁
  List<Offset> _quad = [];
  List<ClothingItem> _tops = [];
  int _selected = 0;
  ui.Image? _garmentImage;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cams = await availableCameras();
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first);
    _controller = CameraController(front, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
    await _controller!.initialize();
    _tops = (await widget.db.allItems)
        .where((i) => i.category == '上装' || i.category == '连衣裙' || i.category == '外套').toList();
    if (_tops.isNotEmpty) await _loadGarment(0);
    await _controller!.startImageStream(_onFrame);
    if (mounted) setState(() => _ready = true);
  }

  void _onFrame(CameraImage image) {
    if (_processing) return; // 丢弃并发帧,保证流畅
    _processing = true;
    _pose.process(image, 0).then((lm) {
      if (lm != null && PoseService.isTorsoValid(lm) && mounted) {
        setState(() => _quad = PoseService.torsoQuad(lm));
      }
    }).whenComplete(() => _processing = false);
  }

  Future<void> _loadGarment(int i) async {
    _selected = i;
    final bytes = await File(_tops[i].imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _garmentImage = frame.image);
  }

  Future<void> _snapshot() async {
    if (_controller == null) return;
    final shot = await _controller!.takePicture();
    final dir = await getApplicationDocumentsDirectory();
    final out = File('${dir.path}/tryon_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(shot.path).copy(out.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存: ${out.path}')));
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('实时试衣镜')),
      body: Stack(children: [
        // 镜像预览:前置摄像头左右翻转
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(3.14159265),
          child: CameraPreview(_controller!),
        ),
        // 衣物贴合层
        Positioned.fill(
          child: CustomPaint(painter: GarmentOverlayPainter(
              garment: _garmentImage, quad: _quad, mirror: true)),
        ),
        Positioned(left: 16, top: 16, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: const Text('正面站立,双臂自然下垂效果最佳', style: TextStyle(color: Colors.white, fontSize: 12)),
        )),
      ]),
      bottomNavigationBar: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 92, child: ListView.builder(
            scrollDirection: Axis.horizontal, itemCount: _tops.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _loadGarment(i),
              child: Container(
                width: 76, margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: i == _selected ? Colors.pink : Colors.grey.shade300, width: 2)),
                child: Image.file(File(_tops[i].imagePath), fit: BoxFit.contain),
              ),
            ),
          )),
          Padding(padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(onPressed: _snapshot,
              icon: const Icon(Icons.camera_alt), label: const Text('拍照保存'))),
        ]),
      ),
    );
  }
}
