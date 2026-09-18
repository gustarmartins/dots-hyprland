# Screenshot and image-search input repair — 2026-09-17

Super+Shift+S and Super+Shift+A use the same corrected selector. The cause is not assumed to be exclusive to Super+I Settings.

Changes:
- A single Hyprland focus grab covers every selector surface; the shared sidebar grab remains suspended.
- Every monitor's frozen image must finish loading before any selection panel appears. Display and crop use the same image, with a unique filename per session.
- One mouse button owns a gesture. Stray releases, extra buttons, cancellation, repeated shortcuts and keys still held cannot turn into a phantom selection.
- Final release coordinates are included, including fast/reverse drags and circle start/end points. Empty selections remain open. Retries start with clean state.
- Click targeting respects enabled target types and recomputes the target at the click. Window rectangles use monitor-local coordinates; edge selections are intersected rather than shifted.
- Screenshot/Lens/OCR results are checked before closing. Upload/clipboard failures stay visible and permit retry. Editor mode releases the overlay while the editor is open.
- Rect/Circle buttons no longer use the looping TabBar binding. Recording releases the selection grab and uses global logical coordinates.

## Your acceptance test

For both Super+Shift+S (rectangle) and Super+Shift+A (configured rectangle/circle):

1. Start with a tiled window focused, then a floating window, then Super+I Settings. Press, hold, drag and release. The selector must stay open while held and complete only at release.
2. Repeat with a sidebar or overview open, then from fullscreen (and an XWayland app if used).
3. Try each monitor, moving onto the other monitor before starting a drag. A drag crossing an output edge captures only its starting output's intersection.
4. Try a quick drag, reverse drag, tiny drag, click on a highlighted window, and click on empty desktop. Empty/zero-area selections must stay open. Check Rect/Circle switching and right-drag to the editor.
5. Try an interrupted/canceled drag followed by another attempt, an extra mouse button while held, and pressing the screenshot shortcut twice.
6. Release the shortcut modifiers before normal selection; separately check pressing the mouse while Super is still down. Client-side modified presses are ignored, but compositor-level mouse shortcuts still require physical acceptance.
7. Escape or the close button should cancel when idle. Copy should produce the selected PNG; Lens should open the actual selected image. Processing failures should show a message and allow another attempt.

Expected limits: this is a per-output selector, not a stitched multi-output capture. The UI is busy while copying/uploading; upload timeout is bounded. Existing editor/recording behavior still needs its normal application-level acceptance.

## Automated evidence

Qt Quick tests: actual MouseArea drag plus state transitions for no-motion releases, cancellation/retry, unmatched releases, extra buttons, modifiers, busy state, reverse/loop motion and tiny clicks.
Geometry tests: clipping at all edges, zero/invalid rectangles, circle bounds and fractional scaling.
Action tests: real ImageMagick crop dimensions; stubbed clipboard/editor/OCR/upload/browser services; malformed upload bodies, network/HTTP failure, URL encoding, path quoting and repeated unique saves.
Integration test: actual selector/session/action code under Xvfb, with only Wayland attached properties omitted from the test fixture. Empty selection, failure retention, successful retry and repeated shortcut ownership passed. This does not prove Hyprland pointer-grab or physical mouse behavior.

Runtime state: `qs ipc -c ii call region status` (no screenshot content or window titles).
Case matrix, tests, logs and rollback snapshots:
`~/.local/state/screenshot-drag-audit/20260917-205858-fix/`.

Focus protocol reference: https://quickshell.org/docs/v0.2.1/types/Quickshell.Hyprland/HyprlandFocusGrab/
Mouse cancellation reference: https://doc.qt.io/qt-6/qml-qtquick-mousearea.html#canceled-signal
