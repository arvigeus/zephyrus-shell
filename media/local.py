"""Identity-based local library shared by catalogue and torrent workers."""
import json
import os
from contextlib import contextmanager
from pathlib import Path
import re
import shutil
import sqlite3
import tempfile
import xml.etree.ElementTree as ET

VIDEO_EXTENSIONS = {'.mkv', '.mp4', '.webm', '.avi', '.mov', '.m4v'}
SUBTITLE_EXTENSIONS = {'.srt', '.ass', '.ssa', '.vtt', '.sub', '.idx'}
AUDIO_EXTENSIONS = {'.flac', '.mp3', '.m4a', '.ogg', '.opus', '.wav'}
BOOK_EXTENSIONS = {'.epub', '.pdf', '.mobi', '.azw3', '.cbz', '.cbr'}
GAME_EXTENSIONS = {'.zip', '.7z', '.tar', '.gz', '.xz', '.bz2', '.iso', '.bin', '.cue',
                   '.appimage', '.exe', '.sh', '.deb', '.rpm', '.dmg'}
EXTENSIONS = {'movie': VIDEO_EXTENSIONS, 'tv': VIDEO_EXTENSIONS,
              'music': AUDIO_EXTENSIONS, 'book': BOOK_EXTENSIONS, 'game': GAME_EXTENSIONS}


def xdg_dir(name, fallback):
    """Resolve the XDG user directory, including user-dirs.dirs on desktops."""
    value = os.environ.get(name)
    if not value:
        config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'user-dirs.dirs'
        try:
            match = re.search(r'^' + re.escape(name) + r'="([^"]*)"\s*$', config.read_text(), re.M)
            value = match.group(1) if match else None
        except OSError:
            pass
    value = (value or str(Path.home() / fallback)).replace('$HOME', str(Path.home()))
    return Path(value).expanduser()


def library_root(kind):
    if kind in ('movie', 'tv'):
        return xdg_dir('XDG_VIDEOS_DIR', 'Videos') / ('Movies' if kind == 'movie' else 'Series')
    if kind == 'music':
        return xdg_dir('XDG_MUSIC_DIR', 'Music')
    if kind == 'book':
        return xdg_dir('XDG_DOCUMENTS_DIR', 'Documents') / 'Books'
    if kind == 'game':
        return Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'zephyrus-shell/games'
    raise ValueError('Unsupported local library type.')


def safe_name(value):
    name = re.sub(r'[\\/:*?"<>|\x00-\x1f]', ' ', str(value or '')).strip(' .')
    return re.sub(r'\s+', ' ', name)[:160] or 'Untitled'


def identity(title):
    kind = title.get('kind')
    identifier = title.get('imdbId') or title.get('id') or ''
    if kind in ('movie', 'tv') and title.get('tmdbId') and not title.get('imdbId'):
        identifier = f'tmdb:{kind}:{title["tmdbId"]}'
    if not kind or not identifier:
        raise ValueError('A catalogue identity is required before importing.')
    return str(identifier)


def label(title):
    year = str(title.get('year') or '')[:4]
    return safe_name(title.get('title')) + (f' ({year})' if year.isdigit() else '')


def episode_numbers(name):
    match = re.search(r'(?i)\bS(\d{1,2})[ ._-]*E(\d{1,3})\b', name)
    return (int(match[1]), int(match[2])) if match else None


def subtitle_associations(videos, subtitles):
    """Assign source-folder subtitles to videos before their filenames change.

    Exact video stems win over episode numbers. An otherwise unmatched lone
    subtitle follows the lone video in its folder when it has no episode ID.
    Ambiguous subtitles stay untouched.
    """
    videos = [Path(path) for path in videos]
    subtitles = [Path(path) for path in subtitles]
    result = {video: [] for video in videos}
    for subtitle in subtitles:
        if (subtitle.suffix.lower() not in SUBTITLE_EXTENSIONS or
                not subtitle.is_file() or subtitle.is_symlink()):
            continue
        siblings = [video for video in videos if video.parent == subtitle.parent]
        sibling_subtitles = [path for path in subtitles
                             if path.parent == subtitle.parent and
                             path.suffix.lower() in SUBTITLE_EXTENSIONS]
        number = episode_numbers(subtitle.stem)
        matches = []
        for video in siblings:
            video_number = episode_numbers(video.stem)
            if number and video_number and number != video_number:
                continue
            stem = video.stem
            prefix = subtitle.stem[:len(stem)].casefold() == stem.casefold()
            if prefix and (len(subtitle.stem) == len(stem) or
                           subtitle.stem[len(stem)] in '._- '):
                matches.append((3, video, subtitle.stem[len(stem):]))
            elif number and number == video_number:
                marker = re.search(r'(?i)\bS\d{1,2}[ ._-]*E\d{1,3}\b', subtitle.stem)
                matches.append((2, video, subtitle.stem[marker.end():]))
            elif len(siblings) == len(sibling_subtitles) == 1 and not number:
                matches.append((1, video, ''))
        if matches:
            matches.sort(key=lambda row: row[0], reverse=True)
            if len(matches) == 1 or matches[0][0] > matches[1][0]:
                _, video, suffix = matches[0]
                result[video].append((subtitle, suffix))
    return result


