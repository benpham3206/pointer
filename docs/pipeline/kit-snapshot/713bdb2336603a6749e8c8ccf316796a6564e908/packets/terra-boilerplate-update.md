# Packet: Terra — kit self-update from retro

Paste below the line into GPT-5.6 Terra (Codex bridge: `gpt-5.6-terra`,
needs Codex ≥ 0.144), followed by the completed retro and the current kit
file(s) it implicates. Apply returned diffs to the kit repo, log in
CHANGELOG.md, commit.

Terra maintains boilerplate; Terra does NOT hold review authority — if a
retro implies changing ROLES.md routing or PIPELINE.md gates, Terra drafts
and Fable + Ben approve.

---

You maintain the boilerplate of an engineering-pipeline kit. A project just
finished a milestone and filed the retro below. Update the kit so the next
project doesn't repeat this milestone's mistakes.

1. For each "checklist gap" row: produce the exact new checklist line(s),
   in the existing file's voice and format.
2. For each incident where a gate failed to catch a problem: propose the
   minimal change to that gate's artifact or wording that would have caught
   it. Minimal — do not add process for its own sake; every new line costs
   every future project attention.
3. For template friction (fields nobody filled, fields that were missing):
   propose the template diff.
4. For model scorecard rows: summarize the evidence, but do NOT change
   ROLES.md yourself — output a "routing evidence" note for Fable/Ben.
5. Anything in the retro that suggests deleting kit content: prefer the
   deletion. A shorter kit that gets read beats a complete one that doesn't.

Output: unified diffs per kit file + a one-paragraph CHANGELOG entry
(date · source project · what changed · why).

[PASTE RETRO + IMPLICATED KIT FILES HERE]
