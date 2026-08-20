import AppKit
import Combine
import CoreServices
import Foundation

enum FolderPadError: Error, Equatable, LocalizedError {
    case fileTooLarge(maximumBytes: Int)
    case invalidItemName
    case itemAlreadyExists
    case notRegularFile
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maximumBytes):
            return "文件超过 \(ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file)) 上限。"
        case .invalidItemName:
            return "名称不能为空、不能是 . 或 ..，也不能包含路径分隔符。"
        case .itemAlreadyExists:
            return "同名文件或文件夹已经存在。"
        case .notRegularFile:
            return "首版只支持普通文本文件。"
        case .notUTF8:
            return "文件不是 UTF-8 文本，首版无法打开。"
        }
    }
}

enum DocumentIO {
    static let maximumDocumentBytes = 5 * 1_024 * 1_024

    static func readUTF8Text(at url: URL, maximumBytes: Int = maximumDocumentBytes) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw FolderPadError.notRegularFile
        }
        guard (values.fileSize ?? 0) <= maximumBytes else {
            throw FolderPadError.fileTooLarge(maximumBytes: maximumBytes)
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8) else {
            throw FolderPadError.notUTF8
        }
        return text
    }

    static func validateNewItemName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.unicodeScalars.contains("\0") else {
            throw FolderPadError.invalidItemName
        }
    }
}

struct FileFingerprint: Equatable {
    let modificationDate: Date?
    let fileSize: Int?

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        modificationDate = values.contentModificationDate
        fileSize = values.fileSize
    }
}

final class FileNode: NSObject {
    let url: URL
    let isDirectory: Bool
    private(set) var children: [FileNode]?

    var name: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    init(url: URL, isDirectory: Bool) {
        self.url = url.standardizedFileURL
        self.isDirectory = isDirectory
    }

    func loadChildren(fileManager: FileManager = .default) throws -> [FileNode] {
        guard isDirectory else { return [] }
        if let children { return children }

        let loaded = try Self.readChildren(of: url, fileManager: fileManager)
        children = loaded
        return loaded
    }

    func refreshLoadedSubtree(fileManager: FileManager = .default) throws {
        guard isDirectory, let existingChildren = children else { return }
        let existingByPath = Dictionary(uniqueKeysWithValues: existingChildren.map { ($0.url.path, $0) })
        let latestChildren = try Self.readChildren(of: url, fileManager: fileManager).map { latest in
            guard let existing = existingByPath[latest.url.path], existing.isDirectory == latest.isDirectory else {
                return latest
            }
            try existing.refreshLoadedSubtree(fileManager: fileManager)
            return existing
        }
        children = latestChildren
    }

    func invalidateChildren() {
        children = nil
    }

    func loadedNode(at targetURL: URL) -> FileNode? {
        let targetPath = targetURL.standardizedFileURL.path
        if url.path == targetPath { return self }
        for child in children ?? [] {
            if let match = child.loadedNode(at: targetURL) { return match }
        }
        return nil
    }

