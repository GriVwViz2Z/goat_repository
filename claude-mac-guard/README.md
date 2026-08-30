# Claude Mac Guard

Claude Mac Guard 是面向 Claude for Mac 的本地网络安全门禁项目。它的目标是
在 macOS 网络层建立明确、可审计的默认拒绝边界；它不修改 Claude 请求，不读取
账号或聊天数据，也不用于规避平台规则。

> 当前版本：**v0.2.0 Claude.app 启动门禁**。它不会阻断 Claude.app 的连接，不能防止
> VPN/代理切换瞬间的请求泄漏。任何“已保护”“已 fail-closed”的描述在 v0.3
> 之前都是错误的。

## 当前实现

v0.2.0 的 SwiftUI 界面会执行六组检查：

- 通过 ipify 与 ifconfig.me 连续交叉采样当前出口 IPv4，验证结果是否完整、
  一致和稳定。
- 通过 ipwho.is 查询出口国家/地区、ASN 与网络组织，作为便于辨认节点的信息；
  它们不参与可信判定。该步骤会把当前出口 IP 发给 ipwho.is；不会发送 Claude
  账号、凭据、聊天或本机文件。
- 本机已确认基线只使用用户亲自确认过的精确出口 IPv4 或 CIDR。稳定采样、系统
  代理与本机策略均满足后，才显示绿色通过。“已确认”不等于节点绝对安全。
- “节点公开信誉”默认不联网查询。用户明确同意后，才把当前出口 IP 发送给
  `reputation.noc.org`，读取网络类型与公开攻击信号；每一个新 IP 都要重新同意。
- 节点卡提供 Ping0、ipdata、Scamalytics 三个交叉检查入口。每次打开前都会说明
  当前 IP 将被写进发给对应网站的网址。应用不抓取这些网页的私有接口：ipdata 与
  Scamalytics 的正式自动化 API 都需要各自的 API Key，Ping0 未公开稳定 API 文档。
- 读取 macOS 系统代理，并观察活动的 `utun` / `ipsec` / `ppp` 接口。
- 独立探测 `api.anthropic.com` 是否存在 IPv6 可达路径；识别 Clash/Mihomo
  `198.18.0.0/15` fake-IP 与 IPv4-mapped IPv6。
- 通过系统 `curl` 验证 TLS，并显示证书 issuer；配置显式 HTTP 代理时检查
  CONNECT 隧道痕迹。
- 验证 `/Applications/Claude.app` 的存在性、代码签名、Bundle ID 与 Anthropic
  Team ID。
- 提供“检测并启动 Claude”门禁。每次点击都会生成一份全新的检测快照；只有出口
  验证、系统代理、IPv6、TLS 和 Claude.app 身份五项全部通过才会启动。Claude 已经
  运行时会拒绝把这次操作描述成受门禁控制的启动。

“节点公开信誉”是辅助证据，不是自动信任分数，也不参与 v0.2 的启动放行。查询未
发现公开攻击记录，不代表节点运营者可信；查询服务暂时不可用也不会暗中改变本地
门禁规则。

这些探测不会启动 Claude.app，不读取 Claude 的配置、凭据、Keychain、聊天内容
或浏览器数据。除了已经披露的 IP 查询，应用不会向第三方发送其他用户数据。

### 外部节点报告

