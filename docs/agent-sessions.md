# AI sessions and workloads

Open **Super+I → AI sessions**, or search for Codex, PID, tmux, Haven, RAM or
workloads. The feature has its own monitoring master and a separate Kitty PID
label switch. Turning monitoring off stops its user service and hides the rows;
it does not stop Codex, change memory limits, freeze processes or resume tasks.

The page searches names, full session IDs, client/child PIDs and workload names;
sorts by sampled workload CPU, resident memory, swap, name or process age; and
expands per-process details. Terminal-client and child-workload memory are
separate. Shared app servers appear once, with the number of held writer locks.
Other agent frontends are shown even when their current session ID is unknown.

CLI:

```sh
agent-monitor status
agent-monitor identify PID --json
agent-monitor snapshot --json   # bounded live diagnostic without enabling a service
agent-monitor disable
agent-monitor enable
agent-monitor titles off
```

## Attribution and recovery behavior

- `CODEX_THREAD_ID`/`CODEX_SESSION_ID` on a process establishes its declared
  originating session. Conflicting values remain unresolved. Verified descendants
  inherit attribution; PID/start-time identity retains it across reparenting.
- An agent boundary stops ancestry inheritance. A dedicated single-session writer
  can identify descendants; a shared server cannot. A shared daemon's inherited
  launch marker cannot claim every later command or MCP process.
- Writer identities require a held WRITE lock in fdinfo, not merely an existing
  lock file or an open descriptor. Names come from the read-only `name`/`cwd`
  metadata columns. The monitor never reads rollout messages, pane contents,
  first prompts, authentication files or arbitrary environment values into its
  output. Environment values are retained only from an attribution allowlist.
- Shared-daemon TUI clients have no native per-client session-ID endpoint in this
  integration. A unique full displayed title/name/CWD match is explicitly labeled
  **displayed title match**. It does not authorize workload ownership. Duplicate
  names or stale/missing titles stay unresolved. Resume argv and saved tmux tags
  are not treated as the current thread after an in-client thread switch.
- A resumed session keeps its session ID, while its PID and start time are
  rediscovered. Multiple terminal clients can display one session without
  duplicating its workloads. Changes to names and new/resumed clients are picked
  up automatically; this does not depend on the restoration launcher.
- tmux identities include the socket, session and pane; `%0` on two servers is
  not the same pane. Detached sessions are retained. An SSH/Haven attachment is
  determined from the local client environment/ancestry, without contacting a
  phone. Only the active pane is associated with a local Kitty attachment.
- A direct SSH client without a local title or dedicated writer may show only
  its launch-session hint, clearly marked current-session unconfirmed. The
  monitor does not invent a current ID from `resume --last`, a stale tmux tag,
  or the launching agent's inherited ID.
- Antigravity launch conversation IDs are hints, not evidence of the currently
  selected conversation. Other providers are process-visible; full session
  attribution is currently implemented for Codex.

The canonical CryoManager build wrapper and build-quota queue now preserve only
`CODEX_THREAD_ID`, `CODEX_SESSION_ID`, and `CODEX_HOME` in their existing service
handoffs. Existing processes or frozen wrappers that previously dropped those
values cannot be retroactively attributed. Such heavy processes remain visible
under **Heavy processes without session attribution**. Jobs that finish between
samples may be missed; this is a sampled monitor, not an execution audit log.

## Memory and collection cost

RSS is resident RAM and can double-count shared pages when summed. Swap is shown
separately. Virtual size is reserved/mapped address space, not physical RAM.
Process age alone is not evidence that a task is abandoned or leaking. Peaks
cover the current monitor run. No cleanup or memory-policy decision uses these
observations.

The Python collector samples every five seconds, coalesces terminal discovery,
and caches allowlisted process environment by PID/start time and exec identity.
Only current process rows and up to 256 session peaks are retained in memory.
Each session shows up to 32 resource-heavy process details; the full process-ID
index remains searchable and available to `identify`. The snapshot is atomically
replaced in the private runtime directory, not written repeatedly to disk.
A stopped/stale collector does not leave a plausible current Kitty PID label.

Files: `~/.config/agent-monitor/config.json`,
`$XDG_RUNTIME_DIR/agent-monitor/snapshot.json`, and
`agent-monitor.service`. The user service is independently enabled; it starts
monitoring after login but never starts an AI agent. Settings can be opened while
it is off. `identify` rechecks PID birth and boot before returning a cached match.

Kitty's custom title renderer adds only a numeric PID to the existing route
marker; native progress/attention/session titles stay intact. It validates the
window and process birth and expires observations after 20 seconds. Updating the
custom Python file in a running Kitty may require clearing its custom-renderer
cache: this installation did so without restarting a terminal or changing focus.

## Verification

- `python tests/test_agent_monitor.py`: eleven cases including shared-server
  separation, nested agents, inherited launch markers, duplicate names, thread
  switching, PID reuse, held-lock proof and a real owned memory workload.
- `python tests/agent_monitor_tmux.py`: disposable real tmux servers, duplicate
  pane IDs across sockets, detached sessions, SSH-style control-client attach,
  and resume with a new writer PID. No real Codex tasks are started or stopped.
- `python tests/test_agent_kitty_title.py`: exact window/PID birth, stale/off data,
  and malformed snapshot handling.
- `tests/agent_sessions_ui.py` under private Xvfb/D-Bus: actual QML master/title
  controls, CPU/name sorting, PID search, details and empty states; unrelated
  desktop configuration remains identical. `tests/settings_catalog.py` passes.
- Canonical build queue: 26 unit tests pass, including identity propagation
  without ambient API keys. The build wrapper passes `bash -n`; no build is
  launched for this metadata-only change.
- Live delivery: service active without restarts, named Codex clients observed,
  and an actual Kitty PID label visually confirmed. A small owned systemd test
  validates attribution after a service launch breaks ordinary PPID ancestry.
  Agent PIDs and desktop focus remain unchanged by the title refresh.

Phone-side Haven rendering has not been exercised. SSH/tmux mapping is qualified
on the host and in disposable fixtures. Local delivery receipts, memory readings
and screenshots remain private under `~/.local/state/agent-monitor-delivery/`.
