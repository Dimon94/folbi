import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图片打开策略判定器。它拥有内容白名单和像素上限，不负责解码或展示。
/// 测试坐标：repo://FolbiTests/ImageOpenPolicyTests.swift。
enum ImageOpenPolicy {
    enum Decision: Equatable {
        case displayable
        case exceedsPixelLimit
        case notImage
    }

    private static let allowedTypes = Set([
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.gif.identifier,
        UTType.heic.identifier,
        UTType.webP.identifier,
    ])

    // 首帧像素总量上限。大于 1 亿时拒绝；等于 1 亿时通过。
    private static let maxPixelCount: Int64 = 100_000_000

    /// 只读取 ImageIO 的类型与首帧属性。无法识别或缺少正尺寸时回落文本路径。
    static func evaluate(_ url: URL) -> Decision {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let type = CGImageSourceGetType(source),
              allowedTypes.contains(type as String)
        else {
            return .notImage
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
              width > 0,
              height > 0
        else {
            return .notImage
        }
        return width > maxPixelCount / height ? .exceedsPixelLimit : .displayable
    }
}
