# RITA-1: Rate-limit the public search endpoint

**Type:** Feature
**Component:** search service

## Problem

Our `GET /search` endpoint is public and unauthenticated. We've seen a
single scraper push enough query volume to degrade search latency for
everyone, and right now the only way to stop it is to ship a deploy.

## Ask

Add per-client rate limiting to the search endpoint so abusive clients
get throttled while normal users are unaffected, and give us a way to
turn enforcement off quickly if it misfires.

## Notes / constraints

- The fleet is small and stable today.
- **Standard library only.** The implementation must use only the Python
  standard library — no new third-party runtime dependencies (no
  `flask-limiter`, no Redis client, etc.) and no new infrastructure on
  the request path. The search endpoint is a plain WSGI app, not a
  framework. This keeps the limiter self-contained and verifiable with
  zero installs.
- Clients are keyed by IP (the gateway forwards it).
