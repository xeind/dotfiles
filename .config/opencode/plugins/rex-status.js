// Reports OpenCode's state to Rex as a program status (OSC 7501) through
// rex_program_status, so Rex shows it working, blocked or done.
//
// OpenCode 2.x runs plugins in its server. rex_program_status writes to the
// nearest ancestor's terminal, which only a private server ("serve --stdio",
// started by "opencode --standalone") has; the shared "serve --service" has
// none and serves every pane, so the plugin stays off there.
import { execFile } from "node:child_process"

const script = `${process.env.HOME}/.local/bin/rex_program_status`

export default {
  id: "rex.status",
  setup(api) {
    if (!process.env.REX_BLOCK || !process.argv.includes("--stdio")) return
    // Send each change once, in order, so a late "working" can't land after "done".
    let last = null
    let queue = Promise.resolve()
    const report = (state) => {
      if (state === last) return
      last = state
      queue = queue.then(() => new Promise((resolve) => execFile(script, [state], () => resolve())))
    }
    // Subagents run their own executions; the pane is done when none is left.
    const running = new Set()
    const finish = (sessionID, state) => {
      running.delete(sessionID)
      if (running.size === 0) report(state)
    }
    ;(async () => {
      for await (const event of api.event.subscribe()) {
        const sessionID = event.data?.sessionID
        switch (event.type) {
          case "session.execution.started":
            running.add(sessionID)
            report("working")
            break
          case "session.execution.succeeded":
          case "session.execution.interrupted":
            finish(sessionID, "done")
            break
          case "session.execution.failed":
            finish(sessionID, "error")
            break
          // The question tool asks through the permission system.
          case "permission.asked":
            report(event.data?.action === "question" ? "question" : "permission")
            break
          case "permission.replied":
            if (running.size > 0) report("working")
            break
        }
      }
    })().catch(() => {})
  },
}
