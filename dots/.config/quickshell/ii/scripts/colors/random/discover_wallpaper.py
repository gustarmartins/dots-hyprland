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


class FetchDeadline(BaseException):
    pass


def emit(message, **extra):
    update = {'message': message, **extra}
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


def fetch_json(url, cache_key=None):
    cache = CACHE / f'{cache_key}.json' if cache_key else None
    if cache and cache.exists() and time.time() - cache.stat().st_mtime < 21600:
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
            pool = fetch_json('https://wallhaven.cc/api/v1/search?' + urllib.parse.urlencode(params), key).get('data', [])
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
    fd, name = tempfile.mkstemp(dir=target, prefix='.download-')
    temp = Path(name)
    try:
        with os.fdopen(fd, 'wb') as output:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=25) as response:
                if not image_url_allowed(response.url, item['provider']):
                    raise ValueError('Unexpected image redirect')
                total = 0
                while chunk := response.read(256 * 1024):
                    total += len(chunk)
                    if total > MAX_BYTES:
                        raise ValueError('Image exceeds 40 MB')
                    output.write(chunk)
        with Image.open(temp) as image:
            width, height = image.size
            extension = {'JPEG': '.jpg', 'PNG': '.png', 'WEBP': '.webp'}.get(image.format)
            image.verify()
        if not extension or width < 1920 or height < 1080 or not 1.55 <= width / height <= 2.2:
            raise ValueError('Downloaded image is not a suitable desktop wallpaper')
        dest = target / f"{theme}-{item['id']}{extension}"
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


def finish(result, history, download_only, reused=False):
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
        result['appliedAt'] = int(time.time())
        atomic_json(STATE / 'current.json', result)
    atomic_json(STATE / 'sources' / f"{result['id']}.json", result)
    atomic_json(STATE / 'history.json', (history + [result])[-150:])
    verb = 'Saved' if download_only else 'Applied'
    suffix = ' (downloaded collection)' if reused else ' (saved search results)' if PROVIDER_ERRORS else ''
    emit(f"{verb}: {result['label']} · {result['width']} × {result['height']}{suffix}", **result, busy=False)
    return 0


def main():
    global PUBLISH_STATUS, STARTED_AT
    PROVIDER_ERRORS.clear()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--theme', choices=['mix', *THEMES, 'konachan'])
    parser.add_argument('--download-only', action='store_true', help='Fetch and validate without changing wallpaper')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'fetch.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({'message': 'A wallpaper is already being fetched.', 'busy': False}), flush=True)
            return 2
        PUBLISH_STATUS = not args.download_only
        STARTED_AT = int(time.time())
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
            seen = {entry['id'] for entry in history[-150:]}
            current_id = read_json(STATE / 'current.json', {}).get('id')
            target = args.output_dir or pictures_dir() / 'Wallpapers' / 'Discovery'
            errors = []
            order = theme_order(theme, settings.get('includeKonachan', False), history)
            for selected in order:
                label = 'Konachan · optional' if selected == 'konachan' else THEMES[selected][0]
                emit('Finding ' + label + '…')
                try:
                    for item in candidates(selected, seen):
                        emit('Downloading ' + label + '…')
                        try:
                            path, width, height = download(item, selected, target)
                        except OSError as error:
                            errors.append(str(error))
                            break  # CDN offline: try this theme's downloaded collection.
                        except ValueError as error:
                            errors.append(str(error))
                            continue
                        result = dict(id=item['id'], theme=selected, label=label, provider=item['provider'],
                                      path=str(path), url=item['url'], source=item.get('source', ''),
                                      width=width, height=height, tags=[tag['name'] for tag in item.get('tags', [])],
                                      fetchedAt=int(time.time()))
                        return finish(result, history, args.download_only)
                except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
                    errors.append(f'{label}: {error}')
                    print(errors[-1], file=sys.stderr)
                # Preserve mixed-theme order during outages instead of defaulting
                # to whichever provider happens to be online (usually Konachan).
                if not args.download_only:
                    for result in local_wallpapers(selected, current_id):
                        return finish(result, history, False, reused=True)
            detail = '; '.join([*PROVIDER_ERRORS.values(), *errors])
            emit('No matching wallpaper is available right now. Your current wallpaper was kept.',
                 error=detail, busy=False)
            return 1
        except FetchDeadline:
            emit('Wallpaper fetch timed out. Try again or choose a downloaded image.', busy=False)
            return 1
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous_handler)
            PUBLISH_STATUS = False


if __name__ == '__main__':
    sys.exit(main())
