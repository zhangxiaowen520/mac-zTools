import Foundation

enum AppVersionInfo {
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.8.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "8"
    }

    static var displayVersion: String {
        "\(shortVersion) (\(build))"
    }

    static let productName = "zTools"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.zeno.ztools"
    static let copyright = "Copyright © 2026 zeno. All rights reserved."

    static let changelog: [(version: String, date: String, items: [String])] = [
        (
            "0.8.0",
            "2026-08-21",
            [
                "界面重构：玻璃浮层、Coral 强调色、统一 OverlayChrome 与设计 token",
                "翻译双栏、剪贴板置顶分节、OCR/取色/笔记布局重做",
                "截图动作条与倒计时改为玻璃；灵动岛纯黑贴刘海，tab 过渡动画",
                "设置窗毛玻璃背景；悬浮球菜单间距与描边修正"
            ]
        ),
        (
            "0.7.0",
            "2026-08-21",
            [
                "灵动岛：贴合刘海胶囊，收起两侧可配日历/时钟/农历/进度/电池/CPU 等",
                "展开：工具、系统应用列表、设备状态；锁定后保持展开",
                "悬停展开、触控板震动、按 tab 变高；设置独立「灵动岛」页",
                "快捷键 ⌥I；URL：ztools://island",
                "钥匙串改用 Data Protection，ad-hoc 重建后权限更稳"
            ]
        ),
        (
            "0.6.0",
            "2026-08-19",
            [
                "笔记：Markdown 文件存储，可配置目录，预览/编辑/置顶",
                "快捷键冲突检测；截图编辑草稿可续编",
                "OCR/取色隐藏悬浮球；多显示器坐标修正",
                "剪贴板图片独立落盘；选区窗口查询节流",
                "String Catalog 英文 locale；单元测试"
            ]
        ),
        (
            "0.5.0",
            "2026-08-10",
            [
                "截图模式：选区/全屏/延时/光标下窗口/上次区域/预设尺寸",
                "选区 HUD：十字线、窗口高亮、尺寸、完成后动作条",
                "默认动作与修饰键：⌘编辑 · ⌥保存 · ⇧钉图 · 双击复制",
                "导出圆角与阴影、截图声效",
                "设置截图三页：模式快捷键 / 效果 / 保存与动作"
            ]
        ),
        (
            "0.4.0",
            "2026-08-10",
            [
                "URL Scheme：ztools://screenshot|ocr|clipboard|translate|color|palette|settings",
                "取色：历史色板，导出 HEX/CSS/SwiftUI/UIColor",
                "时间戳：多格式代码片段、时区收藏",
                "关于页检查更新（内置 changelog / 可接 GitHub Releases）",
                "package-release 打包脚本"
            ]
        ),
        (
            "0.3.0",
            "2026-08-10",
            [
                "剪贴板：来源 App、键盘导航、⌘1-9 快贴、预览、一键翻译",
                "敏感内容启发式跳过（密码管理器 / concealed）",
                "划词翻译（⌘⇧E）与命令面板（⌘K）",
                "OCR / 剪贴板 → 翻译闭环",
                "翻译连通性测试与错误中文化",
                "悬浮球贴边半透明、全屏自动隐藏"
            ]
        ),
        (
            "0.2.0",
            "2026-08-10",
            [
                "截图编辑：马赛克、序号标记",
                "复制并关闭（⌘↩）作为默认完成动作",
                "钉图：截图置顶悬浮预览",
                "设置：关于页、权限修复向导",
                "悬浮球品牌 Logo 与无边框工具面板"
            ]
        ),
        (
            "0.1.0",
            "2026-08-10",
            [
                "菜单栏 + 悬浮球启动",
                "截图选区、标注、OCR、剪贴板、翻译、时间戳、取色",
                "DeepSeek / OpenAI 兼容翻译",
                "全局快捷键与设置窗口"
            ]
        )
    ]
}
