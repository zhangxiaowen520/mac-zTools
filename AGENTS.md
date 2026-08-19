# AGENTS.md — zTools 开发指南

给后续 Agent / 协作者的快速上手说明。改代码前请先读完本文。

---

## 1. 项目是什么

**zTools**：macOS 菜单栏 + 悬浮球效率工具（原生 SwiftUI + AppKit）。

| 能力 | 说明 |
|------|------|
| 截图 | 多模式选区/全屏/延时/窗口/上次区域/预设尺寸 + 标注编辑 + 动作条 |
| OCR | Vision 本地识别，可转翻译 |
| 剪贴板 | 历史、置顶、⌘1-9、来源 App |
| 翻译 | OpenAI 兼容 API（默认 DeepSeek） |
| 时间戳 | 多格式 / 时区 / 代码片段 |
| 取色 | 系统取色器 + 历史色板 + 多格式导出 |

- **产品名**：zTools  
- **Bundle ID**：`com.zeno.ztools`  
- **最低系统**：macOS 15+  
- **技术**：Swift 5/6、SwiftUI、AppKit、ScreenCaptureKit、Vision、Carbon 热键  

---

## 2. 目录结构

```
mac-tools/
├── AGENTS.md                 # 本文
├── README.md
├── scripts/
│   ├── install-and-run.sh    # 推荐：Release 构建 + 安装到 ~/Applications
│   └── package-release.sh    # 打 DMG
├── zTools.xcodeproj/
└── zTools/
    ├── App/                  # 入口、AppState、菜单栏
    ├── Core/                 # 设置、热键、权限、剪贴板存储
    ├── Features/             # Screenshot / OCR / Clipboard / Translate / Timestamp / ColorPicker / Settings
    ├── Overlay/              # FloatingBall / ToolPanel / CommandPalette
    ├── Services/             # AI、URLRouter、Pasteboard、UpdateChecker
    ├── Resources/Assets.xcassets
    ├── Info.plist
    └── zTools.entitlements   # 非沙盒 + network.client
```

核心状态机：`AppState.shared`（`@MainActor`）。新功能优先挂到 `ToolAction` + `handle(_:)`，不要另起全局单例散落逻辑。

---

## 3. 构建与安装（必读）

### 3.1 唯一正确安装路径

```text
~/Applications/zTools.app
```

**禁止**把 `build/Build/Products/.../zTools.app` 当日常运行副本。  
TCC（录屏/辅助功能）绑定路径 + 签名；多副本会导致「设置里已开权限仍失败」。

### 3.2 推荐命令

```bash
# 本机若 Xcode 在非标准路径：
export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer

./scripts/install-and-run.sh
# 或打包：
./scripts/package-release.sh
```

### 3.3 签名要求（权限稳定性）

安装后必须用 **Bundle ID 级 designated requirement** 签名，不要用默认 CDHash-only ad-hoc：

```bash
codesign --force --deep --sign - \
  --identifier "com.zeno.ztools" \
  -r='designated => identifier "com.zeno.ztools"' \
  "$HOME/Applications/zTools.app"
```

验证：

```bash
codesign -d -r- "$HOME/Applications/zTools.app"
# 期望：designated => identifier "com.zeno.ztools"
```

### 3.4 构建注意

- 用 **Release + `ENABLE_DEBUG_DYLIB=NO`**：Debug dylib 壳会导致 TCC 身份不稳。  
- `ENABLE_HARDENED_RUNTIME=NO`（本地 ad-hoc 开发）。  
- 新增 `.swift` 文件后，若工程是手写/脚本生成的 `pbxproj`，需把文件加入 target（或重跑生成脚本），否则编译不到。  
- 改完建议：`xcodebuild ... Release` → 拷到 `~/Applications` → 上述 `codesign` → `open`。

### 3.5 不要每次 reset TCC

`install-and-run.sh` **不要**默认 `tccutil reset`。只有权限彻底坏掉时才手动：

```bash
tccutil reset ScreenCapture com.zeno.ztools
# 辅助功能无对应 reset 时：系统设置里删掉 zTools 再重新添加路径
```

---

## 4. 权限

| 权限 | 用途 | 检测 |
|------|------|------|
| 屏幕录制 | 截图 / OCR 选区 / 取色像素 | `SCShareableContent` 实测，勿只信 `CGPreflight` |
| 辅助功能 | 模拟 ⌘V、划词 | `AXIsProcessTrusted` + `probeAccessibility()`，ad-hoc 易误报 |
| 网络 | 翻译 API | Keychain 存 API Key |
| 钥匙串 | API Key | `KeychainStore` |

