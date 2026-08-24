# Current System Map

Status: active

## 当前事实

- 产品、仓库、Xcode 工程、scheme 和 Swift 模块：Folbi。
- 平台：macOS 13+；Swift 5 语言模式；SwiftUI + AppKit。
- 编辑器：CodeEditSourceEditor 0.15.2，经 Swift Package Manager 精确锁定。
- Markdown 渲染库：MarkdownUI 2.4.1，经 Swift Package Manager 精确锁定；传递依赖 NetworkImage、swift-cmark。
- 入口：`FolbiApp` 的单窗口 SwiftUI scene。
- 本地运行：`script/build_and_run.sh` 统一执行关闭旧进程、构建和启动；`.codex/environments/environment.toml` 将 Codex `Run` 动作指向该脚本。
- 持久状态：用户打开的本地文件；外观模式设置存于 UserDefaults（键 `appearanceMode`）；最近文件夹列表以标准化路径数组存于 UserDefaults（键 `recentFolderPaths`）；应用不维护数据库或配置服务。
- 权限边界：首版为未沙盒化本地应用，直接访问用户选择的根文件夹。
- 外部系统：GitHub 远程仓库 `Dimon94/folbi`（2026-08-20 创建，public，issue tracker 与 wayfinding 编排所在）；CI 尚未创建。

## 链路

    用户 -> ContentView / FolderTreeView -> WorkspaceModel -> FileManager / FSEvents -> 本地文件夹
                              |
                              +-> EditorPane -> CodeEditSourceEditor -> CodeEditLanguages
                              +-> ImagePanel（当前图片，内容源 = 图片文件） -> ImageOpenPolicy 判定 -> GIF 走 AnimatedImageView（NSImageView 包装，按帧时长播放）；其余格式走 ImageIO 降采样
                              +-> MarkdownPreviewView（预览模式，内容源 = 编辑缓冲区） -> FenceAwareChunker 分块（后台线程） -> 每块一个 MarkdownUI 视图（LazyVStack 懒渲染） -> PreviewImageProvider -> ImagePathResolver（本地）/ MarkdownUI 默认网络加载（http(s)）

## 模块

| Module | Owns | Does not own | Public interface | Verification |
| --- | --- | --- | --- | --- |
| `WorkspaceModel` | 根文件夹、最近文件夹、启动恢复、当前文档、当前图片、编辑缓冲区、选中分流、保存和冲突裁决 | 编辑器与图片渲染 | 用户动作方法（`openFile` 分流）与可观察状态 | `FolbiCoreTests`、`WorkspaceModelImageRoutingTests`、`WorkspaceModelRecentFoldersTests` + app build |
| `RecentFolderList` | 最近文件夹的路径标准化、MRU 去重、10 条上限、移除和清空 | 持久读写与根文件夹打开 | `record`、`remove`、`clear`、`paths` | `RecentFolderListTests` |
| `RecentFoldersStore` | UserDefaults 键 `recentFolderPaths` 的路径数组读写与损坏容错 | MRU 规则与工作区状态 | `load`、`save` | `RecentFoldersStoreTests` |
| `FileNode` | 一个目录的惰性子节点快照 | 全局选择、磁盘写入 | `loadChildren`、`refreshLoadedSubtree` | `FolbiCoreTests` |
| `FolderTreeView` | `NSOutlineView` 展示和右键菜单 | 文件树真相 | SwiftUI representable | app build / 手工交互 |
| `ContentView` / `EditorPane` | 窗口布局、工具栏、编辑器绑定、编辑/预览模式切换与预览状态、detail 三态分流（当前图片/当前文档/空态） | 磁盘状态、互斥不变量 | SwiftUI views | app build / 手工交互 |
| `MarkdownPreviewView` | Markdown 预览的分块懒渲染与「是否可预览」判定 | 磁盘状态、编辑缓冲区内容 | `MarkdownPreviewView`、`MarkdownPreviewability.isPreviewable` | `MarkdownPreviewabilityTests` + app build / 手工交互 |
| `FenceAwareChunker` | Markdown 源文本按顶层块边界的 fence 感知切分（纯函数） | 磁盘状态、缓冲区状态 | `FenceAwareChunker.split` | `FenceAwareChunkerTests` |
| `ImagePathResolver` | Markdown 本地图片路径的文档目录解析、根文件夹边界与可读性判定 | 网络加载、图片解码与渲染 | `ImagePathResolver.resolve` | `ImagePathResolverTests` |
| `ImageOpenPolicy` | 图片打开策略的内容白名单与 1 亿像素上限 | 图片解码、展示与选中分流 | `ImageOpenPolicy.evaluate` | `ImageOpenPolicyTests` |
| `ImagePanel` | 当前图片的 GIF 动画播放（`AnimatedImageView` 包装 `NSImageView`）、非 GIF 的 ImageIO 降采样、适应窗口布局与超限/解码失败占位 | 白名单与像素上限（复用 `ImageOpenPolicy`）、选中分流 | `ImagePanel`、`ImagePanel.load` | `ImagePanelTests` + app build / 手工交互 |
| `PreviewImageProvider` | 预览图片的本地、http(s) 与占位分支；本地图片解码 | 本地路径边界规则、远程网络传输 | `PreviewImageProvider.makeImage`、`PreviewImageProvider.classify` | `PreviewImageProviderTests` + app build / 手工交互 |
| `EditorThemes` | 三个主题到编辑器主题结构的映射 | 文档内容 | `EditorThemes.theme` | app build |
| `AppearanceMode` | 外观模式三态、到 `ColorScheme` 的映射和菜单展示名 | 具体配色（归 `EditorThemes`） | `AppearanceMode` enum | `AppearanceModeTests` |

## 不变量

- 文件树不隐藏点文件，只加载已展开目录，并让文件夹排在文件之前。
- 只编辑普通 UTF-8 文本文件；单文件不超过 5 MiB。
- 不静默丢弃未保存修改，也不静默覆盖外部修改。
- `WorkspaceModel` 是状态和磁盘副作用的唯一 owner；UI 与编辑器只是投影。
- 符号链接目录不按目录递归，避免循环遍历。

## 验证

稳定构建和测试命令见根 repo://AGENTS.md。本地启动检查使用 `./script/build_and_run.sh --verify`。当前核心测试覆盖隐藏文件、排序、大小上限、新建名称校验和外观模式映射；编辑器交互仍需手工 smoke test。

## PROTOCOL

根合同变化时同步更新 repo://CONTEXT.md、根 repo://AGENTS.md 和本文件。难回退且存在真实取舍的决定另写 repo://docs/adr/。
