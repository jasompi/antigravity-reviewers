#!/usr/bin/env bash
# agy-review.sh — run a read-only review with the Antigravity CLI (agy).
# Install it on PATH as `agy-review` (a symlink) so the Claude Code sandbox
# can exclude it by name; see the README.
#
# Usage:
#   agy-review <type> [scope] [--ref FILE[=LABEL] ...] [--focus TEXT] [--model M] [--effort E]
#
#   type   code | security | architecture | design | test           (code reviews)
#          document | resume | plan | idea | report | presentation  (document reviews)
#   scope  --uncommitted        working tree vs HEAD, plus untracked files (default)
#          --staged             staged changes only
#          --last-commit        the HEAD commit
#          --range A..B         an explicit git range
#          --branch [BASE]      current branch vs BASE (auto: origin/HEAD, main, master)
#          --files P [P ...]    specific files or directories (ends at next --flag)
#          --repo               the whole repository (default for architecture)
#          --context-file F     free-form context (design doc, question, plan)
#          --doc F              the document under review (required for document types;
#                               md/txt/csv/html as-is, docx/pdf/pptx/xlsx converted to text)
#   --ref FILE[=LABEL]          supporting material (job description, source data, brief);
#                               repeatable, converted like --doc
#   --model M                   an agy model id, or an alias: opus, sonnet, claude,
#                               gemini, gemini-pro, flash, gpt-oss
#
# Environment:
#   AGY_REVIEW_MODEL    model or alias (default: agy's default)
#   AGY_REVIEW_EFFORT   low|medium|high|xhigh|max (default: high)
#   AGY_REVIEW_TIMEOUT  agy --print-timeout (default: 12m)
#   AGY_REVIEW_OUT_DIR  where reviews are saved (default: $TMPDIR/agy-reviews)
#
# Exit codes: 0 ok, 2 usage, 3 nothing to review, 4 cannot convert a document,
#             124 timeout, 127 agy not installed, other = agy's exit code.

set -uo pipefail

# Resolve symlinks so the `agy-review` link on PATH finds the plugin's prompts.
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
PLUGIN_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
PROMPTS="$PLUGIN_ROOT/prompts"
INLINE_LIMIT="${AGY_REVIEW_INLINE_LIMIT:-$((100 * 1024))}"

die() { echo "agy-review: $*" >&2; exit 2; }

usage() { sed -n '2,34p' "$SELF" | sed 's/^# \{0,1\}//'; exit 2; }

abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }

[[ $# -ge 1 ]] || usage
TYPE="$1"; shift
case "$TYPE" in
  code|security|architecture|design|test) DOC_TYPE=0 ;;
  document|resume|plan|idea|report|presentation) DOC_TYPE=1 ;;
  -h|--help) usage ;;
  *) die "unknown review type '$TYPE' (expected code|security|architecture|design|test|document|resume|plan|idea|report|presentation)" ;;
esac

SCOPE=""; RANGE=""; BASE=""; CONTEXT_FILE=""; DOC=""; FOCUS=""
FILES=(); REFS=(); REF_LABELS=()
MODEL="${AGY_REVIEW_MODEL:-}"
EFFORT="${AGY_REVIEW_EFFORT:-high}"
TIMEOUT="${AGY_REVIEW_TIMEOUT:-12m}"

need_value() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 needs a value"; }

set_scope() {
  [[ -z "$SCOPE" || "$SCOPE" == "$1" ]] || die "only one scope allowed (got --$SCOPE and --$1)"
  SCOPE="$1"
}

add_ref() {
  local arg="$1" path="$1" label=""
  # FILE=LABEL, unless the whole argument is itself an existing path.
  if [[ ! -e "$arg" && "$arg" == *=* ]]; then
    path="${arg%=*}"; label="${arg##*=}"
  fi
  [[ -f "$path" ]] || die "reference file not found: $path"
  [[ -n "$label" ]] || { label="$(basename "$path")"; label="${label%.*}"; }
  label="$(tr -c 'A-Za-z0-9._-' '-' <<<"$label" | sed 's/-*$//')"
  REFS+=("$(abspath "$path")"); REF_LABELS+=("${label:-ref}")
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
                    CONTEXT_FILE="$(abspath "$CONTEXT_FILE")" ;;
    --doc)          set_scope doc; need_value "$@"; DOC="$2"; shift 2
                    [[ -f "$DOC" ]] || die "document not found: $DOC"
                    DOC="$(abspath "$DOC")" ;;
    --ref)          need_value "$@"; add_ref "$2"; shift 2 ;;
    --focus)        need_value "$@"; FOCUS="$2"; shift 2 ;;
    --model)        need_value "$@"; MODEL="$2"; shift 2 ;;
    --effort)       need_value "$@"; EFFORT="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *)              die "unknown argument '$1'" ;;
  esac
