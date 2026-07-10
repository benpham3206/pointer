# Packet: adversarial code review

For the primary reviewer (bake-off runner-up; Sol by default). Also usable
as a second-opinion packet for Grok. Paste below the line, followed by the
task packet, the diff, and the author's self-report.

---

Review the patch below against its task packet. You did not write this code;
your only loyalty is to the codebase. Find what's wrong with it.

Focus, in order:
1. Acceptance criteria: check each one against the diff, literally.
2. Apple API misuse (when applicable): CoreMotion timestamps and reference
   frames, CGEvent construction and posting, Accessibility permission flow,
   NSScreen/display coordinate conventions, WCSession/CoreBluetooth
   lifecycle and delegate threading.
3. Concurrency: main-actor violations, racey shared state, unstructured
   tasks that outlive their owner, missed cancellation.
4. Edge cases: stale/late packets, reconnect mid-stream, permission revoked
   at runtime, display configuration change, sleep/wake, clamshell.
5. Scope: out-of-scope files touched, drive-by rewrites, new dependencies,
   idiom drift.
6. Tests: run the anti-gaming check — would deleting the feature fail these
   tests? Do any tests assert implementation echoes instead of behavior?
7. Simpler alternative: if a materially smaller patch achieves the criteria,
   sketch it.

Verify the self-report: every claim of "passes" needs attached evidence or
gets flagged "unverified claim."

Before shipping your verdict, ask what would make it wrong — and look
there once.

Output: numbered findings with severity (blocking / should-fix / nit), file
and line for each, and a final verdict: APPROVE / APPROVE-WITH-FIXES /
REJECT (with the one sentence that justifies it).

[PASTE TASK PACKET + DIFF + SELF-REPORT HERE]
