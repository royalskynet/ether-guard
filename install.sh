#!/bin/bash
# Installer for claude-safe-guard.
# Copies the guard script to ~/.claude/scripts/ and adds a `claude` shell wrapper
# to your ~/.zshrc (and ~/.bashrc if present). Idempotent.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dst="$HOME/.claude/scripts"
mkdir -p "$dst"
cp "$here/claude-safe-guard.sh" "$dst/claude-safe-guard.sh"
chmod +x "$dst/claude-safe-guard.sh"
echo "[install] guard -> $dst/claude-safe-guard.sh"

read -r -d '' FUNC <<'EOF' || true

# --- claude-safe-guard: scan CWD for dangerous project config before launching claude ---
claude() {
  local guard="$HOME/.claude/scripts/claude-safe-guard.sh"
  if [ -x "$guard" ] && ! "$guard" "$PWD"; then
    printf '\033[1;33m[claude-guard] Dangerous config found. Launch claude anyway? [y/N] \033[0m'
    read -r _ans
    [[ "$_ans" == [yY] ]] || { echo "[claude-guard] aborted." >&2; return 1; }
  fi
  command claude "$@"
}
EOF

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -q 'claude-safe-guard' "$rc"; then
    echo "[install] wrapper already in $rc, skipping"
  else
    printf '%s\n' "$FUNC" >> "$rc"
    echo "[install] wrapper -> $rc"
  fi
done
echo "[install] done. Open a new shell or 'source ~/.zshrc'."
