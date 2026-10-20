#!/usr/bin/env bash
# Offline tests for scripts/agy-review.sh, using tests/mock-agy instead of agy.
# Usage: tests/run-tests.sh            (tests with the bash running this file)
#        /bin/bash tests/run-tests.sh  (e.g. macOS's stock bash 3.2)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/agy-review.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
echo "# bash $BASH_VERSION ($BASH)"

# A bin dir with the mock agy plus a fake pdftotext, ahead of the real PATH.
mkdir -p "$T/bin" "$T/tmp" "$T/out" "$T/docs" "$T/nogit"
ln -s "$HERE/mock-agy" "$T/bin/agy"
# `#!/usr/bin/env bash` scripts (agy-review.sh, mock-agy) run with the bash under test.
ln -s "$BASH" "$T/bin/bash"
cat > "$T/bin/pdftotext" <<'SH'
#!/usr/bin/env bash
echo "PDF TEXT of $(basename "$2")" > "${@: -1}"
SH
chmod +x "$T/bin/pdftotext"

# A minimal PATH with no document converters, for the exit-4 / exit-127 tests.
mkdir -p "$T/minbin"
for t in bash env git sed grep awk cat cp mktemp rm mkdir date tr basename dirname readlink wc find sort tail head file; do
  p="$(command -v "$t")" && ln -s "$p" "$T/minbin/$t"
done
rm -f "$T/minbin/bash"; ln -s "$BASH" "$T/minbin/bash"

export TMPDIR="$T/tmp" AGY_REVIEW_OUT_DIR="$T/out"
export MOCK_AGY_LOG="$T/args" MOCK_AGY_PROMPT="$T/prompt" MOCK_AGY_COUNT="$T/models-calls"

printf '# Jane Doe\n\nEngineer.\n' > "$T/docs/resume.md"
printf 'Senior engineer, Go, Kubernetes.\n' > "$T/docs/jd.md"
printf 'fake pdf bytes\n' > "$T/docs/report.pdf"
printf 'PK\003\004 fake docx\000\001' > "$T/docs/deck.docx"
: > "$T/docs/empty.md"
printf 'a,b\n1,2\n' > "$T/docs/data=v2.csv"

