# antigravity-reviewers

Get an independent second opinion on your work from **Google's Antigravity CLI (`agy`)**. Your agent (Claude Code or Codex) orchestrates and agy does the reviewing, read-only, with Gemini or any other model agy offers, including Claude Opus/Sonnet and GPT-OSS. You get agy's findings, your agent's honest take on them, and a choice of what to change.

It reviews **code** and **documents**: resumes, plans, ideas, reports and slide decks, together with the context they're judged against (a job description, the source data, a brief).

Five code review types:

| Type | What agy looks at |
|---|---|
| **Code** | correctness, error handling, concurrency, leaks, performance, readability |
| **Security** | injection, authn/authz, secrets, input handling, SSRF, crypto, data exposure, supply chain |
| **Architecture** | boundaries, coupling, layering, over/under-engineering, failure modes, operability |
| **Design** | API / CLI / schema / UI consistency, ergonomics, error contracts, compatibility |
| **Test** | coverage gaps, edge cases, assertion quality, flakiness, over-mocking |

Six document review types:

| Type | What agy looks at |
|---|---|
| **Resume** | fit to the job description, missing must-haves, impact, ATS keywords, truthfulness |
| **Plan** | goals and success criteria, missing steps, sequencing, feasibility, risks, owners |
| **Idea** | the problem, value, riskiest assumptions, alternatives, the cheapest test |
| **Report** | numbers checked against the source data, supported conclusions, methodology, executive summary |
| **Presentation** | main message, narrative, one idea per slide, text density, audience fit |
| **Document** | anything else: clarity, structure, accuracy, audience, tone |

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

Documents work the same way, typically right after your agent wrote them:

```
tailor my resume to this job posting, then ask gemini to review it
ask opus via agy to review the launch plan
have gpt-oss check the Q2 sales report against sales.csv
ask agy to review the deck, and just apply the fixes
```

Or use the command:

```
/agy-review [code|security|architecture|design|test|all] [scope or focus...]
/agy-review security src/api
/agy-review all this branch
/agy-review resume resume.md against jd.md with opus
```

Scopes: uncommitted changes (default), staged, last commit, a commit range, current branch vs. base, specific files/dirs, the whole repo, or a document such as a design proposal.

Each review:
1. collects the scope deterministically (`git diff HEAD`, `git show HEAD`, `git diff base...HEAD`, …)
2. runs `agy --mode plan --sandbox` with a type-specific rubric, so agy can read the repo but can't change it
3. shows the findings by severity (Critical / High / Medium / Low) and a verdict (`BLOCK`, `NEEDS_WORK`, `APPROVE_WITH_NITS`, `APPROVE`), plus Claude's agree/disagree triage
4. asks what to address, and makes no edits until you choose

The full raw review is saved to `$TMPDIR/agy-reviews/` (outside your repo).

### Document reviews

Document reviews run in your main conversation, not in a subagent, because that's where the draft and its context live and where the edits happen:

