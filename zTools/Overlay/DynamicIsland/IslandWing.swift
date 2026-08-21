import SwiftUI

enum IslandWingKind: String, CaseIterable, Identifiable {
    case none
    case network
    case lunar
    case weekdayDay
    case monthDay
    case weekday
    case clock
    case dayProgress
    case weekProgress
    case monthProgress
    case quarterProgress
    case yearProgress
    case battery
    case cpu
    case memory
    case disk

    var id: String { rawValue }

    static var selectable: [IslandWingKind] {
        allCases.filter { $0 != .none }
    }

    var title: String {
        switch self {
        case .none: "无"
        case .network: "网速"
        case .lunar: "农历"
        case .weekdayDay: "日历"
        case .monthDay: "日期"
        case .weekday: "星期"
        case .clock: "时钟"
        case .dayProgress: "日进度"
        case .weekProgress: "周进度"
        case .monthProgress: "月进度"
        case .quarterProgress: "季进度"
        case .yearProgress: "年进度"
        case .battery: "电池"
        case .cpu: "处理器"
        case .memory: "内存"
        case .disk: "磁盘"
        }
    }

    var needsLiveStats: Bool {
        switch self {
        case .network, .battery, .cpu, .memory, .disk: true
        default: false
        }
    }

    var accent: Color {
        switch self {
        case .dayProgress: Color(red: 1.0, green: 0.62, blue: 0.22)
        case .weekProgress: Color(red: 0.35, green: 0.82, blue: 0.42)
        case .monthProgress: Color(red: 0.35, green: 0.62, blue: 1.0)
        case .quarterProgress: Color(red: 0.95, green: 0.78, blue: 0.22)
        case .yearProgress: Color(red: 0.72, green: 0.48, blue: 0.95)
        case .battery: Color(red: 0.45, green: 0.88, blue: 0.55)
        default: .white
        }
    }
}

enum IslandWingData {
    static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    static func weekdayDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE d"
        return f.string(from: date)
    }

    static func monthDay(_ date: Date) -> (month: String, day: String) {
        let cal = Calendar.current
        return ("\(cal.component(.month, from: date))", "\(cal.component(.day, from: date))")
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func lunar(_ date: Date) -> (month: String, day: String) {
        var cal = Calendar(identifier: .chinese)
        cal.locale = Locale(identifier: "zh_CN")
        let c = cal.dateComponents([.month, .day, .isLeapMonth], from: date)
        let months = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        let m = max(1, min(c.month ?? 1, 12))
        let month = (c.isLeapMonth == true ? "闰" : "") + months[m - 1]
        return (month, lunarDay(c.day ?? 1))
    }

    static func lunarDay(_ day: Int) -> String {
        let n = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        switch day {
        case 1...10: return "初\(n[day - 1])"
        case 11...19: return "十\(n[day - 11])"
        case 20: return "二十"
        case 21...29: return "廿\(n[day - 21])"
        case 30: return "三十"
        default: return "\(day)"
        }
    }

    static func dayProgress(_ date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        return min(1, max(0, date.timeIntervalSince(start) / 86_400))
    }

    static func weekProgress(_ date: Date) -> Double {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        return min(1, max(0, date.timeIntervalSince(start) / (7 * 86_400)))
    }

    static func monthProgress(_ date: Date) -> Double {
        let cal = Calendar.current
        let days = Double(cal.range(of: .day, in: .month, for: date)?.count ?? 30)
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        return min(1, max(0, date.timeIntervalSince(start) / (days * 86_400)))
    }

    static func quarterProgress(_ date: Date) -> Double {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let qStartMonth = ((month - 1) / 3) * 3 + 1
        var comps = cal.dateComponents([.year], from: date)
        comps.month = qStartMonth
        comps.day = 1
        let start = cal.date(from: comps) ?? date
        var endComps = comps
        endComps.month = qStartMonth + 3
        let end = cal.date(from: endComps) ?? start.addingTimeInterval(90 * 86_400)
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / span))
    }

    static func yearProgress(_ date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year], from: date)) ?? date
        let days = Double(cal.range(of: .day, in: .year, for: date)?.count ?? 365)
        return min(1, max(0, date.timeIntervalSince(start) / (days * 86_400)))
    }
}

struct IslandWingView: View {
    let kind: IslandWingKind
    let date: Date
    @ObservedObject var stats: IslandStatsStore
    var compact = true

