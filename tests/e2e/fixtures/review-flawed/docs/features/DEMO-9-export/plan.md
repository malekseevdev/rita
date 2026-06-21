# DEMO-9: plan

## Implementation steps

1. Add `export_job` table and enqueue endpoint.
2. Add worker that renders CSV and uploads to the bucket.
3. Add polling endpoint + UI button.

## Concerns

- Performance: N/A
- Security: N/A

## Dependencies

- Object-store bucket provisioned by infra.

## Deployment plan

Ship behind nothing; it's additive.

## Rollback strategy

TODO

## Definition of done

- [ ] Export works.
- [ ] Tests added.
