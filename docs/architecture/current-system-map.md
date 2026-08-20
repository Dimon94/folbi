# Current System Map

Status: active

## 当前事实

- 产品：Folbi，个人使用的 macOS 轻量文件夹编辑器；仓库、Xcode 工程、scheme 和 Swift 模块保留 `FolderPad`。
- 平台：macOS 13+；Swift 5 语言模式；SwiftUI + AppKit。
- 编辑器：CodeEditSourceEditor 0.15.2，经 Swift Package Manager 精确锁定。
- 入口：`FolderPadApp` 的单窗口 SwiftUI scene。
- 本地运行：`script/build_and_run.sh` 统一执行关闭旧进程、构建和启动；`.codex/environments/environment.toml` 将 Codex `Run` 动作指向该脚本。
- 持久状态：用户打开的本地文件；应用不维护数据库或配置服务。
- 权限边界：首版为未沙盒化本地应用，直接访问用户选择的根文件夹。
- 外部系统：无。GitHub 远程仓库和 CI 尚未创建。

## 链路

    用户 -> ContentView / FolderTreeView -> WorkspaceModel -> FileManager / FSEvents -> 本地文件夹
                              |
                              +-> EditorPane -> CodeEditSourceEditor -> CodeEditLanguages

## 模块

| Module | Owns | Does not own | Public interface | Verification |
| --- | --- | --- | --- | --- |
| `WorkspaceModel` | 根文件夹、当前文档、编辑缓冲区、保存和冲突裁决 | 编辑器渲染 | 用户动作方法与可观察状态 | `FolderPadCoreTests` + app build |
| `FileNode` | 一个目录的惰性子节点快照 | 全局选择、磁盘写入 | `loadChildren`、`refreshLoadedSubtree` | `FolderPadCoreTests` |
| `FolderTreeView` | `NSOutlineView` 展示和右键菜单 | 文件树真相 | SwiftUI representable | app build / 手工交互 |
| `ContentView` / `EditorPane` | 窗口布局、工具栏和编辑器绑定 | 磁盘状态 | SwiftUI views | app build / 手工交互 |
| `EditorThemes` | 三个主题到编辑器主题结构的映射 | 文档内容 | `EditorThemes.theme` | app build |

## 不变量

- 文件树不隐藏点文件，只加载已展开目录，并让文件夹排在文件之前。
- 只编辑普通 UTF-8 文本文件；单文件不超过 5 MiB。
- 不静默丢弃未保存修改，也不静默覆盖外部修改。
- `WorkspaceModel` 是状态和磁盘副作用的唯一 owner；UI 与编辑器只是投影。
- 符号链接目录不按目录递归，避免循环遍历。

## 验证

稳定构建和测试命令见根 repo://AGENTS.md。本地启动检查使用 `./script/build_and_run.sh --verify`。当前核心测试覆盖隐藏文件、排序、大小上限和新建名称校验；编辑器交互仍需手工 smoke test。

## PROTOCOL

根合同变化时同步更新 repo://CONTEXT.md、根 repo://AGENTS.md 和本文件。难回退且存在真实取舍的决定另写 repo://docs/adr/。
