# DEMO-2: Widget processing

> Status: Shipped
> Last reviewed: 2026-03-01
> Ticket: DEMO-2

## Overview

Renders widgets, with an optional fast path.

## How it works

The rendering logic lives in [`src/widget.py`](../../../src/widget.py).
Each processed widget increments a usage counter.

## Configuration

- `FEATURE_WIDGET_FAST` — set to `1` to enable the fast rendering path.

## Open questions

- :warning: needs human input: should the fast path be the default for
  internal tenants? Unresolved since launch.
