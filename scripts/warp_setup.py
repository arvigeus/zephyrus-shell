#!/usr/bin/env python3
"""Explicit authorization for the packaged, on-demand consumer WARP service."""

import json
import os
import pwd
import subprocess
from pathlib import Path


def configure(
    username,
    offline=False,
    root=Path("/"),
    runner=subprocess.run,
    user_lookup=pwd.getpwnam,
    effective_uid=None,
):
    if (os.geteuid() if effective_uid is None else effective_uid) != 0:
        raise PermissionError("WARP setup must run as root")
    account = user_lookup(username)
    if account.pw_uid == 0:
        raise ValueError("Choose a non-root desktop user")
    if not (root / "usr/lib/systemd/system/zephyrus-warp.service").is_file():
        raise ValueError("Install the zephyrus-shell package before WARP setup")
    if not offline:
        result = runner(
            ["systemctl", "is-active", "warp-svc.service"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.stdout.strip() not in ("inactive", "failed", "unknown"):
            raise ValueError("Disconnect and stop WARP before changing its lifetime policy")
    # This vendor lifetime override is opt-in setup, not a package-install side effect.
    asset = root / "usr/share/zephyrus-shell/systemd/system/warp-on-demand.conf"
    contents = asset.read_text()
    dropin = root / "etc/systemd/system/warp-svc.service.d/zephyrus.conf"
    dropin.parent.mkdir(parents=True, exist_ok=True)
    temporary = dropin.with_suffix(".conf.tmp")
    temporary.write_text(contents)
    temporary.chmod(0o644)
    temporary.replace(dropin)
    policy = root / "etc/polkit-1/rules.d/90-zephyrus-warp.rules"
    policy.parent.mkdir(parents=True, exist_ok=True)
    contents = """polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "zephyrus-warp.service" &&
        (action.lookup("verb") == "start" || action.lookup("verb") == "stop") &&
        subject.user == @USER@) {
        return polkit.Result.YES;
    }
});
""".replace("@USER@", json.dumps(username))
    temporary = policy.with_suffix(".rules.tmp")
    temporary.write_text(contents)
    temporary.chmod(0o644)
    temporary.replace(policy)
    runner(["systemctl", "disable", "warp-svc.service"], check=True)
    if not offline:
        runner(["systemctl", "daemon-reload"], check=True)
