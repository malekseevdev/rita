# <Ticket-ID>: plan

<!-- This file is ephemeral — delete it after shipping. -->

Options, trade-offs, and preferred solution live in
[`README.md`](README.md) (evergreen).  Load-bearing assumptions and
verifications live in [`feasibility.md`](feasibility.md) (evergreen).
This file is the working scratchpad — implementation logistics that
don't outlive the launch.

If a feasibility check you *ran* fails (*Observed ≠ Expected*) and there's
no working alternative, don't draft the rest of this plan — rework
`README.md`'s "Options considered" instead.  Assumptions that simply
*can't be verified yet* (infra, production, a human answer) do **not**
block: they're flagged in [`feasibility.md`](feasibility.md), and you
write the full plan around them so the reviewer gets a complete artifact.

## Implementation steps

Ordered sequence.  Aim for steps that can each be merged and tested
independently.  Mark which steps deliver partial value early.

1. ...
2. ...
3. ... <!-- partial value milestone -->
4. ...

## Concerns

For each item, write a brief assessment (1-3 sentences) or
"N/A — <reason>".

- **Performance** — will this add latency, CPU, memory, or I/O
  load?  Estimate the magnitude.
- **Security** — does this touch auth, user input, sensitive data,
  or external APIs?  Does it change trust boundaries?
- **Data migration** — schema changes, backfills, format changes?
  Can they be rolled back?
- **Thread safety** — does this run in multi-threaded or
  multi-process context?  What state is shared?
- **Scalability** — does this work at 10x current load?  What
  breaks first?
- **Observability** — what metrics, logs, and alerts will tell us
  it's working?  (Flesh out in metrics.md.)
- **Failure modes** — what happens when this fails?  What does
  the user/client see?  Is the failure loud or silent?
- **Operability** — does ops need new runbooks, dashboards, or
  on-call knowledge?

## Dependencies

| Dependency           | Type        | Status      |
| -------------------- | ----------- | ----------- |
| <team/system/ticket> | blocks us   | in progress |
| <team/system/ticket> | we block    | not started |

## Deployment plan

- Feature flag name and default (on/off).
- Rollout stages (e.g. staging → 10% → 100%).
- Monitoring to watch during each stage.

## Rollback strategy

- Is it a flag flip, a revert, or a migration rollback?
- What's the blast radius while it's broken?
- Is data at risk (e.g. corrupted state that survives rollback)?

## Definition of done

- [ ] Plan reviewed and approved
- [ ] README.md "Options considered" section finalised
- [ ] feasibility.md frozen with verified blocks
- [ ] Feature doc (README.md) has all shipped-state sections
- [ ] plan.md deleted
- [ ] Metrics for all applicable axes are emitted
- [ ] Metrics catalog in metrics.md lists names + thresholds + dashboards
- [ ] Runbook covers the main failure modes
- [ ] Deployment plan was followed; rollback strategy is documented
- [ ] Concerns checklist has no unresolved items
