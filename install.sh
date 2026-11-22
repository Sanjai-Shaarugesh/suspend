#!/usr/bin/env bash
# KDE Plasma 6 Suspend Widget Installer
# Works with systemd, OpenRC, runit, dinit and s6, and with sudo, doas or su.
#
# Install:    ./install.sh
# Uninstall:  ./install.sh uninstall
# Unattended: ./install.sh --yes     (accept the package-install prompts)

set -Eeuo pipefail

ID='com.custom.suspend'
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG="$HERE"

BACKEND='/usr/local/bin/suspend-backend'
COMPAT_DIR='/usr/local/bin/suspend'
COMPAT_BACKEND="$COMPAT_DIR/backend"

HELPER_DIR='/usr/local/libexec/com.custom.suspend'
HELPER="$HELPER_DIR/suspend-helper"
INSTALLER="$HELPER_DIR/suspend-installer"
POLICY_DIR='/usr/share/polkit-1/actions'
POLICY="$POLICY_DIR/com.custom.suspend.policy"
STATE_DIR='/var/lib/com.custom.suspend'

SHARE_DIR='/usr/local/share/com.custom.suspend'
RULE_SOURCE="$SHARE_DIR/suspend-sleep.rules"
RULE='/etc/polkit-1/rules.d/00-com.custom.suspend.rules'

ICON_DIR='/usr/share/icons/hicolor/scalable/apps'
ICON_NAME='suspend-widget-on'
SYSTEM_ICON="$ICON_DIR/$ICON_NAME.svg"
SYSTEM_APP_ICON="$ICON_DIR/$ID.svg"

USER_ICON_DIR="$HOME/.local/share/icons/hicolor"

ACTION=install
ASSUME_YES=0

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
info() { echo "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<'USAGE'
Usage: ./install.sh [uninstall] [--yes]

  uninstall   Remove the widget, backend, helper and Polkit files.
  --yes, -y   Do not ask before installing missing packages.
USAGE
}

for arg in "$@"; do
    case "$arg" in
        uninstall) ACTION=uninstall ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; fail "Unknown argument: $arg" ;;
    esac
done

# ---------------------------------------------------------------------
# Privilege escalation: sudo, doas or su
# ---------------------------------------------------------------------

ESC=""
for tool in sudo doas su; do
    if have "$tool"; then
        ESC="$tool"
        break
    fi
done

root() {
    case "$ESC" in
        sudo) sudo "$@" ;;
        doas) doas "$@" ;;
        su)
            local cmd
            printf -v cmd '%q ' "$@"
            su -c "$cmd" root
            ;;
        *) fail "None of sudo, doas or su was found." ;;
    esac
}

confirm() {
    local reply

    (( ASSUME_YES )) && return 0
    [[ -t 0 ]] || return 1

    read -r -p "$1 [Y/n] " reply
    [[ -z "$reply" || "$reply" == [Yy]* ]]
}

# ---------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------

detect_init() {
    if [[ -d /run/systemd/system ]]; then
        echo systemd
        return
    fi

    case "$(cat /proc/1/comm 2>/dev/null || true)" in
        openrc-init) echo openrc; return ;;
        dinit) echo dinit; return ;;
        runit|runit-init) echo runit; return ;;
        s6-svscan|s6-linux-init*) echo s6; return ;;
    esac

    if [[ -d /run/openrc ]]; then
        echo openrc
    elif [[ -S /run/dinitctl || -x /usr/bin/dinitctl || -x /bin/dinitctl ]]; then
        echo dinit
    elif [[ -d /run/runit || -d /etc/runit/runsvdir ]]; then
        echo runit
    elif [[ -d /run/s6 || -d /run/s6-linux-init-container ]]; then
        echo s6
    else
        echo unknown
    fi
}

PM=""
for candidate in pacman apt-get dnf yum zypper apk xbps-install emerge; do
    if have "$candidate"; then
        PM="$candidate"
        break
    fi
done

