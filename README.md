> 合并版说明：本仓库以 Gemini stage2 完整功能版为底（功能优先，APK 大小不重要），环境约束改为 Dart >=3.12 / Flutter >=3.44（ML Kit 新版要求），CI 沿用 stage2 的 flutter create 生成新版 Android 脚手架流程。

# AI 电子衣橱与智能穿搭 App（阶段一 + 阶段二实时 AR 试穿）

## 1. 功能总览（零云端付费 API）
- **衣橱管理与本地抠图**：拍照 / 相册多选入库、离线自动抠图（ONNX U²-NetP / Android ML Kit / OpenCV 兜底）、本地自动打标（MobileNetV3 + 主色提取）、极简双维筛选与双列瀑布流卡片。
- **智能穿搭与日历**：接入开源免费 [Open-Meteo](https://open-meteo.com/) 天气感知，本地温度/色彩/版型规则每日推荐 3 套穿搭，支持自由拖拽拼贴画布与穿搭日历打卡。
- **静态试穿 + 阶段二实时 AR 试衣镜**：
  - `TryOnEngineInterface` 统一抽象层；
  - 静态试穿（`StaticTryOnEngine`）：MediaPipe Pose + OpenCV 仿射贴合与边缘羽化；
  - 实时 AR 试衣镜（`NeonStreamTryOnEngine` + `LiveTryOnCameraPage`）：前置镜像摄像头流、`_isProcessing` 帧丢弃并发锁、肩/肘/胯/膝关键点 EMA 平滑滤波、实时仿射变形渲染、底部单品快捷切换与一键截图保存。

## 2. 零电脑手机端 GitHub 云端打包安装步骤
1. 解压 `ai_wardrobe_stage2_full.zip`，将 `ai_wardrobe/` 目录内的全部文件（含 `.github/workflows/build_apk.yml`、`android/`、`lib/`、`assets/`、`pubspec.yaml`）推送或上传至你的 GitHub 仓库根目录。
2. 在手机浏览器打开该 GitHub 仓库，进入顶部 **Actions** 标签页，点击 **Build Android Release APK** 工作流（推送代码会自动触发，也可点击 **Run workflow** 手动触发）。
3. 等待云端自动完成 `flutter create . --platforms=android`、`minSdkVersion 24` 配置、`flutter pub get`、`build_runner` 代码生成与 `flutter build apk --release --split-per-abi`。
4. 构建完成后，在工作流底部的 **Artifacts** 区域点击下载 **`ai-wardrobe-arm64-v8a-release-apk`**，解压出 `app-arm64-v8a-release.apk` 即可直接在 Android 手机安装测试。

## 3. 可选端侧离线模型
如需进一步提升抠图和品类识别精度，可在推送前将以下开源量化模型放入 `assets/models/`（不放也可直接构建运行，程序会自动启用 Android ML Kit / OpenCV 与轮廓启发式兜底）：
- `assets/models/u2netp_quant.onnx`
- `assets/models/mobilenetv3_fashion.onnx`
