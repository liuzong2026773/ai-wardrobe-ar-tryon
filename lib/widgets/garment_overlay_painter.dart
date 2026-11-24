import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 把白底衣物图按躯干四边形做仿射/透视变形后画在视频帧上。
/// 说明:Flutter Canvas 没有逐像素透视 warp,这里用“四边形包围盒 + 旋转/缩放仿射”
/// 近似贴合(正面/轻微侧身效果好),大角度侧身会有拉伸——端侧零付费方案的合理上限。
/// 更精细的网格变形需在原生层/OpenGL 做,见 README 的后续升级建议。
class GarmentOverlayPainter extends CustomPainter {
  final ui.Image? garment;
  final List<Offset> quad; // 左肩、右肩、右胯、左胯(预览坐标)
  final bool mirror; // 前置摄像头镜像
  GarmentOverlayPainter({required this.garment, required this.quad, this.mirror = true});

  @override
  void paint(Canvas canvas, Size size) {
    final g = garment;
    if (g == null || quad.length != 4) return;
    // 镜像:前置预览左右翻转,衣物也要跟着翻
    final q = mirror ? [quad[1], quad[0], quad[3], quad[2]] : quad;
    final topLeft = q[0], topRight = q[1], bottomRight = q[2], bottomLeft = q[3];
    final width = (topRight - topLeft).distance;
    final height = (bottomLeft - topLeft).distance;
    if (width < 20 || height < 20) return;
    final angle = atan2(topRight.dy - topLeft.dy, topRight.dx - topLeft.dx);
    final center = Offset((topLeft.dx + bottomRight.dx) / 2, (topLeft.dy + bottomRight.dy) / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    // 按肩宽/躯干高缩放;衣物图本身已是白底抠图,画时用白色以外的像素即可(简单做法:直接画整图)
    canvas.drawImageRect(
      g,
      Rect.fromLTWH(0, 0, g.width.toDouble(), g.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: width, height: height * 1.05),
      Paint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GarmentOverlayPainter old) =>
      old.garment != garment || old.quad != quad;
}
