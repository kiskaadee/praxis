#!/usr/bin/env bash
# =============================================================================
# scripts/install-hooks.sh
#
# Installs project git hooks into .git/hooks/.
# Run once after cloning:
#
#   bash scripts/install-hooks.sh
#
# Or with uv (if added as a script entry point):
#
#   uv run install-hooks
# =============================================================================
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_SRC="$REPO_ROOT/scripts/hooks"
HOOKS_DST="$REPO_ROOT/.git/hooks"

GREEN=$(tput setaf 2 2>/dev/null || true)
RESET=$(tput sgr0    2>/dev/null || true)

install_hook() {
    local name="$1"
    local src="$HOOKS_SRC/$name"
    local dst="$HOOKS_DST/$name"

    if [[ ! -f "$src" ]]; then
        echo "WARNING: $src not found — skipping."
        return
    fi

    cp "$src" "$dst"
    chmod +x "$dst"
    echo "${GREEN}✔${RESET} Installed $name"
}

install_hook "pre-commit"
install_hook "pre-push"

echo ""
echo "Git hooks installed. Run 'bash scripts/install-hooks.sh' after every fresh clone."
