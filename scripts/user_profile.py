"""Read the current local account without changing its settings."""
import configparser
import json
import os
from pathlib import Path
import pwd


def profile():
    account = pwd.getpwuid(os.getuid())
    name = account.pw_gecos.split(",", 1)[0] or account.pw_name
    avatars = []
    metadata = configparser.ConfigParser(interpolation=None)
    try:
        metadata.read(f"/var/lib/AccountsService/users/{account.pw_name}")
        name = metadata.get("User", "RealName", fallback="") or name
        icon = metadata.get("User", "Icon", fallback="")
        if icon:
            avatars.append(Path(icon))
    except (OSError, configparser.Error):
        pass
    avatars.extend([Path(account.pw_dir) / ".face", Path(account.pw_dir) / ".face.icon",
                    Path("/var/lib/AccountsService/icons") / account.pw_name])
    avatar = next((path.resolve().as_uri() for path in avatars if path.is_file() and os.access(path, os.R_OK)), "")
    return dict(name=name, username=account.pw_name, avatar=avatar, home=account.pw_dir)


if __name__ == "__main__":
    print(json.dumps(profile()))
