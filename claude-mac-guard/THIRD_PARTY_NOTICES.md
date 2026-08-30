# Third-party notices

Claude Mac Guard is an independent project and is not affiliated with Anthropic.

The project reuses and translates ideas from
[`wetlink/claude-guard`](https://github.com/wetlink/claude-guard), commit
`e194834e51ccdf16f30ae73c19f2222ee720d196`, under its MIT License.

The following v0.1 behavior is derived from that project's auditable preflight
logic:

- IPv4 exit-IP observation and allow-list matching.
- CIDR matching for allowed IPv4 ranges.
- An IPv6 reachability probe with special handling for Clash/Mihomo fake-IP
  ranges (`198.18.0.0/15`) and IPv4-mapped IPv6 addresses.
- TLS issuer observation and warning markers for common local interception
  tools.

Claude Code profile, settings, CLI arguments, client binary pinning, OAuth,
model selection, lifecycle control, and watchdog process logic are intentionally
not copied into this project.
