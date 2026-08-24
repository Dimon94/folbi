import Foundation

// COORD: repo://Folbi/RecentFolders.swift
// INPUT: 根文件夹 URL 与 UserDefaults 键 recentFolderPaths。
// OUTPUT: 标准化 MRU 路径列表及其持久读写。
// POS: WorkspaceModel 的确定性列表规则和 UserDefaults 薄壳，不负责打开文件夹。
// TEST: repo://FolbiTests/RecentFoldersTests.swift
// PROTOCOL: 路径格式、上限或持久键变化时同步 spec #38、CONTEXT.md 与系统地图。
struct RecentFolderList: Equatable {
    static let maximumCount = 10

    private(set) var paths: [String]

    init(paths: [String] = []) {
        self.paths = []
        for path in paths.reversed() {
            record(URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    mutating func record(_ url: URL) {
        let path = Self.normalizedPath(url)
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        paths = Array(paths.prefix(Self.maximumCount))
    }

    mutating func remove(_ url: URL) {
        let path = Self.normalizedPath(url)
        paths.removeAll { $0 == path }
    }

    mutating func clear() {
        paths.removeAll()
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

struct RecentFoldersStore {
    private static let key = "recentFolderPaths"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> RecentFolderList {
        guard let paths = userDefaults.stringArray(forKey: Self.key),
              paths.allSatisfy({ ($0 as NSString).isAbsolutePath }) else {
            return RecentFolderList()
        }
        return RecentFolderList(paths: paths)
    }

    func save(_ list: RecentFolderList) {
        userDefaults.set(list.paths, forKey: Self.key)
    }
}
