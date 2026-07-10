# SKILLS.md — harness skills per stage

Models working in Claude Code (or an editor with equivalent skills) use
these instead of freehanding the stage. Skills are invoked with the Skill
tool / slash command. Codex-side: the codex plugin (`codex:rescue`,
`codex:setup`) bridges GPT models; Grok launches from within Codex.
This map is kit-maintained — retros add/remove rows.

| Stage | Skill | Why |
|---|---|---|
| 0–1 idea → PRD | `superpowers:brainstorming` | one-question-at-a-time intake for vague ideas; options with a recommendation |
| 1–2 planning | `superpowers:writing-plans` | turns the approved design into an executable plan doc |
| 2 design (UI) | `frontend-design` / `design-taste-frontend` | direction cards, anti-templated output |
| 2 design (charts) | `dataviz` | before writing any chart code |
| 2 design (Paper) | `paper-desktop:design-to-code` / `code-to-design` | design file ↔ codebase round-trip |
| 2 docs lookup | `context7` (plugin) | current library/API docs instead of memory |
| 3–4 implementation | `superpowers:test-driven-development` | red-before-green is a gate, this enforces it |
| 4 isolation | `superpowers:using-git-worktrees` / EnterWorktree | packet work isolated from the main tree |
| 4 parallel packets | `superpowers:dispatching-parallel-agents` / `superpowers:subagent-driven-development` | independent packets fan out |
| 4–5 debugging | `superpowers:systematic-debugging` | reproduce → localize → mechanism, matches the kit protocol |
| 5 review | `code-review` (harness) / `superpowers:requesting-code-review`, `receiving-code-review` | structured findings; verify feedback instead of performing agreement |
| 5 verification | `verify` / `run` + preview tools, `superpowers:verification-before-completion` | drive the real flow before claiming PASS |
| 5 second opinion | `codex:rescue` | hand a diagnosis/review to Codex-side models with context |
| 6 release | `superpowers:finishing-a-development-branch` | merge/PR/cleanup decision structure |
| 7 retro | `anthropic-skills:consolidate-memory` (Fable memory) + kit retro template | lessons land in files, not vibes |

Rules:
- If a listed skill exists in the session, using it is the default; skipping
  it is a reviewable decision.
- Skills are per-harness: ChatGPT/Grok sessions can't invoke these — their
  packets must therefore be self-contained (which is why the packet format
  exists).
- New personal skills: `~/.claude/skills/<name>/SKILL.md` (see CLAUDE.md);
  if a retro shows the same manual step three times, that's a skill.
