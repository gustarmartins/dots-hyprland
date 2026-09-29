#!/usr/bin/env python3
"""Cache one MPRIS artwork URL read from stdin; never expose its payload in argv."""
import os
from pathlib import Path
import sys
import tempfile
from urllib.request import urlopen

# Bound untrusted media metadata/downloads without blocking the shell UI.
MAX_BYTES = 32 * 1024 * 1024


def main():
    destination = Path(sys.argv[1])
    url = sys.stdin.read(MAX_BYTES + 1)
    if not url or len(url) > MAX_BYTES:
        raise ValueError("invalid artwork URL size")
    if destination.is_file() and destination.stat().st_size:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with urlopen(url, timeout=20) as response:
            with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=destination.name + ".",
                                             delete=False) as output:
                temporary = Path(output.name)
                total = 0
                while chunk := response.read(64 * 1024):
                    total += len(chunk)
                    if total > MAX_BYTES:
                        raise ValueError("artwork is too large")
                    output.write(chunk)
                if not total:
                    raise ValueError("empty artwork")
        os.replace(temporary, destination)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # URL errors may embed the entire data URL: log only the error class.
        print("Cover-art cache failed: " + type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
