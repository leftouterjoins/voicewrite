# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in VoiceWrite, please report it responsibly:

1. **DO NOT** open a public issue
2. Open a private security advisory at [GitHub Security Advisories](https://github.com/leftouterjoins/voicewrite/security/advisories/new)
3. Or email the maintainers directly with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any suggested fixes

We will respond within 48 hours and work with you to address the issue.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Security Measures

VoiceWrite is designed with security in mind:

### No Network Access

The app never connects to the internet. All speech recognition happens locally using Apple's SpeechAnalyzer API.

### Minimal Permissions

VoiceWrite only requests two permissions:
- **Microphone** — For capturing audio to transcribe
- **Accessibility** — For typing transcribed text into other apps

### No Data Storage

- Audio is processed in real-time and immediately discarded
- Transcribed text is only held in memory during the session
- No logs, history, or caches are written to disk

### Open Source

The complete source code is available for audit. We encourage security researchers to review the codebase.

### Code Signing

All releases are signed with a Developer ID certificate and notarized by Apple.

## Security Best Practices for Users

1. **Download from official sources** — Only download VoiceWrite from the official GitHub releases or the linked website
2. **Verify signatures** — macOS will verify the app signature on first launch
3. **Review permissions** — Only grant permissions that you're comfortable with
