#!/usr/bin/env python3
"""Report session-bus generations; stay idle while the connection is healthy.

No app is restarted here. Quickshell owns the monitor and decides whether its
own cached Qt connection belongs to a dead bus. A killed monitor may reconnect
to the same bus without causing a shell restart.
"""
import argparse
import asyncio
import ctypes
import json
import os
import signal
import sys

from dbus_fast import Message, MessageType
from dbus_fast.aio import MessageBus


async def call(bus, member):
    reply = await asyncio.wait_for(bus.call(Message(
        destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
        interface="org.freedesktop.DBus", member=member)), 5)
    if reply.message_type == MessageType.ERROR:
        raise RuntimeError(reply.error_name)
    return reply.body[0]


async def connect():
    bus = MessageBus(bus_address=os.environ.get("DBUS_SESSION_BUS_ADDRESS"))
    try:
        await asyncio.wait_for(bus.connect(), 5)
        generation = await call(bus, "GetId")
        return bus, generation
    except BaseException:
        bus.disconnect()
        raise


def emit(event, **values):
    print(json.dumps({"event": event, **values}), flush=True)


async def ready(timeout):
    deadline = asyncio.get_running_loop().time() + timeout
    delay = .25
    while True:
        try:
            bus, generation = await connect()
            print(generation, flush=True)
            bus.disconnect()
            return
        except (OSError, RuntimeError, asyncio.TimeoutError, EOFError):
            remaining = deadline - asyncio.get_running_loop().time()
            if remaining <= 0:
                raise RuntimeError("session bus unavailable before shell launch")
            await asyncio.sleep(min(delay, remaining))
            delay = min(delay * 2, 4)


def bind_parent_death(owner_pid):
    """Ensure this helper exits automatically if its parent Quickshell crashes."""
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        # PR_SET_PDEATHSIG = 1
        libc.prctl(1, signal.SIGTERM, 0, 0, 0)
    except OSError:
        return
    # Guard against parent already dying before prctl ran (reparented to PID 1).
    if os.getppid() == 1:
        try:
            os.kill(owner_pid, 0)
        except ProcessLookupError:
            sys.exit(0)
        except PermissionError:
            pass


async def watch(pid):
    bind_parent_death(pid)
    delay = .25
    while True:
        bus = None
        try:
            bus, generation = await connect()
            # The tray model is initialized before QML starts this process.
            # Check this shell, not another desktop's host or the tray contents.
            names = await call(bus, "ListNames")
            registered = any(n.startswith(f"org.kde.StatusNotifierHost-{pid}-") for n in names)
            emit("connected", generation=generation, shellRegistered=registered)
            delay = .25
            try:
                await bus.wait_for_disconnect()
            except (OSError, EOFError):
                pass
            emit("disconnected")
        except (OSError, RuntimeError, asyncio.TimeoutError, EOFError) as exc:
            emit("unavailable", error=type(exc).__name__)
        finally:
            if bus:
                bus.disconnect()
        # Retry only a failed connection, with backoff; no healthy-bus polling.
        await asyncio.sleep(delay)
        delay = min(delay * 2, 8)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready", action="store_true")
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--pid", type=int)
    args = parser.parse_args()
    if not args.ready and not args.pid:
        parser.error("watching requires --pid")
    try:
        asyncio.run(ready(args.timeout) if args.ready else watch(args.pid))
    except (RuntimeError, KeyboardInterrupt) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(75)
