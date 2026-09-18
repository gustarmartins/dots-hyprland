#!/usr/bin/env python3
"""Process a frozen region using checked argument arrays; keep the source for retries."""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import quote, urlsplit


def run(args, *, data=None, timeout=30):
    result = subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()[-400:]
        raise RuntimeError(f"{Path(args[0]).name} failed" + (": " + detail if detail else ""))
    return result.stdout


def process(args):
    x, y, width, height = args.geometry
    if min(x, y) < 0 or min(width, height) <= 0:
        raise ValueError("Select an area with a width and height.")
    image = Path(args.image).resolve(strict=True)
    png = run(["magick", str(image), "-crop", f"{width}x{height}+{x}+{y}", "+repage", "PNG:-"])
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("The selected image could not be created.")
    with tempfile.TemporaryDirectory(prefix="quickshell-region-") as directory:
        crop = Path(directory) / "selection.png"
        crop.write_bytes(png)
        if args.action == "copy":
            saved = None
            if args.save_dir:
                folder = Path(args.save_dir).expanduser()
                folder.mkdir(parents=True, exist_ok=True)
                stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H.%M.%S-")
                with tempfile.NamedTemporaryFile(dir=folder, prefix="screenshot-" + stamp, suffix=".png", delete=False) as output:
                    output.write(png)
                    saved = output.name
            # wl-copy's background owner must not inherit our captured output pipes.
            result = subprocess.run(["wl-copy", "--type", "image/png"], input=png,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            if result.returncode:
                raise RuntimeError("Could not copy to the clipboard." + (" Saved to " + saved if saved else ""))
        elif args.action == "edit":
            run([args.editor, "-f", str(crop)], timeout=None)
        elif args.action == "ocr":
            languages = run(["tesseract", "--list-langs"]).decode().splitlines()[1:]
            if not languages:
                raise RuntimeError("No OCR languages are installed.")
            text = run(["tesseract", str(crop), "stdout", "-l", "+".join(languages)])
            result = subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=text,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            if result.returncode:
                raise RuntimeError("Could not copy the recognized text.")
        elif args.action == "search":
            if urlsplit(args.search_url).scheme not in ("https", "http"):
                raise ValueError("The image search address is invalid.")
            reply = run(["curl", "--fail-with-body", "--silent", "--show-error", "--connect-timeout", "10",
                         "--max-time", "30", "-F", "files[]=@" + str(crop), args.upload_url], timeout=35)
            payload = json.loads(reply)
            if not isinstance(payload, dict):
                raise RuntimeError("The image upload service returned an invalid response.")
            if payload.get("success") is False:
                raise RuntimeError("The image upload service rejected the image.")
            files = payload.get("files", [])
            url = files[0].get("url") if isinstance(files, list) and files and isinstance(files[0], dict) else None
            if not isinstance(url, str) or urlsplit(url).scheme not in ("https", "http") or not urlsplit(url).netloc:
                raise RuntimeError("The image upload service returned no usable image URL.")
            opened = subprocess.run(["xdg-open", args.search_url + quote(url, safe="")],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            if opened.returncode:
                raise RuntimeError("Could not open the image search in your browser.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--action", choices=["copy", "edit", "search", "ocr"], required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--geometry", nargs=4, type=int, required=True)
    parser.add_argument("--save-dir", default="")
    parser.add_argument("--search-url", default="https://lens.google.com/uploadbyurl?url=")
    parser.add_argument("--upload-url", default="https://uguu.se/upload")
    parser.add_argument("--editor", choices=["satty", "swappy"], default="swappy")
    try:
        process(parser.parse_args())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
