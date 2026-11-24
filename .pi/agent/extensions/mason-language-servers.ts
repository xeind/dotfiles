// Lets Pi use the language servers Mason installed for Neovim.
// Mason keeps them in <data>/<nvim app>/mason/bin, which is on PATH only
// inside Neovim. This adds that folder to the end of Pi's PATH, so
// pi-lsp-extension (and the bash tool) find every Mason server, including
// ones installed later, without a symlink per server. Appending keeps any
// server already on PATH, such as a project's own, in front.
// `/mason` lists the servers Pi can now start.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

/** Mason's bin folder for the Neovim data directory, as Mason computes it by default. */
export function masonBinDirectory(environment: NodeJS.ProcessEnv): string {
  const dataHome = environment.XDG_DATA_HOME || join(homedir(), ".local", "share");
  const applicationName = environment.NVIM_APPNAME || "nvim";
  return join(dataHome, applicationName, "mason", "bin");
}

/** PATH with the directory appended, unchanged when it is already listed. */
export function appendToPath(path: string | undefined, directory: string): string {
  const entries = (path ?? "").split(delimiter).filter(Boolean);
  return entries.includes(directory) ? entries.join(delimiter) : [...entries, directory].join(delimiter);
}

export default function (pi: ExtensionAPI) {
  const binDirectory = masonBinDirectory(process.env);
  const found = existsSync(binDirectory);
  if (found) process.env.PATH = appendToPath(process.env.PATH, binDirectory);

  pi.registerCommand("mason", {
    description: "List the Mason language servers Pi can start",
    handler: async (_args, ctx) => {
      if (!found) {
        ctx.ui.notify(`Mason bin folder not found: ${binDirectory}`, "warning");
        return;
      }
      const servers = readdirSync(binDirectory).sort();
      ctx.ui.notify(`${servers.length} Mason servers on PATH (${binDirectory}):\n${servers.join("\n")}`, "info");
    },
  });
}
