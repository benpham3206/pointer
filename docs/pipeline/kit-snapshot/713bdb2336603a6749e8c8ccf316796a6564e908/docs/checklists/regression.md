# Regression checklist

Run before any release tag, and after any change to a shared/core path.
The project's PIPELINE instance appends project-specific rows — this is the
universal floor.

- [ ] Full test suite green on a clean checkout (not the working tree)
- [ ] Build from scratch succeeds (no cache): exact command logged
- [ ] The previous release's acceptance criteria still pass (yes, run them)
- [ ] Every bug fixed since last release has a test that fails on the old code
- [ ] Startup/cold-boot path exercised (first run, no config, no permissions yet)
- [ ] Upgrade path: old persisted state/config loads in the new version
- [ ] Degradation paths from DESIGN.md fire correctly when forced (kill the
      dependency, revoke the permission, drop the connection — actually do it)
- [ ] Logs at default verbosity are readable and non-spammy for 5 minutes of use
- [ ] Manual acceptance matrix for hardware-facing features re-run on device

Web/UI-facing additionally (absorbed from the Hermes dogfood skill):
- [ ] Browser console checked after every navigation and significant
      interaction — zero uninvestigated errors
- [ ] Forms exercised with valid, invalid, and empty inputs
- [ ] Rapid/repeated actions (double-submit, spam-click) don't corrupt state
- [ ] Every reported defect carries screenshot + repro steps + expected vs
      actual
