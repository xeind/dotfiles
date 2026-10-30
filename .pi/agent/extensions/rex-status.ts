// Reports Pi's state to Rex as a program status (OSC 7501) through
// rex_program_status, so Rex shows it working, blocked or done. Mirrors
// herdr-agent-state.ts beside it, which does the same for herdr.
// @ts-nocheck
import { execFile } from "node:child_process";

const script = `${process.env.HOME}/.local/bin/rex_program_status`;

export default function (pi) {
  if (!process.env.REX_BLOCK) return;

  let root = false;
  let active = false;
  let blocked = 0;
  let last;
  let queue = Promise.resolve();

  // Send each change once, in order, so a late "working" can't land after "done".
  function publish() {
    const state = blocked > 0 ? "question" : active ? "working" : "done";
    if (state === last) return;
    last = state;
    queue = queue.then(() => new Promise((resolve) => execFile(script, [state], () => resolve())));
  }

  pi.on("session_start", (_event, ctx) => {
    // TUI only: the other modes have no terminal for Rex to show.
    root = ctx?.mode === "tui";
  });

  pi.on("agent_start", () => {
    if (!root) return;
    active = true;
    publish();
  });

  pi.on("agent_settled", (_event, ctx) => {
    if (!root || ctx?.isIdle?.() !== true) return;
    active = false;
    publish();
  });

  // Extensions such as pi-ask announce waiting on the user on this event.
  pi.events.on("herdr:blocked", (data) => {
    if (!root) return;
    blocked = data?.active ? blocked + 1 : Math.max(0, blocked - 1);
    publish();
  });
}
