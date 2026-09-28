#!/bin/sh
# Tab-bar fragment: "! N" when N agents are blocked on you, else nothing.
# Port of the tmux status-bar needs-count.sh; reads herdr's socket API
# instead of tmux-agents state files. One request per connection.
exec python3 - <<'EOF'
import json, os, socket

sock_path = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser("~/.config/herdr/herdr.sock")

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(sock_path)
except OSError:
    raise SystemExit
s.settimeout(3)
s.sendall((json.dumps({"id": "needs-count:agent.list", "method": "agent.list",
                       "params": {}}) + "\n").encode())
buf = b""
while not buf.endswith(b"\n"):
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
s.close()

agents = json.loads(buf)["result"]["agents"]
n = sum(1 for a in agents if a["agent_status"] == "blocked")
if n:
    print(f"! {n}")
EOF
