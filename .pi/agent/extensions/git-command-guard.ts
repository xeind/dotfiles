// Guards git commands the agent runs through bash:
// - Asks the user before any command that stages, commits or pushes
//   (add, stage, rm, mv, commit, push), and blocks it when no one can
//   answer (print and RPC modes).
// - Blocks --no-verify, so the agent fixes a failing hook instead of
//   skipping it.
// - Sets GIT_EDITOR and GIT_SEQUENCE_EDITOR to `true`, so git never opens
//   an editor that would hang the command.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const GIT_ENVIRONMENT = "export GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true GIT_MERGE_AUTOEDIT=no\n";

// `git`, any global options (-C dir, -c key=value, --git-dir=...), then the subcommand.
const GIT_SUBCOMMAND =
  /(?:^|[\s;&|(`])git((?:\s+(?:-C|-c|--git-dir|--work-tree|--namespace)\s+\S+|\s+--?[\w-]+(?:=\S+)?)*)\s+([a-z][\w-]*)/g;

const APPROVAL_SUBCOMMANDS = new Set(["add", "stage", "rm", "mv", "commit", "push"]);

/** Subcommands in the command that need the user's approval, in order. */
export function subcommandsNeedingApproval(command: string): string[] {
  const found: string[] = [];
  for (const match of command.matchAll(GIT_SUBCOMMAND)) {
    const subcommand = match[2];
    if (subcommand !== undefined && APPROVAL_SUBCOMMANDS.has(subcommand) && !found.includes(subcommand)) {
      found.push(subcommand);
    }
  }
  return found;
}

export function usesNoVerify(command: string): boolean {
  return /\bgit\b/.test(command) && /(^|\s)--no-verify\b/.test(command);
}

function isShellTool(toolName: string): boolean {
  return /(^|__)bash$/.test(toolName);
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (!isShellTool(event.toolName)) return undefined;
    const input = event.input as { command?: unknown };
    if (typeof input.command !== "string" || !/\bgit\b/.test(input.command)) return undefined;
    const command = input.command;

    if (usesNoVerify(command)) {
      return {
        block: true,
        reason: "BLOCKED: --no-verify skips the repository's git hooks. Fix what the hook reports, or ask the user.",
      };
    }

    const subcommands = subcommandsNeedingApproval(command);
    if (subcommands.length > 0) {
      const summary = subcommands.map((name) => `git ${name}`).join(", ");
      if (!ctx.hasUI) {
        return { block: true, reason: `BLOCKED: ${summary} needs the user's approval, and no one can answer here.` };
      }
      const approved = await ctx.ui.confirm(`Allow ${summary}?`, command);
      if (!approved) {
        return { block: true, reason: `BLOCKED: the user declined ${summary}. Ask before trying again.` };
      }
    }

    input.command = GIT_ENVIRONMENT + command;
    return undefined;
  });
}
