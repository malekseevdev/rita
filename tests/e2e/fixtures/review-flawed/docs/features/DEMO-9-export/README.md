# DEMO-9: Async CSV export for reports

> Status: Plan
> Last reviewed: 2026-05-01
> Ticket: DEMO-9

## Overview

Let users export a report as CSV. Because some reports are large, the
export runs as a background job and the user downloads the file when it's
ready.

## Why

Users currently copy-paste tables by hand. A one-click CSV export removes
that toil and unblocks finance's monthly close.

## Options considered

| Option        | Pros                          | Cons                         |
| ------------- | ----------------------------- | ---------------------------- |
| (preferred) A: background job + object store | scales to large reports; download link is shareable | needs a worker + bucket |
| B: synchronous export in the request | simplest | times out on large reports |

Preferred: **A** — synchronous export can't handle the big finance reports.

## Impact

- **Users:** report viewers gain an Export button.
- **Systems:** adds a worker queue and an object-store bucket.

## How it works

The request enqueues an `export_job`; a worker renders the CSV and writes
it to the bucket; the UI polls `export.jobs.completed` and shows a link.

## Configuration

`EXPORT_BUCKET`, `EXPORT_JOB_TTL_HOURS`.
