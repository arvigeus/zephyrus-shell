"""Keep the session's lock background alongside the saved desktop choice."""
import json
import os
from pathlib import Path
from urllib.parse import unquote, urlparse


def update_lock_background(image, config):
    target = Path(config) / "zephyrus-shell/lock-wallpaper"
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(".lock-wallpaper-" + str(os.getpid()))
    try:
        temporary.symlink_to(Path(image).resolve())
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def sync_lock_background(config):
    """Migrate an existing shell wallpaper when installing/starting the session."""
    if (Path(config) / "zephyrus-shell/lock-wallpaper").is_file():
        return True
    try:
        setting = json.loads((Path(config) / "zephyrus-shell/wallpaper.json").read_text())
        url = urlparse(setting.get("image", ""))
        if url.scheme != "file" or url.netloc not in ("", "localhost"):
            return False
        image = Path(unquote(url.path))
        if not image.is_file():
            return False
    except (OSError, ValueError, TypeError, AttributeError):
        return False
    update_lock_background(image, config)
    return True
