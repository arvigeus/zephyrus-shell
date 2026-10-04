# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # makepkg metadata and injected build paths
pkgname=('zephyrus-shell-git' 'zephyrus-shell-session-git')
pkgver=r23.g7bb3a0b
pkgrel=1
arch=('any')
url='https://github.com/arvigeus/zephyrus-shell'
license=('LicenseRef-Zephyrus')
makedepends=('git')
source=("zephyrus-shell::git+$url.git")
sha256sums=('SKIP')

pkgver() {
	cd "$srcdir/zephyrus-shell" || return
	printf 'r%s.g%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"
}

_package_payload() {
	cd "$srcdir/zephyrus-shell" || return
	local runtime="$pkgdir/usr/share/zephyrus-shell"
	local file
	local source_files=()
	install -d "$runtime"
	while IFS= read -r -d '' file; do
		[[ -e $file || -L $file ]] || continue
		case $file in
			assets/* | attention/* | books/* | clipboard/* | config/* | core/* | drawers/* | games/* | \
			hyprland/* | media/* | pictures/* | plugins/* | scripts/* | services/* | settings/* | \
			shell/* | systemd/* | widgets/* | desktop/defaults/* | shell.qml) ;;
			*) continue ;;
		esac
		case $file in
			*/__pycache__/* | */QMLTermWidget/* | scripts/check-* | scripts/build-package.sh | \
			scripts/cpu-boost.py | scripts/setup-system.sh | tests/*) continue ;;
		esac
		source_files+=("$file")
	done < <(git ls-files -z --cached --others --exclude-standard)
	((${#source_files[@]} > 0)) || {
		printf 'No Zephyrus runtime payload found in %s\n' "$srcdir/zephyrus-shell" >&2
		return 1
	}
	tar --exclude='__pycache__' --exclude='*.pyc' -cf - -- "${source_files[@]}" \
		| tar --no-same-owner -x -C "$runtime"
	git rev-parse HEAD >"$runtime/REVISION"

	install -Dm755 "$srcdir/zephyrus-shell/packaging/zephyrus-shell" "$pkgdir/usr/bin/zephyrus-shell"
	install -Dm755 "$srcdir/zephyrus-shell/packaging/zephyrus-shell-session" "$pkgdir/usr/bin/zephyrus-shell-session"
	install -Dm755 "$srcdir/zephyrus-shell/packaging/zephyrus-shell-hardware" "$pkgdir/usr/bin/zephyrus-shell-hardware"
	install -Dm755 "$srcdir/zephyrus-shell/scripts/cpu-boost.py" "$pkgdir/usr/lib/zephyrus-shell/cpu-boost"
	install -Dm644 "$srcdir/zephyrus-shell/system/org.zephyrus-shell.cpu-boost.policy" \
		"$pkgdir/usr/share/polkit-1/actions/org.zephyrus-shell.cpu-boost.policy"
	install -Dm644 "$srcdir/zephyrus-shell/systemd/user/zephyrus-clipboard@.service" \
		"$pkgdir/usr/lib/systemd/user/zephyrus-clipboard@.service"
	install -Dm644 "$srcdir/zephyrus-shell/desktop/Zephyrus.colors" \
		"$pkgdir/usr/share/color-schemes/Zephyrus.colors"
	install -Dm644 "$srcdir/zephyrus-shell/desktop/zephyrus.desktop" \
		"$pkgdir/usr/share/wayland-sessions/zephyrus.desktop"
	for file in assets/lucide/LICENSE assets/devicon/LICENSE assets/qt-theme/LICENSE; do
		install -Dm644 "$file" "$pkgdir/usr/share/licenses/zephyrus-shell-git/${file//\//-}"
	done

}

package_zephyrus-shell-git() {
	pkgdesc='Quickshell desktop shell and shared runtime payload'
	arch=('any')
	depends=(
		'quickshell>=0.3.1' 'qt6-declarative' 'qt6-svg'
		'python' 'python-dateutil' 'bash' 'coreutils' 'libpulse' 'polkit' 'systemd' 'glib2' 'xdg-utils' 'xdg-user-dirs'
	)
	provides=('zephyrus-shell')
	conflicts=('zephyrus-shell')
	optdepends=(
		'zephyrus-shell-session-git: full Hyprland session dependency set'
		'qmltermwidget>=2.0: Terminal module (Qt 6)'
		'python-gobject: application GPU selection over D-Bus'
		'python-dbus: Bluetooth pairing agent'
		'hyprshot: screenshots'
		'satty: screenshot annotation'
		'kooha: screen recording'
		'wl-clipboard: copying files and clipboard history'
		'cliphist: clipboard history'
		'libnotify: capture failure notifications'
		'brightnessctl: backlight control (logind fallback available)'
		'ddcutil: external-monitor brightness'
		'i2c-tools: DDC device permissions (explicit host setup required)'
		'pciutils: detailed PCI device names'
		'git: Projects clone and Git maintenance'
		'mise: Projects toolchains and starters'
		'zed: opening Projects in the default editor'
		'legendary: Epic game library'
		'umu-launcher: running supported Epic games with Proton'
		'steam: launching installed Steam games'
		'qbittorrent: torrent handoff (Flatpak installation also supported)'
		'hyprqt6engine: Qt platform theme integration'
		'networkmanager: network controls (enable NetworkManager.service explicitly)'
		'bluez: Bluetooth controls (enable bluetooth.service explicitly)'
		'switcheroo-control: per-application GPU selection (enable switcheroo-control.service explicitly)'
		'mpv: music and radio playback'
		'ffmpeg: media conversion and stream probing'
	)
	_package_payload
}

package_zephyrus-shell-session-git() {
	pkgdesc='Dependencies for the full Zephyrus Hyprland session'
	arch=('any')
	provides=('zephyrus-shell-session')
	conflicts=('zephyrus-shell-session')
	depends=(
		'zephyrus-shell-git'
		'hyprland>=0.56.2' 'hyprlock' 'hypridle' 'hyprpolkitagent' 'uwsm'
		'qt6-wayland' 'qmltermwidget>=2.0'
		'python-dbus' 'python-gobject' 'networkmanager' 'bluez' 'switcheroo-control'
		'xdg-desktop-portal' 'xdg-desktop-portal-hyprland' 'xdg-desktop-portal-gtk'
		'polkit' 'upower' 'pipewire' 'wireplumber' 'pipewire-pulse'
		'wl-clipboard' 'cliphist' 'libnotify'
		'hyprshot' 'satty' 'kooha'
		'brightnessctl' 'ddcutil' 'i2c-tools' 'pciutils'
		'kitty' 'dolphin' 'mpv' 'noto-fonts'
		'qt5-wayland' 'breeze-icons' 'breeze-gtk' 'plasma-integration' 'plasma5-integration'
	)
}
