# 图片解码事实调研（issue #19）

日期：2026-08-24
范围：NSImage/NSImageRep 解码行为、GIF 动画、ImageIO 降采样、扩展格式白名单。
方法：Apple 官方文档（含归档）+ 本地 SDK 头文件原文 + macOS 26.5 SDK 运行实测。实测脚本与数字见附录。

## 摘要

1. **解码惰性且按像素计费**：NSImage 加载不做像素解码，首次绘制才解码；解码内存 ≈ 宽×高×4 字节，与文件大小无关，解码结果默认被缓存复用。
2. **GIF 不是只有首帧**：NSImage 把 GIF 解成"animated NSImage"（NSBitmapImageRep 持全部帧），NSImageView.animates（默认 true）自动播放；手动逐帧与 ImageIO 动画 API 均可行。
3. **降采样是官方推荐路径**：WWDC 2018 Session 219 给出标准配方（`CGImageSourceCreateThumbnailAtIndex` + 4 个选项键）；实测万级像素图生成 512px 缩略图内存增量 9.5 MB，对比全解码 383 MB。
4. **HEIC/TIFF/BMP 等零依赖打开**：NSImage 支持面 ≈ ImageIO 全集（实测 62-64 种 UTI，含 HEIC/WebP/PSD）；成本不在打开而在解码与攻击面，白名单扩展需配像素上限防护。

## 1. NSImage/NSImageRep 对 PNG/JPEG/GIF 的解码行为

### 1.1 解码时机：惰性

