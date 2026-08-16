import ClaudeMacGuardCore
import SwiftUI

struct MonitorView: View {
    @StateObject private var model = MonitorViewModel()
    @State private var pendingPrompt: PendingPrompt?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    boundaryBanner
                    errorBanner
                    statusSummary
                    launchGateCard
                    launchNoticeBanner
                    checks
                }
                .padding(28)
            }
        }
        .task {
            if model.snapshot == nil {
                model.refresh()
            }
        }
        .alert(item: $pendingPrompt) { prompt in
            alert(for: prompt)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Mac Guard")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("v0.2.0 · Claude.app 启动门禁")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("重新检测", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRefreshing)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.lastError {
            Label(error, systemImage: "xmark.octagon.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var boundaryBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("监测不等于阻断")
                    .font(.headline)
                Text("v0.2 只在启动前把关，不会拦截 Claude.app 已建立或之后新建的连接，也不能防止网络切换瞬间的请求泄漏。真正的 fail-closed 从 v0.3 Network Extension 开始。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var launchGateCard: some View {
        if let snapshot = model.snapshot {
            let decision = LaunchGate.evaluate(snapshot)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: decision.isReady ? "lock.shield.fill" : "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(decision.isReady ? .green : .orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(decision.isReady ? "启动门禁已就绪" : "启动门禁尚未满足")
                        .font(.headline)
                    Text(decision.summary)
                        .font(.subheadline)
                    ForEach(decision.blockingReasons, id: \.self) { reason in
                        Text("• \(reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("点击后会重新检测，不会沿用这张旧快照。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.checkAndLaunchClaude()
                    } label: {
                        if model.isLaunching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("检测并启动 Claude", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRefreshing || model.isLaunching)
                    .padding(.top, 4)
                }
                Spacer()
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke((decision.isReady ? Color.green : Color.orange).opacity(0.35), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var launchNoticeBanner: some View {
        if let notice = model.launchNotice {
            let color: Color = notice.kind == .launched ? .green : (notice.kind == .warning ? .orange : .red)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.kind == .launched ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title).font(.headline)
                    Text(notice.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(12)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var statusSummary: some View {
        if let snapshot = model.snapshot {
            HStack(spacing: 12) {
                StateIcon(state: snapshot.overallState, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle(snapshot.overallState))
                        .font(.title3.weight(.semibold))
                    Text("上次检测：\(snapshot.observedAt.formatted(date: .omitted, time: .standard)) · 网络阻断：未启用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 12) {
                ProgressView()
                Text("正在读取本机状态…")
            }
        }
    }

    @ViewBuilder
    private var checks: some View {
        if let snapshot = model.snapshot {
            LazyVStack(spacing: 12) {
                ForEach(snapshot.checks) { check in
                    CheckCard(check: check) { action in
                        switch action {
                        case .confirmExitIPv4(let address):
                            pendingPrompt = .confirmExit(address)
                        case .queryPublicReputation(let address):
                            pendingPrompt = .queryReputation(address)
                        case let .openExternalReport(name, url, address):
                            pendingPrompt = .openReport(name: name, url: url, address: address)
                        }
                    }
                }
            }
        }
    }

    private func summaryTitle(_ state: CheckState) -> String {
        switch state {
        case .passed: "所有已配置检查均通过"
        case .warning: "检测完成，有需要确认的项目"
        case .failed: "检测到不符合本地策略的项目"
        case .unavailable: "部分检测暂时不可用"
        }
    }

    private func alert(for prompt: PendingPrompt) -> Alert {
        switch prompt {
        case .confirmExit(let address):
            Alert(
                title: Text("确认这是你选择的出口？"),
                message: Text("将 \(address) 保存到本机已确认列表。它只表示这是你认识的节点，不代表节点绝对安全。"),
                primaryButton: .default(Text("确认这个 IP")) {
                    model.confirmExitIPv4(address)
                },
                secondaryButton: .cancel()
            )
        case .queryReputation(let address):
            Alert(
                title: Text("查询公开信誉？"),
                message: Text("将把出口 IP \(address) 发送给 reputation.noc.org，仅查询网络类型和公开风险信号，不发送 Claude 账号、聊天或文件。"),
                primaryButton: .default(Text("同意并查询")) {
                    model.queryPublicReputation(address)
                },
                secondaryButton: .cancel()
            )
        case let .openReport(name, url, address):
            Alert(
                title: Text("用 \(name) 交叉检查？"),
                message: Text("将在默认浏览器打开查询页，并把出口 IP \(address) 写入发给 \(name) 的网址。"),
                primaryButton: .default(Text("打开 \(name)")) {
                    model.openExternalReport(url)
                },
                secondaryButton: .cancel()
            )
        }
    }
}

private enum PendingPrompt: Identifiable {
    case confirmExit(String)
    case queryReputation(String)
    case openReport(name: String, url: String, address: String)

    var id: String {
        switch self {
        case .confirmExit(let address): "confirm-\(address)"
        case .queryReputation(let address): "reputation-\(address)"
        case let .openReport(name, _, address): "report-\(name)-\(address)"
        }
    }
}

private struct CheckCard: View {
    let check: CheckResult
    let onAction: (CheckAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StateIcon(state: check.state, size: 24)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(check.title).font(.headline)
                    Spacer()
                    Text(stateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stateColor)
                }
                Text(check.summary)
                    .font(.subheadline)
                ForEach(check.details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !check.actions.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(check.actions.indices, id: \.self) { index in
                            let action = check.actions[index]
                            Button {
                                onAction(action)
                            } label: {
                                Label(actionLabel(action), systemImage: actionSymbol(action))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private var stateLabel: String {
        switch check.state {
        case .passed: "通过"
        case .warning: "需确认"
        case .failed: "不符合"
        case .unavailable: "不可用"
        }
    }

    private var stateColor: Color {
        switch check.state {
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        case .unavailable: .secondary
        }
    }

    private func actionLabel(_ action: CheckAction) -> String {
        switch action {
        case .confirmExitIPv4: "确认这是我的节点"
        case .queryPublicReputation: "查询公开信誉"
        case .openExternalReport(let name, _, _): "用 \(name) 交叉检查"
        }
    }

    private func actionSymbol(_ action: CheckAction) -> String {
        switch action {
        case .confirmExitIPv4: "checkmark.shield"
        case .queryPublicReputation: "magnifyingglass"
        case .openExternalReport: "arrow.up.right.square"
        }
    }
}

private struct StateIcon: View {
    let state: CheckState
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch state {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        case .unavailable: .secondary
        }
    }
}
