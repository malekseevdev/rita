# <Ticket-ID>: <feature name>

> Status: Plan
> Last reviewed: YYYY-MM-DD
> Ticket: <Ticket-ID>

| Document                                 | Purpose                            |
| ---------------------------------------- | ---------------------------------- |
| This file                                | What the feature is and how it works |
| [feasibility.md](feasibility.md)         | Load-bearing assumptions + verifications (evergreen) |
| [plan.md](plan.md)                       | Implementation logistics — ephemeral, deleted at ship |
| [test-cases.md](test-cases.md)           | User-perspective scenarios         |
| [metrics.md](metrics.md)                 | Metrics catalog and baseline       |
| [runbook.md](runbook.md)                 | Agent-friendly operational runbook |

## Overview

One paragraph.  What does this feature do?  Aimed at someone who
has never heard of it.

## Why

The problem this solves.  Don't paste the ticket — distil it.

## Options considered

| Option        | Pros                | Cons                  |
| ------------- | ------------------- | --------------------- |
| (preferred) A | ...                 | ...                   |
| B             | ...                 | ...                   |
| Do nothing    | No cost             | Problem remains       |

Always include "Do nothing" — it forces you to justify the work.

**Preferred:** which option and why.  This stays in the doc after
shipping — readers in a year will want to know which alternatives
were weighed.

## Impact

What this feature affects across the system and the business.
On-call and future modifiers read this section to understand
the blast radius without re-deriving it from code.

**Cross-component (always check):**

- **Audience** — which user segments / customer tiers does
  this affect?
- **Coordinated changes** — which other services require
  matching changes?  Which can be deployed independently and
  which must go together?
- **Client compatibility** — does any client-side software
  need a new version?  Are older clients safe?
- **Backwards compatibility** — do existing APIs, configs, or
  on-disk formats break?

**Project-specific (delete or replace with items relevant to
your project):**

- **Replication / persistence** — does this write to a
  database that fans out to replicas / followers?
- **Admin UI** — new pages, new controls, or changes to
  existing views?
- **Edge / gateway** — routing, caching, headers, or
  rate-limiting changes at the proxy layer?
- **Analytics / data warehouse** — new tables, new columns,
  or changed ingestion?
- **External systems** — issue tracker, chat, error-tracking,
  object storage, third-party feeds?

<!-- Sections below are filled in during implementation: -->

## How it works

End-to-end flow.  Use file:line references for entry points and key
functions so readers can jump to code.

## System interactions

Map of how this feature talks to other systems (HTTP endpoints,
databases, queues, caches, external services, downstream consumers).

## Configuration

Settings, feature flags, environment variables that gate the feature.
Include defaults and what enabling each one does.
