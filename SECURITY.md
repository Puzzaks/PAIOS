# Security Policy

## Supported Versions

Since PAIOS is a client for Google's on-device AI, security updates primarily concern the app's ability to interface safely with `AICore`.

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < 1.1.2 | :x:                |

> **Note**: Older versions (< 1.1.2) are deprecated due to the package name change and Play Store listing issues.

## Reporting a Vulnerability

I take security seriously. If you discover a vulnerability, please follow these steps:

1.  **Do not** open a public issue on GitHub.
2.  **Email** your report to `support@puzzak.page`.
3.  Include:
    *   Description of the vulnerability.
    *   Steps to reproduce.
    *   Potential impact.

I will acknowledge your report and do my best to patch valid vulnerabilities as soon as possible.

### Data Privacy Note
The app uses `SharedPreferences` which stores data in plain text at `/sdcard/Android/data/page.puzzak.paios/`.
*   **Risk**: Access requires **Root** or **ADB** access.
*   **Impact**: malicious apps with root access could read conversation history.
*   **Mitigation**: This is standard Android behavior for local data. Ensure your device is secure.
