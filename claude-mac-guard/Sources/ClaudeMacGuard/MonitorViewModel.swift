import ClaudeMacGuardCore
import AppKit
import Foundation

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var snapshot: SecuritySnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLaunching = false
    @Published private(set) var lastError: String?
    @Published private(set) var launchNotice: LaunchNotice?

    private var service: MonitorService
    private var reputationConsents: Set<String> = []

    init(service: MonitorService = MonitorService()) {
        self.service = service
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        launchNotice = nil
        Task {
            snapshot = await service.inspect(reputationConsents: reputationConsents)
            isRefreshing = false
        }
    }

    func checkAndLaunchClaude() {
        guard !isRefreshing, !isLaunching else { return }

        let bundleIdentifier = service.policy.expectedClaudeBundleIdentifier
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            launchNotice = LaunchNotice(
                kind: .warning,
                title: "Claude 已经在运行",
                message: "v0.2 只能控制启动前检查，不能接管已经运行的 Claude。请先退出 Claude，再从这里启动。"
            )
            return
        }

        isLaunching = true
        isRefreshing = true
        launchNotice = nil

        Task {
            let freshSnapshot = await service.inspect(reputationConsents: reputationConsents)
            snapshot = freshSnapshot
            isRefreshing = false

            let decision = LaunchGate.evaluate(freshSnapshot)
            guard decision.isReady else {
                launchNotice = LaunchNotice(
                    kind: .blocked,
                    title: "Claude 没有启动",
                    message: decision.blockingReasons.joined(separator: "\n")
                )
                isLaunching = false
                return
            }

            let appURL = URL(fileURLWithPath: service.policy.claudeAppPath)
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: configuration
                )
                launchNotice = LaunchNotice(
                    kind: .launched,
                    title: "Claude 已通过启动门禁",
                    message: "启动前检查已通过。v0.2 不会阻断启动后的网络变化；运行中保护要等 v0.3。"
                )
                lastError = nil
            } catch {
                launchNotice = LaunchNotice(
                    kind: .blocked,
                    title: "无法启动 Claude",
                    message: error.localizedDescription
                )
            }
            isLaunching = false
        }
    }

    func confirmExitIPv4(_ address: String) {
        do {
            try PolicyStore.confirmExitIPv4(address)
            service = MonitorService()
            lastError = nil
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func queryPublicReputation(_ address: String) {
        reputationConsents.insert(address)
        refresh()
    }

    func openExternalReport(_ urlString: String) {
        guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else {
            lastError = "无法打开外部报告链接。"
            return
        }
        lastError = nil
    }
}

struct LaunchNotice: Equatable {
    enum Kind: Equatable {
        case launched
        case warning
        case blocked
    }

    let kind: Kind
    let title: String
    let message: String
}
