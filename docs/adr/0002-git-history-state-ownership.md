# Git 历史状态归 Git 历史模型，git CLI 走具体类型门面

Status: accepted

Related: #33、#34、#36、repo://CONTEXT.md、repo://docs/architecture/current-system-map.md、repo://docs/research/2026-08-24-git-library-selection.md、ADR 0001

## Context

Wayfinder 地图 #33 要交付「Git 历史查看」spec：识别根文件夹所属 Git 仓库、仓库级提交历史、逐提交变更文件列表与逐文件差异，严格只读。#34 已定库选型为 git CLI 子进程封装（备选 SwiftGitX）。#36 需裁定 Git 会话状态（当前仓库、提交列表、选中提交、差异）的 canonical owner、git CLI 的 seam 形状、与既有模块的依赖方向和测试面。

已锁定的事实锚点：

- `WorkspaceModel`（repo://Folbi/WorkspaceModel.swift）是工作区状态与磁盘写副作用的唯一 owner，已 485 行，混合状态持有、NSAlert、文件 IO 与 FSEvents。
- ADR 0001 把当前图片选中放进 WorkspaceModel 的核心理由是复用打开、错误回滚、脏守卫三条链路。Git 会话状态与保存、脏检查、外部冲突检测零交互，无链可复用。
- 代码库无任何既有 Git 功能代码；`FolbiApp` 以 `WorkspaceModel.shared` 单例为唯一 composition root。
- 既有测试先例：模型层测试用真实临时目录（repo://FolbiTests/FolbiCoreTests.swift）；内容 fixture 落 `FolbiTests/Fixtures/`。
- 实测（2026-08-24，本机 git 2.50.1）：`git diff-tree` 对合并提交默认输出为空（`-p` 与 `--name-status` 均空），需 `-m`/`--first-parent` 等。合并提交的差异语义不归本 ADR，已在 #33 Not yet specified 记为 spec 待裁定项。

## Decision

### 1. Git 会话状态归新模块 Git 历史模型，不归 WorkspaceModel

新建 `GitHistoryModel`（`@MainActor ObservableObject`）作为 Git 会话状态（当前仓库、提交列表分页、选中提交、选中提交的差异）的唯一 owner。WorkspaceModel 只在 `openRootFolder` 时重建它并持有实例句柄（`gitHistory: GitHistoryModel?`，根文件夹不在仓库中时为 nil），不持有任何 Git 状态字段。UI 经 `model.gitHistory` 观察。

被否方案 A（扩展 WorkspaceModel，沿 ADR 0001 先例）：ADR 0001 的论证基础是链路复用，Git 状态与保存/脏检查/冲突零交互，先例不适用；合入会让已最大的文件再长一个内聚子系统，并稀释「磁盘副作用唯一 owner」不变量。被否方案 B'（FolbiApp/ContentView 层持兄弟节点）：把组装逻辑散进视图层，与单例 composition root 格局相悖。

不变量修订：「WorkspaceModel 是工作区状态与磁盘写副作用的唯一 owner；Git 会话状态归 Git 历史模型，只读且无磁盘副作用」（已同步 current-system-map.md 与 CONTEXT.md「工作区模型」）。

### 2. 依赖方向四条边

- 引用方向：WorkspaceModel → GitHistoryModel 单向持有；GitHistoryModel 不反向引用，唯一输入是打开时传入的根文件夹 URL 值。仓库识别自根文件夹向上（`git rev-parse --show-toplevel`），仓库顶层可能是根文件夹的祖先。
- 刷新时机：`openRootFolder` 重建；FSEvents 不触发 Git 状态自动刷新（沿用 ADR 0001 对图片外部改动的先例：重新进入即最新）。
- 与文件树：零改动，文件树不读 Git 状态、不显示 Git 标记（#33 已把工作区未提交状态划出范围）。
- 与编辑缓冲区：零交互；选中提交/查看差异不改变当前文档与当前图片；差异面板内容源是 Git 历史模型的差异模型，不是编辑缓冲区的投影。

### 3. git CLI 隔具体类型薄门面，不引 protocol

新建具体类型门面（工作名 `GitRepositoryReader`，实现票定名）。公开 interface 仅四个只读方法，签名示意：

- `repositoryTopLevel(of dir: URL) -> URL?`（nil = 非仓库）
- `commits(in repo: URL, skip: Int, maxCount: Int) throws -> [Commit]`
- `changedFiles(of sha: String, in repo: URL) throws -> [FileChange]`
- `patch(of sha: String, path: String?, in repo: URL) throws -> Patch`

实现藏进程起停（`Process` + 参数数组，不走 shell 字符串插值）、NUL 切分、退出码映射。解析层为纯函数（stdout Data + exit code → 领域模型），独立可测；进程执行器是门面的内部 seam（注入函数值测错误路径），不进公开 interface。

被否方案（protocol + DI 预留换 SwiftGitX）：单适配器是假想 seam（codebase-design：两个适配器才是真 seam）；未来真要换库时，具体类型的公开方法签名本身就是 seam，调用点不动。被否方案（GitHistoryModel 直接起进程）：模型混进程与解析细节，解析逻辑无法脱离真实仓库测试。

Git 域错误自立 `GitError` 枚举（git 不可用 / 非仓库 / 解析失败），不进文档域的 `FolbiError`。

### 4. 测试面三层

- 解析层：canned git 输出单测为主——短小样本内嵌字符串字面量，超长 patch 样本落 `FolbiTests/Fixtures/` 沿用现有先例。覆盖 NUL 边界、根提交全 A、重命名/复制状态、中文/空格/换行文件名（`-z` 不转义）、分页边界、退出码 128 → 非仓库、解析失败。
- 门面层：少量集成测试——setUp 在临时目录脚本化构建真实仓库（git init + 固定 author/date 提交），断言识别、分页、文件列表与 patch 各一两条；错误路径（exit 128、git 不可用）用内部注入执行器测。
- GitHistoryModel 层：沿用 FolbiCoreTests 真实临时目录模式，直接对临时真实仓库做集成式测试，不为模型层再造 seam。

被否方案（签入嵌套 .git fixture 仓库）：git 套 git 需改名或打包，维护成本高。已知代价：测试依赖本机 git（目标用户即开发者，风险低；#34 实测进程开销约 8.6 ms/次可忽略）。

## Consequences

### 正面

- 「磁盘副作用唯一 owner」不变量保持强度：Git 链路零磁盘写。
- Git 历史模型与门面各自独立可测；解析层脱离真实仓库。
- 未来换库（SwiftGitX）或加写操作时，门面 interface 与 Git 历史模型的归属不变，改动局部化。

### 负面 / 成本

- WorkspaceModel 公开合同多一个 `gitHistory` 句柄与重建逻辑；多一个模块文件。
- 「工作区模型」与系统地图不变量的定义已改口径（分域表述）。
- 临时仓库集成测试依赖本机 git，未来 CI 环境需保证 git 可用。

### 边界

- 本 ADR 冻结：Git 会话状态的归属（决策 1）、四条依赖边（决策 2）、seam 形状（决策 3）、测试面分层（决策 4）。
- 本 ADR 不裁决：UX 方向与入口、合并提交差异语义、门面内部命令拼装细节、类型命名（Commit/FileChange/Patch/门面的代码级名称）、合并/未跟踪文件等展示语义——均归 spec 票（#37）。
- 未来出现 Git 写操作（#33 Out of scope 之外）时，只读边界与本记录的磁盘副作用口径需重审，立新 ADR supersede 或并列。
