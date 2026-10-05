#!/bin/sh
# Jump to the agent that needs you. The neediest agent wins; otherwise repeated
# presses cycle through every agent pane. Port of the tmux sidebar jump.sh.
# No built-in action focuses the neediest agent directly as of herdr 0.9.3:
# next_agent only walks the panel order, focus_agent is an indexed binding.
# agent.list returns structural order, not the agent_panel_sort = "priority"
# queue, and no API exposes that queue, so rank the states here.
# Socket API, one request per connection.
exec python3 - <<'EOF'
import json, os, socket

sock_path = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser("~/.config/herdr/herdr.sock")

# attention queue: blocked needs a decision, done finished unseen, idle is
# ready for input, working needs nothing.
RANK = {"blocked": 0, "done": 1, "idle": 2, "unknown": 3, "working": 4}

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

def rank(agent):
    return RANK.get(agent["agent_status"], len(RANK))

# within a tier, the latest state change first (what just finished or blocked)
ordered = sorted(enumerate(agents), key=lambda p: (rank(p[1]), -p[1].get("state_change_seq", 0), p[0]))
ids = [a["pane_id"] for _, a in ordered]

current = os.environ.get("HERDR_ACTIVE_PANE_ID")
here = next((a for a in agents if a["pane_id"] == current), None)

if here is not None and rank(ordered[0][1]) >= rank(here):
    # already on the neediest tier: next agent in queue order, wrapping
    target = ids[(ids.index(current) + 1) % len(ids)]
else:
    target = ids[0]

call("agent.focus", {"target": target})
EOF
