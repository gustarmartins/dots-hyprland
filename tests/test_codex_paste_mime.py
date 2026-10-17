import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import Mock, patch

HELPER = Path(__file__).resolve().parents[1] / 'dots/.config/kitty/codex_paste.py'
handler = types.ModuleType('kittens.tui.handler')
handler.result_handler = lambda **kwargs: lambda function: function
with patch.dict(sys.modules, {'kittens': types.ModuleType('kittens'), 'kittens.tui': types.ModuleType('kittens.tui'), 'kittens.tui.handler': handler}):
    spec = importlib.util.spec_from_file_location('codex_paste_mime', HELPER)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)

class ClipboardMimeTests(unittest.TestCase):
    def clipboard(self, data, mime='application/x-dtsz', text=''):
        return Mock(get_text=Mock(return_value=text), get_available_mime_types_for_paste=Mock(return_value=(mime,)), get_mime_data=Mock(return_value=data))

    def test_mislabeled_terminal_text_preserves_nerd_icons_and_newlines(self):
        text = '\ue0b6\uf04b terminal\n  pasted text\t✓'
        self.assertEqual(helper.clipboard_text(self.clipboard(text.encode())), text)

    def test_real_binary_not_decoded(self):
        for data in (b'\xff\x80binary', b'valid\0but\x01binary', b'\x1b[31mcommands'):
            self.assertEqual(helper.clipboard_text(self.clipboard(data)), '')

    def test_other_formats_not_reinterpreted(self):
        cp = self.clipboard(b'contents', 'application/octet-stream')
        self.assertEqual(helper.clipboard_text(cp), '')
        cp.get_mime_data.assert_not_called()

    def test_regular_text_wins(self):
        self.assertEqual(helper.clipboard_text(self.clipboard(b'ignored', text='normal')), 'normal')

    def test_size_limit(self):
        self.assertEqual(helper.clipboard_text(self.clipboard(b'a' * (1024 * 1024 + 1))), '')

    def test_paste_does_not_submit(self):
        window = Mock(send_paste_event=Mock(return_value=False))
        helper.paste(window, self.clipboard('text\nsecond line'.encode()), False)
        window.paste_with_actions.assert_called_once_with('text\nsecond line')
        window.send_key.assert_not_called()