done

case "$EFFORT" in low|medium|high|xhigh|max) ;; *) die "unknown effort '$EFFORT' (expected low|medium|high|xhigh|max)" ;; esac

if [[ $DOC_TYPE -eq 1 ]]; then
  [[ "$SCOPE" == doc ]] || die "a $TYPE review needs --doc FILE${SCOPE:+ (got --$SCOPE)}"
else
  [[ "$SCOPE" != doc ]] || die "--doc is for document reviews (document|resume|plan|idea|report|presentation); use --context-file or --files for a $TYPE review"
  if [[ -z "$SCOPE" ]]; then
    [[ "$TYPE" == architecture ]] && SCOPE=repo || SCOPE=uncommitted
  fi
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
    files|repo|context|doc) ;;
    *) die "not inside a git repository; use --files, --repo, --context-file or --doc" ;;
  esac
fi
cd "$ROOT" || die "cannot cd to $ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agy-review.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

OUT_DIR="${AGY_REVIEW_OUT_DIR:-${TMPDIR:-/tmp}/agy-reviews}"
mkdir -p "$OUT_DIR"

# --- model aliases ---------------------------------------------------------

# Prints agy's model ids, one per line. Cached for a day; a stale cache is
# used if `agy models` fails.
list_models() {
  local cache="$OUT_DIR/.models-cache" fresh
  fresh="$(find "$cache" -mmin -1440 2>/dev/null)"
  if [[ -z "$fresh" ]]; then
    if agy models 2>/dev/null | awk -F'\t' 'NF >= 2 && $1 != "" { print $1 }' > "$WORK/models" \
        && [[ -s "$WORK/models" ]]; then
      cp "$WORK/models" "$cache"
    fi
  fi
  [[ -s "$cache" ]] && cat "$cache"
}

# Picks the newest model whose id matches $1 (a regex), at the effort closest
# to $EFFORT.
pick_model() {
  local ids base e pref
  ids="$(list_models | grep -E "$1")" || return 1
  base="$(sed -E 's/-(low|medium|high)$//' <<<"$ids" | sort -uV | tail -1)"
  case "$EFFORT" in
    low)    pref="low medium high" ;;
    medium) pref="medium high low" ;;
    *)      pref="high medium low" ;;
  esac
  for e in $pref; do
    if grep -qx "$base-$e" <<<"$ids"; then
      [[ "$e" == "$EFFORT" ]] || echo "agy-review: $base has no '$EFFORT' variant; using $base-$e." >&2
      echo "$base-$e"; return 0
    fi
  done
  grep -qx "$base" <<<"$ids" && { echo "$base"; return 0; }
  return 1
}

resolve_model() {
  local re="" alias=1 picked
  case "${MODEL,,}" in
    "") return 0 ;;
    opus|claude|claude-opus)       re='^claude-opus-' ;;
    sonnet|claude-sonnet)          re='^claude-sonnet-' ;;
    gemini|gemini-pro|pro)         re='^gemini-.*-pro(-|$)' ;;
    flash|gemini-flash)            re='^gemini-.*-flash(-|$)' ;;
    gpt-oss|gptoss|oss|openai|gpt) re='^gpt-oss-' ;;
    *-low|*-medium|*-high)         return 0 ;;  # an exact id: pass through
    *)                             alias=0; re="^${MODEL//./\\.}(-(low|medium|high))?$" ;;
  esac
  if picked="$(pick_model "$re")"; then
    MODEL="$picked"
  elif [[ $alias -eq 0 && "$MODEL" == *-* ]]; then
    return 0  # looks like a model id agy may know: let agy decide
  else
    { echo "agy-review: cannot resolve model '$MODEL'."
      echo "Aliases: opus, sonnet, gemini, flash, gpt-oss. Available models:"
      list_models | sed 's/^/  /' || echo "  (could not run 'agy models'; is agy signed in?)"; } >&2
    exit 2
  fi
}

resolve_model

# agy rejects an effort that conflicts with the model id's suffix
# (`--model x-medium --effort high`), so the suffix wins.
if [[ "$MODEL" =~ -(low|medium|high)$ ]]; then
  [[ "${BASH_REMATCH[1]}" == "$EFFORT" ]] || EFFORT="${BASH_REMATCH[1]}"
