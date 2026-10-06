# antigravity-reviewers

Get an independent second opinion on your work from **Google's Antigravity CLI (`agy`)**. Claude orchestrates and agy does the reviewing, read-only. You get agy's findings, Claude's honest take on them, and a choice of what to fix.

Five review types:

| Type | What agy looks at |
|---|---|
| **Code** | correctness, error handling, concurrency, leaks, performance, readability |
| **Security** | injection, authn/authz, secrets, input handling, SSRF, crypto, data exposure, supply chain |
| **Architecture** | boundaries, coupling, layering, over/under-engineering, failure modes, operability |
| **Design** | API / CLI / schema / UI consistency, ergonomics, error contracts, compatibility |
| **Test** | coverage gaps, edge cases, assertion quality, flakiness, over-mocking |

## Usage

Just ask. "agy", "antigravity" and "gemini" all route to this plugin:

```
ask agy to review my changes
using antigravity to review the last commit
ask gemini to review this branch before I open a PR
ask gemini to do a security review of src/auth
using antigravity to review the architecture
ask agy whether the new CLI flags are intuitive
ask gemini if we're missing test cases
```

Or use the command:

```
/agy-review [code|security|architecture|design|test|all] [scope or focus...]
/agy-review security src/api
/agy-review all this branch
```

Scopes: uncommitted changes (default), staged, last commit, a commit range, current branch vs. base, specific files/dirs, the whole repo, or a document such as a design proposal.

Each review:
1. collects the scope deterministically (`git diff HEAD`, `git show HEAD`, `git diff base...HEAD`, …)
2. runs `agy --mode plan --sandbox` with a type-specific rubric, so agy can read the repo but can't change it
3. shows the findings by severity (Critical / High / Medium / Low) and a verdict (`BLOCK`, `NEEDS_WORK`, `APPROVE_WITH_NITS`, `APPROVE`), plus Claude's agree/disagree triage
4. asks what to address, and makes no edits until you choose

The full raw review is saved to `$TMPDIR/agy-reviews/` (outside your repo).

> If another plugin also answers "ask gemini to review…", disable one of them to avoid ambiguous routing.

## Installation

Five steps. Steps 2, 4 and 5 are what let agy run unattended. If you skip them, reviews fail with permission or sandbox errors.

