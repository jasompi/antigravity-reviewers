#!/usr/bin/env bash
# agy-review.sh — run a read-only review with the Antigravity CLI (agy).
# Install it on PATH as `agy-review` (a symlink) so the Claude Code sandbox
# can exclude it by name; see the README.
#
# Usage:
#   agy-review <type> [scope] [--focus TEXT] [--model M] [--effort E]
#
#   type   code | security | architecture | design | test
#   scope  --uncommitted        working tree vs HEAD, plus untracked files (default)
#          --staged             staged changes only
#          --last-commit        the HEAD commit
#          --range A..B         an explicit git range
#          --branch [BASE]      current branch vs BASE (auto: origin/HEAD, main, master)
#          --files P [P ...]    specific files or directories (ends at next --flag)
#          --repo               the whole repository (default for architecture)
#          --context-file F     free-form context (design doc, question, plan)
#
# Environment:
#   AGY_REVIEW_MODEL    model passed to agy --model (default: agy's default)
#   AGY_REVIEW_EFFORT   low|medium|high|xhigh|max (default: high)
#   AGY_REVIEW_TIMEOUT  agy --print-timeout (default: 12m)
#   AGY_REVIEW_OUT_DIR  where reviews are saved (default: $TMPDIR/agy-reviews)
#
# Exit codes: 0 ok, 2 usage, 3 nothing to review, 124 timeout,
#             127 agy not installed, other = agy's exit code.

set -uo pipefail

# Resolve symlinks so the `agy-review` link on PATH finds the plugin's prompts.
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
PLUGIN_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
PROMPTS="$PLUGIN_ROOT/prompts"
INLINE_LIMIT=$((100 * 1024))

die() { echo "agy-review: $*" >&2; exit 2; }

usage() { sed -n '2,26p' "$SELF" | sed 's/^# \{0,1\}//'; exit 2; }

[[ $# -ge 1 ]] || usage
TYPE="$1"; shift
case "$TYPE" in
  code|security|architecture|design|test) ;;
  -h|--help) usage ;;
  *) die "unknown review type '$TYPE' (expected code|security|architecture|design|test)" ;;
esac

SCOPE=""; RANGE=""; BASE=""; CONTEXT_FILE=""; FOCUS=""
FILES=()
MODEL="${AGY_REVIEW_MODEL:-}"
EFFORT="${AGY_REVIEW_EFFORT:-high}"
TIMEOUT="${AGY_REVIEW_TIMEOUT:-12m}"

need_value() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 needs a value"; }

