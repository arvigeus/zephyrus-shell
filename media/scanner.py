"""Reviewable discovery of completed qBittorrent and filesystem media."""
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

from media.local import EXTENSIONS, destination, episode_numbers, library_root

try:
    from guessit import guessit
except ImportError:
    guessit = None


def sidecar_identity(path, kind):
    sidecar = path.with_suffix(path.suffix + '.zephyrus.json')
    if sidecar.is_file():
        try:
            return json.loads(sidecar.read_text())
        except (OSError, ValueError):
            return {}
    if kind not in ('movie', 'tv'):
        return {}
    for folder in (path.parent, path.parent.parent):
        nfo = folder / ('movie.nfo' if kind == 'movie' else 'tvshow.nfo')
        try:
            root = ET.parse(nfo).getroot()
        except (OSError, ET.ParseError):
            continue
        title = {'kind': kind, 'title': root.findtext('title') or '', 'year': root.findtext('year') or ''}
        for item in root.findall('uniqueid'):
            if item.get('type') == 'imdb' and item.text:
                title['id'] = title['imdbId'] = item.text
            elif item.get('type') == 'tmdb' and item.text:
                title['tmdbId'] = item.text
                title.setdefault('id', f'tmdb:{kind}:{item.text}')
        return title if title.get('id') and title.get('title') else {}
    return {}


def audio_tags(path):
    try:
        result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format_tags=title,artist,album,date',
                                 '-of', 'json', str(path)], capture_output=True, text=True, timeout=10, check=True)
        tags = json.loads(result.stdout).get('format', {}).get('tags', {})
        tags = {key.casefold(): value for key, value in tags.items()}
        return {key: tags.get(key, '') for key in ('title', 'artist', 'album', 'date')}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def guess(path, kind):
    if kind in ('movie', 'tv') and guessit:
        try:
            data = guessit(str(path) if kind == 'tv' else path.name,
                           options={'type': 'episode' if kind == 'tv' else 'movie'})
        except (ValueError, TypeError):
            data = {}
        title = str(data.get('title') or path.parent.name)
        year = data.get('year')
        output = {'title': title, 'year': str(year or '')}
        if kind == 'tv':
            output['episodeTitle'] = str(data.get('episode_title') or '')
            season, episode = data.get('season'), data.get('episode')
            if not isinstance(season, int):
                match = re.search(r'(?i)\bSeason[ ._-]*(\d{1,2})\b', path.parent.name)
                if match:
                    season = int(match[1])
                    output['title'] = path.parent.parent.name.split(' (')[0]
            if not isinstance(episode, int):
                match = re.search(r'(?i)\b(?:E|Episode)[ ._-]*(\d{1,3})\b', path.stem)
                if match:
                    episode = int(match[1])
            if isinstance(season, int) and isinstance(episode, int):
                output.update(season=season, episode=episode)
        return output
    if kind == 'music':
        tags = audio_tags(path)
        return {'title': tags.get('title') or path.stem, 'artist': tags.get('artist') or '',
                'album': tags.get('album') or '', 'releaseDate': tags.get('date') or ''}
    return {'title': path.stem}


def catalogue_match(catalogue, kind, parsed):
    if kind not in ('movie', 'tv') or not parsed.get('title') or (kind == 'movie' and not parsed.get('year')):
        return None
    try:
        items = catalogue.browse({'kind': kind, 'query': parsed['title'], 'filters': {}})['items']
    except Exception:
        return None
    normalize = lambda value: re.sub(r'\W+', '', str(value or '').casefold())
    matches = {str(item['id']): item for item in items
               if normalize(item.get('title')) == normalize(parsed['title'])
               and (not parsed.get('year') or str(item.get('year') or '')[:4] == str(parsed['year'])[:4])}
    return next(iter(matches.values())) if len(matches) == 1 else None


def candidates(kind, root, qbit, managed_staging=(), torrents=None):
    """Yield qBittorrent sources first, then ordinary files, with no mutation."""
    seen = set()
    for torrent in (torrents if torrents is not None else qbit.call('torrents/info')):
        if float(torrent.get('progress') or 0) < 1:
            continue
        save = Path(torrent.get('save_path') or '').resolve()
        if not save.is_dir() or str(save) in managed_staging:
            continue
        for file in qbit.call('torrents/files?hash=' + str(torrent['hash'])):
            relative = Path(file.get('name') or '')
            raw = save / relative
            path = raw.resolve()
            episodic = bool(episode_numbers(path.name) or re.search(
                r'(?i)\b\d{1,2}(?:E|x)\d{1,3}\b', path.name))
            if (relative.is_absolute() or '..' in relative.parts or not path.is_relative_to(save)
                    or not path.is_file() or raw.is_symlink() or path.suffix.lower() not in EXTENSIONS[kind]
                    or (kind == 'movie' and episodic)
                    or (kind == 'tv' and not episodic)
                    or (kind in ('movie', 'tv') and ('sample' in path.stem.casefold()
                        or any(part.casefold() in ('extras', 'samples', 'trailers') for part in path.parts)))
                    or int(file.get('priority', 1)) == 0):
                continue
            seen.add(path)
            yield {'path': str(path), 'torrent_hash': str(torrent['hash']), 'source': 'qBittorrent'}
    root = Path(root).expanduser().resolve()
    paths = [root] if root.is_file() else sorted(root.rglob('*')) if root.is_dir() else []
    for path in paths:
        if (path.is_file() and not path.is_symlink() and path.suffix.lower() in EXTENSIONS[kind]
                and path.resolve() not in seen):
            yield {'path': str(path.resolve()), 'torrent_hash': '', 'source': 'Folder'}
