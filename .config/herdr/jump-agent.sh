#!/bin/sh
# Jump to the agent that needs you. Blocked agents win; otherwise repeated
# presses cycle through every agent pane. Port of the tmux sidebar jump.sh.
# No built-in action focuses the blocked agent directly as of herdr 0.8.0:
# next_agent only walks the panel order. Socket API, one request per
# connection.
exec python3 - <<'EOF'
import json, os, socket

sock_path = os.path.expanduser("~/.config/herdr/herdr.sock")

def call(method, params):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    s.settimeout(3)
    s.sendall((json.dumps({"id": f"jump-agent:{method}", "method": method,
                           "params": params}) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf)

agents = call("agent.list", {})["result"]["agents"]
if not agents:
    raise SystemExit

current = os.environ.get("HERDR_ACTIVE_PANE_ID")
target = next((a["pane_id"] for a in agents if a["agent_status"] == "blocked"), None)

if target is None or target == current:
    # next agent after the focused one, wrapping to the first
    ids = [a["pane_id"] for a in agents]
    try:
        target = ids[(ids.index(current) + 1) % len(ids)]
    except ValueError:
        target = ids[0]

call("agent.focus", {"target": target})
EOF
