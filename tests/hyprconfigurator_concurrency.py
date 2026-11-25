"""Overlapping Quick Settings writes must retain each widget's submitted value."""
import fcntl
import importlib.util
import multiprocessing
import os
from pathlib import Path
import tempfile


HELPER = (Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii/scripts"
          / "hyprland/hyprconfigurator.py")


def update(path, key, value, signal, release=None):
    spec = importlib.util.spec_from_file_location("hyprconfigurator", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    replace = os.replace
    flock = fcntl.flock

    def notify_lock(fd, operation):
        if release is None and operation == fcntl.LOCK_EX:
            signal.set()
        return flock(fd, operation)

    def controlled_replace(source, destination):
        if release is not None:
            signal.set()
            if not release.wait(5):
                raise RuntimeError("First writer was never released")
        replace(source, destination)
        if release is None:
            signal.set()

    fcntl.flock = notify_lock
    os.replace = controlled_replace
    module.edit_hyprland_config(path, [(key, value)], [])


def overlap(initial, requested):
    ctx = multiprocessing.get_context("spawn")
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "main.lua"
        path.write_text(f"hl.config({{render={{direct_scanout={initial}}}}})\n")
        saved = ctx.Event()
        second_ready = ctx.Event()
        release = ctx.Event()
        first = ctx.Process(target=update, args=(path, "general:allow_tearing", "1", saved, release))
        second = ctx.Process(target=update, args=(path, "render:direct_scanout", requested, second_ready))
        first.start()
        try:
            assert saved.wait(5), "Unrelated widget never reached the replace"
            second.start()
            assert second_ready.wait(5), "Scanout writer never attempted its update"
        finally:
            release.set()
            first.join(5)
            if second.pid is not None:
                second.join(5)
        assert (first.exitcode, second.exitcode) == (0, 0)
        lines = path.read_text().splitlines()
        expected = [f"hl.config({{render={{direct_scanout={requested}}}}})",
                    "hl.config({general={allow_tearing=1}})"]
        return lines == expected, lines


if __name__ == "__main__":
    results = [(request, overlap(start, request)) for start, request in [("0", "1"), ("1", "0")]]
    for requested, (passed, lines) in results:
        print(f"Requested {requested}, persisted {lines}, passed={passed}")
    assert all(passed for _, (passed, _) in results)
