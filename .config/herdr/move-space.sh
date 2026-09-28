#!/bin/sh
# Move the focused herdr space up or down in the sidebar order.
# Usage: move-space.sh up|down
# Uses the socket API directly: no built-in keybinding action exists for
# workspace.move as of herdr 0.8.0. The server closes the socket after each
# response, so every request opens its own connection.
exec python3 - "$1" <<'EOF'
import json, os, socket, sys

direction = sys.argv[1] if len(sys.argv) > 1 else "down"
sock_path = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser("~/.config/herdr/herdr.sock")

def call(method, params):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    s.settimeout(3)
    s.sendall((json.dumps({"id": f"move-space:{method}", "method": method,
                           "params": params}) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf)

spaces = call("workspace.list", {})["result"]["workspaces"]
pos = next(i for i, w in enumerate(spaces) if w["focused"])
# insert_index is the slot before removal: up = pos-1, down = pos+2
if direction == "up" and pos > 0:
    call("workspace.move", {"workspace_id": spaces[pos]["workspace_id"],
                            "insert_index": pos - 1})
elif direction == "down" and pos < len(spaces) - 1:
    call("workspace.move", {"workspace_id": spaces[pos]["workspace_id"],
                            "insert_index": pos + 2})
EOF
