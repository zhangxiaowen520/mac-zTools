import Darwin
import Foundation
import IOKit.ps

struct IslandAccessory: Identifiable, Equatable {
    let id: String
    let name: String
    var percent: Int?
}

@MainActor
final class IslandStatsStore: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    @Published var batteryPercent: Int?
    @Published var batteryCharging = false
    @Published var accessories: [IslandAccessory] = []
    @Published var netIn: Double = 0
    @Published var netOut: Double = 0
    @Published var diskFree: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var uptime: TimeInterval = 0
    @Published var thermalLabel = "正常"
    @Published var loadAverage = "—"
    @Published var localIP = "—"
    @Published var batteryTime = "—"

    let deviceModel: String = sysctlString("hw.model") ?? "Mac"
    let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }()
    let coreCount: Int = ProcessInfo.processInfo.processorCount

    var memoryRatio: Double {
        guard memoryTotal > 0 else { return 0 }
        return min(1, Double(memoryUsed) / Double(memoryTotal))
    }

    var batteryRatio: Double {
        Double(batteryPercent ?? 0) / 100
    }

    var diskUsed: UInt64 {
        diskTotal - min(diskFree, diskTotal)
    }

    private var timer: Timer?
    private var lastCPU: host_cpu_load_info?
    private var lastNetIn: UInt64 = 0
    private var lastNetOut: UInt64 = 0
    private var lastNetAt: TimeInterval = 0

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { @MainActor in self.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let sample = Self.cpuLoad() {
            if let last = lastCPU {
                cpu = Self.cpuUsage(previous: last, current: sample)
            }
            lastCPU = sample
        }
        let mem = Self.memory()
        memoryUsed = mem.used
        memoryTotal = mem.total
        let power = Self.readPowerSources()
        batteryPercent = power.battery.percent
        batteryCharging = power.battery.charging
        batteryTime = power.battery.timeLabel
        accessories = power.accessories
        let net = Self.linkBytes()
        let now = ProcessInfo.processInfo.systemUptime
        if lastNetAt > 0 {
            let dt = max(0.2, now - lastNetAt)
            let inDelta = net.inBytes >= lastNetIn ? net.inBytes - lastNetIn : 0
            let outDelta = net.outBytes >= lastNetOut ? net.outBytes - lastNetOut : 0
            netIn = Double(inDelta) / dt
            netOut = Double(outDelta) / dt
        }
        lastNetIn = net.inBytes
        lastNetOut = net.outBytes
        lastNetAt = now
        let disk = Self.disk()
        diskFree = disk.free
        diskTotal = disk.total
        uptime = ProcessInfo.processInfo.systemUptime
        thermalLabel = Self.thermalText()
        loadAverage = Self.loadAverageText()
        localIP = Self.localIPv4()
    }

    nonisolated static func cpuLoad() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info : nil
    }

    nonisolated static func cpuUsage(previous: host_cpu_load_info, current: host_cpu_load_info) -> Double {
        let user = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(1, max(0, (user + system + nice) / total))
    }

    nonisolated static func memory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    nonisolated static func readPowerSources() -> (
        battery: (percent: Int?, charging: Bool, timeLabel: String),
        accessories: [IslandAccessory]
    ) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as NSArray?
        else { return ((nil, false, "—"), []) }

        var battery: (percent: Int?, charging: Bool, timeLabel: String) = (nil, false, "—")
        var accessories: [IslandAccessory] = []
        for item in list {
            let source = item as AnyObject
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as NSDictionary? else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            let transport = desc[kIOPSTransportTypeKey] as? String
            let cur = intValue(desc[kIOPSCurrentCapacityKey]) ?? 0
            let cap = max(intValue(desc[kIOPSMaxCapacityKey]) ?? 100, 1)
            let percent = min(100, max(0, cur * 100 / cap))
            let isInternal = type == (kIOPSInternalBatteryType as String)
                || transport == (kIOPSInternalType as String)
            if isInternal, battery.percent == nil {
                let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                let mins = charging
                    ? (intValue(desc[kIOPSTimeToFullChargeKey]) ?? -1)
                    : (intValue(desc[kIOPSTimeToEmptyKey]) ?? -1)
                battery = (
                    percent,
                    charging,
                    formatBatteryMinutes(mins, prefix: charging ? "充满" : "剩余")
                )
            } else if transport == "Bluetooth" {
                let name = (desc[kIOPSNameKey] as? String) ?? "蓝牙设备"
                accessories.append(IslandAccessory(id: name, name: name, percent: percent))
            }
        }
        return (battery, accessories)
    }

    nonisolated static func intValue(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let n = value as? Int { return n }
        if let n = value as? Int8 { return Int(n) }
        if let n = value as? UInt8 { return Int(n) }
        return nil
    }

    nonisolated static func linkBytes() -> (inBytes: UInt64, outBytes: UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(first) }

        var inn: UInt64 = 0
        var out: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifaPtr = cursor {
            let ifa = ifaPtr.pointee
            cursor = ifa.ifa_next
            guard let cName = ifa.ifa_name else { continue }
            let name = String(cString: cName)
            guard shouldCountInterface(name) else { continue }
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_LINK) else { continue }
            guard let dataPtr = ifa.ifa_data else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            inn += UInt64(data.ifi_ibytes)
            out += UInt64(data.ifi_obytes)
        }
        return (inn, out)
    }

    nonisolated static func shouldCountInterface(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("ppp")
    }

    nonisolated static func disk() -> (free: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let freeRaw = values.volumeAvailableCapacityForImportantUsage ?? 0
        let totalRaw = values.volumeTotalCapacity ?? 0
        return (UInt64(max(0, freeRaw)), UInt64(max(0, totalRaw)))
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    static func formatRate(_ bps: Double) -> String {
        if bps < 1024 { return "0 KB/s" }
        if bps < 1_048_576 { return String(format: "%.0f KB/s", bps / 1024) }
        return String(format: "%.1f MB/s", bps / 1_048_576)
    }

    static func formatUptime(_ t: TimeInterval) -> String {
        let s = Int(t)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return "\(d)天 \(h)小时" }
        if h > 0 { return "\(h)小时 \(m)分" }
        return "\(m)分钟"
    }

    nonisolated static func formatBatteryMinutes(_ mins: Int, prefix: String) -> String {
        guard mins > 0 else { return "—" }
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "\(prefix) \(h)小时" : "\(prefix) \(h)小时\(m)分"
        }
        return "\(prefix) \(mins)分钟"
    }

    nonisolated static func thermalText() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "偏高"
        case .serious: return "较高"
        case .critical: return "过高"
        @unknown default: return "—"
        }
    }

    nonisolated static func loadAverageText() -> String {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return "—" }
        return String(format: "%.2f", loads[0])
    }

    nonisolated static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    nonisolated static func localIPv4() -> String {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return "—" }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifaPtr = cursor {
            let ifa = ifaPtr.pointee
            cursor = ifa.ifa_next
            guard let cName = ifa.ifa_name else { continue }
            let name = String(cString: cName)
            guard shouldCountInterface(name), let addr = ifa.ifa_addr else { continue }
            guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let err = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if err == 0 {
                let ip = String(cString: host)
                if !ip.isEmpty, ip != "0.0.0.0" { return ip }
            }
        }
        return "—"
    }
}
