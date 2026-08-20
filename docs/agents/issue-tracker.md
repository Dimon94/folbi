# Issue tracker

本仓的代码和 issue 目标归个人 GitHub 仓库 `Dimon94/folbi`：

```text
https://github.com/Dimon94/folbi
```

远程仓库已创建（2026-08-20，public，MIT License），上述坐标是事实。

## 约定

- **建 issue**：走 GitHub Web UI；任务明确授权自动化时才用 `gh`。
- **读 issue**：按项目坐标打开对应 issue 页面。
- **列 issue**：项目 issue 列表按 label 过滤。
- **评论/关闭/打标**：用 GitHub issue 操作。
- **triage 标签**：五个 canonical 角色与本仓 label 的映射见 repo://docs/agents/triage-labels.md。
- **PR 关联修复**：PR 描述写 `Closes #<number>`。

## 当 skill 说 "publish to the issue tracker"

在本仓 issue tracker 创建 issue。

## 当 skill 说 "fetch the relevant ticket"

按编号打开 issue，读描述、labels 和评论。

## 阻断与依赖

阻断语义以 issue body 里的 `Blocked by: #x #y` 文字为准，平台原生链接只做导航。判断“是否解除阻断”要读被引用 issue 的状态是否 closed。

## Wayfinding 编排

/wayfinder 地图与 ticket 在 issue tracker 的表达约定：

- **map（地图）**：一个 issue，label `wayfinder:map`。
- **子 ticket**：普通 issue，label `wayfinder:map-<number>`（归属哪张图）+ `wayfinder:research|prototype|grilling|task`（类型）；body 首行写 `Map: #<number>`。
- **查某图的 frontier**：按 label `wayfinder:map-<number>` 过滤 open issue，再排除带 `wayfinder:claimed` 的、以及 body 中 `Blocked by` 未闭合的。阻断判定规则见上节。
- **认领**：会话开工前给 ticket 加 label `wayfinder:claimed`；做完在 resolution comment 写结论、close issue、回 map 的 Decisions-so-far 追加一行索引。
- `wayfinder:map-<number>` 标签随地图创建即时新建；静态标签（map/claimed/四种类型）在初始化时预建。

## 程序化访问

只有任务明确授权远程写入时才使用 `gh`。创建仓库、issue、PR、label 或评论后必须回读目标确认；不要把命令退出码当成最终事实。
