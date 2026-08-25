# Git 只读能力走 git CLI 子进程，不引绑定库

Status: accepted

Related: #33、#34、#37、repo://docs/research/2026-08-24-git-library-selection.md、ADR 0002

## Context

Wayfinder 地图 #33 建图时的措辞是「选型开源库」，评估范围为 libgit2 系 Swift 绑定、git CLI 子进程封装、其他纯 Swift 库三路，约束为：严格只读、排除 copyleft（GPL/LGPL）、事实持平时偏好可 SPM 精确锁定的库。#34 调研（repo://docs/research/2026-08-24-git-library-selection.md，macOS 26.5.1 + git 2.50.1 实测）后需裁定最终路线。

候选事实摘要：

- **git CLI 子进程**：三项只读能力（仓库发现、log 分页、单提交文件列表与逐文件 diff）用稳定 plumbing 命令全覆盖；零新增依赖；git 二进制为 GPLv2，但作为独立子进程执行无链接关系。生态先例：CodeEdit 主 app 全部 Git 功能走此路。
- **SwiftGitX 0.4.0**：绑定层 MIT，原生 SPM 精确锁定；但仓库发现不向上查找、根提交 diff 疑似缺陷（源码阅读结论，未实测），且内嵌 libgit2 为 GPLv2 with Linking Exception——「GPL 家族 + 链接例外」是否触线「排除 copyleft」存在灰色地带。
- **SwiftGit2 官方及其余纯 Swift 库**：无 SPM、release 断档六年或停更，已在 #34 明确排除。

## Decision

Git 只读能力走 **git CLI 子进程封装**：`Process` 直起 git 二进制 + 参数数组（不走 shell 字符串插值），自定义 `--format` + `-z` NUL 分隔取机器可解析输出，只解析退出码与机器格式、绝不匹配人类消息文本。落地命令路径：

- 仓库发现：`git -C <dir> rev-parse --show-toplevel`（exit 0 + 输出顶层路径即在仓库内，自动向上查找；exit 128 即非仓库）。
- log 分页：`git -C <dir> log --format='%H%x00%an%x00%ae%x00%aI%x00%s' -z --skip=M --max-count=N`。
- 单提交文件列表与逐文件 diff：`git -C <dir> diff-tree -r --no-commit-id --root --name-status -z <sha>` 与 `... -p <sha>`（可按需追加 `-- <path>` 取单文件）。

**备选 SwiftGitX 0.4.0**：未来需要写操作或进程内高频查询时再评估切换；届时经 ADR 0002 冻结的门面 seam（GitRepositoryReader 四只读方法）局部化改动，解析层整体作废重写。

许可证判定（显式风险接受）：git 二进制虽为 GPLv2，走进程边界不产生链接关系，GPL 不沿进程边界传染（推断，通行解释）；不引入任何库依赖，无组合产物问题。

「事实持平时偏好 SPM 精确锁定」约束的适用说明：该偏好以事实持平为前提；git CLI 路线无需锁定任何依赖，优于需要锁定的方案，不构成对偏好的违反。

## Consequences

### 正面

- 零新增依赖，符合最小依赖原则；无许可证纠缠。
- 三能力全覆盖，命令均为十年以上历史的稳定接口；plumbing 输出稳定性有官方立场背书。
- 换库路径已被 ADR 0002 的门面 seam 局部化。

### 负面 / 成本

- 需自写解析层（约百行量级，NUL 切分无歧义），测试面按 ADR 0002 三层执行。
- 每次查询一个进程（实测 ≈8.6 ms/次，可忽略）。
- 用户机器 git 版本与构建来源不可控（/usr/bin git 为 Xcode CLT shim；Homebrew git 可能本地化人类消息）；按「只解析退出码与机器格式」对策免疫，残余风险低（目标用户为开发者）。

### 边界

- 本 ADR 冻结：路线选择（git CLI 子进程）与许可证风险接受。
- 本 ADR 不裁决：seam 形状与状态归属（ADR 0002 已冻结）、UX 与行为细则（spec #37 收口）。
- 未来引入 Git 写操作或改用绑定库时，立新 ADR supersede。
