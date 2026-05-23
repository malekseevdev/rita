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

[`claude-code/rita-feature/`](claude-code/rita-feature/) is a
Claude Code skill.  The skill folder contains the `SKILL.md`
plus symlinks to Rita's `docs/` and `templates/` directories, so
the install copies everything the agent needs in one shot.

Install with the helper script from the repo root:

```bash
./install-claude-skill.sh                       # user-level: ~/.claude/skills/rita-feature/
./install-claude-skill.sh /path/to/your-project # project-scoped: <project>/.claude/skills/rita-feature/
```

The default (no argument) installs to `~/.claude/skills/`, where
the skill is available in every project on this host.  Pass an
explicit project directory to scope the install to that project
only.  Either way, the script resolves the `docs/` and
`templates/` symlinks at copy time so the installed skill folder
is self-contained.

If you'd rather skip the script, the equivalent one-liner is:

```bash
cp -rL skills/claude-code/rita-feature <your-project>/.claude/skills/
```

The `-L` flag is the load-bearing part — it resolves the
symlinks so the copied skill folder no longer depends on the
location of the Rita repo.

Then in Claude Code, invoke the skill when starting a
non-trivial feature task.

To update an installed skill when Rita changes, just re-run the
installer — it replaces any existing `rita-feature` at the
target.

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
