# Project guardrails

- This project is a local network-safety tool, not an account-ban or platform-risk evasion tool.
- v0.1 is read-only monitoring. v0.2 may gate app launch. Do not claim network leak prevention before the v0.3 Network Extension is installed, enabled, and tested.
- Keep the default network posture for v0.3 fail-closed: Claude flows are denied unless the policy state is explicitly safe.
- Never inspect, copy, log, or modify Claude credentials, prompts, conversations, cookies, Keychain items, or account state.
- Never modify a separate upstream `claude-guard` checkout while working in this repository.
- Keep ordinary tests offline and deterministic. Put any live network diagnostics behind an explicit user action.
- Preserve the upstream MIT notice and record adapted logic in `THIRD_PARTY_NOTICES.md`.
