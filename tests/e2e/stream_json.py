#!/usr/bin/env python3
"""Extract fields from a `claude -p --output-format stream-json` event log.

Replaces a jq dependency in the e2e tests (python3 is already required).
Reads the JSONL log file and pulls the final `result` event.

Usage:
    stream_json.py <stream-file> result   # print the result text; exit 1 if absent/empty
    stream_json.py <stream-file> usage     # print token / turn / cost lines
"""

import json
import sys


def last_result_event(path):
    event = None
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if e.get("type") == "result":
                    event = e   # keep the last one
    except OSError:
        return None
    return event


def main():
    if len(sys.argv) != 3:
        print("usage: stream_json.py <stream-file> <result|usage>", file=sys.stderr)
        return 2
    path, what = sys.argv[1], sys.argv[2]
    event = last_result_event(path)

    if what == "result":
        text = (event or {}).get("result") or ""
        if not text:
            return 1
        sys.stdout.write(text if text.endswith("\n") else text + "\n")
        return 0

    if what == "usage":
        if not event:
            print("(no result event — claude may have failed)")
            return 0
        u = event.get("usage") or {}
        dur = (event.get("duration_api_ms") or 0) / 1000
        print(f"input_tokens:    {u.get('input_tokens', 'n/a')}")
        print(f"cache_read:      {u.get('cache_read_input_tokens', 0)}")
        print(f"cache_creation:  {u.get('cache_creation_input_tokens', 0)}")
        print(f"output_tokens:   {u.get('output_tokens', 'n/a')}")
        print(f"num_turns:       {event.get('num_turns', 'n/a')}")
        print(f"api_duration:    {dur} s")
        print(f"cost:            ${event.get('total_cost_usd', 'n/a')}")
        return 0

    print(f"unknown mode: {what}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