- ImageIO 层默认"渲染时才解码"：`kCGImageSourceShouldCacheImmediately` 文档原文"The default value is kCFBooleanFalse (image decoding will happen at rendering time)"。来源：SDK 头文件 `ImageIO.framework/Headers/CGImageSource.h` 第 50-54 行。
- 实测：10000×10000 PNG，`NSImage(contentsOfFile:)` 后物理内存增量 +0.7 MB；首次全尺寸绘制后 +383 MB。证明 init 不解码像素。见附录 A。
- NSImage 的缓存模式由 `NSImageCacheMode` 控制（default / always / bySize / never），`recache()` 可失效全部 rep 的离屏缓存。来源：`AppKit.framework/Headers/NSImage.h` 第 45-50、140、158 行；[NSImage 文档](https://developer.apple.com/documentation/appkit/nsimage)。
- 归档 Cocoa Drawing Guide："The NSImage class incorporates an internal caching scheme... enabled by default for all image objects." 来源：[Cocoa Drawing Guide: Images](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Images/Images.html)。

### 1.2 解码后缓存：默认保留

- `kCGImageSourceShouldCache`：64 位架构默认 `kCFBooleanTrue`（缓存解码结果）。来源：`CGImageSource.h` 第 42-48 行。
- WWDC 2018 Session 219 幻灯片"Decoding Concerns"原文："CPU-intensive process / Retained for repeat rendering / Persistent large memory allocation / Proportional to original image size, not view size"。来源：[WWDC18 Session 219](https://developer.apple.com/videos/play/wwdc2018/219/)（官方幻灯片 PDF 第 34 页）。
- 含义：一张图被显示过后，解码位图默认驻留内存以备重复渲染；`CGImageSourceRemoveCacheAtIndex`（macOS 10.9+）可主动清。来源：`CGImageSource.h` 第 176-179 行。

### 1.3 大图内存：按像素计费，与文件大小无关

- 幻灯片原文："Buffer size is proportional to image size"（第 17 页）。来源：同上 WWDC18-219。
- RGBA8（8 bit/采样 × 4 通道）= 4 字节/像素。实测 10000×10000 全尺寸绘制后增量 383 MB ≈ 400 MB 理论值。见附录 A。
- 推论（推断）：50+ MiB 的 JPEG/PNG 文件本身不构成内存上限信号；真正指标是像素尺寸。实测反例：一个 10000×10000 纯色 PNG 文件只有 1 MiB，解码仍需 383 MB — 文件越小不代表越安全（解压炸弹形态）。

### 1.4 线程安全

- NSImage 受 AppKit 主线程规则约束，但有官方例外。归档 Thread Safety Summary 原文："One thread can create an NSImage object, draw to the image buffer, and pass it off to the main thread for drawing. The underlying image cache is shared among all threads." 来源：[Thread Safety Summary](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html)。
- `+[NSImage imageWithSize:flipped:drawingHandler:]` 头文件注释原文："the block passed to the below method may be invoked whenever and on whatever thread the image itself is drawn on"。来源：`NSImage.h` 第 117 行。
- 含义：可在线程 A 创建并离屏绘制 NSImage，再交给主线程显示；同一 NSImage 对象不应被多线程同时绘制/修改（共享缓存是竞态来源）。
- ImageIO（CGImageSource 等 CF 接口）无主线程限制（推断：头文件与文档均无主线程要求，Apple 官方降采样示例在后台队列使用）。`CGImageSourceRef` 单对象跨线程并发读写是否安全：Unknown（无官方明示），建议每线程持有独立 source。

## 2. NSImage 与 GIF 动画

### 2.1 NSImage 不是"只暴露静态首帧"

- Apple 官方文档（NSImageView.animates）原文："Decoding an animated GIF file is the only way to create an animated NSImage object."；`animates` 默认 true，为 false 时"only the first frame of an animated image is displayed"。来源：[NSImageView.animates](https://developer.apple.com/documentation/appkit/nsimageview/animates)。
- GIF 经 NSImage 加载后表示为单个 NSBitmapImageRep，动画信息经属性键暴露：`NSImageFrameCount`、`NSImageCurrentFrame`、`NSImageCurrentFrameDuration`、`NSImageLoopCount`。来源：`AppKit.framework/Headers/NSBitmapImageRep.h` 第 69-72 行。
- 实测：3 帧 GIF（delay 0.1/0.2/0.3 s，loopCount=0）经 NSBitmapImageRep 读出 frameCount=3、currentFrame=0、currentFrameDuration=0.1、loopCount=0。见附录 B。
- 即：直接画一个 NSImage（含 SwiftUI `Image(nsImage:)`）呈现的是 currentFrame（默认第 0 帧）的静态图；要动起来需要显式驱动。

### 2.2 播放动画的可行路径与成本

| 路径 | 机制 | 成本 |
| --- | --- | --- |
| NSImageView.animates | 赋 GIF 的 NSImage，自动按帧时长播放（默认 true） | 零代码；AppKit 控件，SwiftUI 需 NSViewRepresentable 包装 |
| 手动驱动 NSBitmapImageRep | Timer 递增 `currentFrame`，按 `currentFrameDuration` 排程 | 少量代码；帧位图已在内存，内存 ≈ 帧数×宽×高×4（推断） |
| ImageIO 动画 API | `CGAnimateImageAtURLWithBlock` / `CGAnimateImageDataWithBlock`（macOS 10.15+），支持 GIF/APNG，"block is called on the main queue at time intervals specified by the delay time" | 官方一线 API，零依赖；回调即 CGImage，需自管视图刷新。来源：`ImageIO.framework/Headers/CGImageAnimation.h` 第 44-58 行 |
| ImageIO 手动逐帧 | `CGImageSourceGetCount` + `CGImageSourceCopyPropertiesAtIndex` 读 `kCGImagePropertyGIFDelayTime` / `UnclampedDelayTime` / 容器级 `kCGImagePropertyGIFLoopCount`，逐帧 `CGImageSourceCreateImageAtIndex` | 控制最全（可做 LRU 帧缓存、限内存）；代码最多。属性键来源：`CGImageProperties.h` 第 267-274 行；实测帧时长读取正确，附录 B |
| 第三方库（SDAnimatedImageView 等） | 现成播放器 | 引入外部依赖，与 Folbi"最小依赖"原则相悖，不建议 |

- SwiftUI `Image` 直接播放 GIF：Unknown（无官方文档支持）；可行做法是 NSViewRepresentable 包 NSImageView，或手动逐帧 + TimelineView 换 CGImage（推断）。

## 3. ImageIO 降采样管线

### 3.1 官方推荐配方（WWDC 2018 Session 219 幻灯片原文代码）

```swift
// Downsampling large images for display at smaller size
let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions)!
let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
let downsampleOptions =
  [kCGImageSourceCreateThumbnailFromImageAlways: true,
   kCGImageSourceShouldCacheImmediately: true,
   kCGImageSourceCreateThumbnailWithTransform: true,
   kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels] as CFDictionary
let downsampledImage =
  CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions)!
```

来源：[WWDC18 Session 219](https://developer.apple.com/videos/play/wwdc2018/219/) 官方幻灯片第 39 页起。

### 3.2 各选项语义（`CGImageSource.h` 头文件原文）

- `kCGImageSourceCreateThumbnailFromImageAlways`：即使源文件内嵌缩略图也从全图生成；"if a maximum pixel size isn't specified, then the thumbnail will be the size of the full image, which probably isn't what you want"。第 78-86 行。
- `kCGImageSourceThumbnailMaxPixelSize`：缩略图最大宽/高（像素）；不指定则不限制。第 88-93 行。
- `kCGImageSourceCreateThumbnailWithTransform`：按原图 orientation 与像素宽高比旋转/缩放。第 95-100 行。
- `kCGImageSourceShouldCache: false`（建 source 时）：不把全尺寸解码结果留在缓存。第 42-48 行。
- `kCGImageSourceShouldCacheImmediately: true`：缩略图在创建时即解码（而非拖到渲染时）。第 50-54 行。
- 另有 `kCGImageSourceSubsampleFactor`（macOS 10.11+）：按 2/4/8 整系数降采样，"Supported file formats are JPEG, HEIF, TIFF, and PNG"。第 102-110 行。

### 3.3 实测性能与内存

10000×10000 PNG → 512px 缩略图：0.27 s，物理内存增量 +9.5 MB（对比全尺寸解码 +383 MB）。见附录 A。

### 3.4 在 SwiftUI 图片面板的建议用法

- 面板显示尺寸远小于原图时，用上述配方按"显示点数 × backingScaleFactor"算 `maxDimensionInPixels`，产出 CGImage 后用 `Image(decorative:cgImage:scale:orientation:)` 上屏（推断：CGImage→SwiftUI Image 为官方公开接口，零拷贝风险低）。
- 解码放后台队列做，主线程只接结果（推断：ImageIO 无主线程约束，见 1.4；后台解码避免阻塞滚动）。
- 需要原尺寸查看/缩放时再用 `CGImageSourceCreateImageAtIndex` 全解码，并预期 §1.3 的内存量级；可用 `CGImageSourceRemoveCacheAtIndex` 及时释放。

## 4. HEIC/TIFF/BMP 等格式与扩展白名单

### 4.1 打开成本：API 层零额外成本

- NSImage 支持面 = 已注册 NSImageRep 子类可处理的 UTI 全集。官方文档原文："Returns an array of UTI strings identifying the image types supported by the registered image representation objects, either directly or through a user-installed filter service." 来源：[NSImage.imageTypes](https://developer.apple.com/documentation/appkit/nsimage/imagetypes)。
- 实测（macOS 26.5 SDK）：`CGImageSourceCopyTypeIdentifiers()` 62 种，`NSImage.imageTypes` 64 种；两者都含 `public.png`、`public.jpeg`、`com.compuserve.gif`、`public.heic`、`public.heif`、`public.tiff`、`com.microsoft.bmp`、`org.webmproject.webp`、`com.adobe.photoshop-image`、`com.microsoft.ico`、`public.jpeg-2000` 等。见附录 C。
- 实测 BMP/TIFF/HEIC/GIF 各一个文件，`NSImage(contentsOfFile:)` 全部直接打开，均为单 NSBitmapImageRep，init 均 < 5 ms（惰性，见 §1.1）。见附录 B。
- 机制（推断）：AppKit 内置 rep 走 ImageIO 解码——WebP/HEIC 无 AppKit 自有解码器却出现在 `NSImage.imageTypes`，只能由 ImageIO 提供。HEIF 另有 ImageIO 一手证据：`CGImageSourceGetPrimaryImageIndex` 注明"Return the primary image index for HEIF images"（`CGImageSource.h` 第 223-226 行）。
- 成本边界：打开（init）零成本；解码成本随格式不同（推断：HEIC 基于 HEVC 帧内编码，解码算力高于 JPEG；TIFF 可能无压缩或多页——`imageRepsWithData:` 注释"some file formats can contain multiple images"，`NSBitmapImageRep.h` 第 88 行）。

### 4.2 扩展白名单的风险

- **解压炸弹（实测存在）**：1 MiB 的 PNG 可对应 10000×10000 像素、383 MB 解码内存（附录 A）。防御：显示前用 `CGImageSourceCopyPropertiesAtIndex` 读 `kCGImagePropertyPixelWidth/Height`（只读头，不解码），超阈值则走降采样或拒绝。
- **解析器攻击面**：格式越多，进程内解析器暴露面越大。macOS 14.2+ 提供官方收窄手段 `CGImageSourceSetAllowableTypes`："To limit the image formats that ImageIO can decode... can only be called once"（`CGImageSource.h` 第 259-264 行）。注意是进程级、一次性设置，适合启动早期收窄到白名单。
- **类型判断依据**：ImageIO 按数据内容嗅探格式，扩展名仅是提示（`kCGImageSourceTypeIdentifierHint` 是 "best guess"，`CGImageSource.h` 第 32-37 行）。白名单应以 UTI 为准，不信扩展名。
- **多图容器**：TIFF/GIF/ICO 等可含多帧，`CGImageSourceGetCount`（`CGImageSource.h` 第 146-149 行）决定取帧策略。
- **HDR/浮点**：`kCGImageSourceShouldAllowFloat` 默认 false；macOS 14+ 新增 `kCGImageSourceDecodeRequest`（DecodeToHDR/SDR）控制 HDR 解码走向（`CGImageSource.h` 第 56-62、241-246 行）。扩展白名单到 HEIC/EXR 类格式时需显式决策 HDR 行为。

## 附录：运行证据

环境：macOS（Darwin 25.5.0），Xcode macOS 26.5 SDK，arm64。脚本为临时 Swift 文件（未入库），核心逻辑如下。

### 附录 A：惰性解码与降采样内存

- 生成 10000×10000 RGBA PNG（文件 1 MiB）。
- `phys_footprint` 基线 389.6 MB → `NSImage(contentsOfFile:)` 后 390.3 MB（+0.7）→ 全尺寸绘制到 NSGraphicsContext 后 773.7 MB（+383）。
- 同图 `CGImageSourceCreateThumbnailAtIndex`（§3.1 配方，MaxPixelSize=512）：0.27 s，增量 +9.5 MB，产出 512×512。

### 附录 B：格式与 GIF 帧

- BMP(64×64)/TIFF-LZW(64×64)/HEIC(2000×2000)/GIF(48×48，3 帧) 各经 ImageIO/AppKit 生成，`NSImage(contentsOfFile:)` 均成功，reps=1，类型 NSBitmapImageRep，init 0.000–0.005 s。
- GIF 帧信息：NSBitmapImageRep 读得 frameCount=3、currentFrame=0、currentFrameDuration=0.1、loopCount=0；CGImageSource 读得 3 帧 delay=0.1/0.2/0.3，容器 loopCount=0。

### 附录 C：类型清单

- `CGImageSourceCopyTypeIdentifiers()`：62 种；`NSImage.imageTypes`：64 种。探针命中的非传统格式：webp ✓、psd ✓、ico ✓、jp2 ✓、tga ✓、avci ✓、heics ✓；未命中：flashpix、exr、camera-raw（该 UTI 未注册）。

## 来源清单

- SDK 头文件（本地 macOS 26.5 SDK，Apple 官方注释即一手文档）：
  - `ImageIO.framework/Headers/CGImageSource.h`
  - `ImageIO.framework/Headers/CGImageAnimation.h`
  - `ImageIO.framework/Headers/CGImageProperties.h`
  - `AppKit.framework/Headers/NSImage.h`
  - `AppKit.framework/Headers/NSBitmapImageRep.h`
  - `AppKit.framework/Headers/NSImageRep.h`
- [WWDC 2018 Session 219: Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219/)（官方幻灯片 PDF）
- [NSImage | Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsimage)
- [NSImage.imageTypes | Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsimage/imagetypes)
- [NSImageView.animates | Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsimageview/animates)
- [Thread Safety Summary（归档）](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html)
- [Cocoa Drawing Guide: Images（归档）](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Images/Images.html)
