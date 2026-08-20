import AppKit
import SwiftUI

@main
struct FolbiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = WorkspaceModel.shared

    var body: some Scene {
        Window("Folbi", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1_100, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            FolbiCommands(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WorkspaceModel.shared.confirmCanAbandonCurrentDocument() ? .terminateNow : .terminateCancel
    }
}

private struct FolbiCommands: Commands {
    @ObservedObject var model: WorkspaceModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开文件夹…") {
                model.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("新建文件…") {
                model.createItem(isDirectory: false)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(model.rootNode == nil)

            Button("新建文件夹…") {
                model.createItem(isDirectory: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(model.rootNode == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                _ = model.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.documentURL == nil || !model.isDirty)
        }
    }
}
