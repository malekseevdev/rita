# <Ticket-ID>: feasibility

Record every load-bearing assumption of the preferred solution
and verify each with the smallest possible test.  An assumption
is load-bearing if the plan dies when it fails.

This file stays in the folder after shipping — it's the record
of what was true at planning time.  If you're modifying the
feature later, re-verify the relevant blocks and update them
(or note that they're no longer load-bearing for the new shape).

See [`docs/how-to.md`](../../../docs/how-to.md#2-feasibility-check)
for the reasoning.  A verified block that comes back
*Observed ≠ Expected* kills the approach — loop back to *Options*, don't
build the plan on it.  An assumption you *can't* verify now (needs
infra, production, or a human answer) does **not** block: flag it below
and write the full plan anyway.

Only the **genuinely uncertain** load-bearing assumptions go here — the
ones that depend on something external you could be *wrong* about.  Do
not verify the self-evident ("the stdlib has `time`"), and do not test
code the plan will ship (a token bucket enforces its limit) — that's
`test-cases.md`.  Many self-contained features have **no verifiable
block at all** — just a few flagged external unknowns, or nothing.  That
is the honest, common result; don't manufacture a block to fill the
section.

Use the **verified-block** format for an uncertain assumption you can
check cheaply *and meaningfully* up front:

---

#### <short label>

- **Assumption:** <one sentence — what must be true for the plan to work>
- **Failure-mode:** <observable thing that would be different if false>
- **Command:** `<single shell command, copy-pasteable>`
- **Env:** <runtime version, distro, dependencies — whatever
  makes the verification reproducible>
- **Expected exit:** 0
- **Observed exit:** 0
- **Observed output:**
  ```
  <last ~10 lines of stdout/stderr that prove the assumption>
  ```
- **Recorded:** YYYY-MM-DD by <username>

<!-- Add more verified blocks below as needed.  If an assumption is too
     expensive to verify directly, add a Proxy-gap field:
     - **Proxy-gap:** <what the proxy doesn't cover>
-->

## Unverified external unknowns (need human input)

For load-bearing assumptions you *can't* honestly check from here
(production environment, a service you don't run, infra topology) —
flag them; never fake an *Observed exit*.  Delete this section if there
are none.

#### <short label of an external unknown>

- **Assumption:** <what must hold for the plan to work>
- **Failure-mode:** <what breaks if it doesn't>
- **Why unverified:** <why it can't be checked from the planning env>
- :warning: **needs human input:** <the specific question for the author>