    var body: some View {
        Group {
            switch kind {
            case .none:
                Color.clear
            case .network:
                networkWing
            case .lunar:
                splitText(IslandWingData.lunar(date).month, IslandWingData.lunar(date).day, accentRight: true)
            case .weekdayDay:
                plain(IslandWingData.weekdayDay(date))
            case .monthDay:
                splitText(IslandWingData.monthDay(date).month + "/", IslandWingData.monthDay(date).day, accentRight: true)
            case .weekday:
                plain(IslandWingData.weekday(date))
            case .clock:
                analogClock
            case .dayProgress:
                progressWing(IslandWingData.dayProgress(date), kind.accent, mark: "日")
            case .weekProgress:
                progressWing(IslandWingData.weekProgress(date), kind.accent, mark: "周")
            case .monthProgress:
                progressWing(IslandWingData.monthProgress(date), kind.accent, mark: "月")
            case .quarterProgress:
                progressWing(IslandWingData.quarterProgress(date), kind.accent, mark: "季")
            case .yearProgress:
                progressWing(IslandWingData.yearProgress(date), kind.accent, mark: "年")
            case .battery:
                batteryWing
            case .cpu:
                iconPercent("cpu", stats.cpu, Color(red: 0.72, green: 0.55, blue: 1.0))
            case .memory:
                iconPercent("memorychip", stats.memoryRatio, Color(red: 0.45, green: 0.82, blue: 1.0))
            case .disk:
                iconPercent("internaldrive", diskRatio, Color.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diskRatio: Double {
        guard stats.diskTotal > 0 else { return 0 }
        return min(1, Double(stats.diskUsed) / Double(stats.diskTotal))
    }

    private var fontSize: CGFloat { compact ? 10 : 12 }
    private var miniSize: CGFloat { compact ? 8 : 9 }

    private func plain(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func splitText(_ left: String, _ right: String, accentRight: Bool) -> some View {
        HStack(spacing: 1) {
            Text(left)
                .foregroundStyle(.white)
            Text(right)
                .foregroundStyle(accentRight ? Color(red: 1.0, green: 0.38, blue: 0.35) : .white)
        }
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func progressWing(_ value: Double, _ color: Color, mark: String) -> some View {
        VStack(spacing: compact ? 2 : 3) {
            HStack(spacing: 2) {
                Text(mark)
                    .foregroundStyle(color)
                Text("\(Int((value * 100).rounded()))%")
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .font(.system(size: miniSize, weight: .semibold, design: .rounded))
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: compact ? 28 : 36, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: (compact ? 28 : 36) * value)
                }
        }
    }

    private func iconPercent(_ icon: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(Int((value * 100).rounded()))%")
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .font(.system(size: miniSize, weight: .semibold, design: .rounded))
        .minimumScaleFactor(0.7)
    }

    private var networkWing: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.up.fill")
                    .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.5))
                Text(IslandStatsStore.formatRate(stats.netIn))
            }
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.down.fill")
                    .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1.0))
                Text(IslandStatsStore.formatRate(stats.netOut))
            }
        }
        .font(.system(size: miniSize, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .minimumScaleFactor(0.6)
    }

    private var batteryWing: some View {
        HStack(spacing: 3) {
            Image(systemName: stats.batteryCharging ? "battery.100percent.bolt" : "battery.100percent")
                .foregroundStyle(Color(red: 0.45, green: 0.88, blue: 0.55))
            Text(stats.batteryPercent.map { "\($0)%" } ?? "—")
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .font(.system(size: miniSize, weight: .semibold, design: .rounded))
        .minimumScaleFactor(0.7)
    }

    private var analogClock: some View {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date) % 12
        let m = cal.component(.minute, from: date)
        let hourA = Double(h) * 30 + Double(m) * 0.5 - 90
        let minA = Double(m) * 6 - 90
        let size: CGFloat = compact ? 16 : 22
        return Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let r = min(canvas.width, canvas.height) / 2
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - r + 0.5, y: c.y - r + 0.5, width: (r - 0.5) * 2, height: (r - 0.5) * 2)),
                with: .color(.white.opacity(0.9)),
                lineWidth: 1
            )
            func hand(_ deg: Double, _ len: CGFloat, _ width: CGFloat) {
                let rad = deg * .pi / 180
                var path = Path()
                path.move(to: c)
                path.addLine(to: CGPoint(x: c.x + CGFloat(cos(rad)) * len, y: c.y + CGFloat(sin(rad)) * len))
                ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            hand(hourA, r * 0.45, 1.6)
            hand(minA, r * 0.7, 1.2)
        }
        .frame(width: size, height: size)
    }
}
