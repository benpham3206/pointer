# Security checklist

Proportional to exposure: a LAN hobby tool doesn't need SOC 2, but every row
here is cheap and the expensive breach is the one you skipped it for.

## Secrets
- [ ] No secrets in repo, history, or logs; `.env` in `.gitignore` before the first key exists
- [ ] Keys loaded from environment/keychain, never hardcoded, never printed

## Input boundaries
- [ ] Every network/IPC/file input validated at the boundary (size, type, range) before use
- [ ] Binary/frame parsers reject malformed, truncated, and oversized frames without crashing
- [ ] Anything that injects into the OS (CGEvent, shell, AppleScript) treats remote input as hostile: rate-limited, bounds-checked, allowlisted event types

## Permissions
- [ ] Request the minimum (Accessibility, local network, motion); each request justified in DESIGN.md
- [ ] Denial is handled gracefully and surfaced — no silent broken state, no permission-nag loop

## Network
- [ ] Unauthenticated LAN listeners documented as such, bound to the narrowest interface that works
- [ ] Anything crossing the internet: TLS, no exceptions
- [ ] Replay/spoof considered for control messages (clicks, keys) — a neighbor on the LAN should not be able to click your Mac

## Supply chain
- [ ] New dependencies get an ADR: maintenance status, license, what it can reach
- [ ] Gating CI workflows pin third-party actions to reviewed **commit SHAs**
      (kit templates ship `@vN` placeholders — pinning is a Stage 2 CI-setup
      step; anything with `contents: write` is pinned before first use, no
      exceptions)
- [ ] Lockfiles committed

## AI-specific
- [ ] Model-generated code diffed and reviewed before execution — especially anything touching `rm`, git history, network, or credentials
- [ ] Prompt packets never contain secrets (they get pasted into third-party chat apps)
