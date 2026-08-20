import Foundation

/// 图片路径解析结果：Markdown 预览只区分「可加载的本地文件」与「占位」两个分支。
enum ImagePathResolution: Equatable {
    /// 根文件夹边界内、存在且可读的文件 URL（符号链接已解析）。
    case loadable(URL)
    /// 越界（fail closed）、缺失、不可读或非本地路径，一律显示占位视图。
    case placeholder
}

/// 预览支持纯逻辑：把 Markdown 图片路径解析为根文件夹内的绝对文件 URL。
/// 相对路径以当前文档所在目录为基准（GitHub 惯例）。
enum ImagePathResolver {
    /// 边界判定分两层。第一层只做标准化路径的逐组件前缀比较（与
    /// WorkspaceModel.copyRootRelativePath 同一条规则），`../` 逃逸在此 fail closed，
    /// 不触碰磁盘。第二层解析符号链接后重查真实路径前缀，防止根内 symlink
    /// 把加载引到边界外；只有过了第一层的候选才会在这一层读盘。
    static func resolve(
        _ path: String,
        documentURL: URL,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> ImagePathResolution {
        guard !path.isEmpty,
              let url = URL(string: path, relativeTo: documentURL.deletingLastPathComponent())
        else {
            return .placeholder
        }

        // 远程 http(s) 等非 file scheme 不属于本地分支，由预览的网络加载路径处理。
        let candidate = url.absoluteURL.standardizedFileURL
        guard candidate.isFileURL else { return .placeholder }

        // 逐组件比较，避免 "/root" 被 "/rooted/..." 这类字符串前缀误判为边界内。
        let lexicalRoot = rootURL.standardizedFileURL
        guard candidate.pathComponents.starts(with: lexicalRoot.pathComponents) else {
            return .placeholder
        }

        let resolvedRoot = lexicalRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.pathComponents.starts(with: resolvedRoot.pathComponents) else {
            return .placeholder
        }

        // 缺失或不可读走占位，不崩溃。
        let candidatePath = resolvedCandidate.path
        guard fileManager.fileExists(atPath: candidatePath),
              fileManager.isReadableFile(atPath: candidatePath)
        else {
            return .placeholder
        }
        return .loadable(resolvedCandidate)
    }
}