def destination(title, source, season=None, episode=None, preserve_name=False):
    kind = title['kind']
    suffix = source.suffix.lower()
    if kind == 'game' and source.name.lower().endswith(('.tar.gz', '.tar.xz', '.tar.bz2')):
        suffix = ''.join(source.suffixes[-2:]).lower()
    if suffix not in EXTENSIONS[kind] and not (kind == 'game' and suffix in ('.tar.gz', '.tar.xz', '.tar.bz2')):
        raise ValueError('This file type is not supported in the selected library.')
    root = library_root(kind)
    name = label(title)
    if kind == 'movie':
        return root / name / (name + suffix)
    if kind == 'tv':
        numbers = (season, episode) if season is not None and episode is not None else episode_numbers(source.name)
        if numbers is None:
            raise ValueError('A TV file needs an S01E01 episode number before it can be imported.')
        s, e = map(int, numbers)
        if not (0 <= s <= 99 and 1 <= e <= 999):
            raise ValueError('Season must be 0–99 and episode must be 1–999.')
        return root / name / f'Season {s:02d}' / f'{name} - S{s:02d}E{e:02d}{suffix}'
    if kind == 'music':
        artist = safe_name(title.get('artist'))
        album = safe_name(title.get('album'))
        release = str(title.get('releaseDate') or title.get('release_date') or '')[:10]
        if not (title.get('artist') and title.get('album') and re.fullmatch(r'\d{4}-\d{2}-\d{2}', release)):
            raise ValueError('Music needs artist, album, and full release date for the flat filename.')
        return root / f'{safe_name(title.get("title"))} - {artist} - {album} ({release}){suffix}'
    if kind == 'book':
        author = safe_name(title.get('author') or 'Unknown author')
        return root / author / name / (name + suffix)
    return root / name / (safe_name(source.name) if preserve_name else name + suffix)


def write_nfo(path, title, *, original_name='', release_name='', source=''):
    kind = title['kind']
    if kind not in ('movie', 'tv'):
        sidecar = path.with_suffix(path.suffix + '.zephyrus.json')
        if not sidecar.exists():
            sidecar.write_text(json.dumps({key: title.get(key) for key in
                                           ('kind', 'id', 'title', 'year', 'artist', 'album',
                                            'releaseDate', 'author') if title.get(key)},
                                          ensure_ascii=False, indent=2) + '\n')
        return
    target = (path.parent if kind == 'movie' else path.parent.parent) / ('movie.nfo' if kind == 'movie' else 'tvshow.nfo')
    created = not target.exists()
    if created:
        root = ET.Element('movie' if kind == 'movie' else 'tvshow')
        ET.SubElement(root, 'title').text = str(title.get('title') or '')
        if title.get('year'):
            ET.SubElement(root, 'year').text = str(title['year'])[:4]
        identifier = str(title.get('id') or '')
        imdb = title.get('imdbId') or (identifier if re.fullmatch(r'tt\d+', identifier) else '')
        tmdb_alias = re.fullmatch(r'tmdb:(?:movie|tv):(\d+)', identifier)
        tmdb = title.get('tmdbId') or (tmdb_alias[1] if tmdb_alias else '')
        ids = [('imdb', imdb), ('tmdb', tmdb)]
        default = 'imdb' if imdb else 'tmdb'
        for provider, value in ids:
            if value:
                ET.SubElement(root, 'uniqueid', type=provider,
                              default='true' if provider == default else 'false').text = str(value)
        target.write_bytes(ET.tostring(root, encoding='utf-8', xml_declaration=True))
    if not original_name:
        return
    release_target = target if kind == 'movie' and created else path.with_suffix('.release.nfo')
    try:
        root = ET.parse(release_target).getroot() if release_target.exists() else ET.Element('episodedetails')
    except ET.ParseError:
        return
    if kind == 'tv':
        numbers = episode_numbers(path.name)
        if numbers:
            for key, value in zip(('season', 'episode'), numbers):
                if root.find(key) is None:
                    ET.SubElement(root, key).text = str(value)
    release = root.find('zephyrusrelease')
    if release is None:
        release = ET.SubElement(root, 'zephyrusrelease')
    for key, value in (('name', release_name or original_name),
                       ('originalfilename', original_name), ('source', source)):
        element = release.find(key)
        if element is None:
            element = ET.SubElement(release, key)
        element.text = str(value)
    release_target.write_bytes(ET.tostring(root, encoding='utf-8', xml_declaration=True))


