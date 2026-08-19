import AppKit
import CodeEditSourceEditor
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel

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
                EditorPane(model: model, documentURL: documentURL)
                    .id(documentURL)
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

private struct EditorPane: View {
    @ObservedObject var model: WorkspaceModel
    let documentURL: URL

    @Environment(\.colorScheme) private var colorScheme
    @State private var editorState = SourceEditorState()

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()

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
