# 只读 Git 历史查看：开源库选型调研（issue #34）

日期：2026-08-24
范围：libgit2 系 Swift 绑定（SwiftGit2、SwiftGitX）、git CLI 子进程封装、其他纯 Swift 替代品；只评估三项只读能力（仓库发现、commit log 遍历分页、单提交文件列表与逐文件 diff）。
方法：GitHub API/仓库页面（commits、releases、LICENSE、Package.swift 与源码原文）+ libgit2 官方头文件注释 + git 官方文档（git-scm 与 git/git 仓库 Documentation 原文）+ 本机运行实测（macOS 26.5.1，git 2.50.1 Apple Git-155）。核查日期均为 2026-08-24。

## 摘要

1. **推荐 git CLI 子进程路线**：三能力全覆盖、零新增依赖、零许可证纠缠；官方承诺 plumbing 接口稳定，用自定义 `--format` + `-z` NUL 分隔可得机器可解析输出。生态先例：CodeEdit 主 app 全部 Git 功能即走此路（无 git 库依赖）。
2. **备选 SwiftGitX（ibrahimcetin/SwiftGitX）**：2025 年活跃开发，MIT，原生 SPM 精确锁定（libgit2 以源码 target 编入，无需 cmake）；三能力 API 齐全，但根提交 diff 疑似缺陷、仓库发现不向上查找，且携带 libgit2 许可证灰色地带（见下）。
3. **SwiftGit2 官方仓库不适合 Folbi**：master 无 Package.swift，构建需 cmake/autotools，最新 release 停在 0.6.0（2019-05-24）；Swift 层只暴露文件级 delta，无逐行 diff API。
4. **许可证灰色地带如实呈现**：libgit2 本体是 GPLv2 with Linking Exception。例外条款允许把编译后的库链入组合产物并自由分发，但「排除 copyleft」这一硬约束是否触线需读者判定；git CLI 走进程边界，无链接关系（GPL 不沿进程边界传染——推断，通行解释）。
5. **无活跃纯 Swift 实现**：Git2Swift（2016）、swift-git（2023）、SwiftGit3（2022）、Gift（2016，作者自荐改用 SwiftGit2）、ObjectiveGit（2021，Obj-C、无 SPM）均已停更。

## 1. 候选清单与逐项对比

| 候选 | 维护活跃度 | 许可证 | SPM 支持 | 三能力覆盖 |
| --- | --- | --- | --- | --- |
| **git CLI 子进程** | git 上游持续发布；macOS 26.5.1 实测自带 2.50.1（Apple Git-155） | git 为 GPLv2，但独立子进程无链接关系（推断） | 无需依赖 | ①向上发现 ✓ ②log+分页 ✓ ③文件列表+逐文件 diff ✓ |
| **SwiftGitX 0.4.0** | 最近 commit 2025-12-01；release 0.4.0（2025-12-01）；159 stars | 绑定层 MIT；内嵌 libgit2 = GPLv2+链接例外 | 原生 Package.swift；依赖 ibrahimcetin/libgit2 exact 1.9.2（源码编译，无需 cmake） | ①不向上查找，半覆盖 ②lazy Sequence ✓ ③changes+patches ✓，但根提交 diff 疑似缺陷、无原始 patch 文本导出 |
| **SwiftGit2（官方）** | 最近 commit 2025-09-23（dependabot），最近实质修复 2025-04-29（Xcode 16）；最新 release 0.6.0（2019-05-24） | 绑定层 MIT；内嵌 libgit2 = GPLv2+链接例外 | 无 Package.swift（master 与 release-2.0 分支均无）；需 cmake/libssh2/autoconf 等 | ①不向上查找，半覆盖 ②lazy Iterator ✓ ③仅文件级 delta，无逐行 diff，半覆盖 |
| ObjectiveGit | 最近 commit 2021-05-07 | MIT | 无 SPM（Carthage/手工） | Obj-C 绑定，不予评估 |
| Git2Swift / swift-git / SwiftGit3 / Gift / light-tech SwiftGit2 fork | 停更于 2016/2023/2022/2016/2021 | Apache-2.0 / NOASSERTION / MIT / MIT / MIT | 部分有，均陈旧；light-tech fork 仅声明 iOS 平台 | 不予评估 |