设置页有「录屏修复向导 / 辅助功能修复」。改权限后通常要 **完全退出再开**。

粘贴：`AppState.previousApp` 记录焦点 App → 关面板 → `activate` → 延迟 ⌘V。不要粘到 zTools 自己身上。

---

## 5. UI / 窗口铁律

### 5.1 需要输入的浮层必须能成为 Key

Borderless `NSPanel` 默认 `canBecomeKey == false`，TextField 无法输入。

```swift
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

`ToolPanelController`、`CommandPaletteController`、截图动作条等需要键盘的面板都用它。

### 5.2 禁止用「整窗可拖」抢走点击

```swift
panel.isMovableByWindowBackground = false
```

拖动请做在标题栏 `DragGesture` 上（见 `ToolPanelChrome`）。

### 5.3 浮层视觉

- 工具面板：无系统标题栏，自定义 chrome，避免红绿灯漂在内容外。  
- 截图动作条：**关闭 `panel.hasShadow`**，阴影只画在 SwiftUI 胶囊上，否则会出现「矩形线框」。  
- 不要用透明 `Button("") + keyboardShortcut(.defaultAction)` 当隐藏回车键，系统会显示成 `...`。  
- 菜单栏 / 悬浮球菜单：展示 `KeyChord.displayString`，并随设置更新。

### 5.4 Retina 截图清晰度

- 捕获：`SCStreamConfiguration` 按 `backingScaleFactor` 设像素宽高；`NSImage` 用 point size + 完整像素 rep（`RetinaImage`）。  
- **禁止**对 Retina 图随便 `lockFocus()` 再导出（会掉到 1x 变糊）。圆角/阴影用 `RetinaImage.render`。  
- 选区 rect 做像素对齐（`RetinaImage.alignRect`）。  
- PNG 导出取最高分辨率 `NSBitmapImageRep`。  
- 默认阴影/圆角建议关；需要再在设置打开。

---

## 6. 截图模块约定

入口：`ScreenshotService.capture(_ mode:)` → `CaptureResult` → `AppState.handleCaptureResult`。

| 模式 | ToolAction / URL |
|------|------------------|
| 选区 | `.screenshot` / `ztools://screenshot` |
| 全屏 | `.screenshotFullscreen` / `fullscreen` |
| 延时全屏 | `.screenshotDelay` / `delay` |
| 光标下窗口 | `.screenshotWindow` / `window` |
| 上次区域 | `.screenshotLastRegion` / `last` |
| 预设尺寸 | `.screenshotPreset` / `preset` |

选区 HUD：

- 十字线、窗口悬停高亮、单击截窗、拖选区域。  
- 拖选松手 → 动作条（复制/编辑/钉图/保存/OCR/取消）。  
- 修饰键：⌘ 编辑 · ⌥ 保存 · ⇧ 钉图 · 双击复制。  
- 截图前隐藏悬浮球，避免入镜。  
- 捕获前等几十毫秒，确保 overlay 已消失。

标注：箭头要大号实心三角 + 加粗箭身（见 `AnnotationCanvas`）。

设置：`ScreenshotSettings.shared` + 设置页「截图」三分段（模式快捷键 / 效果 / 保存与动作）。

---

## 7. 快捷键

- 全局热键：Carbon `HotKeyManager`（`@MainActor`），回调里回主线程。  
- 默认方案：**⌥ + 单键**（两键），见 `SettingsStore.defaultHotKeys`。  
- 方案版本：`currentHotKeysScheme`（当前为 3）。改默认布局时 **必须 +1**，否则老用户不会迁移。  
- **坑**：`init` 里给属性赋值 **不会** 触发 `didSet`。迁移后要 **手动** `defaults.set(encoded, forKey:)`，不能只靠 `didSet { saveHotKeys() }`。  
- 录制 UI：`HotKeyRecorderModel`（`ObservableObject`）持有 monitor，不要把 `NSEvent` monitor 放进 `@State`。  
- 不要在 SwiftUI `onAppear` 里同步 `reloadHotKeys()`（易闪退）；修改后 `DispatchQueue.main.async { reloadHotKeys() }`。

当前默认（摘要）：

