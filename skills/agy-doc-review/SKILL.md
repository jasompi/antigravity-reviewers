---
name: agy-doc-review
description: Use when the user wants an outside AI review of a non-code document, such as a resume, cover letter, plan, proposal, idea, report, analysis or presentation/deck, from Google's Antigravity CLI (agy) or any model agy offers (Gemini, Claude Opus/Sonnet, GPT-OSS). Triggers include "ask gemini to review the resume", "have agy review this plan", "using antigravity to review the report", "ask opus via agy to check the deck", "second opinion on this doc from gpt-oss". Sends the document plus its context (job description, source data, brief) to agy, triages the feedback, asks the user, then revises the document.
---

# Antigravity document review

Gets an independent review of a document from **Google's Antigravity CLI (`agy`)**, using a different model from the one that wrote it. agy runs read-only. You (the host agent) then triage its feedback, let the user decide, and revise the document.

Run this **in the main conversation**, not in a subagent. You already hold the draft and its context (the job description, the data, the user's goals), and you are the one who will edit it.

"gemini", "antigravity" and "agy" all mean this reviewer. "opus", "sonnet", "gpt-oss" and "flash" are models agy can use as the reviewer.

## Hard rules

- **agy writes the review, not you.** Run the script and present its output. If agy fails, report the error and the fix the script printed. Don't substitute your own review.
- **No edits before the user decides**, unless the request said to just apply the feedback ("…and apply it", "just fix it").
- **Never invent facts to satisfy a finding.** If a suggestion needs a metric, achievement, date or data point the sources don't contain (common for resumes and reports), mark it **needs your input** and ask the user for the real value.

## 1. Find the document, in a text format

- If you generated the document, or it exists in several formats (Markdown, a doc or artifact that exports to Word/PDF, a deck built from Markdown or HTML), review the **Markdown or other text source**. Write it to a file if it only exists in the chat. Text edits are exact, and the revised version can still be exported to docx, pdf or pptx afterwards.
- A file the user supplied (`.docx`, `.pdf`, `.pptx`, `.xlsx`) can be passed as is; the script converts it to text. If the conversion fails (exit 4), say so and offer to work from a Markdown export instead.

## 2. Gather the context

agy only sees what you send it. Collect what the document is judged against:

- **Context that only exists in the conversation**, such as a pasted job description, the user's goals, the audience, constraints or a brief: write each one to its own file under `${TMPDIR:-/tmp}/agy-doc-review/<short-slug>/`, for example `job-description.md`.
- **Real source files**, such as the sales CSV a report was built from or the previous resume: pass them directly.

Pass each with `--ref FILE=LABEL`. Before running, tell the user in one line which document and references you're sending.

## 3. Pick the type and the model

| Document | Type |
|---|---|
| resume, CV | `resume` |
| project/launch/business/implementation plan, roadmap | `plan` |
| idea, pitch, proposal, product concept | `idea` |
| report, analysis, data summary, status report | `report` |
| slides, deck, presentation | `presentation` |
| anything else (cover letter, essay, email, policy, doc) | `document` |

- `--model` only if the user named one: an alias (`opus`, `sonnet`, `gemini`, `flash`, `gpt-oss`) or an exact id from `agy models`.
- `--effort low|medium|high|xhigh|max` only if the user asked.
- Put the user's specific concerns in `--focus "..."` (for example, "is it strong enough for a staff-level role?").

## 4. Run agy

Find the command in this order: `agy-review` on `PATH` (check with a separate `command -v agy-review`); else `${CLAUDE_PLUGIN_ROOT}/scripts/agy-review.sh` when that variable is set; else `scripts/agy-review.sh` two directories above this skill's own folder.

```bash
agy-review <type> --doc <file> [--ref <file>=<label> ...] [--focus "..."] [--model <m>] [--effort <e>]
```

- Run it as **one standalone command**: no `cd`, `&&`, `;`, pipes, `$(...)`, `VAR=value` prefixes or redirects. Sandbox and permission rules match only that exact shape.
- Allow up to 15 minutes (in Claude Code, Bash `timeout: 900000`).
- **Sandbox failures.** agy needs network access and a localhost port. If it fails with `bind: operation not permitted` or a network or sign-in error the script attributes to the sandbox, retry the same command once outside the sandbox: in Claude Code, `dangerouslyDisableSandbox: true`; in Codex, request escalated permissions. The user approves that retry. If it is declined or still fails, relay the script's setup instructions.

| Exit | Meaning |
|---|---|
| 0 | ok; output ends with `REVIEWER_MODEL:` and `REVIEW_SAVED:` lines |
| 2 | usage error, or an unknown model (the list of models is printed) |
| 3 | the document is empty |
| 4 | can't convert the document to text: relay the install hint, or use a Markdown export |
| 124 | timeout: lower `--effort` or trim the references |
| 127 | agy is not installed |
| other | agy error: relay stderr. If it says a tool was auto-denied in headless mode, don't retry; relay the allow-rule instructions |

## 5. Present the review

1. A header line: `<Reviewer model> review of <document>: <Verdict>`. Use `REVIEWER_MODEL`; "agy default" means agy's default Gemini model.
2. agy's findings by severity. If they are under about 150 lines, show them verbatim. Otherwise keep every Critical and High finding and condense the rest to ID, location and gist. Always include **Claims to verify**.
3. The `REVIEW_SAVED:` path.
4. **Your triage table.** You know the user's intent and the context better than agy does, so judge each finding on its merits:

| ID | Sev | agy's point | Call | Why |
|---|---|---|---|---|
| D1 | High | Missing Kubernetes experience | Accept | JD lists it; the user's notes mention 2 years of EKS |
| D2 | Med | Add revenue impact | Needs your input | No figure in the sources |
| D3 | Low | Use a two-column layout | Reject | Hurts ATS parsing |

Calls are **Accept**, **Partly** (say which part), **Reject** (with evidence), or **Needs your input**. Don't be defensive about the draft. Agree when agy is right.

## 6. Ask

If the user asked to just apply, skip this step and apply the Accept and Partly items.

Otherwise ask, with your client's question tool if it has one (AskUserQuestion in Claude Code), or in plain text, and wait:

1. Apply my accepted changes
2. Apply only some IDs (e.g. "D1, D4")
3. Override my calls (e.g. "take D3 too")
4. Discuss a finding
5. Dismiss the review

Ask for any **Needs your input** values at the same time.

## 7. Revise

- Edit the text source from step 1, keeping its structure and voice; change only what the chosen findings need.
- Re-export or regenerate other formats from the revised source if the user needs them (docx, pdf, pptx), using your client's tools for those formats. Offer this at the end.
- For a binary file the user supplied: edit its generator or source if one exists, or use your client's docx/pptx tools. **Never overwrite a binary file with the converted text.** If you can't edit it faithfully, give the user a **revision guide** instead: for each applied ID, the location, the current text and the new text.
- Finish with a short change log by finding ID (applied, partly applied, skipped and why).

## 8. Offer a re-review

Offer one re-run of the same review on the revised document, with the same model, to confirm the fixes. Suggest stopping after two rounds; after that, reviewers tend to trade style preferences.

## Setup

If the command is missing or agy isn't set up, see the `antigravity-review` skill's setup section, or run the plugin's `scripts/install.sh`. Converters for binary files are optional: `pandoc` (docx), `pdftotext` from poppler-utils (pdf), and `markitdown` (docx, pdf, pptx, xlsx).
