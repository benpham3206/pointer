# Release checklist

Attached to every tag. [BEN] items are human-only.

- [ ] `regression.md` completed and attached
- [ ] CI green on the exact commit being tagged
- [ ] Version bumped (semver) + CHANGELOG entry written for humans, not for git
- [ ] Docs updated: README quickstart actually works on a machine that isn't yours
- [ ] Secrets audit: `git log -p` since last tag greps clean for keys/tokens
- [ ] `security.md` checklist run if any network/permission/input surface changed
- [ ] Rollback path written down: the exact commands to get back to the previous release
- [ ] Artifacts built by CI, not by hand; checksums/signing/notarization done (Apple: notarize + staple, or TestFlight)
- [ ] [BEN] Smoke test on the real device/environment
- [ ] [BEN] The publish itself (App Store submit, `gh release`, deploy to prod) — one-way door
- [ ] STATE.md updated: what shipped, what's next, where the bodies are buried
