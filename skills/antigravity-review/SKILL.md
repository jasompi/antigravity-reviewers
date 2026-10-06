---
name: antigravity-review
description: Use when the user wants an outside AI review from Google's Antigravity CLI (agy), including phrases like "using antigravity to review", "ask agy to review", "ask antigravity to review", "ask gemini to review", "have gemini check", "second opinion from gemini/agy", or "gemini security / architecture / design / test review". Picks the review type and dispatches the matching antigravity-reviewers agent. Also covers agy install, sign-in, agy allow-rules and Claude Code sandbox troubleshooting. Load this before dispatching any antigravity-reviewers agent.
---

# Antigravity Review

Gets an independent review from **Google's Antigravity CLI (`agy`)**, a different model from the one that wrote the code. agy runs read-only (`--mode plan --sandbox`). Claude then presents its findings, gives its own triage, and asks the user what to act on.

"gemini", "antigravity" and "agy" all mean this reviewer.

## 1. Pick the review type

| The user asks about… | Agent |
|---|---|
| a general review, bugs, "review my changes/commit/PR" (**default**) | `antigravity-reviewers:code-reviewer` |
| security, vulnerabilities, an audit, secrets, auth | `antigravity-reviewers:security-reviewer` |
| architecture, structure, "over-engineered?", a design doc | `antigravity-reviewers:architecture-reviewer` |
| API / CLI / schema / UI design, ergonomics, "is this intuitive?" | `antigravity-reviewers:design-reviewer` |
| tests, coverage, missing cases, flaky tests | `antigravity-reviewers:test-reviewer` |

For "full review" or several types, run the agents **one after another**, never in parallel.

## 2. Dispatch the agent

- **Foreground only.** Never use `run_in_background`. The agent needs Bash permission prompts, and background agents auto-deny them, so the review silently fails.
- In the agent prompt, include the user's request verbatim, the scope (uncommitted, last commit, branch, files, whole repo, or doc), any specific focus, and the script path:
  `${CLAUDE_PLUGIN_ROOT}/scripts/agy-review.sh`
  The agent prefers the `agy-review` command on `PATH` (see setup) and runs it as a single standalone command, so the user's sandbox and permission rules match it.
- Pass along a model or effort level only if the user asked for one.

The agent runs the script, presents agy's findings with Claude's triage, and asks the user what to fix. Relay its final message to the user. Don't re-review the code yourself.

## 3. Setup and troubleshooting

A working setup needs all of these. The README has the exact JSON:

1. **agy installed and signed in**: run `agy` once interactively.
2. **agy allow-rules** in `~/.gemini/antigravity-cli/settings.json` under `permissions.allow`: read-only `command(...)` rules such as `command(git diff)` and `command(grep)`. agy runs headless, so any unapproved tool is auto-denied. Rules must be `tool(target)`; bare names are dropped.
3. **`agy-review` on PATH**: a symlink to the plugin's `scripts/agy-review.sh`, e.g. in `~/.local/bin`.
4. **Claude Code settings** (`~/.claude/settings.json` or the project's `.claude/settings.json`): `permissions.allow: ["Bash(agy-review *)"]`, plus `sandbox.excludedCommands: ["agy-review *"]` if sandboxing is on. Excluding `"agy"` doesn't work: the sandbox matches the command Claude runs, not the programs a script starts.

Don't edit any of these settings for the user without explicit permission.

| Symptom | Fix |
|---|---|
| `agy` not found (exit 127) | `curl -fsSL https://antigravity.google/cli/install.sh \| bash`, then run `agy` once interactively to sign in. See https://antigravity.google/download |
| `headless mode cannot prompt … auto-denied` | agy needed a tool that isn't pre-approved. Add `tool(target)` allow-rules (item 2). Retrying won't help. |
| `agy-review: command not found` | Create the symlink (item 3), or let the agent use the full script path. |
| `listen tcp 127.0.0.1:0: bind: operation not permitted` | The Claude Code sandbox is blocking agy. Add `"agy-review *"` to `sandbox.excludedCommands` (item 4) and restart the session. The agent may retry once with the sandbox disabled, which needs the user's approval. |
| Eligibility / 401 / 403 / sign-in / network errors | Run `agy` interactively to re-authenticate. With sandboxing on, the sandbox may be blocking network access, so use the sandbox fix above. |
| Timeout (exit 124) | Narrow the scope (specific files, one commit), lower the effort (`--effort medium`), or set `AGY_REVIEW_TIMEOUT=14m`. |
| Nothing to review (exit 3) | The working tree is clean. Try `--last-commit`, `--branch`, or `--files`. |

Environment overrides: `AGY_REVIEW_MODEL`, `AGY_REVIEW_EFFORT` (default `high`), `AGY_REVIEW_TIMEOUT` (default `12m`), `AGY_REVIEW_OUT_DIR` (default `$TMPDIR/agy-reviews`).