关键来源：SwiftGit2 仓库文件清单与 release 见 https://github.com/SwiftGit2/SwiftGit2（API 抓取）；SwiftGitX 见 https://github.com/ibrahimcetin/SwiftGitX；各停更库活跃度见第 5 节来源。

## 2. 路线一：libgit2 系 Swift 绑定

### 2.1 libgit2 本体事实

- 许可证：GPLv2 with Linking Exception。COPYING 例外条款原文："In addition to the permissions in the GNU General Public License, the authors give you unlimited permission to link the compiled version of this library into combinations with other programs, and to distribute those combinations without any restriction coming from the use of this file." 同文件注明："The General Public License restrictions do apply in other respects; for example, they cover modification of the file, and distribution when not linked into a combined executable." 来源：https://raw.githubusercontent.com/libgit2/libgit2/main/COPYING
- 即：静态/动态链接进 app 二进制分发，受例外条款豁免；修改 libgit2 源码本身仍受 GPL 约束。「GPL 家族许可证 + 链接例外」是否算触线「排除 copyleft」，由决策人判定。
- 上游活跃：最新 release v1.9.7（2026-08-13）。来源：https://github.com/libgit2/libgit2/releases
- 三能力对应的真实 C API（逐函数从头文件注释核实）：
  - 仓库发现：`git_repository_open_ext(git_repository **out, const char *path, unsigned int flags, const char *ceiling_dirs)`——默认从 start_path 向上走父目录查找，`GIT_REPOSITORY_OPEN_NO_SEARCH` 禁止向上，`GIT_REPOSITORY_OPEN_CROSS_FS` 允许跨文件系统；`git_repository_discover(git_buf *out, const char *start_path, int across_fs, const char *ceiling_dirs)`——"The lookup start from base_path and walk across parent directories if nothing has been found"。注意 `git_repository_open` 不向上查找。来源：https://raw.githubusercontent.com/libgit2/libgit2/main/include/git2/repository.h
  - log 遍历：`git_revwalk_new` / `git_revwalk_push_head` / `git_revwalk_next`（返回 0 或 GIT_ITEROVER）；`git_revwalk_sorting` 接受 GIT_SORT_NONE（注释原文"reverse chronological order. This is the default sorting for new walkers"）、GIT_SORT_TOPOLOGICAL、GIT_SORT_TIME、GIT_SORT_REVERSE。分页=随时停止迭代并 `git_revwalk_free`。来源：https://raw.githubusercontent.com/libgit2/libgit2/main/include/git2/revwalk.h
  - 单提交 diff：`git_commit_tree` 取树；`git_diff_tree_to_tree(diff, repo, old_tree, new_tree, opts)`——"equivalent to `git diff <old-tree> <new-tree>`"，"You can pass NULL to indicate an empty tree"（根提交老树传 NULL，两树不可同 NULL）；文件列表 `git_diff_num_deltas` + `git_diff_get_delta`；逐文件 patch `git_patch_from_diff(&patch, diff, idx)`，结构化遍历 `git_patch_num_hunks` / `git_patch_get_hunk` / `git_patch_get_line_in_hunk`，原始文本 `git_patch_to_buf`（"Get the content of a patch as a single diff text"）；整 diff 文本 `git_diff_print` + `GIT_DIFF_FORMAT_PATCH`。来源：https://raw.githubusercontent.com/libgit2/libgit2/main/include/git2/diff.h 与 .../include/git2/patch.h

### 2.2 SwiftGit2（github.com/SwiftGit2/SwiftGit2）

