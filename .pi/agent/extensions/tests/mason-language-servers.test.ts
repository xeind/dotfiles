import assert from "node:assert/strict";
import { homedir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { appendToPath, masonBinDirectory } from "../mason-language-servers.ts";

test("finds Mason's bin folder the way Mason does by default", () => {
  assert.equal(masonBinDirectory({}), join(homedir(), ".local/share/nvim/mason/bin"));
  assert.equal(masonBinDirectory({ XDG_DATA_HOME: "/data" }), "/data/nvim/mason/bin");
  assert.equal(masonBinDirectory({ XDG_DATA_HOME: "/data", NVIM_APPNAME: "lazyvim" }), "/data/lazyvim/mason/bin");
});

test("appends the folder once, after existing entries", () => {
  assert.equal(appendToPath("/usr/bin:/bin", "/m"), "/usr/bin:/bin:/m");
  assert.equal(appendToPath("/usr/bin:/m:/bin", "/m"), "/usr/bin:/m:/bin");
  assert.equal(appendToPath(undefined, "/m"), "/m");
});
