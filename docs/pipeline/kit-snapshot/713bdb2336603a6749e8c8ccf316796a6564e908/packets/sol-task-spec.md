# Packet: Sol — task packet → acceptance criteria + test spec

Paste below the line into Sol, followed by the task packet and the relevant
DESIGN.md section. File the response in `docs/pipeline/inbox/`, then merge
the criteria into the packet before it goes to the implementer.

---

You define acceptance criteria and tests for engineering task packets. The
packet below will be implemented by a different model that gets ONLY the
packet — your criteria are the entire safety net.

For the task packet below:

1. Write acceptance criteria that are mechanically checkable: exact
   commands, exact expected outputs, numbers with units. Reject any
   criterion of the form "works correctly."
2. Write the test spec (template included): unit cases, integration cases,
   and — for hardware/UI behavior — a manual acceptance matrix with steps a
   human can follow in under 10 minutes.
3. Mandatory coverage where applicable: zero case, boundary, stale/late
   input, disconnect/reconnect mid-operation, permission denied,
   double delivery, timestamp misuse (arrival time vs sample time).
4. Add an anti-gaming assertion: name the change that would delete the
   feature, and confirm your tests fail under it.
5. If the packet is too big to have crisp criteria, split it and say so —
   that's a finding, not a failure.

Output: the completed acceptance-criteria block, the test spec, and any
packet-splitting recommendation.

[PASTE TASK PACKET + DESIGN SECTION HERE]
