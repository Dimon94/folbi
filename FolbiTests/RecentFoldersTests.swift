import XCTest
@testable import Folbi

final class RecentFolderListTests: XCTestCase {
    func testRecordMovesPathToFrontDeduplicatesAndKeepsTen() {
        var list = RecentFolderList()

        for index in 0...10 {
            list.record(URL(fileURLWithPath: "/folder-\(index)", isDirectory: true))
        }
        list.record(URL(fileURLWithPath: "/folder-5/", isDirectory: true))

        XCTAssertEqual(list.paths.count, 10)
        XCTAssertEqual(URL(fileURLWithPath: list.paths[0]).lastPathComponent, "folder-5")
        XCTAssertEqual(list.paths.filter { URL(fileURLWithPath: $0).lastPathComponent == "folder-5" }.count, 1)
        XCTAssertFalse(list.paths.contains { URL(fileURLWithPath: $0).lastPathComponent == "folder-0" })
    }

    func testNormalizesTrailingSlashAndSymbolicLinkBeforeDeduplicating() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var list = RecentFolderList()

        list.record(target)
        list.record(URL(fileURLWithPath: link.path + "/", isDirectory: true))

        XCTAssertEqual(list.paths, [target.standardizedFileURL.resolvingSymlinksInPath().path])
    }

    func testMenuItemsExposeFolderNameAndFullPathInStoredOrder() {
        let list = RecentFolderList(paths: ["/Users/demo/alpha", "/Users/demo/beta"])

        let items = list.menuItems

        XCTAssertEqual(items.map(\.displayName), ["alpha", "beta"])
        XCTAssertEqual(items.map(\.path), list.paths)
    }

    func testRemoveAndClear() {
        let first = URL(fileURLWithPath: "/first", isDirectory: true)
        let second = URL(fileURLWithPath: "/second", isDirectory: true)
        var list = RecentFolderList(paths: [first.path, second.path])

        list.remove(first)
        XCTAssertEqual(list.paths, [second.path])

        list.clear()
        XCTAssertTrue(list.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

final class RecentFoldersStoreTests: XCTestCase {
    func testRoundTripAndMissingValue() {
        let defaults = makeUserDefaults()
        let store = RecentFoldersStore(userDefaults: defaults)
        let list = RecentFolderList(paths: ["/first", "/second"])

        XCTAssertEqual(store.load(), RecentFolderList())
        store.save(list)

        XCTAssertEqual(store.load(), list)
        XCTAssertEqual(defaults.stringArray(forKey: "recentFolderPaths"), list.paths)
    }

    func testCorruptValueLoadsAsEmptyList() {
        let defaults = makeUserDefaults()
        defaults.set("not-an-array", forKey: "recentFolderPaths")

        XCTAssertEqual(RecentFoldersStore(userDefaults: defaults).load(), RecentFolderList())

        defaults.set(["/valid", ""], forKey: "recentFolderPaths")
        XCTAssertEqual(RecentFoldersStore(userDefaults: defaults).load(), RecentFolderList())

        defaults.set(["relative"], forKey: "recentFolderPaths")
        XCTAssertEqual(RecentFoldersStore(userDefaults: defaults).load(), RecentFolderList())
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "RecentFoldersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

@MainActor
final class WorkspaceModelRecentFoldersTests: XCTestCase {
    func testSuccessfulOpenRecordsFolderButFailedOpenDoesNot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file.txt")
        try Data().write(to: file)
        let store = makeStore()
        let model = WorkspaceModel(recentFoldersStore: store)

        XCTAssertTrue(model.openRootFolder(root, presentsError: false))
        XCTAssertFalse(model.openRootFolder(file, presentsError: false))

        XCTAssertEqual(model.recentFolders.paths, [root.standardizedFileURL.resolvingSymlinksInPath().path])
        XCTAssertEqual(store.load(), model.recentFolders)
    }

    func testOpenRecentFolderWithValidPathOpensFolderAndMovesItToFront() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let model = makeModel(paths: [first.path, second.path])

        model.openRecentFolder(at: second.path, presentsError: false)

        XCTAssertEqual(model.rootNode?.url, second.standardizedFileURL)
        XCTAssertEqual(model.recentFolders.paths.first, second.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testOpenRecentFolderWithInvalidPathRemovesEntryAndKeepsWorkspace() throws {
        let current = try makeTemporaryDirectory()
        let surviving = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: current)
            try? FileManager.default.removeItem(at: surviving)
        }
        // 失效两种形态：路径不存在；路径存在但不再是目录（spec #38 §6）。
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let regularFile = current.appendingPathComponent("regular.txt")
        try Data().write(to: regularFile)
        let store = makeStore(paths: [missing.path, regularFile.path, surviving.path])
        let model = WorkspaceModel(recentFoldersStore: store)
        XCTAssertTrue(model.openRootFolder(current, presentsError: false))

        model.openRecentFolder(at: missing.path, presentsError: false)
        model.openRecentFolder(at: regularFile.path, presentsError: false)

        XCTAssertEqual(model.rootNode?.url, current.standardizedFileURL)
        XCTAssertEqual(model.recentFolders.paths, RecentFolderList(paths: [current.path, surviving.path]).paths)
        XCTAssertEqual(store.load(), model.recentFolders)
    }

    func testClearRecentFoldersEmptiesListAndPersists() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = makeStore(paths: [folder.path])
        let model = WorkspaceModel(recentFoldersStore: store)

        model.clearRecentFolders()

        XCTAssertEqual(model.recentFolders, RecentFolderList())
        XCTAssertEqual(store.load(), RecentFolderList())
    }

    func testLaunchRestorationOpensFirstValidFolderWithoutReordering() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let model = makeModel(paths: [first.path, second.path])

        model.restoreRootFolderAtLaunch()

        XCTAssertEqual(model.rootNode?.url, first.standardizedFileURL)
        XCTAssertEqual(model.recentFolders.paths, RecentFolderList(paths: [first.path, second.path]).paths)
    }

    func testLaunchRestorationRemovesInvalidFirstFolderWithoutTryingSecond() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let validSecond = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: validSecond) }
        let store = makeStore(paths: [missing.path, validSecond.path])
        let model = WorkspaceModel(recentFoldersStore: store)

        model.restoreRootFolderAtLaunch()
        model.restoreRootFolderAtLaunch()

        XCTAssertNil(model.rootNode)
        XCTAssertEqual(model.recentFolders.paths, RecentFolderList(paths: [validSecond.path]).paths)
        XCTAssertEqual(store.load(), model.recentFolders)
    }

    func testLaunchRestorationWithEmptyHistoryKeepsEmptyWorkspace() {
        let model = makeModel()

        model.restoreRootFolderAtLaunch()

        XCTAssertNil(model.rootNode)
        XCTAssertTrue(model.recentFolders.paths.isEmpty)
    }

    private func makeModel(paths: [String] = []) -> WorkspaceModel {
        WorkspaceModel(recentFoldersStore: makeStore(paths: paths))
    }

    private func makeStore(paths: [String] = []) -> RecentFoldersStore {
        let defaults = makeUserDefaults()
        let store = RecentFoldersStore(userDefaults: defaults)
        store.save(RecentFolderList(paths: paths))
        return store
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "WorkspaceModelRecentFoldersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
