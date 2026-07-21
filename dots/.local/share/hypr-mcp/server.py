# /// script
# requires-python = ">=3.11"
# dependencies = ["mcp>=1.2.0"]
# ///
import os
import socket
import json as _json
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("hyprland")


def _sock_path() -> str:
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not his:
        raise RuntimeError("HYPRLAND_INSTANCE_SIGNATURE not set; is Hyprland running?")
    xdg = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{xdg}/hypr/{his}/.socket.sock"


def _req(cmd: str) -> str:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect(_sock_path())
        s.sendall(cmd.encode())
        out = bytearray()
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            out += chunk
        return out.decode(errors="replace")
    finally:
        s.close()


def _jreq(cmd: str):
    raw = _req("j/" + cmd)
    try:
        return _json.loads(raw)
    except Exception:
        return raw


@mcp.tool()
def version():
    """Hyprland version, branch, commit and build flags."""
    return _jreq("version")


@mcp.tool()
def monitors():
    """All monitors with resolution, refresh rate, scale, position, VRR state and active workspace."""
    return _jreq("monitors")


@mcp.tool()
def workspaces():
    """All workspaces with window counts and the monitor each lives on."""
    return _jreq("workspaces")


@mcp.tool()
def activeworkspace():
    """The currently focused workspace."""
    return _jreq("activeworkspace")


@mcp.tool()
def clients():
    """All open windows (clients): class, title, geometry, workspace, floating/fullscreen state, pid."""
    return _jreq("clients")


@mcp.tool()
def activewindow():
    """The currently focused window and its properties."""
    return _jreq("activewindow")


@mcp.tool()
def devices():
    """Input devices: keyboards, mice, tablets, touch, switches."""
    return _jreq("devices")


@mcp.tool()
def layers():
    """Layer-shell surfaces per monitor (bars, wallpapers, lockscreens, notifications)."""
    return _jreq("layers")


@mcp.tool()
def binds():
    """All configured keybinds with their modmask, key and dispatcher."""
    return _jreq("binds")


@mcp.tool()
def cursorpos():
    """Current cursor position in global coordinates."""
    return _jreq("cursorpos")


@mcp.tool()
def getoption(option: str):
    """Live value of a single config option, e.g. 'misc:vrr', 'general:gaps_in', 'cursor:no_break_fs_vrr'. Shows whether it was explicitly set."""
    return _jreq("getoption " + option)


@mcp.tool()
def systeminfo():
    """System and GPU info as reported by Hyprland (drm, plugins, env)."""
    return _req("systeminfo")


@mcp.tool()
def rollinglog(lines: int = 40):
    """Tail of Hyprland's in-memory rolling log; useful for diagnosing recent warnings/errors."""
    raw = _req("rollinglog")
    return "\n".join(raw.splitlines()[-lines:])


@mcp.tool()
def dispatch(dispatcher: str, args: str = ""):
    """Run a dispatcher (write). Examples: dispatch('workspace','2'), dispatch('fullscreen','0'), dispatch('togglefloating'), dispatch('exec','kitty'). Returns 'ok' on success."""
    return _req(f"dispatch {dispatcher} {args}".strip())


@mcp.tool()
def keyword(name: str, value: str):
    """Set a config option live at runtime (write), e.g. keyword('misc:vrr','2'). Does NOT persist to config files."""
    return _req(f"keyword {name} {value}")


@mcp.tool()
def reload():
    """Reload the Hyprland config from disk (write)."""
    return _req("reload")


@mcp.tool()
def batch(commands: list[str]):
    """Run several commands atomically in one connection (write). Each element is a full command like 'keyword misc:vrr 2' or 'dispatch workspace 3'."""
    return _req("[[BATCH]]" + " ; ".join(commands))


@mcp.tool()
def raw(command: str):
    """Escape hatch: send any raw request over .socket.sock exactly as hyprctl would (without the leading 'hyprctl'). Prefix with 'j/' for JSON."""
    return _req(command)


if __name__ == "__main__":
    mcp.run()