    private static func readChildren(of url: URL, fileManager: FileManager) throws -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )
        return try urls.map { childURL in
            let values = try childURL.resourceValues(forKeys: Set(keys))
            let followsAsDirectory = values.isDirectory == true && values.isSymbolicLink != true
            return FileNode(url: childURL, isDirectory: followsAsDirectory)
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    static let shared = WorkspaceModel()

    @Published private(set) var rootNode: FileNode?
    @Published private(set) var treeRevision = 0
    @Published var treeSelectionURL: URL?
    @Published private(set) var documentURL: URL?
    @Published private(set) var isDirty = false
    @Published private(set) var hasExternalConflict = false
    @Published var selectedTheme = EditorThemeName.default
    @Published var text = "" {
        didSet {
            guard !isApplyingDiskContent else { return }
            isDirty = text != savedText
        }
    }

    var documentDisplayName: String {
        documentURL?.lastPathComponent ?? "未选择文件"
    }

    private var savedText = ""
    private var fingerprint: FileFingerprint?
    private var isApplyingDiskContent = false
    private let watcher = FSEventsWatcher()

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择根文件夹"
        panel.prompt = "打开"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openRootFolder(url)
    }

    func openRootFolder(_ url: URL) {
        guard confirmCanAbandonCurrentDocument() else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            presentError(FolderPadError.notRegularFile, title: "无法打开文件夹")
            return
        }

        let root = FileNode(url: url, isDirectory: true)
        rootNode = root
        treeSelectionURL = root.url
        clearDocument()
        treeRevision += 1
        watcher.start(rootURL: root.url) { [weak self] in
            self?.handleFileSystemChange()
        }
    }

    @discardableResult
    func openDocument(at url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL != documentURL else { return true }
        guard confirmCanAbandonCurrentDocument() else { return false }

        do {
            try loadDocument(at: standardizedURL)
            treeSelectionURL = standardizedURL
            return true
        } catch {
            presentError(error, title: "无法打开文件")
            return false
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let documentURL else { return true }
        if hasExternalConflict {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "磁盘内容已经变化"
            alert.informativeText = "选择覆盖磁盘版本、重新载入磁盘内容，或取消。"
            alert.addButton(withTitle: "覆盖磁盘")
            alert.addButton(withTitle: "重新载入")
            alert.addButton(withTitle: "取消")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break
            case .alertSecondButtonReturn:
                do {
                    try loadDocument(at: documentURL)
                    return true
                } catch {
                    presentError(error, title: "重新载入失败")
                    return false
                }
            default:
                return false
            }
        }

        do {
            try Data(text.utf8).write(to: documentURL, options: .atomic)
            savedText = text
            isDirty = false
            hasExternalConflict = false
            fingerprint = try FileFingerprint(url: documentURL)
            return true
        } catch {
            presentError(error, title: "保存失败")
            return false
        }
    }

    func confirmCanAbandonCurrentDocument() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保存对“\(documentDisplayName)”的修改吗？"
        alert.informativeText = "不保存会丢失当前修改。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return save()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func createItem(isDirectory: Bool, relativeTo itemURL: URL? = nil) {
        guard let rootURL = rootNode?.url else { return }
        let selectedURL = itemURL ?? treeSelectionURL ?? rootURL
        let parentURL = directoryForNewItem(from: selectedURL, rootURL: rootURL)

        let alert = NSAlert()
        alert.messageText = isDirectory ? "新建文件夹" : "新建文件"
        alert.informativeText = "输入名称。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        nameField.placeholderString = isDirectory ? "文件夹名称" : "文件名称"
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try DocumentIO.validateNewItemName(nameField.stringValue)
            let newURL = parentURL.appendingPathComponent(nameField.stringValue, isDirectory: isDirectory)
            guard !FileManager.default.fileExists(atPath: newURL.path) else {
                throw FolderPadError.itemAlreadyExists
            }
            if isDirectory {
                try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            } else {
                guard FileManager.default.createFile(atPath: newURL.path, contents: Data()) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }

            rootNode?.loadedNode(at: parentURL)?.invalidateChildren()
            treeRevision += 1
            if isDirectory {
                treeSelectionURL = newURL
            } else {
                _ = openDocument(at: newURL)
            }
        } catch {
            presentError(error, title: isDirectory ? "无法新建文件夹" : "无法新建文件")
        }
    }

    func copyAbsolutePath(_ url: URL) {
        copyToPasteboard(url.path)
    }

    func copyRootRelativePath(_ url: URL) {
        guard let rootURL = rootNode?.url else { return }
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let targetComponents = url.standardizedFileURL.pathComponents
        guard targetComponents.starts(with: rootComponents) else { return }
        let relativeComponents = targetComponents.dropFirst(rootComponents.count)
        copyToPasteboard(relativeComponents.isEmpty ? "." : relativeComponents.joined(separator: "/"))
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }

    private func loadDocument(at url: URL) throws {
        let loadedText = try DocumentIO.readUTF8Text(at: url)
        isApplyingDiskContent = true
        text = loadedText
        isApplyingDiskContent = false
        savedText = loadedText
        documentURL = url
        fingerprint = try FileFingerprint(url: url)
        isDirty = false
        hasExternalConflict = false
    }

    private func clearDocument() {
        isApplyingDiskContent = true
        text = ""
        isApplyingDiskContent = false
        savedText = ""
        documentURL = nil
        fingerprint = nil
        isDirty = false
        hasExternalConflict = false
    }

    private func directoryForNewItem(from selectedURL: URL, rootURL: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return selectedURL
        }
        let parent = selectedURL.deletingLastPathComponent()
        return parent.path.hasPrefix(rootURL.path) ? parent : rootURL
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func handleFileSystemChange() {
        do {
            try rootNode?.refreshLoadedSubtree()
            treeRevision += 1
        } catch {
            // The next explicit expansion reports the exact inaccessible directory.
        }

        guard let documentURL else { return }
        do {
            let currentFingerprint = try FileFingerprint(url: documentURL)
            guard currentFingerprint != fingerprint else { return }
            if isDirty {
                hasExternalConflict = true
            } else {
                try loadDocument(at: documentURL)
            }
        } catch {
            hasExternalConflict = true
        }
    }
}

private final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private var handler: (() -> Void)?
    private let queue = DispatchQueue(label: "com.dimon.folderpad.fsevents", qos: .utility)

    deinit {
        stop()
    }

    func start(rootURL: URL, handler: @escaping () -> Void) {
        stop()
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.receiveEvent()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        )
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        handler = nil
    }

    private func receiveEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.handler?()
        }
    }
}
