#!/usr/bin/env python3
"""SFW game art and illustrated worlds, fetched from Wallhaven's public API."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import random
import signal
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from PIL import Image
# QML watches this source tree. Never create module bytecode inside it.
sys.dont_write_bytecode = True
import wallpaper_library as library

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'wallpaper-discovery'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'wallpaper-discovery'
SCRIPT = Path(__file__).resolve()
HEADERS = {'User-Agent': 'illogical-impulse-wallpaper-discovery/1.0', 'Accept': 'application/json'}
THEMES = {
    'mario': ('Mario worlds', ['id:2532', 'Super Mario Galaxy', 'Super Mario Odyssey']),
    'lis': ('Life is Strange · original', ['id:22263', 'Max Caulfield', 'Arcadia Bay']),
    'tomb': ('Tomb Raider', ['id:680', 'Tomb Raider landscape', 'Tomb Raider concept art']),
    'painted': ('Painted landscapes', ['+landscape +illustration', '+landscape +digital art', '+landscape +vector art', '+scenery +fantasy art']),
    'worlds': ('Other game worlds', ['Firewatch', 'Ori and the Blind Forest', 'Journey (game)', 'The Legend of Zelda: Breath of the Wild', 'Hollow Knight', 'GRIS']),
}
BLOCKED_TAGS = {'anime', 'anime girls', 'anime boys', 'ecchi', 'hentai', 'lingerie', 'bikini', 'cleavage', 'large breasts', 'ass', 'nude', 'nudity'}
LIS_OTHER = ('life is strange 2', 'before the storm', 'true colors', 'double exposure', 'reunion', 'sean diaz', 'daniel diaz', 'alex chen')
MAX_BYTES = 40 * 1024 * 1024
PROVIDER_ERRORS = {}
PUBLISH_STATUS = False
STARTED_AT = 0
OPERATION = "fetch"
PREFETCH_PROTECTED = []


class FetchDeadline(BaseException):
    pass


def emit(message, **extra):
    update = {'message': message, 'operation': OPERATION, **extra}
    if PUBLISH_STATUS:
        atomic_json(STATE / 'status.json', dict(update, startedAt=STARTED_AT,
                    updatedAt=int(time.time()), pid=os.getpid(), busy=extra.get('busy', True)))
    print(json.dumps(update, ensure_ascii=False), flush=True)


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def fetch_json(url, cache_key=None, force=False):
    cache = CACHE / f'{cache_key}.json' if cache_key else None
    if not force and cache and cache.exists() and time.time() - cache.stat().st_mtime < 21600:
        return read_json(cache, {})
    host = urllib.parse.urlparse(url).hostname
    cached = read_json(cache, None) if cache else None
    if host in PROVIDER_ERRORS:
        if cached is not None:
            return cached
        raise OSError(PROVIDER_ERRORS[host])
    # Serialize API calls; once a provider fails, use its cache for this run.
    stamp = STATE / 'last-api-request'
    try:
        delay = 1.5 - (time.time() - float(stamp.read_text()))
    except (OSError, ValueError):
        delay = 0
    if delay > 0:
        time.sleep(delay)
    stamp.write_text(str(time.time()))
    try:
        request = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = response.read(8 * 1024 * 1024 + 1)
        if len(payload) > 8 * 1024 * 1024:
            raise ValueError('Wallpaper index response is too large')
        data = json.loads(payload)
        if not isinstance(data, (dict, list)):
            raise ValueError('Wallpaper index returned invalid data')
    except (OSError, ValueError) as error:
        PROVIDER_ERRORS[host] = str(error)
        emit(('Wallhaven' if host == 'wallhaven.cc' else 'Konachan') +
             ' is unavailable; trying saved results and downloaded wallpapers.')
        if cached is not None:
            return cached
        raise
    if cache:
        atomic_json(cache, data)
    return data


def acceptable(item, theme, detail=False):
    if item.get('purity') != 'sfw' or item.get('category') != 'general':
        return False
    width, height = item.get('dimension_x', 0), item.get('dimension_y', 0)
    if width < 1920 or height < 1080 or not 1.55 <= width / height <= 2.2:
        return False
    if item.get('file_size', 0) > MAX_BYTES:
        return False
    if not detail:
        return True
    tags = {tag['name'].lower() for tag in item.get('tags', [])}
    if tags & BLOCKED_TAGS:
        return False
    if theme == 'lis':
        if any(term in tag for tag in tags for term in LIS_OTHER):
            return False
        if not tags & {'life is strange', 'max caulfield', 'chloe price', 'arcadia bay'}:
            return False
    if theme == 'painted':
        if tags & {'screen shot', 'screenshot', 'photography', 'photograph', 'photorealism'}:
            return False
        if not tags & {'digital art', 'illustration', 'vector art', 'artwork', 'fantasy art', 'concept art', 'painting'}:
            return False
        if not tags & {'landscape', 'scenery', 'nature', 'mountains', 'forest', 'fantasy landscape'}:
            return False
    return True


def theme_order(theme, include_konachan, history):
    if theme != 'mix':
        return [theme]
    # Rotate among interests before repeating one, rather than weighting by database size.
    choices = list(THEMES)
    if include_konachan:
        choices.append('konachan')
    recent = [entry['theme'] for entry in history[-(len(choices) - 1):]]
    random.shuffle(choices)
    return sorted(choices, key=lambda key: key in recent)


def candidates(theme, seen):
    if theme == 'konachan':
        tags = 'rating:safe width:>=1920 height:>=1080 order:random'
        url = 'https://konachan.net/post.json?' + urllib.parse.urlencode({'tags': tags, 'limit': 20})
        for entry in fetch_json(url):
            w, h = entry.get('width', 0), entry.get('height', 0)
            identity = 'konachan-' + str(entry['id'])
            if entry.get('rating') != 's' or h < 1080 or w < 1920 or not 1.55 <= w / h <= 2.2 or identity in seen:
                continue
            yield {'id': identity, 'path': entry['file_url'], 'url': f"https://konachan.net/post/show/{entry['id']}", 'source': entry.get('source', ''), 'dimension_x': w, 'dimension_y': h, 'tags': [{'name': tag} for tag in entry.get('tags', '').split()], 'provider': 'Konachan'}
        return
    queries = list(THEMES[theme][1])
    random.shuffle(queries)
    for query in queries:
        params = dict(q=query, categories='100', purity='100', atleast='1920x1080', sorting='random', order='desc')
        key = 'search-' + re.sub(r'[^a-zA-Z0-9]+', '-', query)
        try:
            search_url = 'https://wallhaven.cc/api/v1/search?' + urllib.parse.urlencode(params)
            pool = fetch_json(search_url, key).get('data', [])
            if pool and not any(acceptable(item, theme) and item.get('id') not in seen for item in pool):
                # A read-ahead batch can exhaust a cached random search. Get a
                # fresh pool instead of making previews wait for its six-hour TTL.
                pool = fetch_json(search_url, key, force=True).get('data', [])
        except (OSError, ValueError):
            continue
        pool = [item for item in pool if acceptable(item, theme) and item['id'] not in seen]
        random.shuffle(pool)
        # Prefer 1440p/4K originals. Keep native 1080p art as a fallback, never upscale it.
        pool.sort(key=lambda item: item['dimension_x'] >= 2560 and item['dimension_y'] >= 1440, reverse=True)
        for item in pool[:5]:
            try:
                detail = fetch_json('https://wallhaven.cc/api/v1/w/' + item['id'], 'detail-' + item['id']).get('data', {})
            except (OSError, ValueError):
                continue
            if acceptable(detail, theme, detail=True):
                detail['provider'] = 'Wallhaven'
                yield detail


def image_url_allowed(url, provider):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != 'https':
        return False
    host = parsed.hostname or ''
    if provider == 'Wallhaven':
        return host == 'w.wallhaven.cc'
    return host in {'konachan.net', 'konachan.com'} or host.endswith('.konachan.net') or host.endswith('.konachan.com')


def download(item, theme, target):
    url = item['path']
    if not image_url_allowed(url, item['provider']):
        raise ValueError('Unexpected image host')
    target.mkdir(parents=True, exist_ok=True)
    storage = library.Library(target)
    storage.metadata_path(str(item['id']))
    fd, name = tempfile.mkstemp(dir=target, prefix='.download-')
    temp = Path(name)
    try:
        with os.fdopen(fd, 'wb') as output:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=25) as response:
                if not image_url_allowed(response.url, item['provider']):
                    raise ValueError('Unexpected image redirect')
                announced = response.headers.get('Content-Length')
                expected = int(announced) if announced and announced.isdigit() else MAX_BYTES
                if expected > MAX_BYTES:
                    raise ValueError('Image exceeds 40 MB')
                if library.shutil.disk_usage(target).free < storage.limits[1] + expected:
                    raise library.StorageFull('Downloads paused to preserve your free-space reserve.')
                total = 0
                while chunk := response.read(256 * 1024):
                    total += len(chunk)
                    if total > MAX_BYTES:
                        raise ValueError('Image exceeds 40 MB')
                    if library.shutil.disk_usage(target).free < storage.limits[1] + len(chunk):
                        raise library.StorageFull('Downloads paused to preserve your free-space reserve.')
                    output.write(chunk)
        with Image.open(temp) as image:
            width, height = image.size
            extension = {'JPEG': '.jpg', 'PNG': '.png', 'WEBP': '.webp'}.get(image.format)
            image.verify()
        if not extension or width < 1920 or height < 1080 or not 1.55 <= width / height <= 2.2:
            raise ValueError('Downloaded image is not a suitable desktop wallpaper')
        dest = target / f"{theme}-{item['id']}{extension}"
        # Validate first, then make room for a real original. Failed downloads
        # never evict an earlier wallpaper merely to reserve estimated space.
        storage.enforce(incoming_bytes=max(0, total - (dest.stat().st_size if dest.is_file() else 0)) + 128 * 1024, extra_protected=[dest, *PREFETCH_PROTECTED], allocated=True)
        os.replace(temp, dest)
        return dest, width, height
    finally:
        temp.unlink(missing_ok=True)


def pictures_dir():
    try:
        return Path(subprocess.check_output(['xdg-user-dir', 'PICTURES'], text=True).strip())
    except (OSError, subprocess.CalledProcessError):
        return Path.home() / 'Pictures'


def local_wallpapers(theme, current_id):
    # Previously validated downloads keep rotation useful during API/CDN outages.
    entries = [read_json(p, {}) for p in (STATE / 'sources').glob('*.json')]
    random.shuffle(entries)
    for entry in entries:
        if entry.get('theme') != theme or entry.get('id') == current_id:
            continue
        if not Path(entry.get('path', '')).is_file():
            continue
        try:
            with Image.open(entry['path']) as image:
                w, h = image.size
                image.verify()
            if w >= 1920 and h >= 1080 and 1.55 <= w / h <= 2.2:
                yield dict(entry, width=w, height=h)
        except (OSError, ValueError):
            continue


def finish(result, history, download_only, reused=False, keep_busy=False):
    storage = library.Library(Path(result['path']).parent)
    result = storage.remember(dict(result, queued=True))
    # Record the original even if applying it fails: it remains restorable.
    if not download_only:
        emit('Applying: ' + result['label'] + '…')
        # switchwall starts background theme helpers. Do not let them inherit
        # the QML process pipes and keep its busy state alive after Python exits.
        with (STATE / 'apply.log').open('w') as log:
            try:
                subprocess.run([str(SCRIPT.parent.parent / 'switchwall.sh'), '--image', result['path']],
                               check=True, stdin=subprocess.DEVNULL, stdout=log, stderr=log, timeout=90)
            except (OSError, subprocess.SubprocessError) as error:
                emit('Downloaded, but applying the wallpaper did not finish. Check your desktop before retrying.',
                     error=str(error), busy=False)
                return 1
        result['appliedAt'] = result['lastUsedAt'] = int(time.time())
        result['queued'] = False
        atomic_json(STATE / 'current.json', result)
    storage.remember(result)
    atomic_json(STATE / 'history.json', (history + [result])[-150:])
    verb = 'Saved' if download_only else 'Applied'
    suffix = ' (downloaded collection)' if reused else ' (saved search results)' if PROVIDER_ERRORS else ''
    emit(f"{verb}: {result['label']} · {result['width']} × {result['height']}{suffix}", **result, busy=keep_busy)
    return 0


def fetch_one(theme, settings, history, seen, target, current_id, download_only, storage_limited):
    errors = []
    for selected in theme_order(theme, settings.get('includeKonachan', False), history):
        label = 'Konachan · optional' if selected == 'konachan' else THEMES[selected][0]
        emit('Finding ' + label + '…')
        try:
            for item in (() if storage_limited else candidates(selected, seen)):
                emit('Downloading ' + label + '…')
                try:
                    path, width, height = download(item, selected, target)
                except library.StorageFull as error:
                    storage_limited = True
                    errors.append(str(error))
                    emit(str(error))
                    break
                except OSError as error:
                    errors.append(str(error))
                    break
                except ValueError as error:
                    errors.append(str(error))
                    continue
                return dict(id=item['id'], theme=selected, label=label, provider=item['provider'],
                    path=str(path), url=item['url'], source=item.get('source', ''), width=width, height=height,
                    tags=[tag['name'] for tag in item.get('tags', [])], fetchedAt=int(time.time())), False
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            errors.append(f'{label}: {error}')
            print(errors[-1], file=sys.stderr)
        if not download_only:
            for result in local_wallpapers(selected, current_id):
                return result, True
    if errors:
        print('; '.join(errors), file=sys.stderr)
    return None, False


def main():
    global PUBLISH_STATUS, STARTED_AT, OPERATION
    PROVIDER_ERRORS.clear()
    PREFETCH_PROTECTED.clear()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--theme', choices=['mix', *THEMES, 'konachan'])
    parser.add_argument('--download-only', action='store_true', help='Fetch and validate without changing wallpaper')
    parser.add_argument('--prefetch', type=int, metavar='COUNT', help='Save a batch to the offline preview queue; never apply it')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    if args.prefetch is not None and not 1 <= args.prefetch <= 24:
        parser.error('Prefetch count must be between 1 and 24')
    STATE.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'fetch.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({'message': 'A wallpaper operation is already running.', 'busy': False}), flush=True)
            return 2
        OPERATION = 'prefetch' if args.prefetch else 'fetch'
        PUBLISH_STATUS = bool(args.prefetch) or not args.download_only
        STARTED_AT = int(time.time())
        saved = 0
        if args.prefetch:
            atomic_json(STATE / 'prefetch.json', {'attemptedAt': STARTED_AT})
        def deadline(signum, frame):
            raise FetchDeadline()
        previous_handler = signal.signal(signal.SIGALRM, deadline)
        signal.alarm(180)
        try:
            config = read_json(CONFIG / 'illogical-impulse/config.json', {})
            settings = config.get('background', {}).get('discovery', {})
            theme = args.theme or settings.get('theme', 'mix')
            if theme not in ['mix', *THEMES, 'konachan']:
                theme = 'mix'
            history = read_json(STATE / 'history.json', [])
            target = args.output_dir or pictures_dir() / 'Wallpapers' / 'Discovery'
            storage = library.Library(target)
            entries = storage.entries()
            current_id = next((entry['id'] for entry in entries if entry['current']), read_json(STATE/'current.json',{}).get('id'))
            download_only = args.download_only or bool(args.prefetch)
            # A ready original is available instantly, including with no API/CDN.
            # Never consume a preview merely because someone opens Settings.
            if not download_only:
                queued = [entry for entry in entries if entry.get('queued') and not entry['current']
                    and (theme == 'mix' or entry.get('theme') == theme)]
                if queued:
                    return finish(min(queued, key=lambda entry: entry.get('fetchedAt', 0)), history, False, reused=True)
            storage_limited = False
            try:
                storage.enforce()
            except library.StorageFull as error:
                storage_limited = True
                emit(str(error))
            seen = {entry['id'] for entry in history[-150:]} | {entry['id'] for entry in storage.entries()}
            count = args.prefetch or 1
            while saved < count:
                result, reused = fetch_one(theme, settings, history, seen, target, current_id, download_only, storage_limited)
                if result is None:
                    break
                code = finish(result, history, download_only, reused=reused, keep_busy=bool(args.prefetch))
                if not args.prefetch:
                    return code
                if code != 0:
                    break
                saved += 1
                PREFETCH_PROTECTED.append(result['path'])
                seen.add(result['id'])
                history = read_json(STATE / 'history.json', [])
                emit(f'Prefetched {saved} of {count} wallpapers. Your wallpaper and colors are unchanged.', savedCount=saved, requestedCount=count)
            if args.prefetch:
                emit(f'Saved {saved} of {count} wallpapers for preview and offline use.' +
                    ('' if saved == count else ' No more matching downloads are available right now.'),
                    savedCount=saved, requestedCount=count, busy=False)
                return 0 if saved else 1
            emit('No matching wallpaper is available right now. Your current wallpaper was kept.',
                 error='; '.join(PROVIDER_ERRORS.values()), busy=False)
            return 1
        except FetchDeadline:
            emit(f'Prefetch timed out; {saved} saved wallpapers are ready to preview.' if args.prefetch
                else 'Wallpaper fetch timed out. Try again or choose a downloaded image.', savedCount=saved, busy=False)
            return 0 if args.prefetch and saved else 1
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous_handler)
            PUBLISH_STATUS = False
            OPERATION = 'fetch'
            PREFETCH_PROTECTED.clear()


if __name__ == '__main__':
    sys.exit(main())
