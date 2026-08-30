# Claude Mac Guard 项目存档

存档日期：2026-08-13

当前版本：v0.2.0

源码仓库：<https://github.com/GriVwViz2Z/claude-mac-guard>

## 1. 项目目标

Claude Mac Guard 是一个面向 Claude for Mac 的本地网络安全门禁。它的目标不是规避
平台风控，而是在 macOS 网络层建立可审计的默认拒绝边界：只有本机明确配置的网络
安全条件满足时，才允许 Claude.app 建立网络连接。

项目不读取、复制、记录或修改 Claude 的账号、凭据、Keychain、提示词、聊天记录、
Cookie 或浏览器数据。

## 2. 来源与许可

网络探测思路来自 MIT 开源项目：

- <https://github.com/wetlink/claude-guard>

本项目是独立 Swift 工程，没有修改原仓库，也没有保留 Claude Code CLI、profile、
settings、OAuth、模型参数或进程生命周期逻辑。上游许可与归属记录在
`THIRD_PARTY_NOTICES.md`。

## 3. 已完成版本

### v0.1.3：节点核验与只读监测

- 原创手绘 App 图标。
- SwiftUI 状态界面。
- 通过 ipify 与 ifconfig.me 连续交叉采样出口 IPv4。
- 读取 macOS 系统代理并观察 TUN 类接口。
- 检查到 `api.anthropic.com` 的公开 IPv6 路径以及 fake-IP 映射。
- 验证 TLS，并显示证书颁发者与 HTTP CONNECT 证据。
- 验证 `/Applications/Claude.app` 的签名、Bundle ID 和 Anthropic Team ID。
- 查询地区、ASN 和组织信息；这些信息只帮助辨认节点，不参与自动可信判定。
- 用户可以把亲自确认的精确出口 IPv4 写入本机策略。
- 公开信誉查询采用明确同意机制；Ping0、ipdata、Scamalytics 仅作为用户触发的
  外部交叉检查入口。

### v0.2.0：Claude.app 启动门禁

- 新增“检测并启动 Claude”按钮。
- 每次点击都会重新生成检测快照，不沿用界面上的旧结果。
- 以下五项必须全部通过才允许启动：
  1. 当前稳定出口已由用户确认；
  2. 检测到显式系统代理；
  3. 没有观察到公开 IPv6 旁路；
  4. TLS 验证通过；
  5. Claude.app 身份与代码签名符合预期。
- Claude 已经运行时，应用会拒绝把重新激活描述成受门禁保护的启动。
- 节点公开信誉保持为辅助证据，不作为绝对安全分数，也不参与自动放行。

## 4. 当前安全边界

v0.2 只有启动门禁，没有 Network Extension。

它能做到：

- 在启动 Claude 前重新检查本机网络条件；
- 条件不满足时不启动 Claude；
- 清楚解释是哪一项阻止了启动。

它不能做到：

- 拦截 Claude 已建立或之后新建的连接；
- 防止 Claude 运行期间 VPN、代理或节点突然失效；
- 消除检测与网络变化之间的竞态窗口；
- 在 Guard、过滤扩展或策略读取失败时执行系统级默认拒绝。

因此在 v0.3 的过滤扩展安装、启用并通过真实流量测试以前，不应把项目描述为
“已保护”或“fail-closed”。

## 5. 本机策略与隐私

默认策略文件：

```text
~/.config/claude-mac-guard/policy.json
```

确认新出口时，只把精确 IPv4 加入本机列表。新 IP 不会自动继承旧节点的确认状态。

联网查询边界：

- 出口采样会访问 ipify 与 ifconfig.me；
- 地区和 ASN 查询会把当前出口 IP 发给 ipwho.is；
- 只有用户明确同意后，才把当前出口 IP 发给 reputation.noc.org；
- 打开 Ping0、ipdata 或 Scamalytics 前会再次说明 IP 将写入网址；
- 不发送 Claude 账号、聊天内容、凭据或本机文件。

## 6. 当前工程结构

项目目前仍是 Swift Package，没有 `.xcodeproj`、Network Extension target 或
entitlements 文件。

关键代码：

- `Sources/ClaudeMacGuardCore/MonitorService.swift`：执行网络与 App 检查；
- `Sources/ClaudeMacGuardCore/ExitVerification.swift`：出口验证规则；
- `Sources/ClaudeMacGuardCore/NodeReputation.swift`：公开信誉证据；
- `Sources/ClaudeMacGuardCore/LaunchGate.swift`：v0.2 启动放行判定；
- `Sources/ClaudeMacGuard/MonitorViewModel.swift`：刷新、确认与启动流程；
- `Sources/ClaudeMacGuard/MonitorView.swift`：SwiftUI 界面；
- `Sources/ClaudeMacGuardSelfTest/main.swift`：离线确定性自测；
- `scripts/build-app.sh`：构建、测试、组装与本地 ad-hoc 签名。

构建产物：

```text
dist/Claude Mac Guard.app
```

