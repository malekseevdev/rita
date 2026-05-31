#!/usr/bin/env python3
"""Render a `claude -p --output-format stream-json` event log as readable
progress on stderr.

Reads the JSONL stream on stdin and prints, as it arrives:
  - the model's narration text
  - one line per tool call (name + a short hint: command / file / skill)

So a long headless run shows what it's doing instead of sitting silent.
Pipe a `claude -p ... --output-format stream-json --verbose` stdout
through it (tee the raw stream to a file first if you also need the final
result event).
"""

import json
import sys


def main() -> int:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        t = e.get("type")
        if t == "system" and e.get("subtype") == "init":
            print("  » session started", file=sys.stderr, flush=True)
        elif t == "assistant":
            for b in e.get("message", {}).get("content", []):
                if b.get("type") == "text":
                    txt = b.get("text", "").strip()
                    if txt:
                        print("  " + txt.replace("\n", "\n  "), file=sys.stderr, flush=True)
                elif b.get("type") == "tool_use":
                    inp = b.get("input", {}) or {}
                    hint = inp.get("command") or inp.get("file_path") or inp.get("path") or inp.get("skill") or ""
                    hint = str(hint).splitlines()[0][:90] if hint else ""
                    hint = f"  {hint}" if hint else ""
                    print(f"    ⚙ {b.get('name')}{hint}", file=sys.stderr, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
