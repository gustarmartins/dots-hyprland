#!/usr/bin/env python3
"""Owner-requested FE availability wakeups, shared across existing Codex tasks.

No persistent ADB, daemon/model polling, foreground input, or worker launches.
One queue message per explicit wait registration. Saved LAN endpoints are tried
first; local Tailscale status supplies fallback routes while waits are pending.
"""
import argparse
import datetime
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import time
import uuid

ROOT = Path(os.environ.get("CODEX_FE_WAKE_STATE", "/home/gus/.local/state/codex-fe-wake"))
TIMER = "codex-fe-wake.timer"
CODEX = "/home/gus/.local/bin/codex"


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def read(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def save(path, obj):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
    tmp.chmod(0o600)
    os.replace(tmp, path)


def systemctl(*args):
    return subprocess.run(["/usr/bin/systemctl", "--user", *args],
                          capture_output=True, text=True, timeout=12, check=True)


def writer_present(thread):
    path = Path("/home/gus/.codex/thread-writer-locks") / (thread + ".lock")
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return False
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    finally:
        os.close(fd)


def terminal_goal(thread):
    """Completed/archived tasks stay completed; read-only, never edit Codex DBs."""
    with sqlite3.connect("file:/home/gus/.codex/goals_1.sqlite?mode=ro", uri=True) as c:
        row = c.execute("SELECT status FROM thread_goals WHERE thread_id=?", (thread,)).fetchone()
        if row and row[0] in ["complete", "paused", "usageLimited", "budgetLimited", "usage_limited", "budget_limited"]:
            return True
    with sqlite3.connect("file:/home/gus/.codex/state_5.sqlite?mode=ro", uri=True) as c:
        row = c.execute("SELECT archived FROM threads WHERE id=?", (thread,)).fetchone()
        return bool(row and row[0])


def resume_native_goal(thread, config):
    """Use the existing TUI, retaining exact composer bytes through its native editor."""
    pane = config["threads"][thread].get("pane")
    if not pane:
        return False
    command = [sys.executable, "/home/gus/.local/libexec/codex-native-goal-resume.py",
               "--thread", thread, "--pane", pane]
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = proc.communicate(timeout=45)
        result = json.loads(stdout)
    except subprocess.TimeoutExpired:
        proc.terminate()  # Allow the controller's finally block to restore a draft.
        try:
            proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
        result = {"resumed": False, "attempted_controls": True,
                  "reason": "Native control timed out; reconcile private draft receipts before retry"}
    except (ValueError, OSError) as exc:
        result = {"resumed": False, "attempted_controls": True,
                  "reason": "Native control result unverified: " + str(exc)}
    config.setdefault("_native_resume_results", {})[thread] = result
    return proc.returncode == 0 and result.get("resumed") is True


def lan_candidates(config):
    nodes = []
    for value in config.get("lan_endpoints", [])[:3]:
        host, separator, port = value.rpartition(":")
        address = ipaddress.IPv4Address(host)
        if not separator or not port.isdecimal() or not 1 <= int(port) <= 65535:
            raise ValueError("Invalid saved FE LAN endpoint")
        if not any(address in ipaddress.ip_network(net) for net in
                   ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")):
            raise ValueError("FE LAN endpoint must be a saved private-network address")
        node = {"address": str(address), "port": int(port), "route": "lan"}
        if node not in nodes:
            nodes.append(node)
    return nodes


def fe_candidates(snapshot, config):
    local = lan_candidates(config)
    if snapshot.get("BackendState") != "Running":
        return local
    nodes = []
    for p in snapshot.get("Peer", {}).values():
        same_owner = str(p.get("UserID")) == str(config["owner_user_id"])
        known = p.get("ID") in config["known_peer_ids"]
        same_name = p.get("HostName") == config["hostname"] and p.get("OS") == "android"
        if same_owner and (known or same_name) and p.get("Online") is True:
            for addr in p.get("TailscaleIPs", []):
                if ipaddress.ip_address(addr).version == 4:
                    nodes.append({"peer_id": p["ID"], "address": addr,
                                  "port": config["port"], "created": p.get("Created", ""),
                                  "route": "tailscale"})
    return local + sorted(nodes, key=lambda p: p["created"], reverse=True)[:3]


def reachable(nodes):
    for node in nodes:
        try:
            with socket.create_connection((node["address"], node["port"]), timeout=2):
                return node
        except OSError:
            pass
    return None


def check(state, config, *, snapshot=None, probe=reachable, enqueue=None):
    pending = [(tid, r) for tid, r in state["requests"].items() if r["status"] == "waiting"]
    if not state["enabled"] or not pending:
        return {"waiting": len(pending), "checking": False}
    # Retire completed tasks even while FE is offline, before touching its route.
    for tid, req in pending:
        if terminal_goal(tid):
            req.update(status="finished", finished_at=stamp())
    pending = [(tid, r) for tid, r in pending if r["status"] == "waiting"]
    if not pending:
        return {"waiting": 0, "checking": False}
    eligible = [(tid, r) for tid, r in pending if time.time() >= r["not_before"]]
    if not eligible:
        return {"waiting": len(pending), "checking": False}
    node = None
    if snapshot is None:
        nodes = lan_candidates(config)
        node = probe(nodes) if nodes else None
        if node is None:
            try:
                snapshot = json.loads(subprocess.run(
                    ["/usr/bin/tailscale", "status", "--json"], capture_output=True,
                    text=True, timeout=8, check=True).stdout)
            except (OSError, subprocess.SubprocessError, ValueError):
                snapshot = {}
            fallback = [p for p in fe_candidates(snapshot, config) if p["route"] == "tailscale"]
            nodes += fallback
            node = probe(fallback) if fallback else None
    else:
        nodes = fe_candidates(snapshot, config)
        node = probe(nodes) if nodes else None
    state["last_check"] = {"at": stamp(), "online_candidates": nodes,
                           "tcp_reachable": node, "identity_qualified": False}
    if not node:
        return {"waiting": len(pending), "checking": True, "reachable": False}
    for tid, req in eligible:
        if terminal_goal(tid):
            req.update(status="finished", finished_at=stamp())
            continue
        if not writer_present(tid):
            req["last_issue"] = "No live writer; no duplicate process launched"
            continue
        if req.get("native_resume_review"):
            continue  # Never repeat uncertain editor/input operations automatically.
        if not resume_native_goal(tid, config):
            result = config.get("_native_resume_results", {}).get(tid, {})
            req["native_resume"] = result
            req["native_resume_review"] = bool(result.get("attempted_controls"))
            req["last_issue"] = result.get("reason", "Goal resume deferred; native session mapping or saved draft preserved")
            continue
        req["native_resume"] = config.get("_native_resume_results", {}).get(tid, {})
        req.pop("last_issue", None)
        req.pop("native_resume_review", None)
        req["goal_resume_verified"] = True
        route = "saved local-network route" if node.get("route") == "lan" else "Tailscale route advertised online"
        message = (
            f"Owner-requested FE availability timer: the {route} "
            f"{node['address']}:{node['port']} accepted a bounded TCP connection at {stamp()}. "
            "This proves neither Android identity nor root nor framework readiness. "
            f"Continue your existing authorized task: {req['reason']}. "
            "Reconcile pending operations before repeating any write. Use android-adb-on-demand "
            "for one bounded preflight with current identity/boot/privilege and real resource locks; "
            "preserve foreground use, data and tuning. Continue independent host work if device "
            "access fails. This wait registration is consumed. If FE is still the sole remaining "
            "gate, explicitly re-arm codex-fe-wake wait with this same thread UUID and the exact "
            "pending step; never run an idle model loop or a second polling timer. "
            "Completed work stays completed. No other session messaging is authorized by this wakeup."
        )
        # A crash or timeout after this point is uncertain, not grounds to resend.
        req.update(status="dispatching", dispatch_started_at=stamp(), endpoint=node)
        save(ROOT / "state.json", state)
        try:
            if enqueue is None:
                result = subprocess.run([CODEX, "queue", "--thread", tid, "--message", message],
                                        capture_output=True, text=True, timeout=20)
            else:
                result = enqueue(tid, message)
            req.update(status="woken" if result.returncode == 0 else "queue_failed",
                       queued_at=stamp(), queue_stdout=result.stdout[-1000:],
                       queue_stderr=result.stderr[-1000:], queue_exit=result.returncode)
        except subprocess.TimeoutExpired:
            req.update(status="queue_outcome_uncertain", queued_at=stamp())
        save(ROOT / "state.json", state)
    return {"waiting": sum(r["status"] == "waiting" for r in state["requests"].values()),
            "checking": True, "reachable": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("wait", help="Arm one wakeup for an existing approved task")
    p.add_argument("--thread", required=True)
    p.add_argument("--reason", required=True)
    p = sub.add_parser("done", help="Cancel a task's pending wakeup")
    p.add_argument("--thread", required=True)
    for name in ["check", "status", "on", "off"]:
        sub.add_parser(name)
    args = parser.parse_args()
    os.umask(0o077)
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (ROOT / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        config = read(ROOT / "config.json", {})
        state = read(ROOT / "state.json", {"enabled": True, "requests": {}})
        if args.command in ["wait", "done"]:
            tid = str(uuid.UUID(args.thread))
            if tid not in config["threads"]:
                parser.error("Thread is outside the owner's explicit open-session roster")
            if args.command == "wait":
                old = state["requests"].get(tid, {})
                if old.get("status") == "waiting":
                    print("Already waiting; no duplicate registration")
                elif old.get("status") in ["dispatching", "queue_outcome_uncertain"]:
                    parser.error("Previous queue outcome is uncertain; reconcile before re-arming")
                else:
                    count = old.get("wakes", 0) + int(old.get("status") == "woken")
                    # Only re-arming after an unsuccessful wake uses increasing backoff.
                    delay = min(3600, 60 * (2 ** min(count, 6)))
                    state["requests"][tid] = {"name": config["threads"][tid]["name"],
                        "status": "waiting", "reason": args.reason[:1500],
                        "registered_at": stamp(), "not_before": time.time() + delay, "wakes": count}
            elif tid in state["requests"]:
                state["requests"][tid].update(status="cancelled", cancelled_at=stamp())
        elif args.command in ["on", "off"]:
            state["enabled"] = args.command == "on"
        elif args.command == "check":
            print(json.dumps(check(state, config)))
        if args.command != "status":
            save(ROOT / "state.json", state)
        pending = sum(r["status"] == "waiting" for r in state["requests"].values())
    if args.command == "status":
        print(json.dumps(state, indent=2, ensure_ascii=False))
    else:
        systemctl("start" if state["enabled"] and pending else "stop", TIMER)
        print(json.dumps({"enabled": state["enabled"], "pending": pending}))


if __name__ == "__main__":
    main()
