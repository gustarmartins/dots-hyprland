"""Copy the current Kitty selection with TUI soft-wrap line breaks unwrapped."""
import re
from kittens.tui.handler import result_handler

LIST_ITEM_RE = re.compile(r'^(?:[-*+•◦▪]|\d+[.)])\s+')
BLOCK_START_RE = re.compile(r'^(?:#{1,6}\s+|>\s*|```)')
UNBROKEN_URI_OR_PATH_RE = re.compile(r'^(?:https?://|file://|/|~/)[^\s]+$')


def unwrap_text(text: str) -> str:
    """Join TUI-wrapped lines while preserving paragraphs and list items."""
    lines = [line.rstrip() for line in text.replace('\r\n', '\n').replace('\r', '\n').split('\n')]

    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        return ''

    paragraphs = []
    current = []
    for line in lines:
        if not line.strip():
            if current:
                paragraphs.append(current)
                current = []
        else:
            current.append(line.strip())
    if current:
        paragraphs.append(current)

    out_paragraphs = []
    for para in paragraphs:
        merged = [para[0]]
        for line in para[1:]:
            if LIST_ITEM_RE.match(line) or BLOCK_START_RE.match(line):
                merged.append(line)
            else:
                prev = merged[-1]
                if prev.endswith(('/', '://')) or UNBROKEN_URI_OR_PATH_RE.match(prev):
                    merged[-1] = prev + line
                else:
                    merged[-1] = prev + ' ' + line
        out_paragraphs.append('\n'.join(merged))

    return '\n\n'.join(out_paragraphs)


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None or not window.has_selection():
        return
    raw = window.text_for_selection()
    if not raw:
        return
    unwrapped = unwrap_text(raw)
    if unwrapped:
        boss.clipboard.set_text(unwrapped)
