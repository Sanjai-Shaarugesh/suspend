#!/bin/bash
# install.sh - sets up the system side of the suspend widget and installs the plasmoid.
# usage: bash install.sh            install or update
#        bash install.sh uninstall  remove everything
set -e

ID=com.custom.suspend
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$HERE/$ID"
ICONS="$HOME/.local/share/icons/hicolor/scalable"

restart_shell() {
    systemctl --user restart plasma-plasmashell.service 2>/dev/null \
        || { kquitapp6 plasmashell; sleep 1; kstart plasmashell >/dev/null 2>&1 & }
}

if [ "$1" = uninstall ]; then
    # leave sleep enabled on the way out
    /usr/local/bin/suspend-backend off 2>/dev/null || true
    kpackagetool6 -t Plasma/Applet -r "$ID" 2>/dev/null || true
    sudo rm -f /usr/local/bin/suspend-backend \
               /usr/local/libexec/suspend-helper \
               /usr/share/polkit-1/actions/$ID.policy \
               /usr/share/icons/hicolor/scalable/apps/$ID.svg \
               /etc/elogind/sleep.conf.d/90-suspend-widget.conf
    rm -f "$ICONS/actions/thunderbolt-symbolic.svg" \
          "$ICONS/actions/suspend-widget-on.svg" \
          "$ICONS/apps/$ID.svg"
    restart_shell
    echo "removed"
    exit 0
fi

[ -f "$PKG/metadata.json" ] || { echo "can't find $PKG/metadata.json, run this from the repo folder" >&2; exit 1; }
command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 not found, is Plasma 6 installed?" >&2; exit 1; }
command -v pkexec >/dev/null || echo "warning: pkexec not found, install polkit or the switch won't work" >&2

sudo mkdir -p /usr/local/libexec /usr/share/icons/hicolor/scalable/apps

sudo tee /usr/local/libexec/suspend-helper >/dev/null <<'EOF_H'
#!/bin/bash
# runs as root via pkexec: suspend-helper <systemd|elogind> <on|off>
T=(sleep.target suspend.target hibernate.target hybrid-sleep.target)
D=/etc/elogind/sleep.conf.d
F=$D/90-suspend-widget.conf

case "$1:$2" in
    systemd:on)  exec /usr/bin/systemctl mask   "${T[@]}" ;;
    systemd:off) exec /usr/bin/systemctl unmask "${T[@]}" ;;
    elogind:on)
        mkdir -p "$D" || exit 1
        printf '[Sleep]\nAllowSuspend=no\nAllowHibernation=no\nAllowSuspendThenHibernate=no\nAllowHybridSleep=no\n' > "$F"
        ;;
    elogind:off) rm -f "$F" ;;
    *) echo "usage: $0 systemd|elogind on|off" >&2; exit 2 ;;
esac
EOF_H
sudo chown root:root /usr/local/libexec/suspend-helper
sudo chmod 755 /usr/local/libexec/suspend-helper
sudo restorecon /usr/local/libexec/suspend-helper 2>/dev/null || true

sudo tee /usr/local/bin/suspend-backend >/dev/null <<'EOF_B'
#!/bin/bash
# suspend-backend status|on|off|detect [auto|systemd|openrc|runit|dinit|s6]
TARGETS=(sleep.target suspend.target hibernate.target hybrid-sleep.target)
CONF=/etc/elogind/sleep.conf.d/90-suspend-widget.conf
HELPER=/usr/local/libexec/suspend-helper

detect_init() {
    [ -d /run/systemd/system ] && { echo systemd; return; }
    case "$(cat /proc/1/comm 2>/dev/null)" in
        dinit)                    echo dinit;  return ;;
        runit|runit-init)         echo runit;  return ;;
        s6-svscan|s6-linux-init*) echo s6;     return ;;
        openrc-init)              echo openrc; return ;;
    esac
    # pid 1 is plain "init" on some distros
    if   [ -d /run/openrc ];   then echo openrc
    elif [ -S /run/dinitctl ]; then echo dinit
    elif [ -d /run/runit ] || [ -d /etc/runit/runsvdir ]; then echo runit
    elif [ -d /run/s6 ] || [ -d /run/s6-linux-init-container ]; then echo s6
    else echo unknown
    fi
}

act="$1"
mode="${2:-auto}"
[ "$mode" = auto ] && mode="$(detect_init)"
[ "$mode" = systemd ] && method=systemd || method=elogind

case "$act" in
    detect) echo "$mode ($method)" ;;
    status)
        if [ "$method" = systemd ]; then
            for t in "${TARGETS[@]}"; do
                systemctl is-enabled "$t" 2>/dev/null | grep -qx masked || { echo off; exit 0; }
            done
            echo on
        else
            [ -f "$CONF" ] && grep -qx 'AllowSuspend=no' "$CONF" && echo on || echo off
        fi ;;
    on|off) pkexec "$HELPER" "$method" "$act" ;;
    *) echo "usage: $0 status|on|off|detect [mode]" >&2; exit 2 ;;
esac
EOF_B
sudo chmod 755 /usr/local/bin/suspend-backend

sudo tee /usr/share/polkit-1/actions/$ID.policy >/dev/null <<'EOF_P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>Suspend Widget</vendor>
  <action id="com.custom.suspend.toggle">
    <description>Enable or disable system sleep</description>
    <message>Suspend: authentication is required to turn sleep ON or OFF</message>
    <icon_name>com.custom.suspend</icon_name>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/local/libexec/suspend-helper</annotate>
  </action>
</policyconfig>
EOF_P

# icons come from the package itself
sudo cp "$PKG/contents/ui/suspend-widget-on.svg" /usr/share/icons/hicolor/scalable/apps/$ID.svg
sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
sudo systemctl restart polkit 2>/dev/null || true

mkdir -p "$ICONS/actions" "$ICONS/apps"
cp "$PKG/contents/ui/thunderbolt-symbolic.svg" "$PKG/contents/ui/suspend-widget-on.svg" "$ICONS/actions/"
cp "$PKG/contents/ui/suspend-widget-on.svg" "$ICONS/apps/$ID.svg"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# build the zip from inside the package so metadata.json sits at its top level
TMP="$(mktemp -d)"
python3 -c "import shutil,sys; shutil.make_archive(sys.argv[1],'zip',sys.argv[2])" "$TMP/suspend-widget" "$PKG"
kpackagetool6 -t Plasma/Applet -r "$ID" 2>/dev/null || true
rm -rf "$HOME/.local/share/plasma/plasmoids/$ID"
kpackagetool6 -t Plasma/Applet -i "$TMP/suspend-widget.zip"
rm -rf "$TMP"

kbuildsycoca6 >/dev/null 2>&1 || true
restart_shell
echo "installed. right-click the panel > Add Widgets > search 'suspend'"
