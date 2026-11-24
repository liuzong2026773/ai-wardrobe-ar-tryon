# AI 电子衣橱与实时 AR 试衣镜 — 全本地离线零付费版

Flutter Android App。**零付费 API**:抠图 / 识别 / 数据库 / 穿搭算法 / 实时试穿全部在手机本地运行。
唯一联网调用是免费免 Key 的 Open-Meteo 天气接口(可离线,默认 20°C)。

## 快速开始(手机免电脑云端编译)
1. 把本仓库推到 GitHub → Actions → `Build APK` → 跑完下载 `app-arm64-v8a-release.apk` 安装。
2. 本地编译: `flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter build apk --release --split-per-abi`
3. 首次打开授予相机 / 相册 / 定位权限(定位可拒绝)。

## 功能对照任务清单
| 任务 | 实现位置 |
|---|---|
| 拍照/相册入库,电商截图兼容 | `lib/screens/add_item_screen.dart`, `image_picker` 多选 |
| 本地抠图 ML Kit Subject Segmentation + ONNX 兜底 | `lib/services/segmentation_service.dart` |
| 主色 RGB/HSV 聚类、品类/季节、弹窗微调、Drift SQLite | `lib/services/color_service.dart`, `lib/data/app_database.dart` |
| 首页:总数+搜索、品类/季节双筛、双列瀑布流、白底卡片、收藏、穿搭次数 | `lib/screens/home_screen.dart`, `lib/widgets/clothing_card.dart` |
| 每日 3 套推荐:温度过滤+同色/莫兰迪/互补色+版型 | `lib/services/outfit_service.dart`, `lib/services/weather_service.dart` |
| 自由拼贴画布(缩放/旋转/图层)、穿搭日历打卡 | `lib/screens/collage_screen.dart`, `lib/screens/calendar_screen.dart` |
| **实时试衣镜**:前置镜像预览 + `startImageStream` 帧丢弃锁 24–30 FPS + Pose 33 点 + EMA 平滑 + 仿射/透视网格变形贴合 + 横向换衣 + 拍照保存 | `lib/screens/tryon_mirror_screen.dart`, `lib/services/pose_service.dart`, `lib/widgets/garment_overlay_painter.dart` |
| 静态全身照试穿(1–2 张正面全身照本地保存) | `lib/screens/static_tryon_screen.dart` |

## 数据库 (Drift / SQLite,本地 `app.db`)
- `clothing_items`: id, name, category(上装/下装/连衣裙/外套/鞋子/配饰), season(春夏秋冬), mainColorHex, colorFamily, imagePath(白底图), originalPath, isFavorite, wearCount, createdAt
- `outfits`: id, name, itemIds(JSON), date, isDailyRecommendation
- `wear_logs`: id, outfitId, date, note — 穿搭日历打卡
- `body_photos`: id, imagePath, isPrimary — 静态试穿全身照(最多 2 张)

## 关键设计说明(诚实标注)
- **实时试穿是“贴合渲染”而非 3D 布料仿真**:用肩/胯关键点算躯干四边形,仿射+透视网格把白底衣物图变形贴合,加 EMA 防抖。宽松/褶皱/遮挡效果有限,属端侧零付费方案的合理上限。
- **ML Kit 模型**:首次使用时由 Google Play 服务按需下载本地模型(免费),离线后可继续用;无 Play 服务的设备走 `flutter_onnxruntime` 兜底(需把 ONNX 模型放 `assets/models/`,见该目录 README)。
- **天气**:Open-Meteo 免 Key,失败/无网时默认 20°C 且不阻塞推荐。
- **隐私**:照片、衣橱、试穿照只存本机,不上传任何服务器。

## 目录结构
```
lib/
  main.dart                 入口 + 权限引导 + 底部导航
  models/                   ClothingItem / Outfit / WeatherInfo 等纯模型
  data/app_database.dart    Drift 表结构 + DAO
  services/                 segmentation / color / weather / outfit / pose
  screens/                  home / add / tryon_mirror / static_tryon / collage / calendar / recommend
  widgets/                  clothing_card / garment_overlay_painter / tag_chip
  utils/color_rules.dart    色彩搭配规则库(同色/莫兰迪/互补)
android/app/build.gradle.kts  minSdk 24
.github/workflows/build_apk.yml  flutter create / pub get / build_runner / build apk --split-per-abi
```
