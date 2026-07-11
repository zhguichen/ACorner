# RFC：一隅 ACorner 架构

## 目标与约束

应用是一个 macOS 14+ 原生 Swift Package。它以一个无边框、始终置顶的 `NSPanel` 承载 SwiftUI 视图：悬停不会激活其他窗口，用户主动准备输入时才激活面板并获取键盘焦点。

不引入网络、数据库或第三方依赖。所有计时状态依据真实 `Date` 计算，应用退出后仍能恢复。

## 分层

```text
App → Features/Timer → Domain
                  ↘ Services
```

- `App` 创建 `RecordStore`、`TaskSessionModel` 和浮窗控制器。
- `Domain` 只定义任务状态和可编码的数据模型。
- `Features/Timer` 负责状态转换、计时器、悬浮位置和 SwiftUI 呈现。
- `Services/RecordStore` 负责原生目录选择、书签保存和 JSON 文件读写。

## 状态机

`idle → countdown → waiting → overtime` 是主链路。`waiting` 最长十秒；用户完成后进入 `wrapUp`，用户切换下一任务则直接回到 `idle` 并保留分钟数。

每次状态刷新比较 `Date()` 与 `plannedEndsAt`：计划结束前为 `countdown`，结束后十秒内为 `waiting`，之后为 `overtime`。因此暂停 UI 刷新、应用短暂挂起或重启不会篡改实际时长。

## 存储

`UserDefaults` 保存圆点位置、草稿、未完成任务和记录文件夹书签。任务完成时，`RecordStore` 把全部完成记录写入用户所选文件夹的 `ACornerTasks.json`，日期使用 ISO 8601，按开始时间倒序。备注修改会覆盖同一 `id` 的记录。

JSON 是刻意选择：第一版数据量小、用户可直接查看和备份，并避免引入额外数据库迁移。

## 窗口与交互

面板依据圆点所在屏幕的可用区域选择左右展开方向；上下空间不足时调整卡片相对位置，但圆点本身保持固定。展开后的卡片只在用户点击外部区域时收起。圆点用单一手势区分点击和拖动，防止拖动结束触发卡片展开。

## 后续演进边界

若将来增加历史浏览，应新建 `Features/History` 并由服务层提供只读记录查询；不要让历史 UI 直接解析文件。若存储格式变更，需要先设计迁移与备份策略，并更新本 RFC 和测试文档。
