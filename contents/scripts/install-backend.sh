
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

BACKEND_SOURCE="$SCRIPT_DIR/suspend-backend"
RULE_SOURCE="$SCRIPT_DIR/suspend-sleep.rules"

BACKEND_DEST='/usr/local/bin/suspend-backend'
RULE_DEST='/usr/local/share/com.custom.suspend/suspend-sleep.rules'
COMPAT_DEST='/usr/local/bin/suspend/backend'

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ -f "$BACKEND_SOURCE" ]] ||
    fail "Bundled suspend-backend is missing."

[[ -f "$RULE_SOURCE" ]] ||
    fail "Bundled Polkit rule is missing."

command -v pkexec >/dev/null 2>&1 ||
    fail "Polkit pkexec is not installed."

# Install backend as data, not as a privileged installation script.
pkexec /usr/bin/install -D -m 755 \
    "$BACKEND_SOURCE" "$BACKEND_DEST"

pkexec /usr/bin/install -D -m 644 \
    "$RULE_SOURCE" "$RULE_DEST"

pkexec /usr/bin/ln -sfn \
    "$BACKEND_DEST" "$COMPAT_DEST"

[[ -x "$BACKEND_DEST" ]] ||
    fail "Backend installation could not be verified."

echo "Backend installed successfully."