set_scope() {
  [[ -z "$SCOPE" || "$SCOPE" == "$1" ]] || die "only one scope allowed (got --$SCOPE and --$1)"
  SCOPE="$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uncommitted|--staged|--last-commit|--repo) set_scope "${1#--}"; shift ;;
    --range)        set_scope range; need_value "$@"; RANGE="$2"; shift 2 ;;
    --branch)       set_scope branch; shift
                    if [[ $# -gt 0 && "$1" != --* ]]; then BASE="$1"; shift; fi ;;
    --files)        set_scope files; shift
                    while [[ $# -gt 0 && "$1" != --* ]]; do
                      [[ "$1" == /* ]] && FILES+=("$1") || FILES+=("$PWD/$1"); shift
                    done
                    [[ ${#FILES[@]} -gt 0 ]] || die "--files needs at least one path" ;;
    --context-file) set_scope context; need_value "$@"; CONTEXT_FILE="$2"; shift 2
                    [[ -f "$CONTEXT_FILE" ]] || die "context file not found: $CONTEXT_FILE"
                    CONTEXT_FILE="$(cd "$(dirname "$CONTEXT_FILE")" && pwd)/$(basename "$CONTEXT_FILE")" ;;
    --focus)        need_value "$@"; FOCUS="$2"; shift 2 ;;
    --model)        need_value "$@"; MODEL="$2"; shift 2 ;;
    --effort)       need_value "$@"; EFFORT="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *)              die "unknown argument '$1'" ;;
  esac
done

if [[ -z "$SCOPE" ]]; then
  [[ "$TYPE" == architecture ]] && SCOPE=repo || SCOPE=uncommitted
fi

# --- preflight -------------------------------------------------------------

if ! command -v agy >/dev/null 2>&1; then
  cat >&2 <<'EOF'
agy-review: the Antigravity CLI (agy) is not installed or not on PATH.

Install it:
  curl -fsSL https://antigravity.google/cli/install.sh | bash
Then run `agy` once interactively to sign in.
More info: https://antigravity.google/download
EOF
  exit 127
fi

if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  IN_GIT=1
else
  ROOT="$PWD"; IN_GIT=0
  case "$SCOPE" in
    files|repo|context) ;;
    *) die "not inside a git repository; use --files, --repo or --context-file" ;;
  esac
fi
cd "$ROOT" || die "cannot cd to $ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agy-review.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# --- gather context --------------------------------------------------------

CTX="$WORK/context.txt"
DESC=""

default_base() {
  local ref
  ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" && { echo "$ref"; return; }
  for ref in main master origin/main origin/master; do
    git rev-parse --verify --quiet "$ref" >/dev/null && { echo "$ref"; return; }
  done
  return 1
}

case "$SCOPE" in
  uncommitted)
    DESC="uncommitted changes (working tree vs HEAD)"
    if git rev-parse --verify --quiet HEAD >/dev/null; then
      git diff HEAD --no-color --no-ext-diff > "$CTX"
    else
      git diff --cached --no-color --no-ext-diff > "$CTX"
    fi
    untracked="$(git ls-files --others --exclude-standard)"
    if [[ -n "$untracked" ]]; then
      { echo; echo "## New untracked files (read them from the repository):"; echo "$untracked"; } >> "$CTX"
    fi ;;
  staged)
    DESC="staged changes"
    git diff --cached --no-color --no-ext-diff > "$CTX" ;;
  last-commit)
    DESC="the last commit ($(git log -1 --format='%h %s'))"
    git show HEAD --no-color --no-ext-diff --stat --patch > "$CTX" ;;
  range)
    DESC="commit range $RANGE"
    { git log --format='%h %s' "$RANGE" && echo && git diff "$RANGE" --no-color --no-ext-diff; } > "$CTX" \
      || die "invalid range '$RANGE'" ;;
  branch)
    [[ -n "$BASE" ]] || BASE="$(default_base)" || die "cannot detect a base branch; pass --branch BASE"
    DESC="branch $(git rev-parse --abbrev-ref HEAD) vs $BASE"
    { git log --format='%h %s' "$BASE..HEAD" && echo && git diff "$BASE...HEAD" --no-color --no-ext-diff; } > "$CTX" \
      || die "cannot diff against '$BASE'" ;;
  files)
    DESC="specific files/directories"
    for f in "${FILES[@]}"; do [[ -e "$f" ]] || die "path not found: $f"; done
    { echo "Review these paths (read them from the repository):"; printf -- '- %s\n' "${FILES[@]}"; } > "$CTX" ;;
  repo)
    DESC="the whole repository"
    {
      echo "Repository root: $ROOT"
      echo
      echo "Tracked files (first 2000):"
      if [[ $IN_GIT -eq 1 ]]; then git ls-files | head -2000
      else find . -type f -not -path '*/.*' | head -2000; fi
    } > "$CTX" ;;
  context)
    DESC="the provided context document"
    cp "$CONTEXT_FILE" "$CTX" ;;
esac

if [[ ! -s "$CTX" ]] || ! grep -q '[^[:space:]]' "$CTX"; then
  echo "agy-review: nothing to review for scope '$SCOPE' ($DESC)." >&2
  exit 3
fi

# --- build prompt ----------------------------------------------------------

PROMPT_FILE="$WORK/prompt.md"
{
  cat "$PROMPTS/_common.md"
  echo
  cat "$PROMPTS/$TYPE.md"
  echo
  echo "## What to review"
  echo
  echo "Scope: $DESC"
  echo "Repository root (your workspace): $ROOT"
  if [[ -n "$FOCUS" ]]; then
    echo
    echo "## Requester's focus"
    echo
    echo "$FOCUS"
  fi
  echo
  if [[ $(wc -c < "$CTX") -le $INLINE_LIMIT ]]; then
    echo "<review_context>"
    cat "$CTX"
    echo "</review_context>"
  else
    echo "The review context is too large to inline. Read it from this file before reviewing:"
    echo "  $CTX"
  fi
} > "$PROMPT_FILE"

# --- run agy ---------------------------------------------------------------

OUT_DIR="${AGY_REVIEW_OUT_DIR:-${TMPDIR:-/tmp}/agy-reviews}"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(basename "$ROOT")-$TYPE-$(date +%Y%m%d-%H%M%S).md"
ERR="$WORK/agy.err"

ARGS=(--mode plan --sandbox --add-dir "$ROOT" --add-dir "$WORK"
      --effort "$EFFORT" --print-timeout "$TIMEOUT")
[[ -n "$MODEL" ]] && ARGS+=(--model "$MODEL")

echo "agy-review: running $TYPE review of $DESC (effort=$EFFORT, timeout=$TIMEOUT${MODEL:+, model=$MODEL})..." >&2

agy "${ARGS[@]}" -p "$(cat "$PROMPT_FILE")" > "$OUT" 2> "$ERR"
STATUS=$?

if [[ $STATUS -ne 0 ]] || ! grep -q '[^[:space:]]' "$OUT"; then
  cat "$OUT" "$ERR" >&2
  ALL="$(cat "$ERR")"
  if grep -qiE 'headless mode cannot prompt|auto-denied' <<<"$ALL"; then
    cat >&2 <<'EOF'

agy-review: agy wanted a tool that headless mode can't ask you to approve, so it
was denied. Pre-approve agy's read-only commands in ~/.gemini/antigravity-cli/settings.json
under "permissions": { "allow": [ ... ] }, for example:
  "command(git diff)", "command(git log)", "command(git show)", "command(git status)",
  "command(git ls-files)", "command(git grep)", "command(git blame)",
  "command(grep)", "command(ls)", "command(cat)", "command(head)", "command(tail)", "command(wc)"
Rules must be tool(target); bare names are dropped. See the plugin README.
EOF
  elif grep -qi 'bind: operation not permitted' <<<"$ALL"; then
    cat >&2 <<'EOF'

agy-review: agy could not bind a localhost port; the Claude Code sandbox is blocking it.
Run this script as `agy-review` (a symlink on PATH) and exclude it from the sandbox in
~/.claude/settings.json (or the project's .claude/settings.json), then restart the session:
  { "sandbox": { "excludedCommands": ["agy-review *"] } }
Excluding "agy" alone doesn't help: the sandbox matches the command Claude runs, not
the programs this script starts. See the plugin README.
EOF
  elif grep -qiE 'timeout|timed out|deadline' <<<"$ALL"; then
    echo >&2
    echo "agy-review: agy timed out after $TIMEOUT. Narrow the scope, lower --effort, or raise AGY_REVIEW_TIMEOUT." >&2
    STATUS=124
  elif grep -qiE 'eligibility|unauthenticated|sign.?in|login|forbidden|401|403|network is unreachable|no such host|dial tcp|connection refused|i/o timeout|proxy' <<<"$ALL"; then
    echo >&2
    cat >&2 <<'EOF'
agy-review: agy could not reach or authenticate with Google. Either:
  - you are not signed in: run `agy` interactively once, then retry; or
  - the Claude Code sandbox is blocking agy's network access: add "agy-review *" to
    sandbox.excludedCommands in ~/.claude/settings.json (or the project's
    .claude/settings.json), run the script as `agy-review`, and restart the session.
EOF
  fi
  rm -f "$OUT"
  # Keep the script's reserved exit codes unambiguous.
  [[ $STATUS -eq 124 ]] || [[ ! $STATUS =~ ^(0|2|3|127)$ ]] || STATUS=1
  exit "$STATUS"
fi

cat "$OUT"
echo
echo "REVIEW_SAVED: $OUT"