| 功能 | 键 |
|------|-----|
| 选区/全屏/延时/窗口/上次/预设 | ⌥A / ⌥F / ⌥D / ⌥Z / ⌥X / ⌥G |
| OCR / 剪贴板 / 翻译 / 时间戳 / 取色 | ⌥O / ⌥V / ⌥T / ⌥U / ⌥C |
| 悬浮球 / 命令面板 / 划词译 | ⌥B / ⌥K / ⌥E |

---

## 8. URL Scheme

`Info.plist` → `CFBundleURLTypes` → `ztools://`

```bash
open 'ztools://screenshot'
open 'ztools://fullscreen'
open 'ztools://translate?text=hello'
open 'ztools://palette'
open 'ztools://settings'
```

处理入口：`AppDelegate.application(_:open:)` → `URLRouter.handle`。

---

## 9. 常见坑速查

| 症状 | 原因 | 处理 |
|------|------|------|
| 录屏开关开了仍无权限 | 多路径副本 / CDHash 签名 | 只用 `~/Applications/zTools.app` + identifier DR 签名；必要时删 TCC 项重加 |
| 辅助功能开了仍显示未授权 | `AXIsProcessTrusted` 误报；init 后未重启 | `probeAccessibility`；完全退出重开；路径一致 |
| 面板无法输入 | Panel 不能 key / 整窗可拖 | `KeyablePanel`；`isMovableByWindowBackground = false` |
| 剪贴板粘到 zTools | 未恢复前台 App | `capturePreviousApp` + 延迟 ⌘V |
| 快捷键改了不生效 | scheme 已升但 hotKeys 未写入 | init 末尾手动 save；升 `currentHotKeysScheme` |
| 设置「快捷键」闪退 | onAppear 同步重注册 Carbon | 去掉 onAppear reload；异步 reload |
| 动作条出现 `...` | 隐藏 default Button | 禁止该模式；回车走 keyMonitor |
| 动作条外矩形线框 | 窗口 hasShadow + 透明底 | `hasShadow = false`，阴影只在胶囊 |
| 截图发糊 | lockFocus 1x / 亚像素 | RetinaImage 路径；默认关阴影圆角 |
| 悬浮球右键泄漏 | onAppear 重复 addMonitor | monitor 由 Controller 持有并成对 remove |
| 菜单点了没反应 | global monitor 点在菜单上也 dismiss | 点击坐标在 menu/ball frame 内则忽略 |

---

## 10. 版本与文档

- 版本号：`zTools/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion`  
- 更新说明：`AppVersionInfo.changelog`（设置 → 关于）  
- 发版后同步改：`Info.plist`、`AppVersionInfo`、`README.md`、必要时 `currentHotKeysScheme`  

当前版本以 Info.plist 为准（开发中约 0.6.x）。

---

## 11. 产品迭代方向（摘要）

已完成大致：0.1 MVP → 0.2 标注/钉图/关于 → 0.3 剪贴板+翻译闭环+命令面板 → 0.4 URL/打包 → 0.5 对标 iShot 截图模式与 HUD → 0.6 笔记 Markdown。

后续可考虑（未做或仅部分）：

- 长截图 / 多窗口截图 / 带壳模板深化  
- 贴图缩放透明度管理  
- Developer ID 公证 + Sparkle  
- 快捷键冲突检测  
- 英文 String Catalog  

新需求优先服务主链路：**看到 → 截清 → 标注 → 识字 → 翻译 → 贴上**。

---

## 12. Agent 工作流建议

1. 改前：读本文件 + 相关 Feature 目录。  
2. 改中：遵循现有命名与 `AppState` 分发；UI 对齐现有材质/圆角语言。  
3. 改后：Release 编译；装到 `~/Applications`；identifier DR 签名；手动点关键路径（截图动作条、翻译输入、设置快捷键页）。  
4. 权限/热键/浮层类改动：重点回归第 9 节坑表。  
5. 用户说「没生效」时：先查是否跑了旧路径 app、`defaults read com.zeno.ztools`、签名 DR，再查逻辑。  

---

## 13. 用户偏好（本仓库）

- 产品中文 UI。  
- 快捷键偏好 **两键（⌥+字母）**，少用三键。  
- 截图体验对标 **iShot**（模式矩阵、动作条、设置三分页）。  
- 不要默认每次 reset 权限。  
- 提交前不主动 git commit，除非用户明确要求。  
