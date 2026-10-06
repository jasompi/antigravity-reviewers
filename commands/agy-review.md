---
description: Run an Antigravity (agy) review — code, security, architecture, design, test, or all
argument-hint: "[code|security|architecture|design|test|all] [scope or focus...]"
---

Run an Antigravity CLI (`agy`) review. Follow the `antigravity-review` skill.

Arguments: `$ARGUMENTS`

1. Review type: if the first word is one of `code`, `security`, `architecture`, `design`, `test` or `all`, use it. Otherwise default to `code` and treat all the arguments as scope/focus.
2. Scope/focus: read the rest of the arguments as the scope (e.g. "last commit", "this branch", file paths, "whole repo") plus any focus. With no scope, use the agent's default.
3. Dispatch `antigravity-reviewers:<type>-reviewer` in the **foreground**, passing the scope, focus and script path `${CLAUDE_PLUGIN_ROOT}/scripts/agy-review.sh`. For `all`, run code → security → test → architecture → design one at a time, and finish with a combined summary of verdicts and Critical/High findings.
