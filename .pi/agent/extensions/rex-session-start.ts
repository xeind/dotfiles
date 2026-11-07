// Tells Pi which Rex session and pane it runs in, as the SessionStart hook
// that "rex skill setup" installs does for Claude Code and Codex. Pi has no
// command hooks, so rex cannot install that hook here.
// @ts-nocheck
import { execFile } from "node:child_process";

export default function (pi) {
  if (!process.env.REX_BLOCK) return;

  // Start now, await on first use, so a slow Rex server can't delay startup.
  const context = new Promise((resolve) =>
    execFile("rex", ["__internal", "session-start", "--agent", "pi"], (error, stdout) =>
      resolve(error ? "" : stdout.trim()),
    ),
  );

  // A named section is diffed against what the model already has, so setting
  // it on every run costs nothing after the first.
  pi.on("before_agent_start", async (event) => {
    const text = await context;
    if (text) event.systemPromptOptions.sections.rex = text;
  });
}
