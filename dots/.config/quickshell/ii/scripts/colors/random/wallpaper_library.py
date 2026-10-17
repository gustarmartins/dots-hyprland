#!/usr/bin/env python3
"""Persistent discovery originals, restorable history, and bounded storage."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from PIL import Image, ImageOps

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'wallpaper-discovery'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'wallpaper-discovery'
MIB = 1024 * 1024


class StorageFull(OSError):
    pass


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(value, output, ensure_ascii=False, indent=2)
            output.write('\n')
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def pictures_dir():
    try:
        return Path(subprocess.check_output(['xdg-user-dir', 'PICTURES'], text=True).strip())
    except (OSError, subprocess.CalledProcessError):
        return Path.home() / 'Pictures'


class Library:
    def __init__(self, directory=None):
        self.directory = (directory or pictures_dir() / 'Wallpapers/Discovery').resolve()
        self.directory.mkdir(parents=True, exist_ok=True)
        STATE.mkdir(parents=True, exist_ok=True)
        (STATE / 'sources').mkdir(exist_ok=True)
        (CACHE / 'thumbnails').mkdir(parents=True, exist_ok=True)

    @property
    def settings(self):
        return read_json(CONFIG / 'illogical-impulse/config.json', {}).get('background', {}).get('discovery', {})

    @property
    def limits(self):
        settings = self.settings
        def bounded(key, default, minimum):
            try:
                return max(minimum, min(32768, int(settings.get(key, default)))) * MIB
            except (TypeError, ValueError):
                return default * MIB
        return bounded('storageLimitMiB', 1024, 1), bounded('minFreeMiB', 2048, 0)

    def metadata_path(self, identity):
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', identity):
            raise ValueError('Invalid wallpaper identity')
        return STATE / 'sources' / (identity + '.json')

    def thumbnail_path(self, entry):
        key = hashlib.sha256(str(Path(entry['path']).resolve()).encode()).hexdigest()
        return CACHE / 'thumbnails' / (key + '.jpg')

    def active_paths(self):
        configured = read_json(CONFIG / 'illogical-impulse/config.json', {}).get('background', {}).get('wallpaperPath')
        discovery = read_json(STATE / 'current.json', {}).get('path')
        return {str(Path(path).resolve()) for path in [configured, discovery] if path}

    def entries(self):
        active = self.active_paths()
        configured = read_json(CONFIG / 'illogical-impulse/config.json', {}).get('background', {}).get('wallpaperPath')
        configured = str(Path(configured).resolve()) if configured else None
        result = []
        for record in (STATE / 'sources').glob('*.json'):
            entry = read_json(record, {})
            if not isinstance(entry, dict) or not entry.get('path') or entry.get('id') != record.stem:
                continue
            try:
                path = Path(entry['path'])
                stat = path.stat()
                if not path.is_file():
                    continue
                resolved = path.resolve()
                # Older downloads are already managed; arbitrary user files and
                # symlink targets are never cleanup candidates.
                managed = (not path.is_symlink() and resolved.parent == self.directory
                           and path.stem == f"{entry.get('theme')}-{entry['id']}"
                           and path.suffix.lower() in {'.jpg', '.png', '.webp', '.jpeg'})
                thumb = self.thumbnail_path(entry)
                thumbnail_bytes = thumb.stat().st_size if thumb.is_file() else 0
                result.append(dict(entry, favorite=bool(entry.get('favorite', False)), managed=managed,
                    current=str(resolved) == (configured or next(iter(active), None)),
                    protected=str(resolved) in active or bool(entry.get('favorite', False)),
                    bytes=stat.st_size, storageBytes=stat.st_size + thumbnail_bytes,
                    fileIdentity=[stat.st_dev, stat.st_ino, stat.st_mtime_ns],
                    thumbnail=str(thumb) if thumbnail_bytes else '',
                    lastUsedAt=next((entry[key] for key in ['lastUsedAt', 'appliedAt', 'fetchedAt'] if isinstance(entry.get(key), (int, float))), int(stat.st_mtime))))
            except (OSError, ValueError, TypeError):
                continue
        return sorted(result, key=lambda entry: (entry['lastUsedAt'], entry['id']), reverse=True)

    def thumbnails(self, entries):
        total = sum(entry['storageBytes'] for entry in entries)
        for entry in entries:
            if entry['thumbnail']:
                continue
            try:
                # Browsing does not trigger cleanup or encroach on the disk reserve.
                if shutil.disk_usage(CACHE).free < self.limits[1] + MIB:
                    continue
                target = self.thumbnail_path(entry)
                with Image.open(entry['path']) as original:
                    preview = ImageOps.exif_transpose(original)
                    preview.thumbnail((360, 220))
                    preview = preview.convert('RGB')
                    fd, temp = tempfile.mkstemp(dir=target.parent, prefix='.thumbnail-')
                    try:
                        with os.fdopen(fd, 'wb') as output:
                            preview.save(output, 'JPEG', quality=80)
                        size = Path(temp).stat().st_size
                        if total + size > self.limits[0]:
                            continue
                        os.replace(temp, target)
                        total += size
                    finally:
                        Path(temp).unlink(missing_ok=True)
            except (OSError, ValueError):
                continue

    def snapshot(self, generate_thumbnails=False):
        entries = self.entries()
        if generate_thumbnails:
            self.thumbnails(entries)
            entries = self.entries()
        limit, reserve = self.limits
        tracked = {str(Path(entry['path']).resolve()) for entry in entries}
        untracked_bytes = 0
        for path in self.directory.iterdir():
            if path.is_file() and path.suffix.lower() in {'.jpg', '.png', '.webp', '.jpeg'} and str(path.resolve()) not in tracked:
                untracked_bytes += path.stat().st_size
        total = sum(entry['storageBytes'] for entry in entries) + untracked_bytes
        free = shutil.disk_usage(self.directory).free
        summary = dict(entries=entries, count=len(entries), totalBytes=total, limitBytes=limit,
            freeBytes=free, minimumFreeBytes=reserve, directory=str(self.directory),
            queuedCount=sum(bool(entry.get('queued')) for entry in entries),
            untrackedBytes=untracked_bytes,
            keptCount=sum(entry['favorite'] for entry in entries),
            protectedBytes=sum(entry['storageBytes'] for entry in entries if entry['protected']),
            overBudget=total > limit, lowSpace=free < reserve, updatedAt=int(time.time()))
        atomic_json(STATE / 'library.json', summary)
        return summary

    def enforce(self, incoming_bytes=0, extra_protected=(), allocated=False):
        """Oldest unkept managed originals first; never delete active/user files."""
        limit, reserve = self.limits
        entries = self.entries()
        total = self.snapshot()['totalBytes']
        protected = {str(Path(path).resolve()) for path in extra_protected}
        removed = []
        disk_incoming = 0 if allocated else incoming_bytes
        for entry in reversed(entries):
            if total + incoming_bytes <= limit and shutil.disk_usage(self.directory).free >= reserve + disk_incoming:
                break
            if not entry['managed'] or entry['protected'] or str(Path(entry['path']).resolve()) in protected:
                continue
            # Recheck identity and active wallpaper immediately before unlinking.
            path = Path(entry['path'])
            before = path.stat()
            if path.is_symlink() or path.resolve().parent != self.directory or str(path.resolve()) in self.active_paths():
                continue
            if [before.st_dev, before.st_ino, before.st_mtime_ns] != entry['fileIdentity'] or before.st_size != entry['bytes']:
                continue
            path.unlink()
            self.thumbnail_path(entry).unlink(missing_ok=True)
            self.metadata_path(entry['id']).unlink(missing_ok=True)
            total -= entry['storageBytes']
            removed.append(entry['id'])
        summary = self.snapshot()
        summary['removed'] = removed
        if summary['totalBytes'] + incoming_bytes > limit or summary['freeBytes'] < reserve + disk_incoming:
            raise StorageFull('Wallpaper storage is full. Increase its limit or unkeep an older image; your current and kept wallpapers are protected.')
        return summary

    def remember(self, entry):
        path = self.metadata_path(entry['id'])
        previous = read_json(path, {})
        stored = dict(previous, **entry)
        stored['favorite'] = bool(previous.get('favorite', False))
        for key in ['thumbnail', 'bytes', 'storageBytes', 'managed', 'current', 'protected', 'fileIdentity']:
            stored.pop(key, None)
        atomic_json(path, stored)
        self.snapshot(generate_thumbnails=True)
        return stored

    def keep(self, identity, favorite):
        path = self.metadata_path(identity)
        entry = read_json(path, {})
        if not entry or not Path(entry.get('path', '')).is_file():
            raise FileNotFoundError('That wallpaper is no longer stored locally')
        entry['favorite'] = favorite
        atomic_json(path, entry)
        return self.snapshot()

    def restore(self, identity):
        entry = read_json(self.metadata_path(identity), {})
        path = Path(entry.get('path', ''))
        if not path.is_file():
            raise FileNotFoundError('That wallpaper is no longer stored locally')
        with Image.open(path) as image:
            image.verify()
        script = Path(__file__).resolve().parent.parent / 'switchwall.sh'
        with (STATE / 'apply.log').open('w') as log:
            subprocess.run([str(script), '--image', str(path)], stdin=subprocess.DEVNULL,
                stdout=log, stderr=log, check=True, timeout=90)
        entry['appliedAt'] = entry['lastUsedAt'] = int(time.time())
        entry['queued'] = False
        atomic_json(self.metadata_path(identity), entry)
        atomic_json(STATE / 'current.json', entry)
        history = read_json(STATE / 'history.json', [])
        atomic_json(STATE / 'history.json', (history + [entry])[-150:])
        return self.snapshot()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['list', 'prune', 'keep', 'restore'])
    parser.add_argument('identity', nargs='?')
    parser.add_argument('--value', choices=['true', 'false'], default='true')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'fetch.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({'error': 'A wallpaper operation is already running. Try again when it finishes.'}))
            return 2
        library = Library()
        restoring = args.action == 'restore'
        if restoring:
            atomic_json(STATE / 'status.json', dict(message='Restoring your saved wallpaper…', busy=True,
                startedAt=int(time.time()), updatedAt=int(time.time())))
        try:
            if args.action == 'list':
                summary = library.snapshot(generate_thumbnails=True)
            elif args.action == 'prune':
                summary = library.enforce()
            elif args.action == 'keep':
                summary = library.keep(args.identity or '', args.value == 'true')
            else:
                summary = library.restore(args.identity or '')
            if restoring:
                atomic_json(STATE / 'status.json', dict(message='Restored from your saved wallpapers.', busy=False, updatedAt=int(time.time())))
            print(json.dumps({'library': summary}))
            return 0
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            if restoring:
                atomic_json(STATE / 'status.json', dict(message='Could not restore that wallpaper. Your saved copy was kept.', busy=False, updatedAt=int(time.time())))
            print(json.dumps({'error': str(error), 'library': library.snapshot()}))
            return 1


if __name__ == '__main__':
    sys.exit(main())
