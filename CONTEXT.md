# Folbi Context

本文件保存项目统一语言。代码、测试、issue 和文档使用以下 canonical term。

## 使用规则

- 代码、测试、issue、ADR 和文档使用本文件定义的词。
- 一个概念只保留一个 canonical term。
- 新概念必须有运行证据、需求或 accepted ADR 支持。
- 需要区分近义词时，写清边界和 Avoid 列表。
- 不确定的定义标为 Unknown。不要提前固化。

## 产品边界

Folbi 是产品、仓库、Xcode 工程、scheme、Swift 模块和拟人 IP 的统一名称。

Folbi 是个人使用的 macOS 轻量文件夹编辑器。它打开一个本地文件夹，展示完整文件树，并编辑其中的 UTF-8 文本文件。

首版不提供 LSP、Git、终端、插件、自动保存或公开分发。不要把它描述为完整 IDE。

## 已确认词汇

**根文件夹（Root Folder）**
: 用户当前打开的唯一顶层文件夹。文件树和相对路径都以它为边界。

**文件树（File Tree）**
: 根文件夹的原生树状投影。按需读取已展开目录，不隐藏点文件，文件夹排在文件之前。

**文档（Document）**
: 当前选中的普通 UTF-8 文本文件。首版单文件上限为 5 MiB。

**编辑缓冲区（Edit Buffer）**
: 文档在内存中的可编辑文本。它只通过显式保存写回磁盘。

**未保存修改（Dirty Buffer）**
: 编辑缓冲区与最近一次磁盘载入或保存的内容不同。切换文档、根文件夹或退出前必须提示。

**外部修改冲突（External Conflict）**
: 文档在编辑缓冲区存在未保存修改时又被其他进程改动。保存前必须让用户选择覆盖、重新载入或取消。

**编辑器主题（Editor Theme）**
: 语法高亮与编辑区颜色组合。首版提供 Default、GitHub 和 Solarized，每套自带明暗两种配色，随外观模式切换。

**外观模式（Appearance Mode）**
: 应用界面的明暗外观设置：跟随系统、浅色或深色。选择持久化在 UserDefaults（键 `appearanceMode`），切换即时生效；编辑器主题随外观选用明或暗配色。

**工作区模型（Workspace Model）**
: 根文件夹、文件树、当前文档、编辑缓冲区和冲突状态的唯一 owner。

**Markdown 预览（Markdown Preview）**
: Markdown 文档的单面板渲染查看功能。渲染走 MarkdownUI（固定 .gitHub 主题）；只认 6 个扩展名（`md / mkd / mkdn / mdwn / mdown / markdown`，小写不敏感），无扩展名文件不启用；入口为工具栏 toggle 按钮与 View 菜单「切换预览」（⌘⇧V 单一绑定在菜单项上）。

**预览模式（Preview Mode）**
: 单面板下与编辑模式互斥的面板状态。内容源为编辑缓冲区（含未保存修改），进入时触发一次后台分块，Markdown 块按滚动懒渲染；预览期间不随编辑刷新。预览开关是 ContentView 的视图层状态，不进入工作区模型；切换文档时总是重置回编辑模式。

## Avoid

- 用“项目”指代 Root Folder。
- 用“自动保存”描述显式保存。
- 把文件树或编辑器控件当作磁盘状态 owner。
- 暗示首版具备完整 IDE 能力。
