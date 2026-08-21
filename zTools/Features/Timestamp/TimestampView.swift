import SwiftUI

struct TimestampView: View {
    @State private var input = ""
    @State private var date = Date()
    @State private var copied: String?
    @State private var favoriteIDs: [String] = TimestampFavorites.load()
    @State private var isEditingFromPicker = false
    @State private var showCalendar = false

    private let codeFormats: [(id: String, title: String, build: (Date) -> String)] = [
        ("sec", "Unix 秒", { String(Int($0.timeIntervalSince1970)) }),
        ("ms", "Unix 毫秒", { String(Int($0.timeIntervalSince1970 * 1000)) }),
        ("iso", "ISO8601", {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: $0)
        }),
        ("iso_frac", "ISO8601+ms", {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: $0)
        }),
        ("local", "本地时间", { format($0, tz: .current, fmt: "yyyy-MM-dd HH:mm:ss") }),
        ("utc", "UTC", { format($0, tz: TimeZone(secondsFromGMT: 0)!, fmt: "yyyy-MM-dd HH:mm:ss") }),
        ("date_only", "仅日期", { format($0, tz: .current, fmt: "yyyy-MM-dd") }),
        ("swift_date", "Swift", {
            "Date(timeIntervalSince1970: \(Int($0.timeIntervalSince1970)))"
        }),
        ("js_date", "JavaScript", {
            "new Date(\(Int($0.timeIntervalSince1970 * 1000)))"
        }),
        ("python", "Python", {
            "datetime.fromtimestamp(\(Int($0.timeIntervalSince1970)))"
        }),
        ("json", "JSON", { "\(Int($0.timeIntervalSince1970))" }),
        ("rfc2822", "RFC2822", {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            f.timeZone = .current
            return f.string(from: $0)
        })
    ]

    private let zones: [(id: String, title: String, tz: TimeZone)] = [
        ("local", "本地", .current),
        ("utc", "UTC", TimeZone(identifier: "UTC")!),
        ("shanghai", "上海", TimeZone(identifier: "Asia/Shanghai")!),
        ("tokyo", "东京", TimeZone(identifier: "Asia/Tokyo")!),
        ("ny", "纽约", TimeZone(identifier: "America/New_York")!),
        ("london", "伦敦", TimeZone(identifier: "Europe/London")!),
        ("la", "洛杉矶", TimeZone(identifier: "America/Los_Angeles")!)
    ]

    private var parsedDate: Date? {
        parse(input) ?? date
    }

    private var displayDate: Date { parsedDate ?? date }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 输入
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("输入", icon: "textformat.123")
                    HStack(spacing: 8) {
                        Image(systemName: "number")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("时间戳或日期字符串", text: $input)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .onChange(of: input) { _, newValue in
                                guard !isEditingFromPicker else { return }
                                if let d = parse(newValue) {
                                    isEditingFromPicker = true
                                    date = d
                                    isEditingFromPicker = false
                                }
                            }
                        if !input.isEmpty {
                            Button {
                                input = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusControl, style: .continuous))
                }

                // 时间选择器卡片
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionLabel("选择时间", icon: "calendar")
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showCalendar.toggle()
                            }
                        } label: {
                            Label(showCalendar ? "收起" : "日历", systemImage: showCalendar ? "chevron.up" : "calendar")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                    }

                    // 当前选中时间展示
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: ZTheme.radiusTile, style: .continuous)
                                .fill(ZTheme.selectionFill)
                                .frame(width: 52, height: 52)
                            VStack(spacing: 0) {
                                Text(monthDay(displayDate).0)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(ZTheme.accent)
                                Text(monthDay(displayDate).1)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(format(displayDate, tz: .current, fmt: "yyyy 年 M 月 d 日 EEEE"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(format(displayDate, tz: .current, fmt: "HH:mm:ss"))
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(ZTheme.fillQuiet, in: RoundedRectangle(cornerRadius: ZTheme.radiusTile, style: .continuous))

                    // 紧凑步进选择：日期 + 时间
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            pickerChip {
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .controlSize(.regular)
                            }
                            pickerChip {
                                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .controlSize(.regular)
                            }
                            // 秒
                            secondStepper
                        }

                        if showCalendar {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                                .padding(8)
                                .background(ZTheme.fillQuiet, in: RoundedRectangle(cornerRadius: ZTheme.radiusTile, style: .continuous))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .onChange(of: date) { _, newValue in
                        guard !isEditingFromPicker else { return }
                        isEditingFromPicker = true
                        input = String(Int(newValue.timeIntervalSince1970))
                        isEditingFromPicker = false
                    }

                    HStack(spacing: 8) {
                        Button {
                            let now = Date()
                            isEditingFromPicker = true
                            date = now
                            input = String(Int(now.timeIntervalSince1970))
                            isEditingFromPicker = false
                        } label: {
                            Label("现在", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            PasteboardUtil.copyString(String(Int(displayDate.timeIntervalSince1970)))
                            copied = "Unix 秒"
                        } label: {
                            Label("复制秒", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            PasteboardUtil.copyString(String(Int(displayDate.timeIntervalSince1970 * 1000)))
                            copied = "Unix 毫秒"
                        } label: {
                            Label("复制毫秒", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let copied {
                        Text("已复制 \(copied)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                if parsedDate != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("时区", icon: "globe")
                        ForEach(zones.filter { favoriteIDs.contains($0.id) || $0.id == "local" || $0.id == "utc" }, id: \.id) { z in
                            zoneRow(z, date: displayDate)
                        }
                        DisclosureGroup("更多时区") {
                            VStack(spacing: 6) {
                                ForEach(zones.filter { !favoriteIDs.contains($0.id) && $0.id != "local" && $0.id != "utc" }, id: \.id) { z in
                                    zoneRow(z, date: displayDate)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption.weight(.medium))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("格式 / 代码", icon: "curlybraces")
                        ForEach(codeFormats, id: \.id) { item in
                            copyRow(item.title, item.build(displayDate))
                        }
                    }
                } else {
                    Label("无法解析输入，请检查格式", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(14)
        }
        .onAppear {
            if input.isEmpty {
                input = String(Int(date.timeIntervalSince1970))
            }
        }
    }

    private var secondStepper: some View {
        let cal = Calendar.current
        let second = cal.component(.second, from: date)
        return HStack(spacing: 4) {
            Text("秒")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(format: "%02d", second))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 28)
            Stepper("", value: Binding(
                get: { second },
                set: { newSec in
                    var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    c.second = max(0, min(59, newSec))
                    if let d = cal.date(from: c) {
                        date = d
                    }
                }
            ), in: 0...59)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
            .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
    }

    private func pickerChip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }

    private func monthDay(_ date: Date) -> (String, String) {
        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "zh_CN")
        f1.dateFormat = "MMM"
        let f2 = DateFormatter()
        f2.dateFormat = "d"
        return (f1.string(from: date).uppercased(), f2.string(from: date))
    }

    private func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) {
            if value > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: value / 1000)
            }
            return Date(timeIntervalSince1970: value)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd"] {
            f.dateFormat = pattern
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }

    private func zoneRow(_ z: (id: String, title: String, tz: TimeZone), date: Date) -> some View {
        HStack(spacing: 6) {
            copyRow(z.title, format(date, tz: z.tz, fmt: "yyyy-MM-dd HH:mm:ss zzz"))
            if z.id != "local" && z.id != "utc" {
                Button {
                    toggleFavorite(z.id)
                } label: {
                    Image(systemName: favoriteIDs.contains(z.id) ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("收藏时区")
            }
        }
    }

    private func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) {
            favoriteIDs.removeAll { $0 == id }
        } else {
            favoriteIDs.append(id)
        }
        TimestampFavorites.save(favoriteIDs)
    }

    private func copyRow(_ title: String, _ value: String) -> some View {
        Button {
            PasteboardUtil.copyString(value)
            copied = title
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .leading)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private func format(_ date: Date, tz: TimeZone, fmt: String) -> String {
    let f = DateFormatter()
    f.dateFormat = fmt
    f.timeZone = tz
    f.locale = Locale(identifier: "zh_CN")
    return f.string(from: date)
}

enum TimestampFavorites {
    private static let key = "timestamp.favoriteZones"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? ["shanghai", "tokyo"]
    }

    static func save(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: key)
    }
}
