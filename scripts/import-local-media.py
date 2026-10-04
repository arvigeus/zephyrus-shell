#!/usr/bin/env python3
"""Inventory and explicitly match existing files to catalogue identities."""

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from media.local import EXTENSIONS, LocalLibrary, destination, library_root


def identity_from_sidecar(path, kind):
    sidecar = path.with_suffix(path.suffix + ".zephyrus.json")
    if sidecar.is_file():
        try:
            return json.loads(sidecar.read_text())
        except (OSError, ValueError):
            return {}
    nfo = (path.parent.parent if kind == "tv" else path.parent) / (
        "tvshow.nfo" if kind == "tv" else "movie.nfo"
    )
    try:
        root = ET.parse(nfo).getroot()
    except (OSError, ET.ParseError):
        return {}
    fields = {"title": root.findtext("title") or "", "year": root.findtext("year") or ""}
    for item in root.findall("uniqueid"):
        if item.get("type") == "imdb":
            fields["imdbId"] = item.text
            fields["id"] = item.text
        elif item.get("type") == "tmdb":
            fields["tmdbId"] = item.text
            fields.setdefault("id", f"tmdb:{kind}:{item.text}")
    return fields


def inventory():
    rows = []
    for kind, extensions in EXTENSIONS.items():
        root = library_root(kind)
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.is_symlink() or path.suffix.lower() not in extensions:
                continue
            fields = identity_from_sidecar(path, kind)
            rows.append(
                {
                    "kind": kind,
                    "path": str(path),
                    "id": fields.get("id") or "",
                    "title": fields.get("title") or "",
                    "year": fields.get("year") or "",
                    **{
                        key: value
                        for key, value in fields.items()
                        if key not in ("id", "title", "year")
                    },
                }
            )
    return rows


def apply_manifest(rows, apply):
    data = (
        Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zephyrus-shell/media"
    )
    library = LocalLibrary(data)
    video_sources = [
        Path(row["path"]).expanduser()
        for row in rows
        if row.get("kind") in ("movie", "tv") and row.get("path")
    ]
    failures = 0
    for row in rows:
        try:
            source = Path(row["path"]).expanduser()
            title = {key: value for key, value in row.items() if key != "path"}
            preserve_name = row.get("kind") == "game"
            target = destination(
                title, source, row.get("season"), row.get("episode"), preserve_name
            )
            if not (row.get("id") and row.get("title")):
                raise ValueError("fill in id and title from the catalogue")
            print(f"{source} -> {target}")
            if apply:
                library.add(
                    title,
                    source,
                    season=row.get("season"),
                    episode=row.get("episode"),
                    preserve_name=preserve_name,
                    move=True,
                    association_videos=video_sources,
                )
        except (KeyError, OSError, ValueError) as error:
            failures += 1
            print(f"SKIP {row.get('path', '?')}: {error}", file=sys.stderr)
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(
        description="Inventory existing media or import a reviewed identity manifest."
    )
    parser.add_argument(
        "--inventory",
        action="store_true",
        help="print a JSON manifest of files in XDG library folders",
    )
    parser.add_argument("--manifest", type=Path, help="reviewed JSON manifest to preview or import")
    parser.add_argument(
        "--apply", action="store_true", help="import the manifest; omitted means dry run"
    )
    args = parser.parse_args()
    if args.inventory and not args.manifest and not args.apply:
        print(json.dumps(inventory(), ensure_ascii=False, indent=2))
        return 0
    if not args.manifest or args.inventory:
        parser.error("choose --inventory or --manifest FILE [--apply]")
    try:
        rows = json.loads(args.manifest.read_text())
        if not isinstance(rows, list):
            raise ValueError("manifest must be a JSON array")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    return apply_manifest(rows, args.apply)


if __name__ == "__main__":
    raise SystemExit(main())
