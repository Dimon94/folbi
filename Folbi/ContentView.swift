import AppKit
import CodeEditSourceEditor
import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel

    /// 预览模式开关（spec #10 §2）：视图层状态，值为正在预览的文档 URL，不进入 WorkspaceModel。
    /// 切换文档后 URL 不再匹配即回到编辑模式；onChange 再清空，切回旧文档也不恢复预览（不做按文档记忆）。
    @State private var previewingDocumentURL: URL?
    /// 历史模式开关（spec #42 §2、#45）：视图层状态，值为进入历史视图时的 GitHistoryModel 句柄。
    /// 进入历史视图时由 model.gitHistory 重建并拉取第一页；切回编辑器时恢复进入前状态。
    @State private var historyModel: GitHistoryModel?
    @Environment(\.colorScheme) private var colorScheme

    private var isPreviewing: Bool {
        previewingDocumentURL != nil && previewingDocumentURL == model.documentURL
    }

    private var isShowingHistory: Bool {
        historyModel != nil
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
            // 三态分流（ADR 0001 决策 3）：当前图片 → 图片面板；当前文档 → 编辑器栈；否则 → 空态。
            // 互斥不变量由 WorkspaceModel 持有，此处照读，不投影为局部枚举。
            if let currentImageURL = model.currentImageURL {
                ImagePanel(url: currentImageURL)
                    .id(currentImageURL)
            } else if let historyModel = historyModel {
                GitHistoryView(model: historyModel)
            } else if let documentURL = model.documentURL {
                VStack(spacing: 0) {
                    ZStack {
                        // 编辑器在预览/历史期间保持挂载（保住光标与撤销栈），只隐藏并让出交互。
                        EditorPane(model: model, documentURL: documentURL)
                            .id(documentURL)
                            .opacity(isPreviewing || isShowingHistory ? 0 : 1)
                            .allowsHitTesting(!isPreviewing && !isShowingHistory)
                            .accessibilityHidden(isPreviewing || isShowingHistory)
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

            if model.gitHistory != nil {
                ToolbarItem(placement: .automatic) {
                    Button {
                        toggleHistory()
                    } label: {
                        Label(isShowingHistory ? "编辑" : "历史",
                              systemImage: isShowingHistory ? "pencil" : "clock")
                    }
                    .help("切换历史（⌘⇧H）")
                }
            }
        }
        .onChange(of: model.documentURL) { _ in
            previewingDocumentURL = nil
            if !isShowingHistory {
                historyModel = nil
            }
        }
        .onChange(of: model.gitHistory?.repositoryURL) { _ in
            historyModel = nil
        }
        .onAppear {
            model.restoreRootFolderAtLaunch()
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
            historyModel = nil
            NSApp.keyWindow?.makeFirstResponder(nil)
            previewingDocumentURL = model.documentURL
        }
    }

    /// 编辑/历史双向切换：工具栏按钮。
    private func toggleHistory() {
        if isShowingHistory {
            historyModel = nil
        } else if let gitHistory = model.gitHistory {
            // 进入历史视图时刷新一次：重置浏览状态并拉取第一页。
            gitHistory.enterHistory()
            historyModel = gitHistory
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
            Text(model.rootNode == nil ? "打开一个文件夹开始" : "从左侧选择一个文件")
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
                // 超长行软换行（issue #48）：false 时内容随最长行横向扩展，溢出 UI 边界。
                wrapLines: true
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
