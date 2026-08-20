# Issue tracker

本仓的代码和 issue 目标归个人 GitHub 仓库：

```text
https://github.com/Dimon94/folbi
```

远程仓库已创建（2026-08-20，public，MIT License），上述坐标是事实。

## 约定

- 建、评论、关闭 issue：优先使用 GitHub Web UI；任务明确授权自动化时使用 `gh`。
- 读、列 issue：按上述仓库坐标读取，并按 label 过滤。
- triage 标签：canonical 角色映射见 repo://docs/agents/triage-labels.md。
- PR 使用 `Closes #<number>` 关联修复。

## 阻断与依赖

阻断语义以 issue body 的 `Blocked by: #x #y` 为准。判断是否解除阻断时，回读被引用 issue 的 closed 状态。

## Wayfinding 编排

- map：一个带 `wayfinder:map` label 的 issue。
- 子 ticket：使用 `wayfinder:map-<number>` 和一个类型 label；body 首行写 `Map: #<number>`。
- 认领：添加 `wayfinder:claimed`；完成后写 resolution comment、关闭 issue，并更新 map。

## 程序化访问

只有任务明确授权远程写入时才使用 `gh`。创建仓库、issue、PR、label 或评论后必须回读目标确认；不要把命令退出码当成最终事实。
