#!/usr/bin/env python3
"""Install the local bridge and package its Thunderbird add-on (no accounts)."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HOME = Path.home()
config = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config'))
data = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share'))
files = ['.local/bin/qs-mail', '.local/bin/qs-mail-native', '.local/lib/qs-mail/bridge.py', '.config/systemd/user/qs-mail.service']
for relative in files:
    dest = config / relative.removeprefix('.config/') if relative.startswith('.config/') else HOME / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'dots' / relative, dest)
    if relative.startswith('.local/bin/'): dest.chmod(0o755)
native = HOME / '.mozilla/native-messaging-hosts/org.quickshell.mail.json'
native.parent.mkdir(parents=True, exist_ok=True)
native.write_text(json.dumps({'name':'org.quickshell.mail', 'description':'Local Quickshell Mail bridge', 'path':str(HOME / '.local/bin/qs-mail-native'), 'type':'stdio', 'allowed_extensions':['qs-mail@dots-hyprland']}, indent=2) + '\n')
package = data / 'qs-mail/qs-mail.xpi'
package.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in (ROOT / 'integrations/mail/thunderbird').iterdir():
        if path.is_file(): archive.write(path, path.name)
subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
print(f'Bridge installed. In Thunderbird: Add-ons and Themes → gear → Install Add-on From File → {package}')
print('Then use Super+I → Mail. New installations start disabled; accounts are opt-in.')
