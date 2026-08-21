# zTools

macOS 菜单栏 + 悬浮球 + 灵动岛效率工具：截图、OCR、剪贴板、笔记、AI 翻译、时间戳、取色。

> 原生 SwiftUI + AppKit · 最低 **macOS 15+** · Bundle ID `com.zeno.ztools`

---

## 功能一览

| 模块 | 能力 |
|------|------|
| **截图** | 选区 / 全屏 / 延时全屏 / 光标下窗口 / 上次区域 / 预设尺寸；十字线、窗口高亮、动作条；标注（矩形/箭头/画笔/高亮/马赛克/序号/文字）；钉图；圆角阴影（可选） |
| **OCR** | Vision 本地中英识别 → 复制 / 翻译 |
| **剪贴板** | 文本/图片历史、来源 App、置顶、搜索、⌘1–9 快贴、预览、一键翻译；敏感内容启发式跳过 |
| **翻译** | OpenAI 兼容 API（默认 DeepSeek）；划词翻译；连通性测试 |
| **时间戳** | Unix 秒/毫秒、多时区、代码片段（Swift/JS/Python…） |
| **笔记** | Markdown 文件（.md）；可配置目录；列表/搜索/置顶/预览；⌥N |
| **取色** | 系统取色器；HEX/RGB/HSL/CSS/SwiftUI/UIColor；历史色板 |
| **灵动岛** | 贴合刘海；收起两侧可配日历/时钟/农历/进度/电池/CPU 等；展开工具、应用列表、设备状态 |

---

## 交互形态

- **菜单栏**：功能入口（截图为子菜单）+ 设置  
- **悬浮球**：可拖动、边缘磁吸、贴边半透明、全屏可隐藏；单击功能网格  
- **灵动岛**：贴合硬件刘海；悬停或点击展开；可锁定；设置里配置左右翼  
- **命令面板**：⌥K，搜索功能与剪贴板  
- **全局快捷键**：默认 **⌥ + 单键**（见下表）

### 默认快捷键

| 功能 | 键 | 功能 | 键 |
|------|-----|------|-----|
| 选区截图 | ⌥A | OCR | ⌥O |
| 全屏 | ⌥F | 剪贴板 | ⌥V |
| 延时全屏 | ⌥D | 翻译 | ⌥T |
| 光标下窗口 | ⌥Z | 时间戳 | ⌥U |
| 上次区域 | ⌥X | 取色 | ⌥C |
| 预设尺寸 | ⌥G | 悬浮球 | ⌥B |
| 命令面板 | ⌥K | 划词翻译 | ⌥E |
| 笔记 | ⌥N | 灵动岛 | ⌥I |

可在 **设置 → 快捷键** 中修改或「恢复默认」。

---

## 环境要求

- macOS 15+  
- Xcode 16+（或 Xcode beta）  
- 本机若 Xcode 不在默认路径：

```bash
export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer
```

---

## 构建与安装（推荐）

**日常请只运行：**

```text
~/Applications/zTools.app
```

不要用 `build/` 目录里的副本当正式运行（会导致录屏/辅助功能权限异常）。

```bash
# 一键：Release 构建 + 签名 + 安装到 ~/Applications + 启动
./scripts/install-and-run.sh

# 打包 DMG 到 dist/
./scripts/package-release.sh
```

安装脚本会用 **Bundle ID 级 designated requirement** 签名，保证重建后权限尽量保持：

```bash
codesign --force --deep --sign - \
  --identifier "com.zeno.ztools" \
  -r='designated => identifier "com.zeno.ztools"' \
  "$HOME/Applications/zTools.app"
```

### 用 Xcode 打开

```bash
open zTools.xcodeproj
```

建议 Scheme 用 **Release**，并关闭 Debug dylib（`ENABLE_DEBUG_DYLIB=NO`），再手动拷到 `~/Applications` 并按上面方式签名。

---

## 权限说明

| 权限 | 用途 |
|------|------|
| **屏幕录制** | 截图、OCR 选区、取色 |
| **辅助功能** | 剪贴板模拟粘贴、划词翻译 |
| **网络** | AI 翻译 |
| **钥匙串** | 存储 API Key |

首次截图会触发录屏授权。若系统设置里已打开仍失败：

1. 确认运行的是 `~/Applications/zTools.app`  
2. 系统设置 → 隐私与安全性 → 录屏：删掉全部旧 zTools，只添加上述路径  
3. 完全退出 zTools 再打开  

应用内：**设置 → 权限** 有修复向导。  
**不要**每次安装都 `tccutil reset`，仅权限彻底损坏时使用。

翻译：在 **设置 → AI 翻译** 配置 Base URL / Model / API Key（默认 DeepSeek）。

---

## URL Scheme

```bash
open 'ztools://screenshot'          # 选区
open 'ztools://fullscreen'          # 全屏
open 'ztools://delay'               # 延时全屏
open 'ztools://window'              # 光标下窗口
open 'ztools://last'                # 上次区域
open 'ztools://preset'              # 预设尺寸
open 'ztools://ocr'
open 'ztools://clipboard'
open 'ztools://translate?text=hello'
open 'ztools://color'
open 'ztools://palette'             # 命令面板
open 'ztools://island'              # 显示/隐藏灵动岛
open 'ztools://settings'
open 'ztools://selection-translate'
```

可在快捷指令、Alfred、终端中调用。

---

## 截图小提示

- 选区：悬停高亮窗口 → **单击**截窗；**拖拽**选区域  
- 拖选松手后出现动作条：复制 / 编辑 / 钉图 / 保存 / OCR  
- 修饰键：⌘ 编辑 · ⌥ 保存 · ⇧ 钉图 · 双击复制  
- 设置 → 截图：模式快捷键 / 效果（十字线、阴影、圆角）/ 保存与默认动作  
- 默认关闭阴影与圆角以保持 Retina 清晰；需要可在设置打开  

---

## 项目结构

```
mac-tools/
├── AGENTS.md              # 给 Agent / 协作者的开发约定（必读）
├── README.md
├── scripts/
│   ├── install-and-run.sh
│   └── package-release.sh
├── zTools.xcodeproj/
└── zTools/
    ├── App/               # 入口、AppState、菜单栏
    ├── Core/              # 设置、热键、权限、存储
    ├── Features/          # 各业务功能
    ├── Overlay/           # 悬浮球、工具面板、命令面板、灵动岛
    ├── Services/          # AI、URL、剪贴板监听、更新检查
    └── Resources/
```

状态分发中心：`AppState.shared`。

---

## 版本

- 版本号见 `zTools/Info.plist`  
- 更新日志见应用内 **设置 → 关于**（`AppVersionInfo.changelog`）  
- 当前主线：**0.8.0**（界面重构：玻璃浮层与 Coral 强调色）

---

## 给开发者 / Agent

请先阅读 **[AGENTS.md](./AGENTS.md)**，其中包含：

- 签名与 TCC 铁律  
- UI 浮层（KeyablePanel、动作条线框等）踩坑  
- 快捷键方案版本与 `didSet` 陷阱  
- Retina 截图清晰度约定  
- 回归清单  

---

## License

Copyright © 2026 zeno. 仅供个人学习与使用。