# run [env...] -- args...   (runs from $T/nogit unless CWD is set)
run() {
  local envs=()
  while [[ $# -gt 0 && "$1" != -- ]]; do envs+=("$1"); shift; done
  shift
  rm -f "$T/args" "$T/prompt"
  OUT="$(cd "${CWD:-$T/nogit}" && env PATH="$T/bin:$PATH" ${envs[@]+"${envs[@]}"} "$SCRIPT" "$@" 2>"$T/stderr")"
  CODE=$?
  ERR="$(cat "$T/stderr")"
  if grep -qE 'unbound variable|bad substitution|syntax error' <<<"$ERR"; then
    fail "bash error running: $*"
  fi
}

ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; echo "       code=$CODE"; echo "$ERR" | sed 's/^/       stderr: /' | head -8; }
expect_code() { [[ $CODE -eq $2 ]] && ok "$1" || fail "$1 (expected exit $2)"; }
expect() { local name="$1"; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
has() { grep -qF -- "$2" "$1"; }

# --- argument handling ---
run -- resume;                                      expect_code "document type without --doc is rejected" 2
expect "  ...and says --doc is needed" grep -q 'needs --doc' <<<"$ERR"
run -- resume --uncommitted;                        expect_code "document type rejects git scopes" 2
run -- code --doc "$T/docs/resume.md";              expect_code "--doc is rejected for code reviews" 2
run -- resume --doc "$T/docs/missing.md";           expect_code "missing document" 2
run -- resume --doc "$T/docs/resume.md" --ref "$T/docs/nope.md"; expect_code "missing reference" 2
run -- resume --doc "$T/docs/resume.md" --effort huge; expect_code "bad effort" 2
run -- bogus;                                       expect_code "unknown review type" 2

# --- a document review outside git ---
run -- resume --doc "$T/docs/resume.md" --ref "$T/docs/jd.md=job-description" --focus "senior role"
expect_code "resume review outside git" 0
expect "  prompt uses the document contract" has "$T/prompt" "Number the findings \`D1\`"
expect "  prompt uses the resume rubric" has "$T/prompt" "Review type: Resume"
expect "  document block inlined" has "$T/prompt" "<document path=\"$T/docs/resume.md\""
expect "  document text inlined" has "$T/prompt" "Engineer."
expect "  reference block labeled" has "$T/prompt" "<reference label=\"job-description\" original=\"$T/docs/jd.md\""
expect "  reference text inlined" has "$T/prompt" "Senior engineer, Go, Kubernetes."
expect "  focus included" has "$T/prompt" "senior role"
expect "  document dir added to workspace" has "$T/args" "$T/docs"
expect "  read-only flags passed" "$BASH" -c "grep -qx -- '--sandbox' '$T/args' && grep -qx plan '$T/args'"
expect "  reviewer model printed" grep -q '^REVIEWER_MODEL: agy default$' <<<"$OUT"
expect "  review saved" "$BASH" -c "f=\$(sed -n 's/^REVIEW_SAVED: //p' <<<'$OUT'); [[ -s \$f && \$f == *resume-resume-* ]]"

run -- report --doc "$T/docs/resume.md" --ref "$T/docs/data=v2.csv"
expect_code "a reference path containing '=' still works" 0
expect "  label taken from the file name" has "$T/prompt" 'label="data-v2"'

run -- resume --doc "$T/docs/empty.md";             expect_code "empty document is nothing to review" 3

# --- conversion ---
run -- report --doc "$T/docs/report.pdf"
expect_code "pdf converted with pdftotext" 0
expect "  converted text in the prompt" has "$T/prompt" "PDF TEXT of"
expect "  nothing written next to the source" "$BASH" -c "[[ ! -e '$T/docs/report.txt' ]]"

OLDPATH="$PATH"
# shellcheck disable=SC2123  # a minimal PATH on purpose
PATH="$T/minbin"
run -- presentation --doc "$T/docs/deck.docx"
PATH="$OLDPATH"
expect_code "no converter installed gives exit 4" 4
expect "  ...with install hints" grep -q 'pipx install' <<<"$ERR"

run AGY_REVIEW_INLINE_LIMIT=10 -- resume --doc "$T/docs/resume.md" --ref "$T/docs/jd.md"
expect_code "large inputs" 0
expect "  are referenced by path, not inlined" has "$T/prompt" "Too large to inline"

# --- model aliases ---
rm -f "$T/out/.models-cache" "$T/models-calls"
run -- plan --doc "$T/docs/resume.md" --model opus
expect "opus resolves to claude-opus-5-5-high" has "$T/args" "claude-opus-5-5-high"
expect "  REVIEWER_MODEL shows it" grep -q '^REVIEWER_MODEL: claude-opus-5-5-high$' <<<"$OUT"
run -- plan --doc "$T/docs/resume.md" --model gpt-oss
expect "gpt-oss at high falls back to -medium" has "$T/args" "gpt-oss-120b-medium"
expect "  ...with a note" grep -q "no 'high' variant" <<<"$ERR"
expect_code "  ...and the run succeeds" 0
expect "  --effort follows the model suffix" "$BASH" -c "grep -A1 -x -- '--effort' '$T/args' | grep -qx medium"
run -- plan --doc "$T/docs/resume.md" --model claude-opus-5-5-low
expect_code "an exact id with a different default effort still runs" 0
run -- plan --doc "$T/docs/resume.md" --model gemini --effort medium
expect "gemini at medium picks the nearest (pro-high)" has "$T/args" "gemini-3.1-pro-high"
run -- plan --doc "$T/docs/resume.md" --model flash --effort low
expect "flash picks the newest flash at low" has "$T/args" "gemini-3.8-flash-low"
run -- plan --doc "$T/docs/resume.md" --model claude-sonnet-5-5
expect "a base id gets the effort suffix" has "$T/args" "claude-sonnet-5-5-high"
run -- plan --doc "$T/docs/resume.md" --model Claude-Sonnet-5-5
expect "a mixed-case base id resolves" has "$T/args" "claude-sonnet-5-5-high"
run -- plan --doc "$T/docs/resume.md" --model Claude-Opus-5-5-Low
expect_code "a mixed-case exact id runs" 0
expect "  as the lowercase id" has "$T/args" "claude-opus-5-5-low"
expect "  --effort follows its suffix" "$BASH" -c "grep -A1 -x -- '--effort' '$T/args' | grep -qx low"
expect "agy models was called once (cached)" "$BASH" -c "[[ \$(wc -l < '$T/models-calls') -eq 1 ]]"

rm -f "$T/models-calls"
run -- plan --doc "$T/docs/resume.md" --model claude-opus-5-5-low
expect "an exact id passes through" has "$T/args" "claude-opus-5-5-low"
expect "  without calling agy models" "$BASH" -c "[[ ! -e '$T/models-calls' ]]"

touch -t 202001010000 "$T/out/.models-cache"  # stale; POSIX touch, also BSD/macOS
run MOCK_AGY_MODELS_FAIL=1 -- plan --doc "$T/docs/resume.md" --model sonnet
expect "a stale cache is used when agy models fails" has "$T/args" "claude-sonnet-5-5-high"

run -- plan --doc "$T/docs/resume.md" --model gemma
expect_code "unknown alias" 2
expect "  lists the models" grep -q 'gpt-oss-120b-medium' <<<"$ERR"

# --- agy failures ---
run MOCK_AGY_EXIT=5 -- resume --doc "$T/docs/resume.md";  expect_code "agy's exit code is passed through" 5
run MOCK_AGY_EXIT=4 -- resume --doc "$T/docs/resume.md";  expect_code "agy exit codes that clash with ours map to 1" 1
run MOCK_AGY_EXIT=1 MOCK_AGY_STDERR="print timeout exceeded" -- resume --doc "$T/docs/resume.md"
expect_code "timeouts map to 124" 124
OLDPATH="$PATH"
# shellcheck disable=SC2123  # a minimal PATH on purpose
PATH="$T/minbin"
CODE=0; ( cd "$T/nogit" && env PATH="$T/minbin" "$T/minbin/bash" "$SCRIPT" resume --doc "$T/docs/resume.md" ) >/dev/null 2>"$T/stderr"; CODE=$?; ERR="$(cat "$T/stderr")"
PATH="$OLDPATH"
expect_code "agy not installed gives 127" 127

# --- code reviews still work ---
git init -q "$T/repo" && printf 'x = 1\n' > "$T/repo/a.py" \
  && git -C "$T/repo" add a.py && git -C "$T/repo" -c user.name=t -c user.email=t@t commit -qm init
CWD="$T/repo" run -- code --uncommitted;            expect_code "clean tree is nothing to review" 3
CWD="$T/repo" run -- code --last-commit
expect_code "code review of the last commit" 0
expect "  prompt uses the code contract" has "$T/prompt" "independent senior engineer"
expect "  review_context block" has "$T/prompt" "<review_context>"
CWD="$T/repo" run -- code --last-commit --ref "$T/docs/jd.md=spec"
expect "--ref works with code reviews" has "$T/prompt" '<reference label="spec"'
CWD="$T/nogit" run -- code --last-commit;           expect_code "git scopes outside git" 2

# --- every scope, with/without a mixed-case --model alias and a reference ---
# main: init; feature: + c.py; then a.py modified (unstaged), b.py staged, u.py untracked.
git() { command git -C "$T/repo" -c user.name=t -c user.email=t@t "$@"; }
git branch -q -m main && git checkout -q -b feature
printf 'z = 1\n' > "$T/repo/c.py" && git add c.py && git commit -qm "add c"
printf 'x = 2\n' > "$T/repo/a.py"; printf 'y = 1\n' > "$T/repo/b.py"; printf 'u = 1\n' > "$T/repo/u.py"
git add b.py
unset -f git
printf 'Design: add a cache.\n' > "$T/docs/design.md"
for scope in "--uncommitted" "--staged" "--last-commit" "--range HEAD~1..HEAD" "--branch" "--branch main" \
             "--files a.py b.py" "--context-file $T/docs/design.md" "--repo"; do
  for model in "" "--model Opus"; do
    for ref in "" "--ref $T/docs/jd.md=spec"; do
      name="code $scope${model:+ $model}${ref:+ --ref}"
      # shellcheck disable=SC2086  # word-split the flag strings on purpose
      CWD="$T/repo" run -- code $scope $model $ref
      expect_code "$name" 0
      expect "  repo is the workspace" has "$T/args" "$T/repo"
      if [[ -n "$model" ]]; then
        expect "  Opus resolves to claude-opus-5-5-high" has "$T/args" "claude-opus-5-5-high"
      else
        expect "  no --model passed" "$BASH" -c "[[ -s '$T/args' ]] && ! grep -qx -- '--model' '$T/args'"
      fi
      if [[ -n "$ref" ]]; then
        expect "  reference included" has "$T/prompt" '<reference label="spec"'
        expect "  reference dir added to workspace" has "$T/args" "$T/docs"
      else
        expect "  no reference section" "$BASH" -c "[[ -s '$T/prompt' ]] && ! grep -q '## Reference material' '$T/prompt'"
      fi
    done
  done
done
CWD="$T/repo" run -- code --files a.py b.py
expect "--files lists both paths" "$BASH" -c "grep -qF -- '- $T/repo/a.py' '$T/prompt' && grep -qF -- '- $T/repo/b.py' '$T/prompt'"
CWD="$T/repo" run -- code --uncommitted
expect "--uncommitted includes the diff" has "$T/prompt" "+x = 2"
expect "  and untracked files" has "$T/prompt" "u.py"
CWD="$T/repo" run -- code --staged
expect "--staged includes only staged changes" "$BASH" -c "grep -qF -- '+y = 1' '$T/prompt' && ! grep -qF -- '+x = 2' '$T/prompt'"
CWD="$T/repo" run -- code --range HEAD~1..HEAD
expect "--range includes the commit" has "$T/prompt" "+z = 1"
CWD="$T/repo" run -- code --branch
expect "--branch detects main as the base" has "$T/prompt" "branch feature vs main"
expect "  and includes the branch's commit" has "$T/prompt" "+z = 1"

# --- uppercase extensions ---
printf 'fake pdf bytes\n' > "$T/docs/SCAN.PDF"
for model in "" "--model Opus"; do
  for ref in "" "--ref $T/docs/jd.md"; do
    # shellcheck disable=SC2086
    run -- report --doc "$T/docs/SCAN.PDF" $model $ref
    expect_code "report --doc SCAN.PDF${model:+ $model}${ref:+ --ref}" 0
    expect "  .PDF converted with pdftotext" has "$T/prompt" "PDF TEXT of SCAN.PDF"
  done
done

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
