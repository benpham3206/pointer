# Packet: Fable — integration review

Run in a Claude Code session in the project repo, after the correctness
review passes. Fable has repo access, so this packet lists what to check
rather than what to paste.

---

Integration review for <packet ID>. The patch passed correctness review.
Your question is narrower and different: **does this belong in this
codebase, here, shaped like this?**

1. Architecture fit: does the change live in the module DESIGN.md assigns
   to this concern? Logic in a transport layer, UI state in a manager, or
   parsing in a view = REJECT with the correct location named.
2. Boundary respect: no new coupling between modules that were independent;
   data crosses boundaries in the established format, not a new ad-hoc one.
3. Idiom: consistent with the file it lives in (error style, naming,
   logging shape). One codebase, one voice.
4. Trajectory: after this patch, is the next similar change easier or
   harder? A patch that works but paints the architecture into a corner is
   a should-fix.
5. Docs/STATE: README, DESIGN.md, and STATE.md updated if the patch moved
   any ground truth they describe.

Verdict: APPROVE / APPROVE-WITH-FIXES / REJECT, logged in the packet's
review table. Then hand to Ben for the human run (Stage 5.3).