## 7. 已完成验证

- 完整 Xcode 26.6 已安装在 `/Applications/Xcode.app`。
- 系统默认 `xcode-select` 当前仍指向 Command Line Tools；构建脚本会单独指定完整
  Xcode，不需要为了本项目修改全局设置。
- Release 构建成功。
- `ClaudeMacGuardSelfTest` 通过。
- v0.2 界面已实际启动检查。
- 当前出口未加入确认列表时，启动门禁正确拒绝放行。
- App 内版本为 `0.2.0 (5)`。
- 构建产物复制到不受 Documents File Provider 干扰的位置并清除附加属性后，
  `codesign --verify --deep --strict` 验证通过。

已知环境现象：Documents 的文件同步服务会立即给 `.app` 外壳重新添加
`com.apple.FinderInfo`，导致原目录中的严格 codesign 检查报告“附加数据”。这不是
可执行代码内容发生变化；后续正式分发仍应改用规范的 Developer ID 签名、打包与
notarization 流程。

## 8. v0.3 真正门禁还缺什么

### A. Xcode 与签名层

- 建立完整 Xcode 工程；
- 保留现有 Core 模块和离线自测；
- 新增 Network Extension / Content Filter target；
- 为主 App 与扩展配置独立 Bundle ID；
- 配置 Network Extension、System Extension 和必要的 App Group entitlement；
- 使用能包含这些权限的开发团队、证书和 provisioning profile；
- 让用户在 macOS 系统设置中明确批准扩展。

Apple 参考：

- <https://developer.apple.com/documentation/networkextension/filtering-network-traffic>
- <https://developer.apple.com/documentation/networkextension/nefilterdataprovider>
- <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension>
- <https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers>

### B. 只识别 Claude 流量

macOS 上不能依赖简单的 `NEFilterFlow.sourceAppIdentifier`；当前 SDK 将这个属性标记为
macOS 不可用。过滤扩展应使用 `sourceAppAuditToken`，再通过 Security framework
解析并验证运行中代码的 signing identifier、Team ID 和 designated requirement。

未知、缺失或无法验证的 Claude 身份不能被默认放行。正式实现前需要在这台 Mac 上
确认 Claude 主进程及辅助进程产生的 flow 都能提供足够的身份信息。

Apple 参考：

- <https://developer.apple.com/documentation/networkextension/nefilterflow/sourceappaudittoken>
- <https://developer.apple.com/documentation/security/code-signing-services>

### C. fail-closed 状态机

目标规则：

```text
不是 Claude flow                 -> 允许，不影响其他 App
无法确认 flow 是否来自 Claude     -> 不得假装已保护，进入保守处理
确认是 Claude，但安全状态缺失       -> 拒绝
确认是 Claude，但状态过期或网络已变更 -> 拒绝
确认是 Claude，且当前状态明确安全     -> 允许
```

主 App 与扩展之间需要共享一个很小的、原子更新的安全状态，至少包含：

- 当前网络代次；
- 已确认出口；
- 检测时间与有效期；
- 五项必需检查结果；
- 明确的 allow/deny 状态。

任何解析失败、状态过期、扩展启动失败或通信失败都必须回到 deny，不能保留上一次的
绿色状态。

### D. 必须覆盖的真实测试

- Claude 冷启动；
- Claude 已运行；
- 切换 Shadowrocket 节点；
- 关闭 Shadowrocket；
- 系统代理仍存在但本地代理端口失效；
- IPv4 与 IPv6 路径变化；
- Wi-Fi 切换；
- Mac sleep/wake；
- Guard 主 App 退出或崩溃；
- Network Extension 退出或被禁用；
- 策略文件损坏、缺失或过期；
- Mac 重启后 Claude 抢先启动；
- Claude 更新后签名身份仍正确匹配；
- 已允许的长连接在网络变化后是否被撤销。

只有上述测试能证明：异常时连接先被阻止，而不是请求发出后才被发现。

## 9. 下一步建议

不要直接把当前 Swift Package 改成复杂的完整产品。先做一个最小 v0.3 技术验证：

1. 新建 Xcode host App 与 Filter Data Provider target；
2. 让扩展能够被正确签名、安装、启用和停用；
3. 初期用明确的测试开关验证 allow/drop，不接真实 Claude；
4. 验证 macOS audit token 到代码签名身份的映射；
5. 在确认只会命中 Claude 后，才接入现有 LaunchGate 安全状态；
6. 最后测试 VPN、节点、sleep/wake、崩溃与重启故障。

如果签名或 entitlement 无法获得，应停在技术验证阶段，不使用第三方内核模块、修改
系统完整性保护或其他绕过 macOS 安全模型的方式。

## 10. Git 与回滚

继续开发 v0.3 时应从 `main` 创建独立开发分支。发布版本时可依据
`CHANGELOG.md` 创建对应的 Git 标签；不要移动或覆盖已经发布到远程仓库的标签。
如果实验失败，应从最近一个已验证的发布标签重新建立分支。
