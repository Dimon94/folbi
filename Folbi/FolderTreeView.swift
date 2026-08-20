import AppKit
import SwiftUI

struct FolderTreeView: NSViewRepresentable {
    @ObservedObject var model: WorkspaceModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = ContextOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("File"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 14
        outlineView.style = .sourceList
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.handleDoubleClick)
        outlineView.contextMenuProvider = context.coordinator.contextMenu(for:)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        context.coordinator.outlineView = outlineView
        context.coordinator.update(root: model.rootNode, revision: model.treeRevision, selectedURL: model.treeSelectionURL)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.update(root: model.rootNode, revision: model.treeRevision, selectedURL: model.treeSelectionURL)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var model: WorkspaceModel
        weak var outlineView: NSOutlineView?
        private var root: FileNode?
        private var lastRevision = -1
        private var lastRootPath: String?
        private var isSynchronizingSelection = false

        init(model: WorkspaceModel) {
            self.model = model
        }

        func update(root: FileNode?, revision: Int, selectedURL: URL?) {
            self.root = root
            let rootPath = root?.url.path
            if revision != lastRevision || rootPath != lastRootPath {
                lastRevision = revision
                lastRootPath = rootPath
                outlineView?.reloadData()
                if let root {
                    outlineView?.expandItem(root)
                }
            }
            synchronizeSelection(to: selectedURL)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil { return root == nil ? 0 : 1 }
            guard let node = item as? FileNode, node.isDirectory else { return 0 }
            do {
                return try node.loadChildren().count
            } catch {
                model.presentError(error, title: "无法读取文件夹")
                return 0
            }
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil { return root as Any }
            guard let node = item as? FileNode else { return NSObject() }
            do {
                return try node.loadChildren()[index]
            } catch {
                model.presentError(error, title: "无法读取文件夹")
                return NSObject()
            }
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode)?.isDirectory == true
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("FileCell")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
                ?? makeCell(identifier: identifier)
            cell.textField?.stringValue = node.name
            cell.textField?.toolTip = node.url.path
            cell.imageView?.image = NSImage(
                systemSymbolName: node.isDirectory ? "folder" : "doc",
                accessibilityDescription: nil
            )
            cell.setAccessibilityLabel(node.name)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSynchronizingSelection,
                  let outlineView,
                  outlineView.selectedRow >= 0,
                  let node = outlineView.item(atRow: outlineView.selectedRow) as? FileNode else { return }
            let previousURL = model.treeSelectionURL
            model.treeSelectionURL = node.url
            if !node.isDirectory, !model.openDocument(at: node.url) {
                model.treeSelectionURL = previousURL
                synchronizeSelection(to: previousURL)
            }
        }

        @objc func handleDoubleClick() {
            guard let outlineView,
                  outlineView.clickedRow >= 0,
                  let node = outlineView.item(atRow: outlineView.clickedRow) as? FileNode,
                  node.isDirectory else { return }
            outlineView.isItemExpanded(node) ? outlineView.collapseItem(node) : outlineView.expandItem(node)
        }

        func contextMenu(for node: FileNode) -> NSMenu {
            let menu = NSMenu()
            menu.addItem(menuItem("新建文件…", action: #selector(createFile(_:)), node: node))
            menu.addItem(menuItem("新建文件夹…", action: #selector(createFolder(_:)), node: node))
            menu.addItem(.separator())
            menu.addItem(menuItem("复制绝对路径", action: #selector(copyAbsolutePath(_:)), node: node))
            menu.addItem(menuItem("复制相对路径", action: #selector(copyRelativePath(_:)), node: node))
            menu.addItem(menuItem("在 Finder 中显示", action: #selector(revealInFinder(_:)), node: node))
            return menu
        }

        @MainActor @objc private func createFile(_ sender: NSMenuItem) {
            if let node = sender.representedObject as? FileNode {
                model.createItem(isDirectory: false, relativeTo: node.url)
            }
        }

        @MainActor @objc private func createFolder(_ sender: NSMenuItem) {
            if let node = sender.representedObject as? FileNode {
                model.createItem(isDirectory: true, relativeTo: node.url)
            }
        }

        @MainActor @objc private func copyAbsolutePath(_ sender: NSMenuItem) {
            if let node = sender.representedObject as? FileNode {
                model.copyAbsolutePath(node.url)
            }
        }

        @MainActor @objc private func copyRelativePath(_ sender: NSMenuItem) {
            if let node = sender.representedObject as? FileNode {
                model.copyRootRelativePath(node.url)
            }
        }

        @MainActor @objc private func revealInFinder(_ sender: NSMenuItem) {
            if let node = sender.representedObject as? FileNode {
                model.revealInFinder(node.url)
            }
        }

        private func synchronizeSelection(to url: URL?) {
            guard let outlineView else { return }
            let row = (0..<outlineView.numberOfRows).first { row in
                (outlineView.item(atRow: row) as? FileNode)?.url == url
            }
            let target = row.map { IndexSet(integer: $0) } ?? IndexSet()
            guard outlineView.selectedRowIndexes != target else { return }
            isSynchronizingSelection = true
            outlineView.selectRowIndexes(target, byExtendingSelection: false)
            isSynchronizingSelection = false
        }

        private func menuItem(_ title: String, action: Selector, node: FileNode) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = node
            return item
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(icon)
            cell.addSubview(label)
            cell.imageView = icon
            cell.textField = label
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
}

private final class ContextOutlineView: NSOutlineView {
    var contextMenuProvider: ((FileNode) -> NSMenu)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0, let node = item(atRow: clickedRow) as? FileNode else { return nil }
        selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        return contextMenuProvider?(node)
    }
}
