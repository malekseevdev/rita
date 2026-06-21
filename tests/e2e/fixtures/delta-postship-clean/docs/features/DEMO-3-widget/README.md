# DEMO-3: Widget processing

> Status: Shipped
> Last reviewed: 2026-06-10
> Ticket: DEMO-3

## Overview

Renders widgets, with an optional fast path.

## How it works

The rendering logic lives in [`src/widget.py`](../../../src/widget.py).
Each processed widget increments a usage counter.

## Configuration

- `FEATURE_WIDGET_FAST` — set to `1` to enable the fast rendering path.