### 1. Install the Antigravity CLI and sign in

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```

See https://antigravity.google/download. Make sure `~/.local/bin` is on your `PATH`, then sign in once interactively:

```bash
agy
```

### 2. Pre-approve agy's read-only tools

The plugin runs agy headless (`agy -p`), so agy can't ask you to approve a tool. Any shell command or URL fetch that isn't pre-approved is auto-denied, and the review is lost (`headless mode cannot prompt … auto-denied`). Add these rules to `~/.gemini/antigravity-cli/settings.json`, merging with what's already there:

```json
{
  "permissions": {
    "allow": [
      "command(git diff)",
      "command(git log)",
      "command(git show)",
      "command(git status)",
      "command(git ls-files)",
      "command(git grep)",
      "command(git blame)",
      "command(grep)",
      "command(ls)",
      "command(cat)",
      "command(head)",
      "command(tail)",
      "command(wc)"
    ]
  }
}
```

- Each rule must be `tool(target)`. agy silently drops bare names such as `"command"`.
- `command(git diff)` is a prefix rule: it allows `git diff` with any arguments.
- Don't use wildcards such as `command(*)`. Together with `--mode plan --sandbox`, these rules keep agy read-only.
- The reviewer prompt tells agy to use only these commands and not to fetch URLs. To let it check online docs, add domain rules such as `"read_url(code.claude.com)"`.

### 3. Install the plugin

From a marketplace that lists it:

```
/plugin install antigravity-reviewers
```

Or load it locally:

```bash
claude --plugin-dir /path/to/antigravity-reviewers
```

### 4. Put `agy-review` on your PATH

The Claude Code sandbox and permission rules match the literal command Claude runs. A rule for `agy` doesn't cover a script that calls agy, and a rule can't match a long plugin path reliably. So expose the script under a short, stable name:

```bash
SCRIPT="$(find ~/.claude/plugins /path/to/antigravity-reviewers -path '*antigravity-reviewers/scripts/agy-review.sh' 2>/dev/null | sort | tail -1)"
ln -sf "$SCRIPT" ~/.local/bin/agy-review
agy-review --help
```

Re-run the `ln` line after a plugin update, because the installed path includes the version. The reviewer agents use `agy-review` when it's on `PATH`, and fall back to the full script path otherwise.

### 5. Allow `agy-review` in Claude Code

Add these to `~/.claude/settings.json` (or the project's `.claude/settings.json`), merging with what's already there, then restart Claude Code:

```json
{
  "permissions": {
    "allow": ["Bash(agy-review *)"]
  },
  "sandbox": {
    "excludedCommands": ["agy-review *"]
  }
}
```

- `permissions.allow` lets the reviewer agent run the review without a permission prompt each time.
- `sandbox.excludedCommands` is needed only if Claude Code sandboxing is on. agy binds a localhost port and calls Google's servers, and the sandbox can block both (`bind: operation not permitted`, or sign-in and network errors). The entry needs the trailing ` *`: a pattern without a wildcard matches only the bare command with no arguments. The entry also matches only when the command is run by itself, with no `cd`, `&&`, `$(...)` or redirects, and the agents run it that way.
- If you'd rather not exclude it, the agent retries a sandbox failure once with the sandbox disabled, and you approve that retry when asked.

## Configuration

Optional environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `AGY_REVIEW_MODEL` | agy default | model passed to `agy --model` (see `agy models`) |
| `AGY_REVIEW_EFFORT` | `high` | `low`, `medium`, `high`, `xhigh`, `max` |
| `AGY_REVIEW_TIMEOUT` | `12m` | agy `--print-timeout`; keep it under 15m (the Bash tool limit) |
| `AGY_REVIEW_OUT_DIR` | `$TMPDIR/agy-reviews` | where raw reviews are saved |

You can also ask for these in plain language, e.g. "ask agy to review with max effort".

## Running the script directly

```bash
agy-review <code|security|architecture|design|test> \
  [--uncommitted | --staged | --last-commit | --range A..B | --branch [BASE] |
   --files PATH... | --repo | --context-file FILE] \
  [--focus "text"] [--model M] [--effort E]
```

Exit codes: `0` ok, `2` usage error, `3` nothing to review, `124` timeout, `127` agy not installed. Any other code is agy's own exit code.

## Troubleshooting

| Problem | Fix |
|---|---|
| `agy` not found | Install it (step 1) and make sure `~/.local/bin` is on your `PATH`. |
| `headless mode cannot prompt … auto-denied` | agy wanted a tool you haven't pre-approved. Add `tool(target)` allow-rules (step 2). |
| `agy-review: command not found` | Create the symlink (step 4). Re-create it after plugin updates. |
| `bind: operation not permitted` | The Claude Code sandbox is blocking agy. Exclude `agy-review *` (step 5), run the review as plain `agy-review …`, and restart the session. |
| Eligibility / 401 / 403 / network errors | Run `agy` interactively to sign in again. With sandboxing on, it can also mean the sandbox is blocking agy's network access (step 5). |
| Review times out | Narrow the scope, use `--effort medium`, or raise `AGY_REVIEW_TIMEOUT` (max ~14m). |
| "Nothing to review" | The working tree is clean. Ask for the last commit, the branch, or specific files. |
| The review never starts | Reviewer agents must run in the **foreground**. Background agents can't approve Bash prompts. |

## Plugin layout

```
.claude-plugin/plugin.json
skills/antigravity-review/SKILL.md   # routing + setup guidance
agents/*-reviewer.md                 # code, security, architecture, design, test
commands/agy-review.md               # /agy-review
prompts/_common.md, prompts/*.md     # shared reviewer contract + per-type rubrics
scripts/agy-review.sh                # scope collection + agy invocation
```

## Author

Jasom Pi (jasom.pi@gmail.com)