# Package names per package manager. "agent" is the KDE Polkit
# authentication agent.
pkg_for() {
    case "$1:$PM" in
        polkit:pacman|polkit:dnf|polkit:yum|polkit:zypper|polkit:apk|polkit:xbps-install)
            echo polkit ;;
        polkit:apt-get)
            if apt-cache show pkexec >/dev/null 2>&1; then
                echo "polkitd pkexec"
            else
                echo policykit-1
            fi
            ;;
        polkit:emerge) echo sys-auth/polkit ;;

        python:pacman) echo python ;;
        python:apt-get|python:dnf|python:yum|python:zypper|python:apk|python:xbps-install)
            echo python3 ;;
        python:emerge) echo dev-lang/python ;;

        agent:pacman|agent:xbps-install) echo polkit-kde-agent ;;
        agent:apt-get|agent:apk) echo polkit-kde-agent-1 ;;
        agent:dnf|agent:yum) echo polkit-kde ;;
        agent:zypper) echo polkit-kde-agent-6 ;;
        agent:emerge) echo kde-plasma/polkit-kde-agent ;;

        *) echo "" ;;
    esac
}

install_pkgs() {
    case "$PM" in
        pacman) root pacman -S --needed --noconfirm "$@" ;;
        apt-get)
            root apt-get update
            root apt-get install -y "$@"
            ;;
        dnf) root dnf install -y "$@" ;;
        yum) root yum install -y "$@" ;;
        zypper) root zypper --non-interactive install "$@" ;;
        apk) root apk add "$@" ;;
        xbps-install) root xbps-install -Sy "$@" ;;
        emerge) root emerge --noreplace "$@" ;;
        *) return 1 ;;
    esac
}

find_agent() {
    local f

    for f in \
        /usr/lib/polkit-kde-authentication-agent-1 \
        /usr/lib64/polkit-kde-authentication-agent-1 \
        /usr/libexec/polkit-kde-authentication-agent-1 \
        /usr/libexec/kf6/polkit-kde-authentication-agent-1 \
        /usr/lib/kf6/polkit-kde-authentication-agent-1 \
        /usr/lib/*/libexec/polkit-kde-authentication-agent-1 \
        /usr/lib/*/polkit-kde-authentication-agent-1 \
        /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
        /usr/libexec/polkit-gnome-authentication-agent-1 \
        /usr/lib/mate-polkit/polkit-mate-authentication-agent-1
    do
        [[ -x "$f" ]] && return 0
    done

    have lxqt-policykit-agent && return 0
    have lxpolkit && return 0

    pgrep -f 'polkit.*authentication.*agent|policykit-agent' \
        >/dev/null 2>&1
}

