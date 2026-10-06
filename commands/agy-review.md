---
description: Run an Antigravity (agy) review — code, security, architecture, design, test, all, or a document (resume, plan, idea, report, presentation, document)
argument-hint: "[code|security|architecture|design|test|all|resume|plan|idea|report|presentation|document] [scope, file or focus...] [with opus|gpt-oss|...]"
---

Run an Antigravity CLI (`agy`) review.

Arguments: `$ARGUMENTS`

1. Review type: if the first word is one of `code`, `security`, `architecture`, `design`, `test`, `all`, `resume`, `plan`, `idea`, `report`, `presentation` or `document`, use it. Otherwise default to `code`, unless the arguments name a document (a resume, plan, report, deck…), in which case pick the matching document type.
2. Scope/focus: read the rest of the arguments as the scope (e.g. "last commit", "this branch", file paths, "whole repo", or the document and its reference files) plus any focus.
3. Model: if the arguments name a reviewer model ("with opus", "using gpt-oss", "flash"), pass it as `--model` (aliases: `opus`, `sonnet`, `gemini`, `flash`, `gpt-oss`).
4. **Code types**: follow the `antigravity-review` skill and dispatch `antigravity-reviewers:<type>-reviewer` in the **foreground**, passing the scope, focus, model and script path `${CLAUDE_PLUGIN_ROOT}/scripts/agy-review.sh`. `all` means the five code types only: run code → security → test → architecture → design one at a time, and finish with a combined summary of verdicts and Critical/High findings.
5. **Document types**: follow the `agy-doc-review` skill inline in this conversation (no agent): gather the document and its references, run the review, triage, ask, then revise.
