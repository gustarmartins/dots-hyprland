# /// script
# requires-python = ">=3.11"
# dependencies = ["mcp>=1.2.0"]
# ///
import os
import socket
import json as _json
import re
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


def _lua_literal(value: str) -> str:
    """Return a safe Lua literal for a CLI-style scalar value."""
    lowered = value.lower()
    if lowered in {"true", "false"}:
        return lowered
    if re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)", value):
        return value
    return _json.dumps(value)


def _config_expr(name: str, value: str) -> str:
    parts = name.split(":")
    if not parts or any(not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", part) for part in parts):
        raise ValueError(f"Invalid Hyprland Lua config path: {name!r}")
    nested = _lua_literal(value)
    for part in reversed(parts):
        nested = f"{{ {part} = {nested} }}"
    return f"hl.config({nested})"


def _legacy_dispatch_expr(dispatcher: str, args: str) -> str:
    """Translate the small compatibility surface previously advertised here."""
    quoted = _json.dumps(args)
    if dispatcher == "workspace":
        return f"hl.dsp.focus({{ workspace = {quoted} }})"
    if dispatcher == "movetoworkspacesilent":
        return f"hl.dsp.window.move({{ workspace = {quoted}, follow = false }})"
    if dispatcher == "movetoworkspace":
        return f"hl.dsp.window.move({{ workspace = {quoted}, follow = true }})"
    if dispatcher == "focusmonitor":
        return f"hl.dsp.focus({{ monitor = {quoted} }})"
    if dispatcher == "exec":
        return f"hl.dsp.exec_cmd({quoted})"
    if dispatcher == "togglefloating":
        return 'hl.dsp.window.float({ action = "toggle" })'
    if dispatcher == "fullscreen":
        mode = "maximized" if args == "1" else "fullscreen"
        return f'hl.dsp.window.fullscreen({{ mode = "{mode}", action = "toggle" }})'
    raise ValueError(
        f"Legacy dispatcher {dispatcher!r} has no safe Lua mapping; "
        "pass a complete hl.dsp.*(...) expression instead"
    )


def _dispatch_expr(dispatcher: str, args: str = "") -> str:
    if dispatcher.lstrip().startswith("hl.dsp."):
        if args:
            raise ValueError("Do not pass args separately with a Lua hl.dsp expression")
        return dispatcher.strip()
    return _legacy_dispatch_expr(dispatcher, args)


def _batch_expr(command: str) -> str:
    kind, separator, rest = command.strip().partition(" ")
    if not separator:
        raise ValueError(f"Batch command is missing arguments: {command!r}")
    if kind == "eval":
        return rest
    if kind == "keyword":
        name, separator, value = rest.partition(" ")
        if not separator:
            raise ValueError(f"Keyword command is missing a value: {command!r}")
        return _config_expr(name, value)
    if kind == "dispatch":
        dispatcher, _, args = rest.partition(" ")
        expression = _dispatch_expr(dispatcher, args)
        return f"hl.dispatch({expression})"
    raise ValueError(f"Unsupported Lua batch command: {kind!r}")


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
    """Run a Lua dispatcher (write). Prefer a complete expression such as 'hl.dsp.focus({ workspace = "2" })'. A small legacy compatibility map remains for workspace, move-to-workspace, focus-monitor, exec, floating, and fullscreen."""
    return _req("dispatch " + _dispatch_expr(dispatcher, args))


@mcp.tool()
def keyword(name: str, value: str):
    """Set a Lua config option live at runtime (write), e.g. keyword('misc:vrr','2'). Does NOT persist to config files."""
    return _req("eval " + _config_expr(name, value))


@mcp.tool()
def eval_lua(code: str):
    """Evaluate Lua in the active Hyprland config manager (write)."""
    return _req("eval " + code)


@mcp.tool()
def reload():
    """Reload the Hyprland config from disk (write)."""
    return _req("reload")


@mcp.tool()
def batch(commands: list[str]):
    """Run several Lua config/dispatcher expressions in one eval request (write). Accepts 'eval ...', mapped 'keyword ...', or mapped 'dispatch ...' entries."""
    return _req("eval " + "; ".join(_batch_expr(command) for command in commands))


@mcp.tool()
def raw(command: str):
    """Escape hatch: send a raw socket request. With the Lua manager, writes must use 'eval ...' or 'dispatch hl.dsp.*(...)'; legacy keyword/dispatcher syntax is intentionally not translated here."""
    return _req(command)


if __name__ == "__main__":
    mcp.run()
