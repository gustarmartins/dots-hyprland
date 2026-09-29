#!/usr/bin/env python3
"""Read-only build/documentation check; search the exact pinned engine source."""
import argparse
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("terms", nargs="*", help="Literal API names to find in the engine")
parser.add_argument("--source", default=os.environ.get("QS_SOURCE_DIR"),
                    help="Engine git checkout (or set QS_SOURCE_DIR)")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
package = repo / "sdata/dist-arch/illogical-impulse-quickshell-git"
recipe = (package / "PKGBUILD").read_text()
pin = re.search(r"^_commit='([0-9a-f]+)'", recipe, re.M)[1]
print("Fork engine pin:", pin, flush=True)
for command in (["qs", "--version"], ["hyprctl", "version"]):
    result = subprocess.run(command, capture_output=True, text=True, timeout=5)
    print((result.stdout or result.stderr).splitlines()[0], flush=True)
print("Official references:")
for url in ("https://quickshell.org/docs/v0.3.0/types/",
            "https://quickshell.org/changelog/",
            "https://wiki.hypr.land/IPC/",
            "https://doc.qt.io/qt-6/qtquick-performance.html"):
    print(" ", url)
print("The matched source and local patches take precedence over newer API docs.", flush=True)
if not args.source:
    if args.terms:
        parser.error("Source search needs --source or QS_SOURCE_DIR; refusing an unverified checkout")
    raise SystemExit(0)
source = Path(args.source).resolve()
head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
if head != pin:
    raise SystemExit("Source mismatch: " + head + " != " + pin)
for patch in sorted(package.glob("*.patch")):
    result = subprocess.run(["git", "-C", str(source), "apply", "--reverse", "--check", str(patch)],
                            capture_output=True, text=True)
    if result.returncode:
        raise SystemExit("Source does not contain the expected patch: " + patch.name)
    print("Verified patch:", patch.name, flush=True)
if args.terms:
    command = ["rg", "-n", "-F", "--glob", "*.{cpp,hpp,md}"]
    for term in args.terms:
        command.extend(["-e", term])
    command.append(str(source / "src"))
    raise SystemExit(subprocess.run(command).returncode)
