import 'dart:convert';

class BodyPoint {
  final double x;
  final double y;
  final double confidence;

  const BodyPoint({
    required this.x,
    required this.y,
    this.confidence = 1.0,
  });

  BodyPoint lerp(BodyPoint target, double alpha) {
    final t = alpha.clamp(0.0, 1.0);
    return BodyPoint(
      x: x + (target.x - x) * t,
      y: y + (target.y - y) * t,
      confidence: confidence + (target.confidence - confidence) * t,
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'confidence': confidence,
      };

  factory BodyPoint.fromJson(Map<String, dynamic> json) => BodyPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      );
}

/// 标准化人体关键点模型（肩、肘、腰、胯/臀、膝），兼容静态图与阶段二实时视频流
class PoseLandmarks {
  final BodyPoint leftShoulder;
  final BodyPoint rightShoulder;
  final BodyPoint leftElbow;
  final BodyPoint rightElbow;
  final BodyPoint leftHip;
  final BodyPoint rightHip;
  final BodyPoint leftKnee;
  final BodyPoint rightKnee;
  final int imageWidth;
  final int imageHeight;

  const PoseLandmarks({
    required this.leftShoulder,
    required this.rightShoulder,
    required this.leftElbow,
    required this.rightElbow,
    required this.leftHip,
    required this.rightHip,
    required this.leftKnee,
    required this.rightKnee,
    required this.imageWidth,
    required this.imageHeight,
  });

  BodyPoint get shoulderCenter => BodyPoint(
        x: (leftShoulder.x + rightShoulder.x) / 2,
        y: (leftShoulder.y + rightShoulder.y) / 2,
        confidence: (leftShoulder.confidence + rightShoulder.confidence) / 2,
      );

  BodyPoint get hipCenter => BodyPoint(
        x: (leftHip.x + rightHip.x) / 2,
        y: (leftHip.y + rightHip.y) / 2,
        confidence: (leftHip.confidence + rightHip.confidence) / 2,
      );

  BodyPoint get waistCenter => BodyPoint(
        x: (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4,
        y: (leftShoulder.y + rightShoulder.y) * 0.21 +
            (leftHip.y + rightHip.y) * 0.29,
      );

  /// 指数移动平均（EMA）平滑滤波，防止实时视频流试穿画面抖动
  PoseLandmarks smoothWith(PoseLandmarks next, double alpha) {
    return PoseLandmarks(
      leftShoulder: leftShoulder.lerp(next.leftShoulder, alpha),
      rightShoulder: rightShoulder.lerp(next.rightShoulder, alpha),
      leftElbow: leftElbow.lerp(next.leftElbow, alpha),
      rightElbow: rightElbow.lerp(next.rightElbow, alpha),
      leftHip: leftHip.lerp(next.leftHip, alpha),
      rightHip: rightHip.lerp(next.rightHip, alpha),
      leftKnee: leftKnee.lerp(next.leftKnee, alpha),
      rightKnee: rightKnee.lerp(next.rightKnee, alpha),
      imageWidth: next.imageWidth,
      imageHeight: next.imageHeight,
    );
  }

  String toJsonString() => jsonEncode({
        'leftShoulder': leftShoulder.toJson(),
        'rightShoulder': rightShoulder.toJson(),
        'leftElbow': leftElbow.toJson(),
        'rightElbow': rightElbow.toJson(),
        'leftHip': leftHip.toJson(),
        'rightHip': rightHip.toJson(),
        'leftKnee': leftKnee.toJson(),
        'rightKnee': rightKnee.toJson(),
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      });

  factory PoseLandmarks.fromJsonString(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final ls = BodyPoint.fromJson(map['leftShoulder'] as Map<String, dynamic>);
    final rs = BodyPoint.fromJson(map['rightShoulder'] as Map<String, dynamic>);
    final lh = BodyPoint.fromJson(map['leftHip'] as Map<String, dynamic>);
    final rh = BodyPoint.fromJson(map['rightHip'] as Map<String, dynamic>);

    // 兼容阶段一未包含肘部字段的历史数据
    final le = map['leftElbow'] != null
        ? BodyPoint.fromJson(map['leftElbow'] as Map<String, dynamic>)
        : BodyPoint(x: (ls.x + lh.x) / 2, y: (ls.y + lh.y) / 2, confidence: 0.5);
    final re = map['rightElbow'] != null
        ? BodyPoint.fromJson(map['rightElbow'] as Map<String, dynamic>)
        : BodyPoint(x: (rs.x + rh.x) / 2, y: (rs.y + rh.y) / 2, confidence: 0.5);

    return PoseLandmarks(
      leftShoulder: ls,
      rightShoulder: rs,
      leftElbow: le,
      rightElbow: re,
      leftHip: lh,
      rightHip: rh,
      leftKnee: BodyPoint.fromJson(map['leftKnee'] as Map<String, dynamic>),
      rightKnee: BodyPoint.fromJson(map['rightKnee'] as Map<String, dynamic>),
      imageWidth: (map['imageWidth'] as num).toInt(),
      imageHeight: (map['imageHeight'] as num).toInt(),
    );
  }
}
