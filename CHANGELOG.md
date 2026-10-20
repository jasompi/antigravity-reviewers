# Changelog

## 1.1.1

- Fix `agy-review.sh` on macOS's stock bash 3.2.57 (`/bin/bash`, used by `#!/usr/bin/env bash` when Homebrew bash isn't installed). It failed while parsing its arguments, before running agy:
  - `${MODEL,,}: bad substitution`: `${var,,}` (lowercase) is bash 4+. Lowercasing now uses `tr`.
  - `REFS[@]: unbound variable`: bash before 4.4 treats an empty array as unbound under `set -u`. Arrays that can be empty are now expanded as `${arr[@]+"${arr[@]}"}`.
- Minimum bash version: 3.2. Behavior and output are otherwise unchanged.
- Tests: `tests/run-tests.sh` now uses the bash that runs it and covers every scope with and without a mixed-case `--model` and `--ref`, plus documents with an uppercase extension (`.PDF`). New `tests/lint.sh` runs shellcheck and flags bash 4+ features. CI runs both under bash 5, bash 3.2 and macOS's `/bin/bash`.

## 1.1.0

- Document reviews (resume, plan, idea, report, presentation, document) with `--doc` and `--ref`, model aliases (`opus`, `sonnet`, `gemini`, `flash`, `gpt-oss`), and Codex support.
