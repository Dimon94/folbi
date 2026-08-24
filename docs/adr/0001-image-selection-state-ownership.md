# 当前图片选中状态归工作区模型

Status: accepted

Related: #18、#20、repo://CONTEXT.md、repo://docs/research/2026-08-24-image-decoding-facts.md

## Context

图片预览（map #18）要求：文件树中选中 PNG/JPEG/GIF 图片时，内容区选中即显示图片面板（无 toggle），仅适应窗口。此前「文档（Document）」定义为当前选中的普通 UTF-8 文本文件，绑定编辑缓冲区、显式保存、脏检查与外部冲突检测一整套文本语义（repo://CONTEXT.md）。

已锁定的事实锚点：

- `documentURL` 是当前文档唯一身份；`save()` 无条件把编辑缓冲区写回 `documentURL`（repo://Folbi/WorkspaceModel.swift）。若让 `documentURL` 指向图片而缓冲区为空，⌘S 将把图片写成空文件。
- 打开入口、失败回滚树选中、脏检查守卫、FSEvents 外部修改检测四条链路现状全部在工作区模型（repo://Folbi/WorkspaceModel.swift、repo://Folbi/FolderTreeView.swift）。
- 预览开关是 ContentView 的视图层状态（repo://CONTEXT.md「预览模式」、repo://Folbi/ContentView.swift）。该归属成立的前提是预览不改变内容源 owner——预览内容源始终是编辑缓冲区。

未知项：图片格式白名单与大小上限（Unknown，归 #21）；图片面板行为细节（归 #23）。

## Decision

### 1. 图片不是文档

「文档」定义不扩展。选中图片时无当前文档：`documentURL = nil`，编辑缓冲区不参与。保存、脏检查、外部冲突检测语义零改动，`save()` 不存在触及图片文件的路径。被否方案：Document 泛化为「当前选中文件」（`documentURL` 指向图片）——保存、脏检查、冲突检测、状态栏、工具栏每个消费点都要加类型守卫，漏一处即毁图，违反 fail-closed；图片不复用文本语义的任何一条，收益为零。

### 2. 当前图片选中归工作区模型，形态为互斥字段

工作区模型持有当前图片，形态为与 `documentURL` 互斥的 URL 字段（`private(set)`，互斥由集中的打开/清空方法保证）。被否方案：状态留视图层（类比预览开关）——类比不成立，选中图片把内容区的内容源从编辑缓冲区换成图片文件本身，属模型层事实；视图层方案下打开路径分叉、FSEvents 对图片缺位（外部删除后面板悬空）、类型判断渗入树视图或 ContentView。被否形态：立即引入 selection 枚举——当前只有文档/图片两态，互斥字段满足需求且 `documentURL` 全部读写点零改动；第三种内容类型出现时再收枚举。

### 3. 分流点在 ContentView detail 原位展开三态

detail 区由「`documentURL` 非 nil 二选一」原位展开为三态：当前图片 → 图片面板（独立 View）；当前文档 → 编辑器栈；否则 → 空态。互斥不变量由模型层持有，视图照读，不重复投影为局部枚举（避免第二真相）。工具栏保存/主题按钮与预览 toggle 均以 `documentURL` 为条件，图片态自动不出现，零改动。

## Consequences

### 正面

- 打开、错误回滚、脏检查守卫三条链路对图片复用现状路径，不分叉。
- FSEvents 对图片可达（工作区模型持有当前图片）；外部改动首版不自动刷新、重新选中即最新（#23 裁决），本记录不承诺自动刷新。
- `save()` 永远无法写入图片文件（fail-closed）。
- 「图片面板」「当前图片」成为 canonical term（repo://CONTEXT.md）。

### 负面 / 成本

- 工作区模型公开合同扩大；「工作区模型」owner 定义加入当前图片。
- 互斥不变量靠集中方法维持而非类型系统；新增读写路径必须经过这些方法。

### 边界

- 本 ADR 冻结：Document 边界（图片非文档）、当前图片的状态归属（工作区模型）、detail 分流点位置。
- 本 ADR 不裁决：格式白名单与大小上限（#21）、图片面板行为细节（#23）、文件树图片图标区分。
- 未来出现第三种内容类型时，重新评估 selection 枚举化（实现演进，不必然 supersede 本记录）。
- 若图片获得编辑能力（批注、裁剪、写回），Document 边界与互斥语义需重审，立新 ADR supersede 本记录。
