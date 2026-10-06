#!/usr/bin/env bash
# install.sh — put `agy-review` on PATH and check the setup. Safe to re-run.
# It changes nothing except the symlink; it prints the settings to add.
#
# Usage: scripts/install.sh [BIN_DIR]     (default: ~/.local/bin)

set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT="$(dirname "$SELF")/agy-review.sh"
BIN="${1:-$HOME/.local/bin}"

ok()   { echo "  ok    $*"; }
warn() { echo "  WARN  $*"; }
info() { echo "  --    $*"; }

echo "antigravity-reviewers setup"
echo

echo "1. agy-review on PATH"
mkdir -p "$BIN"
chmod +x "$SCRIPT"
ln -sfn "$SCRIPT" "$BIN/agy-review" && ok "$BIN/agy-review -> $SCRIPT"
case ":$PATH:" in
  *":$BIN:"*) ok "$BIN is on PATH" ;;
  *) warn "$BIN is not on PATH. Add this to ~/.bashrc or ~/.zshrc, then open a new shell:"
     echo "          export PATH=\"$BIN:\$PATH\"" ;;
esac
info "Re-run this script after a plugin update: the installed path includes the version."
echo

echo "2. Antigravity CLI"
if command -v agy >/dev/null 2>&1; then
  ok "agy found at $(command -v agy)"
  if agy models >/dev/null 2>&1; then ok "agy is signed in (agy models works)"
  else warn "agy models failed: run \`agy\` once interactively to sign in."; fi
else
  warn "agy not found. Install: curl -fsSL https://antigravity.google/cli/install.sh | bash"
fi
echo

echo "3. Document converters (optional; for docx/pdf/pptx/xlsx reviews)"
have() { command -v "$1" >/dev/null 2>&1; }
pymod() { python3 -c "import $1" >/dev/null 2>&1; }
have pandoc     && ok "pandoc (docx)"                         || info "pandoc missing (docx): sudo apt install pandoc"
have pdftotext  && ok "pdftotext (pdf)"                       || info "pdftotext missing (pdf): sudo apt install poppler-utils"
have markitdown && ok "markitdown (docx, pdf, pptx, xlsx)"    || info "markitdown missing (docx, pdf, pptx, xlsx): pipx install 'markitdown[all]'"
pymod pptx      && ok "python-pptx (pptx)"                    || info "python-pptx missing (pptx fallback): pip install --user python-pptx"
pymod openpyxl  && ok "openpyxl (xlsx)"                       || info "openpyxl missing (xlsx fallback): pip install --user openpyxl"
info "Markdown, text, CSV and HTML need no converter."
echo

cat <<'EOF'
4. Settings to add yourself (merge with what is already there)

   agy, ~/.gemini/antigravity-cli/settings.json — read-only tools agy may use headless:
     { "permissions": { "allow": [
         "command(git diff)", "command(git log)", "command(git show)", "command(git status)",
         "command(git ls-files)", "command(git grep)", "command(git blame)",
         "command(grep)", "command(ls)", "command(cat)", "command(head)", "command(tail)", "command(wc)"
     ] } }

   Claude Code, ~/.claude/settings.json — run agy-review without prompts, outside the sandbox:
     { "permissions": { "allow": ["Bash(agy-review *)"] },
       "sandbox": { "excludedCommands": ["agy-review *"] } }

   Codex — agy-review needs network access, which Codex's default sandbox blocks.
   Approve it with "always allow" when Codex first asks, or add this rule to
   ~/.codex/rules/default.rules (allowed commands run outside the sandbox):
     prefix_rule(pattern=["agy-review"], decision="allow")
   See the README's "Install in Codex" section.
EOF