ensure_dependencies() {
    local missing=() names="" pkgs=() logical

    have pkexec || missing+=(polkit)
    have python3 || missing+=(python)

    if (( ${#missing[@]} > 0 )); then
        if [[ -z "$PM" ]]; then
            fail "Missing: ${missing[*]}. No supported package manager was found. Install polkit (pkexec) and python3 manually."
        fi

        for logical in "${missing[@]}"; do
            names+="$(pkg_for "$logical") "
        done

        read -ra pkgs <<< "$names"

        echo "Required packages are missing: ${pkgs[*]}"

        if ! confirm "Install them with $PM (administrator access needed)?"; then
            fail "Required packages were not installed. Install them, then re-run (use --yes for unattended mode)."
        fi

        install_pkgs "${pkgs[@]}" ||
            fail "Package installation failed. Install: ${pkgs[*]}"

        hash -r

        have pkexec || fail "pkexec is still missing after installation."
        have python3 || fail "python3 is still missing after installation."
    fi

    # An authentication agent is needed for the password dialog.
    if ! find_agent; then
        local agent_pkg
        agent_pkg="$(pkg_for agent)"

        warn "No Polkit authentication agent found. The password prompt will not appear without one."

        if [[ -n "$PM" && -n "$agent_pkg" ]]; then
            if confirm "Try to install '$agent_pkg' with $PM?"; then
                read -ra pkgs <<< "$agent_pkg"
                install_pkgs "${pkgs[@]}" ||
                    warn "Could not install '$agent_pkg'. Install the KDE Polkit agent for your distribution manually."
            fi
        fi
    fi

    # Informational checks. These never stop the installation.
    if [[ "$INIT" != systemd ]]; then
        if ! have loginctl && [[ ! -x /etc/init.d/elogind ]] &&
           [[ ! -d /run/elogind ]]; then
            warn "elogind was not detected. The sleep block relies on logind (org.freedesktop.login1). Install and start elogind."
        fi
    fi

    if have pkaction; then
        local ver
        ver="$(pkaction --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1 || true)"

        if [[ "$ver" =~ ^0\.([0-9]+) ]] && (( BASH_REMATCH[1] < 106 )); then
            warn "Polkit $ver is older than 0.106 and does not support the JavaScript rules this widget uses."
        fi
    fi
}

restart_shell() {
    if have kquitapp6; then
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        sleep 1

        if have kstart; then
            kstart plasmashell >/dev/null 2>&1 &
        elif have kstart6; then
            kstart6 plasmashell >/dev/null 2>&1 &
        elif have setsid; then
            setsid plasmashell >/dev/null 2>&1 &
        else
            echo "Start Plasma Shell manually: plasmashell --replace"
        fi
    else
        echo "Restart Plasma Shell manually to reload the widget."
    fi
}

# ---------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------

INIT="$(detect_init)"

[[ "$(id -u)" -eq 0 ]] &&
    fail "Run this installer as your normal desktop user, not as root."

[[ -n "$ESC" ]] ||
    fail "None of sudo, doas or su was found. One is required for the administrator steps."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------

if [[ "$ACTION" == uninstall ]]; then
    if have kpackagetool6; then
        kpackagetool6 -t Plasma/Applet -r "$ID" >/dev/null 2>&1 || true
    fi

    cat > "$TMP/priv-uninstall.sh" <<EOF
set -u

# Re-enable sleep first.
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target || true
fi

rm -f '$RULE' '$POLICY' '$BACKEND' '$COMPAT_BACKEND' \\
      '$SYSTEM_ICON' '$SYSTEM_APP_ICON'
rm -rf '$SHARE_DIR' '$HELPER_DIR' '$STATE_DIR'
rmdir '$COMPAT_DIR' >/dev/null 2>&1 || true

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF

    info "Administrator access is needed to remove the system files."
    root bash "$TMP/priv-uninstall.sh"

    rm -f \
        "$USER_ICON_DIR/actions/thunderbolt-symbolic.svg" \
        "$USER_ICON_DIR/actions/$ICON_NAME.svg" \
        "$USER_ICON_DIR/apps/$ID.svg"

    have gtk-update-icon-cache &&
        gtk-update-icon-cache -f -t "$USER_ICON_DIR" >/dev/null 2>&1 || true

    have kbuildsycoca6 &&
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

    restart_shell

    echo "Suspend widget uninstalled."
    echo "Sleep has been re-enabled."
    exit 0
fi

# ---------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------

have kpackagetool6 ||
    fail "KDE Plasma 6 (kpackagetool6) was not found. Install Plasma 6 first."

for required in \
    metadata.json \
    contents/ui/main.qml \
    contents/ui/suspend-widget-on.svg \
    contents/ui/thunderbolt-symbolic.svg \
    contents/scripts/suspend-backend \
    contents/scripts/suspend-helper \
    contents/scripts/suspend-installer \
    contents/scripts/suspend-sleep.rules \
    contents/scripts/com.custom.suspend.policy
do
    [[ -f "$PKG/$required" ]] || fail "Missing $required in $PKG."
done

echo "Detected init system:      $INIT"
echo "Detected package manager:  ${PM:-none}"
echo "Administrator access via:  $ESC"
echo

ensure_dependencies

# All administrator work runs in ONE privileged step (one password prompt).
cat > "$TMP/priv-install.sh" <<EOF
set -Eeuo pipefail

install -d -m 755 /usr/local/bin '$SHARE_DIR' '$COMPAT_DIR' \\
    '$HELPER_DIR' '$ICON_DIR' '$POLICY_DIR' '$STATE_DIR'

install -D -m 755 '$PKG/contents/scripts/suspend-backend' '$BACKEND'
install -D -m 755 '$PKG/contents/scripts/suspend-helper' '$HELPER'
install -D -m 755 '$PKG/contents/scripts/suspend-installer' '$INSTALLER'
install -D -m 644 '$PKG/contents/scripts/com.custom.suspend.policy' '$POLICY'
install -D -m 644 '$PKG/contents/scripts/suspend-sleep.rules' '$RULE_SOURCE'

ln -sfn '$BACKEND' '$COMPAT_BACKEND'

# World-readable state file that mirrors the current rule.
if [ -f '$RULE' ]; then state=on; else state=off; fi
printf '%s\n' "\$state" > '$STATE_DIR/state'
chmod 644 '$STATE_DIR/state'

install -m 644 '$PKG/contents/ui/suspend-widget-on.svg' '$SYSTEM_ICON'
install -m 644 '$PKG/contents/ui/suspend-widget-on.svg' '$SYSTEM_APP_ICON'

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF

if [[ "$INIT" == openrc ]]; then
    cat >> "$TMP/priv-install.sh" <<'EOF'

if command -v rc-update >/dev/null 2>&1; then
    if [ -x /etc/init.d/dbus ]; then
        rc-update add dbus default >/dev/null 2>&1 || true
        rc-service dbus start >/dev/null 2>&1 || true
    fi
    if [ -x /etc/init.d/elogind ]; then
        rc-update add elogind boot >/dev/null 2>&1 || true
        rc-service elogind start >/dev/null 2>&1 || true
    fi
    if [ -x /etc/init.d/polkit ]; then
        rc-update add polkit default >/dev/null 2>&1 || true
        rc-service polkit restart >/dev/null 2>&1 ||
            rc-service polkit start >/dev/null 2>&1 || true
    fi
fi
EOF
fi

info "Administrator access is needed to install the backend and Polkit files."
root bash "$TMP/priv-install.sh"

case "$INIT" in
    runit|dinit|s6)
        echo "$INIT detected. Ensure D-Bus, elogind and Polkit services are enabled and running."
        ;;
    unknown)
        echo "Unknown init system. Ensure D-Bus, elogind and Polkit are available."
        ;;
esac

# User-level icons
mkdir -p "$USER_ICON_DIR/actions" "$USER_ICON_DIR/apps"

install -m 644 "$PKG/contents/ui/thunderbolt-symbolic.svg" \
    "$USER_ICON_DIR/actions/thunderbolt-symbolic.svg"
install -m 644 "$PKG/contents/ui/suspend-widget-on.svg" \
    "$USER_ICON_DIR/actions/$ICON_NAME.svg"
install -m 644 "$PKG/contents/ui/suspend-widget-on.svg" \
    "$USER_ICON_DIR/apps/$ID.svg"

have gtk-update-icon-cache &&
    gtk-update-icon-cache -f -t "$USER_ICON_DIR" >/dev/null 2>&1 || true

# Widget package
python3 - "$PKG" "$TMP/suspend-widget.zip" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])

with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in root.rglob("*"):
        if path.is_file():
            archive.write(path, path.relative_to(root))
PY

kpackagetool6 -t Plasma/Applet -r "$ID" >/dev/null 2>&1 || true
kpackagetool6 -t Plasma/Applet -i "$TMP/suspend-widget.zip"

have kbuildsycoca6 &&
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

echo
echo "Suspend Widget Installed Successfully"
echo
echo "Init system: $INIT"
echo "Backend:     $BACKEND"
echo "Helper:      $HELPER"
echo "Policy:      $POLICY"

echo
echo "Backend detect: $("$BACKEND" detect auto 2>&1 || true)"
echo "Backend status: $("$BACKEND" status auto 2>&1 || true)"

echo
echo "Add Suspend from Plasma's Add Widgets menu."

restart_shell
