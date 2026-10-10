"""Recursive transfers with collision-safe commits and source removal only after success."""

import os
import tempfile
from pathlib import Path

from modules.files import local
from modules.files.cloud import CHUNK, EXPORTS, name_checked, provider, unique_name
from services.jobs import check_cancelled, progress


def all_entries(remote, path):
    cursor = ""
    seen = set()
    result = []
    while True:
        check_cancelled()
        page = remote.list(path, cursor)
        result.extend(page["entries"])
        cursor = page.get("cursor", "")
        if not cursor:
            return result
        if cursor in seen or len(result) > 10000:
            raise ValueError("This folder is too large or returned invalid pagination.")
        seen.add(cursor)


def download_name(record):
    """Google Workspace items download as an exported office document."""
    return record["name"] + EXPORTS.get(record.get("mime"), ("", ""))[1]


def transfer(request):
    source_kind, destination_kind = request.get("source", "local"), request.get("destination")
    source = request.get("path")
    target = request.get("target")
    if source_kind == "local":
        requested_source = Path(source)
        if not requested_source.is_absolute():
            requested_source = local.HOME / requested_source
        if requested_source.is_symlink() and request.get("move"):
            raise ValueError("Copy symbolic links instead of moving their targets.")
        source_path = local.safe_path(source)
        if source_path == local.HOME:
            raise ValueError("Choose an item inside Home to transfer.")
        source = str(source_path)
        item = {
            "name": source_path.name,
            "path": source,
            "is_dir": source_path.is_dir(),
            "size": 0 if source_path.is_dir() else source_path.stat().st_size,
        }
        reader = None
    else:
        reader = provider(source_kind)
        item = reader.metadata(source)
        if source in ("/", "root"):
            raise ValueError("Choose an item inside the cloud drive to transfer.")
    if destination_kind == "local":
        destination = local.safe_path(target)
        if not destination.is_dir():
            raise ValueError("Choose a destination folder.")
        target = str(destination)
        writer = None
        if source_kind == "local" and (
            destination == source_path or destination.is_relative_to(source_path)
        ):
            raise ValueError("Choose a folder outside the source folder.")
    else:
        writer = provider(destination_kind)
        if not writer.metadata(target)["is_dir"]:
            raise ValueError("Choose a destination folder.")
    if source_kind == destination_kind and source == target:
        raise ValueError("Choose a different destination.")
    if source_kind == destination_kind == "nextcloud" and target.startswith(
        source.rstrip("/") + "/"
    ):
        raise ValueError("Choose a folder outside the source folder.")

    manifest = []
    visited = set()

    def collect(record, relative):
        check_cancelled()
        name_checked(record["name"])
        if len(manifest) >= 10000 or len(relative) > 64:
            raise ValueError("This folder exceeds the transfer size or nesting limit.")
        key = record.get("target_path") or record["path"]
        if record["is_dir"] and key in visited:
            raise ValueError("This folder contains a circular shortcut or symbolic link.")
        visited.add(key)
        if not reader:
            info = local.safe_path(record["path"]).stat()
            record["signature"] = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
        manifest.append((record, relative))
        if record["is_dir"]:
            children = (
                all_entries(reader, key) if reader else local.list_directory(record["path"])["entries"]
            )
            for child in children:
                if not reader:
                    path = Path(child["path"])
                    if path.is_symlink():
                        raise ValueError(
                            "Transfer symbolic links individually; folders containing links are not copied."
                        )
                    local.safe_path(path)
                    child["size"] = 0 if child["is_dir"] else path.stat().st_size
                collect(child, relative + (child["name"],))

    progress(detail="Reading folders…")
    collect(item, ())
    if source_kind == destination_kind and item["is_dir"] and target in visited:
        raise ValueError("Choose a folder outside the source folder.")
    files = [record for record, _ in manifest if not record["is_dir"]]
    total = sum(record.get("size", 0) for record in files)
    if any(not record.get("size") for record in files):
        total = 0
    if reader and writer:
        total *= 2
    done = 0

    def update(count):
        nonlocal done
        done += count
        progress(done=done, total=total)

    existing = (
        {x["name"] for x in all_entries(writer, target)} if writer else set(os.listdir(target))
    )
    top_name = unique_name(item["name"] if item["is_dir"] else download_name(item), existing)
    destinations = {(): target}
    outputs = []
    progress(total=total, detail="Transferring " + str(item["name"]))
    for record, relative in manifest:
        check_cancelled()
        parent = target if not relative else destinations[relative[:-1]]
        if not relative:
            name = top_name
        else:
            name = record["name"] if record["is_dir"] else download_name(record)
        name_checked(name)
        progress(detail=record["name"])
        if record["is_dir"]:
            if writer:
                location = writer.mkdir(parent, name)
            else:
                location = str(Path(parent) / name)
                # Never merge with a pre-existing folder, including a symlink.
                Path(location).mkdir()
            destinations[relative] = location
            outputs.append(location)
            continue
        if writer:
            if reader:
                with tempfile.TemporaryDirectory(prefix="zephyrus-transfer-") as temporary:
                    staging = Path(temporary) / name
                    with staging.open("wb") as sink:
                        reader.download(record, sink, update)
                    if record.get("mime") not in EXPORTS and staging.stat().st_size != record.get(
                        "size", staging.stat().st_size
                    ):
                        raise ValueError(
                            "The source changed or the download was incomplete. Its source was kept."
                        )
                    location = writer.upload(staging, parent, name, update)
            else:
                location = writer.upload(local.safe_path(record["path"]), parent, name, update)
        else:
            with tempfile.NamedTemporaryFile(
                prefix=".zephyrus-transfer-", dir=parent, delete=False
            ) as sink:
                temporary_path = Path(sink.name)
                try:
                    if reader:
                        reader.download(record, sink, update)
                    else:
                        with local.safe_path(record["path"]).open("rb") as stream:
                            while chunk := stream.read(CHUNK):
                                check_cancelled()
                                sink.write(chunk)
                                update(len(chunk))
                    if record.get("mime") not in EXPORTS and sink.tell() != record.get(
                        "size", sink.tell()
                    ):
                        raise ValueError(
                            "The source changed or the download was incomplete. Its source was kept."
                        )
                    sink.flush()
                    os.fsync(sink.fileno())
                    check_cancelled()
                    # Hard-link commit is atomic and will never replace another item.
                    for _ in range(10001):
                        name = unique_name(name, set(os.listdir(parent)))
                        location = str(Path(parent) / name)
                        try:
                            os.link(temporary_path, location)
                            break
                        except FileExistsError:
                            continue
                    else:
                        raise ValueError("The destination is busy. Try again.")
                finally:
                    temporary_path.unlink(missing_ok=True)
        outputs.append(location)
    if request.get("move"):
        check_cancelled()
        progress(detail="Moving source to Trash…")
        if reader:
            progress(detail="Checking source before moving…")

            def remote_snapshot(record, snapshot, seen, depth=0):
                check_cancelled()
                key = record.get("target_path") or record["path"]
                if depth > 64 or len(snapshot) >= 10000 or record["is_dir"] and key in seen:
                    raise ValueError(
                        "The source changed during the copy. Its source was not moved."
                    )
                seen.add(key)
                snapshot[record["path"]] = (
                    record["is_dir"],
                    record.get("size"),
                    record.get("version", ""),
                    record.get("target_path", ""),
                )
                if record["is_dir"]:
                    for child in all_entries(reader, key):
                        remote_snapshot(child, snapshot, seen, depth + 1)
                return snapshot

            before = {
                record["path"]: (
                    record["is_dir"],
                    record.get("size"),
                    record.get("version", ""),
                    record.get("target_path", ""),
                )
                for record, _ in manifest
            }
            after = remote_snapshot(reader.metadata(source), {}, set())
            if before != after:
                raise ValueError(
                    "The source changed during the copy. The copy was kept and its source was not moved."
                )
            reader.trash(source, item.get("etag"))
        else:
            for record, _ in manifest:
                info = local.safe_path(record["path"]).stat()
                signature = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
                if signature != record["signature"]:
                    raise ValueError(
                        "The source changed during the copy. The copy was kept and its source was not moved."
                    )
            local.delete_entry(source)
    return {
        "message": ("Moved " if request.get("move") else "Copied ") + str(item["name"]),
        "path": outputs[0] if outputs else target,
        "source": source_kind,
        "destination": destination_kind,
        "target": target,
    }
