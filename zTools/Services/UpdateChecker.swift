import Foundation

struct UpdateInfo: Equatable {
    let version: String
    let notes: String
    let url: URL?
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var latest: UpdateInfo?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isChecking = false

    /// 可改为你的 GitHub releases latest API
    var feedURL: URL? {
        // 占位：本地 changelog 对比；有远端时替换
        nil
    }

    func check(manual: Bool = true) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let current = AppVersionInfo.shortVersion

        if let feedURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: feedURL)
                if let remote = parseGitHubRelease(data) {
                    latest = remote
                    if isNewer(remote.version, than: current) {
                        statusMessage = "发现新版本 \(remote.version)"
                    } else {
                        statusMessage = manual ? "已是最新版本 \(current)" : nil
                    }
                    return
                }
            } catch {
                statusMessage = "检查失败：\(error.localizedDescription)"
                return
            }
        }

        // 未配置远端更新源：诚实提示，避免误导用户以为在检查远程
        latest = nil
        if manual {
            statusMessage = "未配置更新源，当前为本地开发版 \(current)"
        }
    }

    private func parseGitHubRelease(_ data: Data) -> UpdateInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard var tag = obj["tag_name"] as? String else { return nil }
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
        let body = obj["body"] as? String ?? ""
        let html = obj["html_url"] as? String
        return UpdateInfo(version: tag, notes: body, url: html.flatMap(URL.init(string:)))
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