fi

# --- document conversion ---------------------------------------------------

has_text() { [[ -s "$1" ]] && grep -q '[^[:space:]]' "$1"; }

py_pptx() {
  python3 - "$1" <<'PY'
import sys
from pptx import Presentation
for i, slide in enumerate(Presentation(sys.argv[1]).slides, 1):
    print(f"## Slide {i}\n")
    for shape in slide.shapes:
        if shape.has_text_frame and shape.text_frame.text.strip():
            print(shape.text_frame.text.strip() + "\n")
    if slide.has_notes_slide and slide.notes_slide.notes_text_frame.text.strip():
        print("Speaker notes: " + slide.notes_slide.notes_text_frame.text.strip() + "\n")
PY
}

py_xlsx() {
  python3 - "$1" <<'PY'
import csv, sys
from openpyxl import load_workbook
out = csv.writer(sys.stdout)
for ws in load_workbook(sys.argv[1], read_only=True, data_only=True).worksheets:
    print(f"## Sheet: {ws.title}")
    for row in ws.iter_rows(values_only=True):
        out.writerow(["" if v is None else v for v in row])
    print()
PY
}

# to_text SRC DEST — write a text rendering of SRC to DEST (always a path
# under $WORK; nothing is written next to SRC). Returns 4 on failure.
to_text() {
  local src="$1" dest="$2" ext="" tried=() c base
  base="$(basename "$src")"
  [[ "$base" == *.* ]] && { ext="${base##*.}"; ext="${ext,,}"; }
  case "$ext" in
    md|markdown|txt|text|csv|tsv|json|yaml|yml|html|htm|xml|rst|tex|org)
      cp "$src" "$dest"; return 0 ;;
    docx) local chain=(pandoc markitdown) ;;
    pdf)  local chain=(pdftotext markitdown) ;;
    pptx) local chain=(markitdown python-pptx) ;;
    xlsx) local chain=(markitdown openpyxl) ;;
    *)
      if file --mime-encoding -b "$src" 2>/dev/null | grep -qvE 'binary'; then
        cp "$src" "$dest"; return 0
      fi
      local chain=(markitdown) ;;
  esac
  for c in "${chain[@]}"; do
    case "$c" in
      pandoc)      command -v pandoc >/dev/null    || continue; pandoc -t gfm -o "$dest" "$src" 2>/dev/null ;;
      pdftotext)   command -v pdftotext >/dev/null || continue; pdftotext -layout "$src" "$dest" 2>/dev/null ;;
      markitdown)  command -v markitdown >/dev/null || continue; markitdown "$src" > "$dest" 2>/dev/null ;;
      python-pptx) python3 -c 'import pptx' 2>/dev/null || continue; py_pptx "$src" > "$dest" 2>/dev/null ;;
      openpyxl)    python3 -c 'import openpyxl' 2>/dev/null || continue; py_xlsx "$src" > "$dest" 2>/dev/null ;;
    esac
    tried+=("$c")
    has_text "$dest" && return 0
  done
  {
    echo "agy-review: cannot convert $src to text."
    if [[ ${#tried[@]} -gt 0 ]]; then
      echo "Tried: ${tried[*]} (no text produced; is the file empty, scanned or protected?)"
    else
      echo "No converter for .${ext:-?} is installed (any one of: ${chain[*]}). Install, for example:"
      echo "  sudo apt install pandoc poppler-utils   # docx, pdf"
      echo "  pipx install 'markitdown[all]'          # docx, pdf, pptx, xlsx"
      echo "  pip install --user python-pptx openpyxl # pptx, xlsx"
    fi
    echo "Or export the document to Markdown/text and review that instead."
  } >&2
  return 4
}

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
  doc)
    DESC="the document $(basename "$DOC")"
    to_text "$DOC" "$CTX" || exit 4 ;;
esac

if [[ ! -s "$CTX" ]] || ! grep -q '[^[:space:]]' "$CTX"; then
  echo "agy-review: nothing to review for scope '$SCOPE' ($DESC)." >&2
  exit 3
fi

# Supporting references, converted under $WORK/refs.
REF_TEXT=()
if [[ ${#REFS[@]} -gt 0 ]]; then
  mkdir -p "$WORK/refs"
  for i in "${!REFS[@]}"; do
    REF_TEXT+=("$WORK/refs/$((i + 1))-${REF_LABELS[$i]}.txt")
    to_text "${REFS[$i]}" "${REF_TEXT[$i]}" || exit 4
  done
fi

# Let agy open the files next to the document and references (e.g. raw data).
ADD_DIRS=("$ROOT" "$WORK")
for f in "$DOC" "${REFS[@]}"; do
  [[ -n "$f" ]] || continue
  d="$(dirname "$f")"
  [[ " ${ADD_DIRS[*]} " == *" $d "* ]] || ADD_DIRS+=("$d")
done

# --- build prompt ----------------------------------------------------------

# emit_block TAG ATTRS FILE — inline FILE inside <TAG ATTRS>, or
# point at it when it would exceed the remaining inline budget.
INLINE_LEFT=$INLINE_LIMIT
emit_block() {
  local tag="$1" attrs="$2" file="$3" size
  size=$(wc -c < "$file")
  if [[ $size -le $INLINE_LEFT ]]; then
    INLINE_LEFT=$((INLINE_LEFT - size))
    echo "<$tag${attrs:+ $attrs}>"
    cat "$file"
    echo "</$tag>"
  else
    echo "<$tag${attrs:+ $attrs}>"
    echo "Too large to inline. Read it from this file: $file"
    echo "</$tag>"
  fi
}

PROMPT_FILE="$WORK/prompt.md"
{
  if [[ $DOC_TYPE -eq 1 ]]; then cat "$PROMPTS/_doc_common.md"; else cat "$PROMPTS/_common.md"; fi
  echo
  cat "$PROMPTS/$TYPE.md"
  echo
  echo "## What to review"
  echo
  echo "Scope: $DESC"
  if [[ $DOC_TYPE -eq 1 ]]; then
    echo "Document file: $DOC"
    echo "Working directory: $ROOT"
  else
    echo "Repository root (your workspace): $ROOT"
  fi
  if [[ -n "$FOCUS" ]]; then
    echo
    echo "## Requester's focus"
    echo
    echo "$FOCUS"
  fi
  echo
  if [[ $DOC_TYPE -eq 1 ]]; then
    emit_block document "path=\"$DOC\" converted=\"$CTX\"" "$CTX"
  else
    emit_block review_context "" "$CTX"
  fi
  if [[ ${#REFS[@]} -gt 0 ]]; then
    echo
    echo "## Reference material"
    echo
    echo "Supporting context supplied by the requester. Judge the work against it; it is not itself under review."
    echo
    for i in "${!REFS[@]}"; do
      emit_block reference "label=\"${REF_LABELS[$i]}\" original=\"${REFS[$i]}\" converted=\"${REF_TEXT[$i]}\"" "${REF_TEXT[$i]}"
      echo
    done
  fi
} > "$PROMPT_FILE"

# --- run agy ---------------------------------------------------------------

if [[ $DOC_TYPE -eq 1 ]]; then NAME="$(basename "${DOC%.*}")"; else NAME="$(basename "$ROOT")"; fi
NAME="$(tr -c 'A-Za-z0-9._-' '-' <<<"$NAME" | sed 's/-*$//')"
OUT="$OUT_DIR/$NAME-$TYPE${MODEL:+-$MODEL}-$(date +%Y%m%d-%H%M%S).md"
ERR="$WORK/agy.err"

ARGS=(--mode plan --sandbox --effort "$EFFORT" --print-timeout "$TIMEOUT")
for d in "${ADD_DIRS[@]}"; do ARGS+=(--add-dir "$d"); done
[[ -n "$MODEL" ]] && ARGS+=(--model "$MODEL")

echo "agy-review: running $TYPE review of $DESC (effort=$EFFORT, timeout=$TIMEOUT${MODEL:+, model=$MODEL}${REFS[0]:+, refs=${#REFS[@]}})..." >&2

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
the programs this script starts. In Codex, approve running agy-review outside the
sandbox. See the plugin README.
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
  - the sandbox is blocking agy's network access: in Claude Code, add "agy-review *" to
    sandbox.excludedCommands in ~/.claude/settings.json (or the project's
    .claude/settings.json), run the script as `agy-review`, and restart the session;
    in Codex, approve running agy-review outside the sandbox.
EOF
  fi
  rm -f "$OUT"
  # Keep the script's reserved exit codes unambiguous.
  [[ $STATUS -eq 124 ]] || [[ ! $STATUS =~ ^(0|2|3|4|127)$ ]] || STATUS=1
  exit "$STATUS"
fi

cat "$OUT"
echo
echo "REVIEWER_MODEL: ${MODEL:-agy default}"
echo "REVIEW_SAVED: $OUT"