- 维护：master 最近 commit 2025-09-23（dependabot 升 CI），最近实质修复 2025-04-29「Fix build with XCode 16 (#216)」；最新 release 0.6.0（2019-05-24），release 断档 6 年。来源：https://github.com/SwiftGit2/SwiftGit2/commits/master 与 /releases
- 许可证：MIT（绑定层）。来源：https://github.com/SwiftGit2/SwiftGit2（license API: MIT）
- SPM 集成：**master 根目录无 Package.swift**（仓库文件清单：SwiftGit2.xcodeproj、Cartfile、External/ 与 libgit2/ 子模块；release-2.0 分支同样无）。README 安装路径为 Carthage 或 submodule + Xcode 工程；构建前置工具原文："cmake, libssh2, libtool, autoconf, automake, pkg-config"。来源：https://raw.githubusercontent.com/SwiftGit2/SwiftGit2/master/README.md 与仓库 contents API
- 真实 Swift API（以源码为准）：
  - 打开/校验：`Repository.at(_ url: URL)` 内部调 `git_repository_open`（**不向上查找父目录**）；`Repository.isValid(url:)` 调 `git_repository_open_ext` + `GIT_REPOSITORY_OPEN_NO_SEARCH`（**只认精确目录**）。来源：SwiftGit2/Repository.swift 第 125-137、939-956 行
  - log：`commits(in branch:)` / `commits(from base: OID)` 返回 `CommitIterator`（IteratorProtocol + Sequence，内部 revwalk，排序 GIT_SORT_TOPOLOGICAL | GIT_SORT_TIME，惰性，随时停=分页）。来源：SwiftGit2/CommitIterator.swift、Repository.swift 第 573/581 行
  - diff：`diff(for commit: Commit)` 处理了根提交（`diff(from: nil, to:)`）与 merge（`git_diff_merge` 合并各 parent），但返回的 `Diff` 只有 `deltas: [Delta]`（status/oldFile/newFile）；**Diffs.swift 全文无 patch/hunk/line API**（grep 实证）。逐行 diff 需越过 Swift 层直接调 Clibgit2。来源：SwiftGit2/Repository.swift 第 707 行起、SwiftGit2/Diffs.swift
- 结论：无官方 SPM、构建链重、release 断档、逐文件 diff 半覆盖。不满足「SPM 精确锁定」偏好，排除。

### 2.3 SwiftGitX（github.com/ibrahimcetin/SwiftGitX）

- 维护：最近 commit 2025-12-01；release 0.4.0（2025-12-01）、0.3.0（2025-11-29）、0.2.0（2025-11-25）、0.1.10（2025-11-23），2025-08 起活跃迭代；159 stars / 28 forks。来源：https://github.com/ibrahimcetin/SwiftGitX（releases/commits API）
- 许可证：MIT（绑定层）。来源：https://github.com/ibrahimcetin/SwiftGitX（license API: MIT）
- SPM 集成：原生 Package.swift（swift-tools 5.7），平台 macOS 10.15 / iOS 13 / tvOS 13 / watchOS 6 / visionOS 1 起；依赖 `.package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2")`。来源：https://raw.githubusercontent.com/ibrahimcetin/SwiftGitX/main/Package.swift
- libgit2 提供方式：ibrahimcetin/libgit2 是上游 fork，SwiftPM 清单只挂在 tag 上（1.8.0/1.9.1/1.9.2；main 分支无 Package.swift）。tag 1.9.2 的 Package.swift 把 libgit2 作为 C target 从源码编译：vendored deps（llhttp/pcre/xdiff/zlib/ntlmclient），Apple 平台用 CommonCrypto 做 hash，SSH 走 `GIT_SSH_EXEC`（调系统 ssh 命令）；产物 `.library(name: "libgit2")`。**无需 cmake**；Folbi 侧可额外声明 `.product(name: "libgit2", package: "libgit2")` 直接 import C API 补足绑定缺口。来源：https://github.com/ibrahimcetin/libgit2（contents API，ref=1.9.2 的 Package.swift 第 229-245 行）
- 真实 Swift API（以源码为准）：
  - 打开：`Repository.open(at: URL)` 与 `Repository(at: URL, createIfNotExists:)` 均调 `git_repository_open`——**不向上查找父目录**；源码树 grep 无 discover 包装。子目录发现需自行上溯或 `import libgit2` 调 `git_repository_discover`。来源：Sources/SwiftGitX/Repository/Repository.swift 第 33-58、176-203 行
  - log：`repo.log(sorting:)` / `log(from:)` 返回 `CommitSequence`（Swift `Sequence`，惰性 revwalk 包装，提前 break=分页；`LogSortingOption` 映射 GIT_SORT_NONE/TIME/TOPOLOGICAL/REVERSE）。`Commit` 模型含 id、author、committer（Signature: name/email/date/timezone）、message、summary、body、date、parents。来源：Sources/SwiftGitX/Repository/Repository+log.swift、Sequences/CommitSequence.swift、Objects/Commit.swift、Models/Options/LogSortingOption.swift
  - diff：`repo.diff(commit:)` → `Diff`，含 `changes: [Delta]`（文件列表+状态）与 `patches: [Patch]`（Patch=hunks，Hunk=header+lines，结构化逐行）。实现细节：`Diff.init` 对每个 delta 立即 `git_patch_from_diff`，属一次性全量物化。**疑似缺陷**：`diff(commit:)` 对无 parent 的根提交走 `diff(from: commit, to: commit)`，自比得空 diff（推断：根提交文件列表会丢；集成时需实测，绕法为直接调 `git_diff_tree_to_tree` 传 NULL 老树）。另有 `patch(from oldBlob:to newBlob:)` 做 blob 对 patch；未见 `git_patch_to_buf` 的原始文本导出包装。来源：Sources/SwiftGitX/Repository/Repository+diff.swift、Models/Diff/Diff.swift、Models/Diff/Patch.swift、Repository/Repository+patch.swift
- 结论：三能力基本齐备且纯 SPM 锁定，是绑定路线唯一可用候选；注意根提交 diff 与仓库发现两个缺口及 libgit2 许可证灰色地带。

## 3. 路线二：git CLI 子进程封装（基准线）

### 3.1 三能力真实命令与官方依据

1. **仓库发现/识别**：`git -C <dir> rev-parse --show-toplevel`（在仓库子目录时输出顶层绝对路径）或 `--is-inside-work-tree`（"print 'true', otherwise 'false'"）。
   - `-C <path>` 官方定义："Run as if git was started in '<path>' instead of the current working directory"。来源：https://raw.githubusercontent.com/git/git/master/Documentation/git.adoc
   - `--show-toplevel` 官方定义："Show the (by default, absolute) path of the top-level directory of the working tree"。来源：https://raw.githubusercontent.com/git/git/master/Documentation/git-rev-parse.adoc
   - 退出码语义：官方文档只说非仓库时 "fatal error"，未写死数值；本机实测非仓库目录返回 exit=128，stderr "fatal: not a git repository (or any of the parent directories): .git"；仓库子目录 exit=0 并输出顶层路径（macOS 26.5.1，git 2.50.1 实测）。
2. **commit log 遍历与分页**：`git -C <dir> log --format='<占位符>' -z --max-count=N --skip=M`。
   - 占位符官方定义：%H commit hash、%h 缩写、%s subject、%an author name、%ae author email、%aI "author date, strict ISO 8601 format"、%aD RFC2822、%cn committer name。来源：https://git-scm.com/docs/git-log（PRETTY FORMATS）
   - `tformat:` vs `format:` 官方原文："The `tformat:` format works exactly like `format:`, except that it provides 'terminator' semantics instead of 'separator' semantics. In other words, each commit has the message terminator character (usually a newline) appended, rather than a separator placed between entries." 来源：https://raw.githubusercontent.com/git/git/master/Documentation/pretty-formats.adoc 第 394-400 行
   - `-z` 官方原文（log 族）："Separate the commits with NULs instead of newlines. Also, when --raw or --numstat has been given, do not munge pathnames and use NULs as output field terminators." 来源：https://raw.githubusercontent.com/git/git/master/Documentation/diff-options.adoc 第 306-315 行
   - `--max-count` "Limit the output to the first <number> commits"；`--skip` "Skip <number> commits before starting to show the commit output"（Commit Limiting）。来源：https://git-scm.com/docs/git-log
   - 本机实测：`--format='%H%x00%an%x00%ae%x00%aI%x00%s' -z` 输出字段按 NUL 分隔、记录按 NUL 分隔（od 验证）；`--skip=2 --max-count=2` 分页正确。
3. **单提交文件列表与逐文件 diff**：`git -C <dir> diff-tree -r --no-commit-id --name-status <sha>`（列表）与 `git -C <dir> diff-tree -r --no-commit-id -p <sha>`（逐文件 patch），根提交加 `--root`。
   - `--root` 官方原文："When --root is specified the initial commit will be shown as a big creation event. This is equivalent to a diff against the NULL tree."
   - `--no-commit-id`："git diff-tree outputs a line with the commit ID when applicable. This flag suppresses the commit ID output."
   - `--name-status`："Show only the name(s) and status of each changed file."；`-r` "Recurse into sub-trees."；`-p` "Generate patch."；`-z`："do not munge pathnames and use NULs as output field terminators."
   - 来源：https://git-scm.com/docs/git-diff-tree
   - 本机实测：根提交（Folbi 仓库 51dc27b）`diff-tree --root -r --name-status` 全列 `A` 状态；普通提交（a62e4bd）列 `M/A` 状态正确；不带 `--no-commit-id` 时首行确为 commit id。

### 3.2 输出解析脆弱性评估

- **官方稳定性立场**（git(1) 原文）："The interface (input, output, set of options and the semantics) to these low-level commands are meant to be a lot more stable than Porcelain level commands, because these commands are primarily for scripted use. The interface to Porcelain commands on the other hand are subject to change in order to improve the end user experience." 来源：https://git-scm.com/docs/git
- 推论：`diff-tree`、`rev-parse`、`rev-list` 是 plumbing，输出稳定；`log` 名义上是 porcelain，但自定义 `--format=<占位符>` 的输出由调用方完全定义（推断：占位符语义属文档化合同，风险集中在默认 pretty 格式，不用默认格式即规避）。
- **NUL 分隔**：字段内含换行/任意字符时，`%x00` 字段分隔 + `-z` 记录分隔可无损切分（实测）；文件名用 `-z` 避免 core.quotePath 转义（diff-options.adoc 同节注明 "Without this option, pathnames with 'unusual' characters are quoted"）。
- **本地化**：git 人类可读消息可随 gettext 本地化；本机 Apple Git 在 `LC_ALL=de_DE.UTF-8` / `zh_CN.UTF-8` 下 fatal 消息仍为英文（实测，单一构建证据）。其他构建（如 Homebrew git）可能本地化（推断）。对策：只解析退出码与机器格式，绝不匹配人类消息文本。
- **git 来源差异**：`/usr/bin/git` 是 Xcode CLT shim，版本随用户 Xcode/CLT 而变；用户 PATH 里可能有更新的 Homebrew git。本机实测 `/usr/bin/git` 与 `xcrun git` 均 2.50.1（Apple Git-155），PATH 首项为 /usr/local/bin/git。只读三命令用到的选项（rev-parse/log --format/-z/--skip/diff-tree --root）为十年以上历史的稳定接口（推断），版本漂移风险低；如需下限可钉 `git version` 探测。
- **进程开销与大仓库**：本机实测 30 次 `git rev-parse` 连发总耗时 0.257 s（≈8.6 ms/次）。log 整史为单次进程 + git 自身 C 速 revwalk + 管道解析，1 万提交量级为一次流式输出（推断：解析成本线性且低，瓶颈在 UI 侧物化数量；可用 --max-count 分页控制）。

### 3.3 生态先例：CodeEdit 主 app 走 git CLI

- CodeEdit（Folbi 复用其 CodeEditSourceEditor 的上游主 app）`CodeEdit.xcodeproj/project.pbxproj` 的 17 个 SPM 远程依赖中**无任何 git 库**（无 SwiftGit2/SwiftGitX）。来源：https://github.com/CodeEditApp/CodeEdit（project.pbxproj 原文 grep）
- 其 Git 实现为 `CodeEdit/Features/SourceControl/Client/GitClient.swift` + `CodeEdit/Utils/ShellClient/Models/ShellClient.swift`：经 `/bin/zsh -lic "cd <dir>;git <cmd>"` 起子进程，读 stdout 字符串解析。commit 历史命令原文：`log --no-merges -z --pretty=%h¦%H¦%s¦%aN¦%ae¦%cn¦%ce¦%aD¦%b¦%D¦ -n <count> ...`，按 `\0` 与 `¦` 切分。来源：https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/SourceControl/Client/GitClient+CommitHistory.swift
- 注：CodeEdit 用 zsh 登录交互壳拼字符串命令是脆弱写法（注入与环境噪声面大）；Folbi 若走此路应直接 `Process` 起 git 二进制 + 参数数组 + NUL 格式（推断，属实现建议）。

## 4. 路线三：其他纯 Swift 库与绑定现状

| 库 | 最近活动 | 许可证 | 备注 | 来源 |
| --- | --- | --- | --- | --- |
| damicreabox/Git2Swift | pushed 2016-10-13 | Apache-2.0 | 停更 | github.com/damicreabox/Git2Swift |
| sharplet/swift-git | pushed 2023-06-23 | NOASSERTION（许可证不明） | 21 stars，停更 | github.com/sharplet/swift-git |
| joehinkle11/SwiftGit3 | pushed 2022-05-29 | MIT | 59 stars，停更 | github.com/joehinkle11/SwiftGit3 |
| modocache/Gift | pushed 2016-09-13 | MIT | README 自荐改用 SwiftGit2 | github.com/modocache/Gift |
| libgit2/objective-git | 最近 commit 2021-05-07 | MIT | Obj-C，无 SPM（Carthage/手工） | github.com/libgit2/objective-git |
| light-tech/SwiftGit2 | pushed 2021-05-28 | MIT | SPM fork，但平台仅声明 iOS 13、依赖 branch 锁定的 Clibgit2，停更 | github.com/light-tech/SwiftGit2 |

结论：无活跃纯 Swift Git 实现；Unknown：是否存在 2025-2026 新出现的玩具级实现（搜索未见成气候者）。

## 5. 推荐与备选

### 推荐：git CLI 子进程封装

正面回应三条硬约束：

1. **只读**：三命令（rev-parse / log / diff-tree）全为读操作，天然满足。
2. **非 copyleft**：git 二进制是 GPLv2，但作为独立子进程执行不产生链接关系，GPL 不沿进程边界传染（推断，通行解释）；不引入任何库依赖，无组合产物问题。
3. **SPM 精确锁定偏好**：该偏好以「事实持平时」为前提——此路线无需锁定任何依赖，优于需要锁定的方案。

落地 API 路径（真实命令）：

- 仓库发现：`Process` 执行 `git -C <dir> rev-parse --show-toplevel`，exit 0 + 输出路径即在仓库内（自动向上查找）；exit 128 即非仓库。
- log 分页：`git -C <dir> log --format='%H%x00%an%x00%ae%x00%aI%x00%s' -z --max-count=N --skip=M`，按 NUL 切记录与字段。
- 单提交文件列表：`git -C <dir> diff-tree -r --no-commit-id --root --name-status -z <sha>`。
- 单提交逐文件 diff：`git -C <dir> diff-tree -r --no-commit-id --root -p <sha>`（或按需对单文件追加 `-- <path>`）。

附加优势：零依赖符合 Folbi 最小依赖原则（图片解码调研同口径拒绝第三方播放器）；生态先例 CodeEdit 全量 Git 功能走此路；不沙盒化可直接起子进程。

已知代价：每次查询一个进程（实测 ≈8.6 ms）；需自写解析层（约百行量级，NUL 切分无歧义）；用户机器 git 版本不可控（风险低，用钉版本探测兜底）。

### 备选：SwiftGitX 0.4.0

- 许可证：绑定层 MIT；内嵌 libgit2 为 GPLv2 with Linking Exception（例外条款原文见 §2.1）——链接进 app 分发获例外豁免，但「GPL 家族」是否触线由决策人判定。
- SPM：`.package(url: "https://github.com/ibrahimcetin/SwiftGitX.git", exact: "0.4.0")`，其 libgit2 依赖同为 exact 1.9.2 源码编译，无需 cmake。
- 获取「单提交逐文件差异」的具体 API 路径：`let diff = try repo.diff(commit: commit)` → `diff.changes`（`[Diff.Delta]`，文件列表+状态）与 `diff.patches`（`[Patch]`，`Patch.hunks` → `Hunk.lines` 结构化逐行）。缺口：根提交疑似返回空 diff（§2.3，需实测）、仓库发现不向上查找（自行上溯后 `Repository.open(at:)`，或 `import libgit2` 调 `git_repository_discover`）、无原始 unified diff 文本导出（需自行从 hunks/lines 重组或直调 `git_patch_to_buf`）。
- 选用场景：未来需要写操作（stage/commit/branch）或进程内高频查询时，再评估切换；届时其写 API（commit/checkout/push 等）已就绪。

### 明确排除

- SwiftGit2 官方：无 SPM、构建链重、release 断档 6 年、无逐行 diff Swift API。
- ObjectiveGit / Git2Swift / swift-git / SwiftGit3 / Gift / light-tech fork：停更或平台不符。

## 6. 测试缺口与剩余风险

- SwiftGitX 根提交 diff 空结果与 `Diff.init` 全量物化的性能，均为源码阅读结论（推断），未实测。
- git CLI 在 1 万+ 提交仓库的端到端耗时未实测（仅测得进程开销 ≈8.6 ms/次）；分页后首屏成本可控（推断）。
- Apple Git 之外的构建（Homebrew/自编译）消息本地化行为未实测；按「只解析退出码与机器格式」对策可免疫（推断）。
- 未评估 git 不存在于用户机器的极端情形（CLT 未装时 /usr/bin/git 为触发安装 shim——推断；Folbi 目标用户为开发者，风险低）。

## 来源清单

一手来源（核查日期 2026-08-24）：

- libgit2 许可证原文：https://raw.githubusercontent.com/libgit2/libgit2/main/COPYING
- libgit2 官方头文件（API 注释即官方文档）：
  - https://raw.githubusercontent.com/libgit2/libgit2/main/include/git2/repository.h
  - https://raw.githubusercontent.com/libgit2/libgit2/main/include/git2/revwalk.h
  - https://raw.githubusercontent.com/libgit2/libgit2/main/include/git2/diff.h
  - https://raw.githubusercontent.com/libgit2/libgit2/main/include/git2/patch.h
- libgit2 releases：https://github.com/libgit2/libgit2/releases（v1.9.7，2026-08-13）
- git 官方文档：
  - https://git-scm.com/docs/git（plumbing/porcelain 稳定性立场）
  - https://git-scm.com/docs/git-log（占位符、--max-count/--skip）
  - https://git-scm.com/docs/git-diff-tree（--root/--name-status/--no-commit-id/-z）
  - https://raw.githubusercontent.com/git/git/master/Documentation/git.adoc（-C）
  - https://raw.githubusercontent.com/git/git/master/Documentation/git-rev-parse.adoc（--show-toplevel/--is-inside-work-tree）
  - https://raw.githubusercontent.com/git/git/master/Documentation/pretty-formats.adoc（tformat/format 语义）
  - https://raw.githubusercontent.com/git/git/master/Documentation/diff-options.adoc（-z 定义，第 306-315 行）
- 候选库仓库与源码：
  - https://github.com/SwiftGit2/SwiftGit2（commits/releases/contents/license API；Repository.swift、CommitIterator.swift、Diffs.swift 原文）
  - https://raw.githubusercontent.com/SwiftGit2/SwiftGit2/master/README.md
  - https://github.com/ibrahimcetin/SwiftGitX（releases/commits/license API；Repository.swift、Repository+log.swift、Repository+diff.swift、Repository+patch.swift、CommitSequence.swift、Diff.swift、Patch.swift、Commit.swift、LogSortingOption.swift 原文）
  - https://raw.githubusercontent.com/ibrahimcetin/SwiftGitX/main/Package.swift
  - https://github.com/ibrahimcetin/libgit2（tag 1.9.2 的 Package.swift）
  - https://github.com/libgit2/objective-git、https://github.com/damicreabox/Git2Swift、https://github.com/sharplet/swift-git、https://github.com/joehinkle11/SwiftGit3、https://github.com/modocache/Gift、https://github.com/light-tech/SwiftGit2（活跃度与许可证 API）
- 生态先例：
  - https://github.com/CodeEditApp/CodeEdit（project.pbxproj 依赖清单）
  - https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/SourceControl/Client/GitClient.swift
  - https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Features/SourceControl/Client/GitClient+CommitHistory.swift
  - https://github.com/CodeEditApp/CodeEdit/blob/main/CodeEdit/Utils/ShellClient/Models/ShellClient.swift
- 本机运行证据：macOS 26.5.1（Darwin 25.5.0），git 2.50.1（Apple Git-155）；rev-parse 退出码、log -z NUL 输出、diff-tree --root、30 次进程连发 0.257 s；命令与结果见 §3.1/§3.2 各实测条目。
