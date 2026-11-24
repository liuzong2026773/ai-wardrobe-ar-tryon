# 本地 ONNX 兜底模型(可选)

主路是 ML Kit(免费本地模型,首次使用由 Play 服务下载)。
无 Play 服务的设备才走 `flutter_onnxruntime` 兜底,需要把模型放这里:

- `cloth_segment.onnx` — 轻量人体/衣物分割,如 `segformer-b0-clothes` 量化版
- `cloth_classify.onnx` — 品类分类(上装/下装/连衣裙/外套/鞋子/配饰)

来源建议(自行下载,注意各自开源协议):
- Hugging Face 搜索 `cloth segmentation onnx` / `segformer clothes`
- 模型需为 fp16/int8 量化版,控制在 50MB 以内,否则低端机加载慢。

放好后在 `lib/services/segmentation_service.dart` 的 catch 分支里
用 `OrtSession.fromAsset('assets/models/cloth_segment.onnx')` 加载即可。
不放模型也不影响编译和主路使用。
