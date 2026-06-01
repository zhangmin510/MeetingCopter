# MeetingCopter 调试回顾 · 2026-06-01

一次会话里连续修了三个 bug，每个都有"看代码以为对、实际跑起来错"的成分。记下来下次少踩。

环境：macOS 15+（内置 Retina 1728×1117 + ACER 外接 1920×1080，外接位于内置右侧、Cocoa frame `{{1728, 422}, {1920, 1080}}`）。Swift 6，纯 SwiftUI + AppKit。

---

## Bug 1 · 直升机不在屏幕中央，从右上角一闪而过

### 症状
点 Test 触发直升机动画，预期"从左飞到中、再到右"，实际几秒钟内从屏幕右上方掠过就消失。只在外接屏复现，内置屏正常。

### 根因
`HelicopterOverlay.show()` 里 flightPath 用的是 **屏幕坐标**：

```swift
let startX = screenFrame.minX - 280    // 屏幕原点偏移
let endX   = screenFrame.maxX + 360
let baseY  = screenFrame.midY
```

但绘制发生在 `contentView` 的 **view-local 坐标系**——origin 在 window 自己的左下角，跟 window 在桌面上的位置无关。两套坐标只有在屏幕原点 `(0, 0)` 时才相等。

- 内置屏：frame `{{0, 0}, {1728, 1117}}` → 屏幕坐标 == view-local，"凑巧"对了
- ACER：frame `{{1728, 422}, {1920, 1080}}` → 屏幕 `(2702, 962)` 被当成 view-local 来画，于是实际渲染到屏幕 `(2702 + 1728, 962 + 422) = (4430, 1384)`，向右越界、向上靠顶

### 证据（关键）
在 `show()` 和 `tick()` 里写文件日志（NSLog 默认 `<private>` 遮蔽），跑一次 Test：

```
window placed frame={{1728, 422}, {1920, 1080}} on screen=ACER
tick 0   anchor={1450.99, 962}   ← 起点
tick 840 anchor={3966.96, 962}   ← 终点
```

view-local anchor 起点 1450（panel 宽 1920，0..1920 才在屏内），1920 以外就飞出窗口。

### 修复
flightPath 改用 view-local（去掉屏幕原点偏移）：

```swift
let startX: CGFloat = -280
let endX   = screenFrame.width + 360
let baseY  = screenFrame.height / 2
```

commit: `571bc3c fix: use view-local coords for flight path so overlay centers on non-primary screens`

### 教训
**任何"在窗口里画东西"的代码都不能直接用 `NSScreen.frame.midY/midX`**。先想清楚目标坐标系（窗口 local vs 屏幕 global），用 `screenFrame.width/height` 而不是 `minX/maxX`，或显式 `convertFromScreen`/`convertToScreen`。在 origin = (0,0) 的主屏上凑巧对的代码，多屏下必翻车。

---

## Bug 2 · 日历提醒没触发

### 症状
日历里加了一个事件，应该提前 5 分钟弹直升机，没有任何反应。

### 根因（两层）

**表层**：调试时发现"刚才"那次错过提醒，是因为重启 app 周期里的某次窗口正好覆盖了那个事件的"5 分钟前"时刻，并且当时 `HelicopterOverlay` 还带着 Bug 1 的坐标错——飞机即使弹了也飞在外接屏顶端角落、几秒就出屏。

**深层 / 跨会话隐患**：`CalendarMonitor` 两处守卫都只比 `.authorized`：

```swift
} else if authorizationStatus == .authorized {
    startPolling()
}
// ...
guard authorizationStatus == .authorized else { return }
```

macOS 14+ 已弃用 `.authorized`，授权后系统返回 `.fullAccess`（rawValue 5）而不是 `.authorized`（rawValue 3）。一旦 app 在新系统上重启读到 `.fullAccess`，两条 guard 都不通过 → `startPolling()` 永远不调用 → 30s 轮询从来不开 → 永远不会触发。

授权回调里又硬编码 `authorizationStatus = granted ? .authorized : .denied`，让进程内状态与系统记录的真实值脱钩——bug 必在下次启动暴露。

### 证据
加一次性 wide-window dump（过去 2h / 未来 1h）：

```
requestAccess: initial status raw=0 (notDetermined)
requestAccess callback: granted=true
dumpWide: total calendars=3
  cal 'Calendar' source='Default' ...
  cal '中国大陆节假日' source='Subscribed Calendars' ...
  evt '教育数据QA评测' start=11:00:00 startsIn=-1489s endsIn=2110s
checkUpcomingEvents: event '教育数据QA评测' startsIn=-1489s willFire=false
```

事件 22 分钟前开始，远超 `(-30s, +5min]` 触发窗——错过的提醒确实在我们看不见的过去时刻被错过了。这次系统返回 raw=3 没踩 `.fullAccess` 的坑，但定时炸弹仍在。

### 修复
- 抽出 `hasReadAccess` 同时接受 `.authorized` 和 `.fullAccess`
- 两处守卫改用它
- 授权回调里 **回读系统状态** 而不是硬编码 `.authorized`
- macOS 14+ 改用 `requestFullAccessToEvents(completion:)`，老系统回退到 `requestAccess(to:)`

commit: `9c906fa fix: recognize .fullAccess so polling survives across app restarts on macOS 14+`

