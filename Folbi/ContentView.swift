import AppKit
import CodeEditSourceEditor
import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel

    /// 预览模式开关（spec #10 §2）：视图层状态，值为正在预览的文档 URL，不进入 WorkspaceModel。
    /// 切换文档后 URL 不再匹配即回到编辑模式；onChange 再清空，切回旧文档也不恢复预览（不做按文档记忆）。
    @State private var previewingDocumentURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private var isPreviewing: Bool {
        previewingDocumentURL != nil && previewingDocumentURL == model.documentURL
    }

    var body: some View {
        NavigationSplitView {
            if model.rootNode == nil {
                EmptySidebar(model: model)
            } else {
                FolderTreeView(model: model)
                    .accessibilityLabel("文件树")
            }
        } detail: {
            if let documentURL = model.documentURL {
                VStack(spacing: 0) {
                    ZStack {
                        // 编辑器在预览期间保持挂载（保住光标与撤销栈），只隐藏并让出交互。
                        EditorPane(model: model, documentURL: documentURL)
                            .id(documentURL)
                            .opacity(isPreviewing ? 0 : 1)
                            .allowsHitTesting(!isPreviewing)
                            .accessibilityHidden(isPreviewing)
                        if isPreviewing {
                            MarkdownPreviewView(
                                text: model.text,
                                background: Color(nsColor: EditorThemes.theme(model.selectedTheme, colorScheme: colorScheme).background)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    DocumentStatusBar(model: model, documentURL: documentURL)
                }
            } else {
                EmptyEditor(model: model)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
                .help("打开根文件夹")
            }

            if model.documentURL != nil {
                ToolbarItem(placement: .automatic) {
                    Button {
                        _ = model.save()
                    } label: {
                        Label("保存", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!model.isDirty)
                    .help("保存当前文件（⌘S）")
                }

                ToolbarItem(placement: .automatic) {
                    Picker("主题", selection: $model.selectedTheme) {
                        ForEach(EditorThemeName.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("编辑器主题")
                }
            }

            if MarkdownPreviewability.isPreviewable(documentURL: model.documentURL) {
                ToolbarItem(placement: .automatic) {
                    Button {
                        togglePreview()
                    } label: {
                        Label(isPreviewing ? "编辑" : "预览",
                              systemImage: isPreviewing ? "pencil" : "eye")
                    }
                    .help("切换预览（⌘⇧V）")
                }
            }
        }
        .onChange(of: model.documentURL) { _ in
            previewingDocumentURL = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMarkdownPreview)) { _ in
            togglePreview()
        }
    }

    /// 编辑/预览双向切换：工具栏按钮与 View 菜单通知共用同一入口。
    private func togglePreview() {
        guard MarkdownPreviewability.isPreviewable(documentURL: model.documentURL) else { return }
        if isPreviewing {
            previewingDocumentURL = nil
        } else {
            // 编辑器保持挂载但不可见，先交出键盘焦点，避免按键落入不可见编辑器。
            NSApp.keyWindow?.makeFirstResponder(nil)
            previewingDocumentURL = model.documentURL
        }
    }
}

private struct EmptySidebar: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Button("打开文件夹…") {
                model.chooseFolder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
    }
}

private struct EmptyEditor: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: model.rootNode == nil ? "folder.badge.plus" : "doc.text")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.rootNode == nil ? "打开一个文件夹开始" : "从左侧选择一个文本文件")
                .font(.title3)
            if model.rootNode == nil {
                Button("打开文件夹…") {
                    model.chooseFolder()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 文档状态栏：路径 + 未保存/外部冲突提示。编辑与预览两种模式下都保持可见。
private struct DocumentStatusBar: View {
    @ObservedObject var model: WorkspaceModel
    let documentURL: URL

    var body: some View {
        HStack(spacing: 8) {
            Text(documentURL.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(documentURL.path)
            Spacer()
            if model.hasExternalConflict {
                Label("磁盘内容已变化", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if model.isDirty {
                Text("未保存")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}

private struct EditorPane: View {
    @ObservedObject var model: WorkspaceModel
    let documentURL: URL

    @Environment(\.colorScheme) private var colorScheme
    @State private var editorState = SourceEditorState()

    var body: some View {
        SourceEditor(
            $model.text,
            language: .detectLanguageFrom(
                url: documentURL,
                prefixBuffer: String(model.text.prefix(1_024)),
                suffixBuffer: String(model.text.suffix(1_024))
            ),
            configuration: configuration,
            state: $editorState
        )
        .accessibilityLabel("\(model.documentDisplayName) 编辑器")
    }

    private var configuration: SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: EditorThemes.theme(model.selectedTheme, colorScheme: colorScheme),
                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                wrapLines: false
            ),
            behavior: .init(
                isEditable: true,
                isSelectable: true,
                indentOption: .spaces(count: 4)
            ),
            layout: .init(editorOverscroll: 0),
            peripherals: .init(
                showGutter: true,
                showMinimap: false,
                showReformattingGuide: false,
                showFoldingRibbon: false
            )
        )
    }
}
