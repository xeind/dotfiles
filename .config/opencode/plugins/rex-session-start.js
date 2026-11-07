// Tells OpenCode which Rex session and pane it runs in, as the SessionStart
// hook that "rex skill setup" installs does for Claude Code and Codex.
// OpenCode has no command hooks, so rex cannot install that hook here.
//
// OpenCode 2.x runs plugins in its server. The shared background server
// ("serve --service") keeps the environment of whichever pane started it, so
// its REX_* values are wrong for every other pane. Only a private server
// ("serve --stdio", started by "opencode --standalone") has this pane's
// values, so the plugin adds the context there and nowhere else.
import { execFile } from "node:child_process"

export default {
  id: "rex.session-start",
  setup(api) {
    if (!process.env.REX_BLOCK || !process.argv.includes("--stdio")) return
    // Start now, await on first use, so a slow Rex server can't delay startup.
    const context = new Promise((resolve) =>
      execFile("rex", ["__internal", "session-start", "--agent", "opencode"], (error, stdout) =>
        resolve(error ? "" : stdout.trim()),
      ),
    )
    api.session.hook("context", async (request) => {
      const text = await context
      if (text) request.system.push({ type: "text", text })
    })
  },
}