1. **Text first.** If your agent wrote the document, it reviews the Markdown (or other text) source. The revised version can still be exported to Word, PDF or PowerPoint afterwards. A `.docx`, `.pdf`, `.pptx` or `.xlsx` you supply is converted to text by the script (see [converters](#document-converters-optional)).
2. **Context goes along.** Context that only exists in the chat (a pasted job description, your goals, the audience) is written to temp files and sent as references, together with real source files such as the CSV behind a report. The agent tells you what it's sending.
3. agy returns numbered findings (`D1`, `D2`, …) with concrete suggested changes, a **Claims to verify** list, and a verdict (`NOT_READY`, `NEEDS_REVISION`, `MINOR_EDITS`, `READY`).
4. Your agent shows a triage table: accept, partly accept, reject, or **needs your input** for anything that would require facts it doesn't have. It never invents resume metrics or data to satisfy a reviewer.
5. You choose what to apply (or say "just apply" up front). The agent revises the document, lists the changes by finding ID, and offers one re-review.

### Choosing the reviewer model

Say it in the request ("ask opus via agy…", "with gpt-oss") or pass `--model`. Aliases resolve against `agy models` (cached for a day) and pick the newest matching model at your effort level, or the nearest level that exists:

| Alias | Resolves to (example) |
|---|---|
| *(none)* | agy's default model |
| `gemini`, `gemini-pro` | `gemini-3.1-pro-high` |
| `flash` | `gemini-3.8-flash-high` |
| `opus`, `claude` | `claude-opus-5-5-high` |
| `sonnet` | `claude-sonnet-5-5-high` |
| `gpt-oss` | `gpt-oss-120b-medium` (its only level) |

An exact id from `agy models` is passed through unchanged. The model used is printed as `REVIEWER_MODEL:` and included in the saved file name.

> If another plugin also answers "ask gemini to review…", disable one of them to avoid ambiguous routing.

## Installation

Using Codex? Do steps 1, 2 and 4 below, then see [Install in Codex](#install-in-codex).

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

This repo is its own plugin marketplace. In Claude Code:

```
/plugin marketplace add jasompi/antigravity-reviewers
/plugin install antigravity-reviewers@antigravity-reviewers
```

Then restart Claude Code (or run `/reload-plugins`). Later, `/plugin marketplace update antigravity-reviewers` pulls new versions.

Or load it from a local clone for one session:

```bash
claude --plugin-dir /path/to/antigravity-reviewers
```

### 4. Put `agy-review` on your PATH

The quickest way is the setup helper. It creates the symlink, checks agy and the document converters, and prints the settings for steps 2 and 5 without changing them:

```bash
/path/to/antigravity-reviewers/scripts/install.sh
```

Or by hand:

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

### Document converters (optional)

Markdown, text, CSV and HTML need nothing. For other formats, the script uses the first converter it finds:

| Format | Converters, in order |
|---|---|
| `.docx` | `pandoc`, `markitdown` |
| `.pdf` | `pdftotext` (poppler-utils), `markitdown` |
| `.pptx` | `markitdown`, `python-pptx` |
| `.xlsx` | `markitdown`, `openpyxl` |

```bash
sudo apt install pandoc poppler-utils     # or: brew install pandoc poppler
pipx install 'markitdown[all]'            # covers all four formats
```

Converted text goes to a temporary directory; nothing is written next to your files.

## Install in Codex

Codex reads this repo's `.claude-plugin/marketplace.json` and installs the plugin from `.codex-plugin/plugin.json`. You get both skills: `antigravity-review` for code and `agy-doc-review` for documents. Codex has no subagents, so code reviews also run inline, with the same steps.

1. Do installation steps 1, 2 and 4 above: install agy and sign in, add the agy allow-rules, and put `agy-review` on your `PATH` (`scripts/install.sh`).
2. Add the marketplace and install the plugin:

   ```bash
   codex plugin marketplace add jasompi/antigravity-reviewers   # or a local clone's path
   codex plugin add antigravity-reviewers@antigravity-reviewers
   codex plugin list                                            # shows "installed, enabled"
   ```

   Later, `codex plugin marketplace upgrade antigravity-reviewers` pulls new versions.
3. Let `agy-review` run outside Codex's sandbox. agy needs network access and a localhost port, which the default `workspace-write` sandbox blocks. Use one of these:
   - When Codex first asks to run `agy-review` with escalated permissions, approve it and choose to always allow commands that start with `agy-review`. Codex saves that as a rule.
   - Or add the rule yourself, in `~/.codex/rules/default.rules`:

     ```
     prefix_rule(pattern=["agy-review"], decision="allow")
     ```

   An `allow` rule runs the matching command outside the sandbox. It matches only when `agy-review` is run as a plain command, without redirects, `$VARS` or `$(...)`, and the skills run it that way.

Then ask as usual, e.g. "ask gemini to review my changes" or "have opus via agy review this resume against the job description".

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
  [--ref FILE[=LABEL] ...] [--focus "text"] [--model M] [--effort E]

agy-review <resume|plan|idea|report|presentation|document> --doc FILE \
  [--ref FILE[=LABEL] ...] [--focus "text"] [--model M] [--effort E]
```

For example:

```bash
agy-review resume --doc resume.md --ref job.md=job-description --model opus
agy-review report --doc q2-report.md --ref sales.csv=source-data --focus "are the growth numbers right?"
```

Exit codes: `0` ok, `2` usage error (including an unknown model), `3` nothing to review, `4` a document couldn't be converted to text, `124` timeout, `127` agy not installed. Any other code is agy's own exit code.

Tests run offline against a mock agy: `tests/run-tests.sh`.

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
| `cannot convert … to text` (exit 4) | Install a converter ([above](#document-converters-optional)), or review a Markdown export of the document. |
| `cannot resolve model` (exit 2) | Use an alias from the table above, or an exact id from `agy models`. |
| The review never starts | Reviewer agents must run in the **foreground**. Background agents can't approve Bash prompts. |

## Plugin layout

```
.claude-plugin/plugin.json, marketplace.json   # Claude Code plugin + marketplace
.codex-plugin/plugin.json                      # Codex plugin
skills/antigravity-review/SKILL.md   # code-review routing + setup guidance
skills/agy-doc-review/SKILL.md       # document reviews (inline: review, triage, ask, revise)
agents/*-reviewer.md                 # code, security, architecture, design, test (Claude Code)
commands/agy-review.md               # /agy-review
prompts/_common.md, _doc_common.md   # reviewer contracts for code and for documents
prompts/*.md                         # per-type rubrics
scripts/agy-review.sh                # scope collection, conversion, model aliases, agy invocation
scripts/install.sh                   # symlink + setup check
tests/run-tests.sh, tests/mock-agy   # offline tests
```

## Author

Jasom Pi (jasom.pi@gmail.com)

## License

[MIT](LICENSE)
