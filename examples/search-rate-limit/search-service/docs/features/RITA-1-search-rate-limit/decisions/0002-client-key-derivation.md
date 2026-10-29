# ADR 0002: deriving the rate-limit client key

- **Status:** Proposed (until the RITA-1 plan is approved)
- **Feature:** RITA-1, per-client rate limiting of `GET /search` in
  `search-service`

## Context

The limiter keys token buckets "per client, by IP" (ticket).  The
service sits behind a gateway, so the TCP peer (`REMOTE_ADDR`) is the
gateway, not the client; the gateway forwards the client IP in a header.
Clients can send their own `X-Forwarded-For`, so naively reading the
first entry lets a scraper choose its key and evade the limit.  Which
header the gateway uses, and whether it appends or overwrites, is
**unconfirmed** (:warning: needs human input, RITA-1 feasibility.md
*Gateway header*).

## Decision

-   Key = the `SEARCH_RATELIMIT_TRUSTED_HOPS`-th entry counted from the
    **right** of `X-Forwarded-For` (default 1 = the entry our gateway
    appended).  Entries to its left are client-controlled and ignored.
    The header name is configurable once the gateway answer is in.
-   IPv4: the address.  IPv6: its `/64` network, because one subscriber
    typically owns a whole /64 and can rotate addresses inside it
    freely.  Parsed with `ipaddress`.
-   No usable key — header missing, fewer entries than `TRUSTED_HOPS`,
    or the chosen entry is not an IP — → the request passes **unlimited**
    and `search.ratelimit.key_fallback{reason=missing|unparsable}` is
    counted.

## Alternatives considered

-   **Leftmost `X-Forwarded-For` entry:** spoofable by the client.
    Rejected.
-   **`REMOTE_ADDR`:** the gateway's address, so every user shares one
    bucket.  Rejected.
-   **A shared `"unknown"` bucket on no key:** a gateway misconfiguration
    that drops the header would then throttle all users at once.
    Rejected in favour of fail-open plus a loud metric.
-   **Per-address IPv6 keys:** trivially evaded.  Rejected.

## Consequences

-   A client cannot reach the fail-open path: it can't remove entries
    the gateway itself appends.  This holds only if the gateway behaves as
    assumed and the app port is reachable only from the gateway.
-   Many users behind one IPv4 NAT, or one IPv6 /64, share a bucket.
    The limits are sized from shadow data to allow for that.
-   If the gateway stops sending the header, protection silently drops
    to zero for users, while `key_fallback` rises (runbook symptom 2).
