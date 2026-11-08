# suspend

A KDE Plasma 6 panel widget that turns system sleep ON or OFF with one switch.

When the switch is **ON**, sleep is disabled and the bolt icon turns green. When it is **OFF**, sleep works normally.

<!-- add a screenshot here: ![screenshot](screenshot.png) -->

## Features

- Real toggle switch in the system tray (hidden-icons popup or pinned)
- Reads the actual system state on load and every 5 seconds, so changes made from a terminal show up too
- Green bolt icon when sleep is disabled, theme-coloured icon when enabled
- Password prompt through polkit, with its own name and icon in the dialog
- Works on any Linux distro running Plasma 6
- Supports systemd, OpenRC, runit, dinit and s6, detected automatically
- Manual init-system override and icon size in the widget settings
- Keyboard shortcut and right-click action to toggle
- About & Support page with version, links and donation QR code

## Supported systems

| Part | Supported |
|---|---|
| Desktop | KDE Plasma 6 (developed on 6.8) |
| Distros | Fedora, Arch and Manjaro, Debian and Ubuntu (with Plasma 6), openSUSE, Void, Artix, Alpine, Gentoo and others |
| Init systems | systemd, OpenRC, runit, dinit, s6 |

Tested on Fedora KDE with systemd. Everything else is untested, and reports are welcome.

## How it works

| Init system | ON | OFF |
|---|---|---|
| systemd | masks the `sleep`, `suspend`, `hibernate` and `hybrid-sleep` targets | unmasks them |
| OpenRC, runit, dinit, s6 | writes `/etc/elogind/sleep.conf.d/90-suspend-widget.conf` with `Allow*=no` | removes that file |

The widget only calls `/usr/local/bin/suspend-backend`. Changing the state goes through `pkexec` and a small root helper, `/usr/local/libexec/suspend-helper`, which accepts only `systemd|elogind` and `on|off`.

## Requirements

- KDE Plasma 6 with `kpackagetool6` and the `plasma5support` QML module
- `polkit` and a running polkit agent (Plasma starts `polkit-kde-agent` by default)
- `python3` (used by the installer to build the zip)
- `qrencode` (optional, only to generate the donation QR)
- elogind, for the non-systemd setups

Package names differ by distro. Typical installs:

| Distro | Command |
|---|---|
| Fedora | `sudo dnf install plasma5support polkit qrencode` |
| Arch, Manjaro, Artix | `sudo pacman -S plasma5support polkit qrencode` |
| Debian, Ubuntu | `sudo apt install polkitd pkexec qrencode` (Plasma 6 pulls in the rest) |
| openSUSE | `sudo zypper install polkit qrencode` |
| Void | `sudo xbps-install polkit qrencode` |
| Alpine | `sudo apk add polkit qrencode` |

If the widget shows a QML error about `plasma5support`, search your distro's repos for the package that provides it.

## Install

```bash
git clone https://github.com/YOUR_GITHUB_USER/suspend-widget.git
cd suspend-widget
bash install.sh
```

The installer sets up the system files (backend, helper, polkit policy), builds the package and installs the widget. It asks for your sudo password once.

Then right-click the panel, choose *Add Widgets*, and search for **suspend**.

## Usage

- Click the bolt icon and use the switch, or
- Press the shortcut you set under *Configure suspend, Keyboard Shortcuts*, or
- Right-click the widget and choose the toggle action

From a terminal:

```bash
suspend-backend status    # on or off
suspend-backend detect    # e.g. "systemd (systemd)" or "openrc (elogind)"
```

## Limitations

- The widget alone is not enough. The backend, helper and polkit policy are system files, so installing only the `.plasmoid` from the KDE Store gives a widget that cannot toggle anything. Run `install.sh` for the full setup.
- On non-systemd systems, ON blocks suspend requests that go through elogind (lid, power key, desktop menu, `loginctl`). Tools that suspend directly, such as `zzz` or `pm-suspend`, are not blocked.
- Non-systemd setups need elogind 246 or newer, because older versions ignore `Allow*` options in `sleep.conf.d`.
- On a system without polkit, the switch cannot ask for a password and will fail.

## Distro notes

- **SELinux (Fedora, RHEL):** the installer runs `restorecon` on the helper. If you get "Not authorized", check `ls -lZ /usr/local/libexec/suspend-helper`.
- **Debian and Ubuntu:** the polkit package is `polkitd` on recent releases and `policykit-1` on older ones.
- **Non-systemd distros:** make sure elogind and a polkit agent are running (`loginctl` and `pgrep -a polkit`).
- **Restarting the shell:** the installer tries `systemctl --user restart plasma-plasmashell.service`. If that fails, run `kquitapp6 plasmashell; kstart plasmashell` (some distros call it `kstart6`).
- **Icon cache:** `gtk-update-icon-cache` may be missing on minimal installs. That is harmless, and logging out and in refreshes the icons.

## Files

```
com.custom.suspend/
├── metadata.json
└── contents/
    ├── config/   main.xml, config.qml
    └── ui/       main.qml, configGeneral.qml, configSupport.qml, info.js, icons
```

System side:

```
/usr/local/bin/suspend-backend
/usr/local/libexec/suspend-helper
/usr/share/polkit-1/actions/com.custom.suspend.policy
/usr/share/icons/hicolor/scalable/apps/com.custom.suspend.svg
```

## Uninstall

Turn the switch OFF first, otherwise the sleep targets stay masked. Then:

```bash
kpackagetool6 -t Plasma/Applet -r com.custom.suspend
sudo rm -f /usr/local/bin/suspend-backend \
           /usr/local/libexec/suspend-helper \
           /usr/share/polkit-1/actions/com.custom.suspend.policy \
           /usr/share/icons/hicolor/scalable/apps/com.custom.suspend.svg \
           /etc/elogind/sleep.conf.d/90-suspend-widget.conf
```

If you forgot to turn it OFF on systemd:

```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

## Troubleshooting

- **Blank or old icon:** restart plasmashell, or log out and back in.
- **No password dialog, "Not authorized":** check that a polkit agent is running (`pgrep -a polkit`) and use the switch in the widget rather than a bare terminal.
- **Wrong init detected:** set it manually in the widget settings. Check with `cat /proc/1/comm`.
- **ON has no effect on non-systemd:** check elogind is running and new enough (`loginctl --version`).
- **QML errors:** `journalctl --user -b | grep -i -E "suspend|qml"`

## Support

If this saved you some trouble, you can [buy me a coffee](https://www.buymeacoffee.com/YOUR_NAME).

Bugs and ideas go in the [issue tracker](https://github.com/YOUR_GITHUB_USER/suspend-widget/issues).

## License

GPL-2.0-or-later. Add a `LICENSE` file with the full text when you create the repo.

Created by sanjai shaarugesh.
