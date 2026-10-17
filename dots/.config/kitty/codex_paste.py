"""Keep normal text paste and attach image clipboards in local Codex terminals."""
from pathlib import Path
import os
import subprocess
import tempfile
import unicodedata
from kittens.tui.handler import result_handler

IMAGE_TYPES = {'image/png': '.png', 'image/jpeg': '.jpg', 'image/webp': '.webp'}

def codex_descendant(pid):
    """Require a Codex process in the terminal's foreground process group."""
    rows = [line.split(None, 4) for line in subprocess.check_output(
        ['ps', '-u', str(os.getuid()), '-o', 'pid=,ppid=,pgid=,tpgid=,comm='], text=True, timeout=2).splitlines()]
    parents = {int(pid)}
    for _ in range(8):
        children = {int(p) for p, parent, *_ in rows if int(parent) in parents}
        if any(int(p) in parents | children and comm == 'codex' and group == foreground
               for p, _, group, foreground, comm in rows):
            return True
        if children <= parents:
            break
        parents |= children
    return False

def is_codex_window(window):
    # /proc/PID/exe points to "codex (deleted)" after a CLI update. The
    # foreground process identity remains valid for the running session.
    if codex_descendant(window.child.pid):
        return True
    try:
        group = int((Path('/proc') / str(window.child.pid) / 'stat').read_text().rsplit(')', 1)[1].split()[5])
    except (OSError, ValueError, IndexError):
        group = -1
    foreground = list(window.child.foreground_processes or [])
    if group > 0:
        foreground.append({'pid': group})
    clients = set()
    for process in foreground:
        try:
            proc = Path('/proc') / str(process['pid'])
            kind = (proc / 'comm').read_text().strip()
            state = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
        except OSError:
            continue
        if kind in ('tmux', 'tmux: client') and state[2] == state[5]:
            clients.add(str(process['pid']))
    if not clients:
        return False
    result = subprocess.run(['tmux', 'list-clients', '-F', '#{client_pid}\t#{pane_pid}'],
                            capture_output=True, text=True, timeout=2)
    return any(client in clients and codex_descendant(pid)
               for client, pid in (line.split('\t') for line in result.stdout.splitlines()))

def clipboard_text(clipboard):
    text = clipboard.get_text()
    if text or 'application/x-dtsz' not in clipboard.get_available_mime_types_for_paste():
        return text
    # wl-copy/libmagic can misclassify UTF-8 terminal text with Nerd Font
    # symbols as DTSZ compressed data. Do not decode arbitrary binary formats.
    data = clipboard.get_mime_data('application/x-dtsz')
    if len(data) > 1024 * 1024:
        return ''
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        return ''
    if any(unicodedata.category(c) == 'Cc' and c not in '\r\n\t' for c in text):
        return ''
    return text

def paste(window, clipboard, image_allowed, image_only=False):
    mime = next((mime for mime in clipboard.get_available_mime_types_for_paste() if mime in IMAGE_TYPES), None)
    if mime and (image_allowed() if callable(image_allowed) else image_allowed):
        data = clipboard.get_mime_data(mime)
        if not data or len(data) > 32 * 1024 * 1024:
            raise ValueError('Clipboard image is empty or exceeds 32 MiB')
        cache = Path.home() / '.cache/codex-clipboard'
        cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        cache.chmod(0o700)
        fd, filename = tempfile.mkstemp(prefix='kitty-', suffix=IMAGE_TYPES[mime], dir=cache)
        with os.fdopen(fd, 'wb') as output:
            output.write(data)
        # Kitty retains bracketed-paste framing and does not press Enter.
        window.paste_with_actions(filename)
    elif image_only:
        # Keep Ctrl+V's application meaning outside an image paste in Codex.
        window.send_key('ctrl+v')
    elif not window.send_paste_event():
        window.paste_with_actions(clipboard_text(clipboard))

def main(args):
    pass

@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    try:
        paste(window, boss.clipboard, lambda: is_codex_window(window),
              image_only='--image-only' in args[1:])
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        boss.show_error('Clipboard paste failed', str(error))
