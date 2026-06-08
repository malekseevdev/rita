# Agent integrations

Rita's framework is designed to be executed by an AI agent.  This
directory holds the integrations.

If you haven't already, clone Rita first:

```bash
git clone https://github.com/malekseevdev/rita.git
cd rita
```

The install commands below assume you're inside the cloned
`rita/` directory.

## Claude Code

Three Claude Code skills live under [`claude-code/`](claude-code/):

- [`rita-plan/`](claude-code/rita-plan/) — plan and ship a
  non-trivial feature through the Rita lifecycle.  Its folder bundles
  `SKILL.md` plus symlinks to Rita's `docs/` and `templates/`.
- [`rita-review/`](claude-code/rita-review/) — grade an existing Rita
  feature folder against the shared `RUBRIC.md` and print a scorecard.
  Plan-time and doc-internal; useful before review, or to compare plans
  from different models.
- [`rita-drift/`](claude-code/rita-drift/) — audit a feature folder
  against the *code*: mechanical drift (`drift_check.py`), doc↔code
  gaps, open questions, and stalled status, with fix options to choose
  from.  Run during implementation and at maintenance reviews.

Install both with the helper script from the repo root:

```bash
./install-claude-skills.sh                       # user-level: ~/.claude/skills/
./install-claude-skills.sh /path/to/your-project # project-scoped: <project>/.claude/skills/
```

The default (no argument) installs to `~/.claude/skills/`, where the
skills are available in every project on this host.  Pass an explicit
project directory to scope the install to that project only.  Either way,
the script resolves the `docs/` and `templates/` symlinks at copy time so
each installed skill folder is self-contained.

If you'd rather skip the script, the equivalent one-liner per skill is:

```bash
cp -rL skills/claude-code/rita-plan <your-project>/.claude/skills/
```

The `-L` flag is the load-bearing part — it resolves the
symlinks so the copied skill folder no longer depends on the
location of the Rita repo.

Then in Claude Code, invoke `rita-plan` when starting a non-trivial
feature task, `rita-review` to grade a plan, or `rita-drift` to audit a
feature folder against the code.

To update installed skills when Rita changes, just re-run the
installer — it replaces any existing skills at the target.

## Generic agent prompt

[`agent-prompt.md`](agent-prompt.md) is a harness-agnostic prompt
for any agent (Cursor, Continue, GitHub Copilot Workspace, etc.)
when you start feature work.

Unlike the Claude Code skill, the generic prompt doesn't bundle
docs/templates — it references them by absolute path on the
host where the Rita repo is checked out.  Before pasting the
prompt, edit `<RITA-ROOT>` to the path where Rita lives on
disk.  Without a working path the prompt is inert.

If your harness has a native skill / rule format and you'd like
a bundled version, the Claude Code skill's structure is a
reasonable template — copy the SKILL.md, swap the frontmatter
for whatever your harness expects, keep the relative-path
references intact.

## What's coming

- Cursor `.cursorrules` snippet — TODO
- Continue and other harness-specific shims — TODO

All integrations are thin wrappers that point the agent at
Rita's [`docs/how-to.md`](../docs/how-to.md) as the procedural
reference.  The framework lives in the docs; the integrations
just route agents there.