class LocalLibrary:
    def __init__(self, data):
        self.data = Path(data)
        self.data.mkdir(parents=True, exist_ok=True)
        with self.db() as db:
            db.execute('CREATE TABLE IF NOT EXISTS local_files ('
                       'kind TEXT NOT NULL, title_id TEXT NOT NULL, season INTEGER NOT NULL DEFAULT 0, '
                       'episode INTEGER NOT NULL DEFAULT 0, path TEXT NOT NULL UNIQUE, '
                       'title_json TEXT NOT NULL, PRIMARY KEY(kind,title_id,season,episode,path))')
            db.execute('CREATE TABLE IF NOT EXISTS local_sources ('
                       'path TEXT PRIMARY KEY, torrent_hash TEXT NOT NULL DEFAULT \'\', '
                       'source_path TEXT NOT NULL DEFAULT \'\')')

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.data / 'library.sqlite', timeout=20)
        try:
            with db:
                yield db
        finally:
            db.close()

    def add(self, title, source, *, season=None, episode=None, preserve_name=False,
            torrent_hash='', move=False, source_path=None, release_name='',
            association_videos=None):
        source = Path(source)
        if not source.is_file() or source.is_symlink():
            raise ValueError('The completed file is unavailable or is a symbolic link.')
        target = destination(title, source, season, episode, preserve_name)
        subtitle_moves = []
        if title['kind'] in ('movie', 'tv') and move and source != target:
            siblings = list(source.parent.iterdir())
            videos = {path for path in siblings if path.is_file() and not path.is_symlink()
                      and path.suffix.lower() in VIDEO_EXTENSIONS}
            videos.update(Path(path) for path in association_videos or []
                          if Path(path).parent == source.parent)
            subtitles = [path for path in siblings if path.suffix.lower() in SUBTITLE_EXTENSIONS]
            for subtitle, remainder in subtitle_associations(videos, subtitles).get(source, []):
                renamed = target.with_name(target.stem + remainder + subtitle.suffix.lower())
                if renamed.exists() and renamed != subtitle:
                    raise ValueError(f'A subtitle already exists at the library destination: {renamed.name}')
                if any(previous == renamed for _, previous in subtitle_moves):
                    raise ValueError(f'Several subtitles would have the same library name: {renamed.name}')
                subtitle_moves.append((subtitle, renamed))
        target.parent.mkdir(parents=True, exist_ok=True)
        created = False
        moved = False
        moved_subtitles = []
        if target.exists():
            if not target.samefile(source):
                raise ValueError('A different file already exists at the library destination.')
        elif move:
            shutil.move(str(source), str(target))
            created = moved = True
        else:
            try:
                os.link(source, target)
                created = True
            except FileExistsError:
                raise ValueError('A file already exists at the library destination.') from None
            except OSError:
                with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temporary:
                    temporary_path = Path(temporary.name)
                    try:
                        with source.open('rb') as incoming:
                            shutil.copyfileobj(incoming, temporary)
                    except Exception:
                        temporary_path.unlink(missing_ok=True)
                        raise
                try:
                    os.link(temporary_path, target)
                    created = True
                except Exception:
                    raise
                finally:
                    temporary_path.unlink(missing_ok=True)
        try:
            for subtitle, renamed in subtitle_moves:
                if subtitle != renamed:
                    shutil.move(str(subtitle), str(renamed))
                    moved_subtitles.append((subtitle, renamed))
            write_nfo(target, title, original_name=Path(source_path or source).name,
                      release_name=release_name, source='qBittorrent' if torrent_hash else 'Local')
            numbers = (season, episode) if season is not None and episode is not None else episode_numbers(target.name)
            s, e = numbers if title['kind'] == 'tv' else (0, 0)
            with self.db() as db:
                db.execute('INSERT OR REPLACE INTO local_files VALUES (?,?,?,?,?,?)',
                           (title['kind'], identity(title), s, e, str(target), json.dumps(title)))
                db.execute('INSERT OR REPLACE INTO local_sources VALUES (?,?,?)',
                           (str(target), torrent_hash, str(source_path or source)))
        except Exception:
            for subtitle, renamed in reversed(moved_subtitles):
                shutil.move(str(renamed), str(subtitle))
            if moved:
                shutil.move(str(target), str(source))
            elif created:
                target.unlink(missing_ok=True)
            raise
        if move and not moved and source.resolve() != target.resolve():
            source.unlink()
        return str(target)

    def source(self, path):
        with self.db() as db:
            row = db.execute('SELECT torrent_hash,source_path FROM local_sources WHERE path=?',
                             (str(path),)).fetchone()
        return {'torrent_hash': row[0], 'source_path': row[1]} if row else {'torrent_hash': '', 'source_path': ''}

    def remove(self, paths):
        """Remove registered files; movie and season folders include their extra files."""
        paths = [str(path) for path in paths]
        with self.db() as db:
            rows = db.execute('SELECT kind,path FROM local_files').fetchall()
            registered = {path for _, path in rows}
            if any(path not in registered for path in paths):
                raise ValueError('The selected file is no longer in the local library.')
            folders = set()
            for path in paths:
                kind = next(kind for kind, saved in rows if saved == path)
                if kind in ('movie', 'tv'):
                    target = Path(path)
                    folder = target.parent
                    root = library_root(kind).resolve()
                    if (not folder.resolve().is_relative_to(root) or folder == root
                            or folder.is_symlink()):
                        raise ValueError('The library folder is unsafe to remove.')
                    folders.add(folder)
            paths = sorted(set(paths) | {saved for _, saved in rows
                                         if any(Path(saved).is_relative_to(folder) for folder in folders)})
            if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='subtitle_managed'").fetchone():
                db.executemany('DELETE FROM subtitle_managed WHERE video_path=?', ((path,) for path in paths))
            for folder in sorted(folders, key=lambda value: len(value.parts), reverse=True):
                if folder.exists():
                    shutil.rmtree(folder)
            for path in paths:
                target = Path(path)
                kind = db.execute('SELECT kind FROM local_files WHERE path=?', (path,)).fetchone()[0]
                if not any(target.is_relative_to(folder) for folder in folders):
                    target.unlink(missing_ok=True)
                    target.with_suffix(target.suffix + '.zephyrus.json').unlink(missing_ok=True)
                db.execute('DELETE FROM local_sources WHERE path=?', (path,))
                db.execute('DELETE FROM local_files WHERE path=?', (path,))
                folder = target.parent if kind == 'movie' else target.parent.parent if kind == 'tv' else None
                if folder and not db.execute('SELECT 1 FROM local_files WHERE kind=? AND path LIKE ? LIMIT 1',
                                             (kind, str(folder) + '/%')).fetchone():
                    (folder / ('movie.nfo' if kind == 'movie' else 'tvshow.nfo')).unlink(missing_ok=True)
                parent = target.parent if target.parent.exists() else target.parent.parent
                root = library_root(kind)
                while parent != root and parent.is_relative_to(root) and parent.is_dir():
                    try:
                        parent.rmdir()
                    except OSError:
                        break
                    parent = parent.parent

    def list(self, kind):
        with self.db() as db:
            rows = db.execute('SELECT title_id,path,title_json FROM local_files WHERE kind=? ORDER BY title_id', (kind,)).fetchall()
        titles = {}
        for identifier, path, payload in rows:
            if Path(path).is_file():
                title = json.loads(payload)
                titles[identifier] = title | {'local': True, 'localPath': path,
                                               'torrent': bool(self.source(path)['torrent_hash'])}
        return sorted(titles.values(), key=lambda item: (item.get('title') or '').casefold())

    def files(self, title):
        aliases = {str(value) for value in (title.get('id'), title.get('imdbId')) if value}
        if title.get('tmdbId'):
            aliases.add(f'tmdb:{title["kind"]}:{title["tmdbId"]}')
        if not aliases:
            return []
        with self.db() as db:
            rows = db.execute('SELECT title_id,season,episode,path,title_json FROM local_files WHERE kind=?',
                              (title['kind'],)).fetchall()
        files = []
        for identifier, season, episode, path, payload in rows:
            stored = json.loads(payload)
            ids = {identifier} | {str(value) for value in (stored.get('imdbId'), stored.get('id')) if value}
            if stored.get('tmdbId'):
                ids.add(f'tmdb:{stored["kind"]}:{stored["tmdbId"]}')
            if not aliases.isdisjoint(ids) and Path(path).is_file():
                files.append({'season': season, 'episode': episode, 'path': path,
                              'torrent': bool(self.source(path)['torrent_hash'])})
        return files