### 教训
- 「macOS 14+ 弃用 X、用 Y 替代」的编译 warning 不是噪音，是 ticking bomb——尤其涉及权限/auth/系统资源的 enum，弃用值和新值通常 **不相等**
- 用户报"东西没生效"时，先用 wide-window event dump 列出系统看到的所有相关数据，比一开始就猜原因快得多

---

## Bug 3 · 状态栏菜单浮窗离图标太远 / 替换实现后看不见

### 症状（一）
点菜单栏 ✈️ 图标，NSPopover 弹出位置离图标 ~30pt，"不符合常识"——典型菜单栏 app（Wi-Fi、电量）都是贴菜单栏的。

### 根因（一）
NSPopover 自带 ~12pt 箭头 + 上下边距，总间距固定 ~24-30pt。**没有公开 API 可去**——业内要么用私有 KVC `shouldHideAnchor`（脆弱），要么彻底换实现。

### 症状（二）—— 第一次替换尝试失败
换成自定义 borderless `NSPanel` + `NSVisualEffectView`（`layer.cornerRadius`）+ `NSHostingView`，点图标后日志显示 `visible=true key=true frame` 在状态栏下方正确位置，**用户屏幕上完全看不见任何东西**。

### 根因（二）
两个错叠加：
1. **`NSVisualEffectView` 用 `layer.cornerRadius + masksToBounds`** 会与 SwiftUI 内部 CALayer 层级冲突，在某些 macOS 14+ 子版本里让 SwiftUI 的 Text 完全不画（Image/Slider 还在，因为它们有自己的 intrinsic size 和独立 layer）。正确做法是 `NSVisualEffectView.maskImage = <带 capInsets 的圆角 NSImage>`
2. **panel 显示前没 commit 真实的 content size**：`NSHostingView` 在 borderless panel 里如果父容器没给宽度约束，SwiftUI Text 走"intrinsic 0 宽"路径不渲染（Image/Slider 因 intrinsic size 非 0 仍然画）

### 调研后的方案
派 agent 调研 2026 年通用做法，结论是抄 [Calendr](https://github.com/pakerwreah/Calendr/blob/master/Calendr/Components/Popover.swift) 和 [jordanbaird/Ice](https://github.com/jordanbaird/Ice/blob/main/Ice/UI/IceBar/IceBar.swift) 的模板：

| 部件 | 做法 |
|---|---|
| Panel | `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`、子类 override `canBecomeKey = true`、`canBecomeMain = false`、`level = .popUpMenu`、`backgroundColor = .clear`、`isOpaque = false`、`hasShadow = true` |
| 背景 | `NSVisualEffectView` material `.menu`、state `.active`、blending `.behindWindow`、**`maskImage` 圆角**（不要用 layer.cornerRadius） |
| SwiftUI 装载 | **`NSHostingController`**（不是 NSHostingView 直接装），用 controller.view 拿到 NSView 再 add 进 visualEffect，4 边 autolayout 撑满 |
| 尺寸 | show 时先 `controller.sizeThatFits(in: ...)` → `controller.preferredContentSize = size` → `panel.setContentSize(size)`，**然后才**定位 |
| 定位 | `button.window.convertToScreen(button.convert(button.bounds, to: nil))` → 中心对齐、0pt 贴底 |
| 关闭 | `NSEvent.addGlobalMonitorForEvents([.leftMouseDown, .rightMouseDown])` + `windowDidResignKey` 兜底，`hideMenu` 加 `guard isVisible` 防止重入 |

commit: 待提交

### 教训
- macOS 自定义状态栏浮窗的"行业最佳实践"是有具体模板的，先 30 分钟看 2-3 个活跃开源项目源码，能省 2 小时自己踩坑
- `NSVisualEffectView` 圆角必须 `maskImage`，不能 `layer.cornerRadius`——这是公开 docs 里没写、要看源码才知道的"民间知识"
- SwiftUI 嵌 AppKit 时，**优先 NSHostingController**（管 lifecycle 和 environment），NSHostingView 是 view-only、缺少 controller 的隐式约束

---

## 通用教训（meta）

1. **多屏 ≠ 主屏放大**：任何用 `NSScreen.frame.minX/midY/maxX` 的代码都要检查"如果原点不是 (0,0) 会怎样"。
2. **deprecation warning 不是噪音**：尤其权限/auth/系统资源 enum，弃用值与新值 **rawValue 不同**。
3. **NSLog `<private>` 遮蔽**：用 `os_log` 显式 `%{public}@` 或直接写文件，比 NSLog 上 Console 看 `<private>` 高效得多。
4. **端到端验证才算修了**：
   - 看代码能编译 ≠ 跑起来对
   - 跑起来不报错 ≠ 用户能看到
   - "panel 日志说 visible=true" ≠ "屏幕上真的有像素"
   - 验证流水线：(a) 编译过 → (b) app 内 `cacheDisplay` 快照确认 view-tree 在画 → (c) 全屏 `screencapture` 确认 compositor 真合成出来 → (d) 用户点交互 → 才能 claim done
5. **写诊断日志要尽早**：debug 前 5 分钟加 NSLog/文件日志，比靠肉眼推断快 10 倍。诊断代码在 commit 前清掉即可。
