#!/usr/bin/env bash
# Lint the plugin's shell scripts: shellcheck, plus a check for features newer
# than bash 3.2 (macOS's /bin/bash), which shellcheck can't target by version.
# Usage: tests/lint.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
FILES=("$ROOT/scripts/agy-review.sh" "$ROOT/scripts/install.sh" "$ROOT/tests/run-tests.sh" "$ROOT/tests/mock-agy" "$ROOT/tests/lint.sh")
STATUS=0

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --shell=bash --severity=warning "${FILES[@]}" || STATUS=1
else
  echo "lint: shellcheck not installed; skipping it" >&2
fi

# Bash 4+ only. Each check is "name<TAB>extended regex"; comment lines are skipped.
CHECKS=(
  'case modification ${x,,} ${x^^pat}	\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,?|\^\^?)[^}]*\}'
  'transformation ${x@Q}	\$\{[^}]*@[QEPAaKkUuL]\}'
  'associative array or nameref	(declare|local|typeset) +-[a-zA-Z]*[An]'
  'mapfile or readarray	(^|[^A-Za-z0-9_-])(mapfile|readarray)([^A-Za-z0-9_-]|$)'
  'redirection &>> or pipe |&	&>>|\|&'
  'negative array index	\[-[0-9]+\]'
  'case fall-through ;& or ;;&	;;?&'
  'coproc, globstar or lastpipe	(^|[^A-Za-z0-9_])coproc |shopt +-s +(globstar|lastpipe)'
  'automatic fd {var}>	\{[A-Za-z_][A-Za-z0-9_]*\}[<>]'
  'EPOCHSECONDS, EPOCHREALTIME or BASHPID	\$\{?(EPOCHSECONDS|EPOCHREALTIME|BASHPID)'
)
TAB="$(printf '\t')"
for f in "${FILES[@]}"; do
  [[ "$(basename "$f")" == lint.sh ]] && continue  # its patterns would match themselves
  for c in "${CHECKS[@]}"; do
    name="${c%%"$TAB"*}"; re="${c#*"$TAB"}"
    if hits="$(grep -nE -- "$re" "$f" | grep -vE '^[0-9]+:[[:space:]]*#')"; then
      echo "$f: bash 4+ feature ($name), not available in bash 3.2:"
      echo "$hits" | sed 's/^/  /'
      STATUS=1
    fi
  done
done

[[ $STATUS -eq 0 ]] && echo "lint: ok"
exit "$STATUS"
