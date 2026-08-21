import AppKit
import MarkdownUI
import SwiftUI

/// Markdown 预览的图片加载（#16）。
///
/// MarkdownUI 先用 imageBaseURL（= 当前文档 URL，见 MarkdownPreviewView）把相对图片路径
/// 解析成绝对 file URL，再交给本 provider（2.4.1 ImageView.swift 源码实证）：
/// - 本地 file URL：回传 absoluteString 给 ImagePathResolver（#13）重走完整校验——词法
///   边界、symlink、存在性与可读性，`../` 逃逸根文件夹 fail closed；缺失、不可读、解码
///   失败与本地 SVG（可渲染性 Unknown，ticket 裁决按占位处理）统一走占位视图，不崩溃。
/// - 远程 http(s)：委托 MarkdownUI 默认网络加载（DefaultImageProvider），零额外代码。
struct PreviewImageProvider: ImageProvider {
    /// 解析基准与边界：当前文档与根文件夹。预览只在两者俱在时可达；
    /// 缺上下文时到达本 provider 的显式 file URL 仍 fail closed 走占位
    /// （相对引用无基准 URL 时在 MarkdownUI 侧已无法解析为 file URL）。
    let documentURL: URL?
    let rootURL: URL?

    func makeImage(url: URL?) -> some View {
        switch Self.classify(url: url, documentURL: documentURL, rootURL: rootURL) {
        case .local(let image):
            return AnyView(
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // 上限取自然尺寸：小图不被放大，大图随预览宽度收缩。
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
            )
        case .remote(let remoteURL):
            return AnyView(DefaultImageProvider.default.makeImage(url: remoteURL))
        case .placeholder(let name):
            return AnyView(Self.placeholder(name: name))
        }
    }

    /// 加载分支：判定与视图构建分离，供单元测试直验。
    enum ImageLoad {
        /// 根文件夹边界内、存在可读且可解码的本地图片。
        case local(NSImage)
        /// 远程 URL，交 MarkdownUI 默认网络加载。
        case remote(URL)
        /// 占位：URL 为空、越界、缺失、不可读、解码失败或本地 SVG。
        case placeholder(name: String?)
    }

    /// 判定一个图片 URL 走哪个分支。纯逻辑（磁盘只读），视图与网络都不参与。
    static func classify(
        url: URL?,
        documentURL: URL?,
        rootURL: URL?
    ) -> ImageLoad {
        guard let url else { return .placeholder(name: nil) }
        guard url.isFileURL else { return .remote(url) }
        let name = url.lastPathComponent
        guard let documentURL, let rootURL else { return .placeholder(name: name) }
        // 本地 SVG 可渲染性 Unknown（ticket #16 推断不支持）：按缺失/不可读走占位分支。
        guard url.pathExtension.lowercased() != "svg" else { return .placeholder(name: name) }
        // absoluteString 原样回传：解析器的 URL(string:relativeTo:) 对绝对 URL 串原样还原，
        // 边界与存在性规则只在解析器一处定义，这里不复制。
        guard case .loadable(let fileURL) = ImagePathResolver.resolve(
            url.absoluteString,
            documentURL: documentURL,
            rootURL: rootURL
        ) else {
            return .placeholder(name: name)
        }
        // 解码失败（损坏文件、零 representation）同样占位，不崩溃。
        guard let image = NSImage(contentsOf: fileURL), image.isValid else {
            return .placeholder(name: name)
        }
        return .local(image)
    }

    /// 占位视图：给出文件名，用户据此修正路径或补齐文件（自然恢复动作）。
    private static func placeholder(name: String?) -> some View {
        Label {
            Text(name.map { "图片不可用：\($0)" } ?? "图片不可用")
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: "photo")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
