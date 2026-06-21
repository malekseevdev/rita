# DEMO-4: plan

## Implementation steps

1. Add a sliding-window counter keyed by client.
2. Reject requests once a client exceeds **100 requests per minute**.
3. Emit a rejection metric.

## Deployment plan

Ship behind a kill switch.

## Definition of done

- [ ] Limit is enforced at 100 requests/minute.
- [ ] The limit is configurable at runtime via `THROTTLE_RATE`.
- [ ] Rejections emit `svc.throttle.rejected`.