- [`reputation.noc.org`](https://reputation.noc.org/api-docs/)：正式免密 API，当前文档
  标注免费 200 次/日；只有用户同意后才调用。
- [`Ping0`](https://ping0.cc/)：提供网页报告；项目未找到可依赖的公开 API 文档，
  因此只做用户触发的外部链接。
- [`ipdata`](https://docs.ipdata.co/docs/getting-started)：正式 API 需要 API Key；当前
  不抓取其网页内部接口。
- [`Scamalytics`](https://www.scamalytics.com/ip/api/pricing)：正式 API 有免费额度但
  需要账号与 API 配置；当前只做用户触发的外部链接。

应用图标使用原创的“盾牌网络门”隐喻：clay 背景、手剪 ivory 盾牌和粗糙
near-black 墨线，不包含 Anthropic 或 Claude 的官方标志。`scripts/build-icon.sh`
会保留源图的纸张颗粒与手绘不规则感，并生成 16px–1024px 完整 `.icns`。

## 运行 v0.2

当前构建脚本会优先使用 `/Applications/Xcode.app` 中的完整 Apple 工具链；v0.2
本身仍然只是普通 SwiftUI 应用：

```bash
cd "/path/to/ClaudeMacGuard"
swift run ClaudeMacGuardSelfTest
swift run -c release ClaudeMacGuardSelfTest
swift run ClaudeMacGuard
```

也可以组装一个本地 ad-hoc 签名的 `.app`：

```bash
./scripts/build-app.sh
open "dist/Claude Mac Guard.app"
```

这个本地 `.app` 只有启动门禁，不带 Network Extension。它不会持续监控或阻断已
启动 Claude 的连接。

## 配置已确认出口

应用会加载下面的本机策略文件；文件不存在时使用保守默认值，并把“已识别出口但
尚未建立已确认出口基线”显示为警告：

```text
~/.config/claude-mac-guard/policy.json
```

格式见 [`Config/policy.example.json`](Config/policy.example.json)。当稳定出口与
显式系统代理均已确认时，界面会提供“确认这是我的节点”按钮。应用只有在用户再次
确认后，才把这个精确 IPv4 写入本机已确认列表；新的出口永远不会自动加入。

这个设计沿用上游 `claude-guard` 的核心门禁思路：以用户明确允许的出口 IP/CIDR
作为确认锚点，再独立检查代理路径、IPv6 与 TLS。国家、城市、ASN 只帮助用户辨认
当前节点，不会因为“看起来在某个国家”就自动变成安全。这里的“通过”只表示符合
本地网络规则，不表示平台账号风险保证，也不表示 v0.2 已经具备网络阻断能力。

## 分阶段边界

| 阶段 | 能力 | 能否保证异常请求不先发出 |
| --- | --- | --- |
| v0.1 | SwiftUI GUI + 只读状态检测 | 否 |
| v0.2 | 安全条件不满足时不启动 Claude.app | 仅覆盖启动前；运行中不能保证 |
| v0.3 | Network Extension / Content Filter 默认拒绝 Claude flow | 目标是能；须经真实流量测试 |
| v0.4 | 网络切换、sleep/wake、VPN/TUN 掉线时实时更新策略 | 目标是能；须覆盖竞态与恢复测试 |
| v1.0 | 菜单栏、脱敏日志、规则配置、一键安全启动 | 继承已验证的 v0.3/v0.4 边界 |

v0.3 不能只靠一个轮询 watchdog。预期结构是：

```text
Claude.app 新建网络 flow
          ↓
NEFilterDataProvider（系统扩展）
          ↓
策略状态明确为 safe？
       ↙       ↘
     allow     drop（默认）
```

macOS Content Filter 需要完整 Xcode、Network Extension capability、相应签名与
provisioning profile，并需要用户在系统设置中批准扩展。当前机器已经有完整 Xcode，
但尚未配置开发者团队、Network Extension capability 和 provisioning profile，
因此本仓库仍不会放入一个无法签名验证的“假 v0.3”。

## 上游来源

网络探测思路来自 MIT 开源项目
[`wetlink/claude-guard`](https://github.com/wetlink/claude-guard)。本项目是独立的
Swift 工程，不修改原仓库，也不复制 Claude Code 的 profile、settings、CLI 参数、
模型、OAuth 或进程生命周期逻辑。完整归属说明见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 开发与安全报告

提交改动前可运行下面的离线检查；GitHub Actions 会对 push 到 `main` 和 pull request
执行同样的构建与自测：

```bash
swift build
swift run ClaudeMacGuardSelfTest
```

安全漏洞、隐私问题或网络绕过发现请不要直接发布到公开 Issue。报告方式和所需信息见
[`SECURITY.md`](SECURITY.md)。
