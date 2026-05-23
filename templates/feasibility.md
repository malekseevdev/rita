# <Ticket-ID>: feasibility

Record every load-bearing assumption of the preferred solution
and verify each with the smallest possible test.  An assumption
is load-bearing if the plan dies when it fails.

This file stays in the folder after shipping — it's the record
of what was true at planning time.  If you're modifying the
feature later, re-verify the relevant blocks and update them
(or note that they're no longer load-bearing for the new shape).

See [`docs/how-to.md`](../../../docs/how-to.md#feasibility-check)
for the format and [`docs/rationale.md`](../../../docs/rationale.md#why-feasibility-check)
for the reasoning.  **Don't write anything past *Preferred solution*
in [`plan.md`](plan.md) until every block here has
*Observed exit == Expected exit*.**

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

<!-- Add more blocks below as needed.  If an assumption is too
     expensive to verify directly, add a Proxy-gap field:
     - **Proxy-gap:** <what the proxy doesn't cover>
-->
