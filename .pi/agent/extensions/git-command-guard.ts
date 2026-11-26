// Guards git commands the agent runs through bash:
// - Asks the user before any command that stages, commits or pushes
//   (add, stage, rm, mv, commit, push), and blocks it when no one can
//   answer (print and RPC modes).
// - Blocks git commands that skip the repository's hooks (--no-verify,
//   commit -n, -c core.hooksPath=...), so the agent fixes a failing hook
//   instead. Quoted text, such as a commit message, does not count.
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

// Hook-skip check. Same rules as ~/.agents/bin/git-skips-hooks (Claude Code, OpenCode); keep in
// step, test cases in ~/.agents/bin/git-skips-hooks.cases. Only real git invocations count:
// quoted text is dropped first, so a commit message or an echo that mentions the flag passes.
const QUOTED = /'[^']*'|"(?:\\.|[^"\\])*"/g;
const SEPARATORS = /\|\||&&|[;&|\n]|\$\(|`|\)/;
const WRAPPERS = new Set(["env", "command", "exec", "sudo", "nohup", "time", "xargs", "noglob"]);
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;
const GLOBAL_WITH_VALUE = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"]);

/** Why the command skips git hooks (--no-verify, commit -n, -c core.hooksPath=...), or null. */
export function hookSkipReason(command: string): string | null {
  for (const segment of command.replace(QUOTED, " Q ").split(SEPARATORS)) {
    const tokens = segment.split(/\s+/).filter(Boolean);
    let i = 0;
    while (i < tokens.length && (ASSIGNMENT.test(tokens[i]!) || WRAPPERS.has(tokens[i]!))) i++;
    const program = tokens[i];
    if (program === undefined || !(program === "git" || program.endsWith("/git"))) continue;
    i++;
    while (i < tokens.length && tokens[i]!.startsWith("-")) {
      let option = tokens[i]!;
      let value: string | undefined;
      if (GLOBAL_WITH_VALUE.has(option) && i + 1 < tokens.length) value = tokens[++i];
      else if (option.includes("=")) [option, value] = [option.slice(0, option.indexOf("=")), option.slice(option.indexOf("=") + 1)];
      if (option === "-c" && value?.toLowerCase().startsWith("core.hookspath=")) {
        return "git -c core.hooksPath=... skips the repository's git hooks";
      }
      i++;
    }
    const subcommand = tokens[i];
    if (subcommand === undefined) continue;
    const rest = tokens.slice(i + 1);
    if (rest.includes("--no-verify")) return `git ${subcommand} --no-verify skips the repository's git hooks`;
    if (subcommand === "commit" && rest.some((token) => /^-[A-Za-z]*n[A-Za-z]*$/.test(token))) {
      return "git commit -n (--no-verify) skips the repository's git hooks";
    }
  }
  return null;
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

    const skip = hookSkipReason(command);
    if (skip) {
      return { block: true, reason: `BLOCKED: ${skip}. Fix what the hook reports, or ask the user.` };
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
