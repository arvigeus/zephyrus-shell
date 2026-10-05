# Cloudflare WARP

The shell's optional consumer WARP integration owns its runtime controller,
service, authorization setup, registration and local exclusions. An installer
such as dotfiles-linux only provides packages and calls the public setup command.

On Arch, install `cloudflare-warp-nox-bin` (AUR), `python-dbus` and
`python-gobject` alongside the shell package. Then, with WARP stopped:

```sh
sudo zephyrus-shell-warp setup --user USERNAME
zephyrus-shell-warp connect
zephyrus-shell-warp status --json
zephyrus-shell-warp disconnect
```

Setup grants that exact account only start/stop of `zephyrus-warp.service`; it
requires neither wheel membership nor an interactive password in the shell's
systemd user service. It disables `warp-svc.service` at boot. Provisioning may
pass `--offline` to avoid contacting a running systemd instance. Nothing registers
or connects during package installation, setup or boot.

First activation accepts Cloudflare's consumer terms, registers only if needed,
selects `warp+doh`, and excludes private, link-local, multicast and broadcast
ranges before connecting. Failures abort connection and release the daemon.
Existing registration persists in `/var/lib/cloudflare-warp`. These exclusions
preserve routing for local DNS, SSH, shares, KDE Connect and local virtual networks;
firewall rules still belong to their applications/host. Globally routable LANs
need explicit exclusions. Zero Trust policies can forbid consumer settings;
organization enrollment and WARP+ licensing remain advanced `warp-cli` operations.

The service requires the vendor daemon only while enabled. Disconnect stops both;
no WARP daemon or status CLI remains when off. A single passive systemd D-Bus
subscriber remains in the shell, with a CLI status stream only while the daemon
is active. Settings and all status pills share events rather than periodic
queries. A bounded IPC-readiness retry runs only at stream startup/failure.
Status-listener errors remain visible; restart the shell after repairing missing
packages or a failed listener. Restarting the shell does not disconnect WARP.

For a development checkout, install a package built by `scripts/build-package.sh`
for root-owned system assets, then run setup; QML and user-side scripts can still
run from the checkout. Do not run user-writable checkout scripts as a persistent
root service.

Verify on a real host: connect, wait for the row and bar logo, check
`curl https://www.cloudflare.com/cdn-cgi/trace` (`warp=on`), exercise local services,
then disconnect and check both units are inactive with no `warp-svc` process.
Check boot activation remains disabled. The isolated test is
`bash scripts/check-warp.sh`; it never uses the host daemon or system bus.

Sources: [Cloudflare Linux setup](https://developers.cloudflare.com/warp-client/get-started/linux/)
and [status notifications](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/troubleshooting/connectivity-status/).
