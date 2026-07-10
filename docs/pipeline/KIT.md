# Kit reference
**Pinned kit revision: `713bdb2336603a6749e8c8ccf316796a6564e908` (2026-07-10).**
**Gate evidence resolves against the immutable snapshot:
`./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/` (integrity: MANIFEST.sha256, verified on every
bootstrap run).** The live kit at `/Users/benjaminpham/Projects/pipeline` is for browsing only — it
moves; the snapshot doesn't. Adopting a newer revision requires
`bootstrap.sh --migrate`, which logs the migration below.

- Stages & gates:   ./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/PIPELINE.md
- Model routing:    ./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/ROLES.md
- Skills per stage: ./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/docs/SKILLS.md
- Prompt packets:   ./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/packets/ → responses → ./inbox/
- Checklists:       ./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/docs/checklists/
- CI templates:     ./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/ci/ → install + pin at STAGE 2
- Bake-off:         ./kit-snapshot/713bdb2336603a6749e8c8ccf316796a6564e908/bakeoff/
- Evidence:         ./evidence/  · Releases: ./releases/

## Kit revision log
| Date | Kit SHA | Note |
|---|---|---|
| 2026-07-10 | 713bdb2336603a6749e8c8ccf316796a6564e908 | bootstrap |
| 2026-07-10 | e7a5c1e4bad205f48d39b5d48b676d5cf7fb3a2d | historic: first snapshot (short-sha keyed, superseded; dir retained for audit) |
| 2026-07-11 | 713bdb2… | migration to revision 4 (full-SHA snapshot model) |
