import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 图片面板（spec #25 §3/§4/§5、CONTEXT.md「图片面板」）。
///
/// 内容源为图片文件本身，不是编辑缓冲区的投影。白名单与像素上限由 `ImageOpenPolicy`（#26）拥有，
/// 本面板复用其判定，不复制阈值。超限与解码失败面板内占位、不回滚文件树选中。
/// 显示路径按内容类型分流：GIF 由 `AnimatedImageView`（NSImageView 包装）按帧时长播放（#28）；
/// 其余格式恒走 ImageIO 降采样（WWDC18-219 配方，repo://docs/research/2026-08-24-image-decoding-facts.md §3.1），
/// 不做全尺寸解码上屏。外部改动不自动刷新，重新选中即最新（既有 FSEvents 行为不扩展）。
struct ImagePanel: View {
    let url: URL
    @Environment(\.displayScale) private var displayScale
    @State private var content: Content = .loading

    var body: some View {
        GeometryReader { geometry in
            // maxPixelSize = 面板点尺寸 × 显示缩放，供降采样按显示尺寸而非原图尺寸解码。
            let maxPixelSize = max(1, Int((max(geometry.size.width, geometry.size.height) * displayScale).rounded()))
            view(for: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .task(id: TaskKey(path: url.path, maxPixelSize: maxPixelSize)) {
                    content = Self.load(url: url, maxPixelSize: maxPixelSize)
                }
        }
    }

    @ViewBuilder
    private func view(for content: Content) -> some View {
        switch content {
        case .loading:
            Color.clear
        case .image(let image, let pixelSize):
            // 适应窗口 = 缩小不放大：内层 frame 上限取自然点尺寸（像素 ÷ 显示缩放），
            // 小图停在原始像素尺寸、大图随面板收缩；外层撑满并居中；宽高比由 .fit 保持。
            let naturalPoint = CGSize(width: pixelSize.width / displayScale, height: pixelSize.height / displayScale)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: naturalPoint.width, maxHeight: naturalPoint.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("图片 \(url.lastPathComponent)")
        case .gif(let image, let pixelSize):
            // 自然点尺寸语义与静态分支一致；缩放与居中由 NSImageView 承担。
            let naturalPoint = CGSize(width: pixelSize.width / displayScale, height: pixelSize.height / displayScale)
            AnimatedImageView(image: image, naturalPointSize: naturalPoint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("图片 \(url.lastPathComponent)")
        case .exceedsPixelLimit:
            placeholder("图片像素超过 1 亿上限，无法显示。")
        case .decodeFailed:
            placeholder("图片已损坏或无法解码，无法显示。")
        }
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    /// 面板显示态。静态图携带降采样后像素尺寸，GIF 携带原始帧像素尺寸，均供视图换算自然点尺寸。
    enum Content {
        case loading
        case image(NSImage, pixelSize: CGSize)
        case gif(NSImage, pixelSize: CGSize)
        case exceedsPixelLimit
        case decodeFailed
    }

    /// 解码分流（纯逻辑，磁盘只读）：先复用 `ImageOpenPolicy` 判定白名单与像素上限，
    /// 再按内容类型分流——GIF 走动画内容，其余按 WWDC18-219 配方降采样。判定与视图分离，供单元测试直验。
    static func load(url: URL, maxPixelSize: Int) -> Content {
        switch ImageOpenPolicy.evaluate(url) {
        case .exceedsPixelLimit:
            return .exceedsPixelLimit
        case .notImage:
            return .decodeFailed
        case .displayable:
            if let gif = gifContent(url: url) {
                return gif
            }
            guard let (image, pixelSize) = downsample(url: url, maxPixelSize: maxPixelSize) else {
                return .decodeFailed
            }
            return .image(image, pixelSize: pixelSize)
        }
    }

    /// GIF 分流：内容类型为 GIF 才接管，产出动画内容；GIF 文件无法被 AppKit 解析时回落
    /// 解码失败占位，与静态路径同一失败语义。非 GIF 返回 nil，继续走降采样路径。
    /// NSImageView 播放时按需解码全部帧；首帧像素上限已由 `ImageOpenPolicy` 拦截。
    private static func gifContent(url: URL) -> Content? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let type = CGImageSourceGetType(source),
              type as String == UTType.gif.identifier
        else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
              width > 0,
              height > 0,
              let image = NSImage(contentsOf: url)
        else { return .decodeFailed }
        return .gif(image, pixelSize: CGSize(width: Double(width), height: Double(height)))
    }

    /// ImageIO 降采样：产出不超过 maxPixelSize 的缩略图；maxPixelSize 不放大原图。
    private static func downsample(url: URL, maxPixelSize: Int) -> (NSImage, CGSize)? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        return (NSImage(cgImage: cgImage, size: pixelSize), pixelSize)
    }

    /// maxPixelSize 变化才触发重解码；面板缩放时按需降采样，避免全尺寸驻留。
    private struct TaskKey: Equatable {
        let path: String
        let maxPixelSize: Int
    }
}

/// GIF 动画视图（spec #25 §4）：NSViewRepresentable 包装 NSImageView，`animates` 按帧时长
/// 自动播放，零新增依赖。适应窗口语义由 NSImageView 承担：`scaleProportionallyDown` 缩小不放大、
/// `alignCenter` 居中；naturalPointSize（像素 ÷ 显示缩放）赋给 image.size，小图按原始像素尺寸显示。
private struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage
    let naturalPointSize: CGSize

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyDown
        view.imageAlignment = .alignCenter
        updateImage(in: view)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        // image 换实例（重新选中/重载）或 naturalPointSize 随显示缩放变化时都要重设。
        if view.image !== image || image.size != naturalPointSize {
            updateImage(in: view)
        }
    }

    private func updateImage(in view: NSImageView) {
        image.size = naturalPointSize
        view.image = image
    }
}
