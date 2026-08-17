# Security policy

## Supported version

Security fixes are applied to the latest version on the `main` branch.

## Reporting a vulnerability

Please do not disclose vulnerabilities, privacy issues, or network-bypass findings in a public
GitHub issue. Use the repository's private vulnerability reporting feature under **Security →
Advisories → Report a vulnerability**. If that feature is unavailable, contact the maintainer
through a non-public channel listed on their GitHub profile.

Include the affected version, macOS version, reproduction steps, expected behavior, and observed
behavior. Do not include Claude credentials, cookies, prompts, conversations, Keychain data, or
other private account information.

This project currently provides a launch gate only. Until a Network Extension is implemented and
verified, reports that rely solely on the documented v0.2 limitation—no continuous traffic
blocking after Claude launches—are not security-boundary violations.
