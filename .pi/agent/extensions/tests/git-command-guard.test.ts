import assert from "node:assert/strict";
import { test } from "node:test";
import { hookSkipReason, subcommandsNeedingApproval } from "../git-command-guard.ts";

test("finds subcommands that stage, commit or push", () => {
  assert.deepEqual(subcommandsNeedingApproval("git add -- a.ts && git commit -m x"), ["add", "commit"]);
  assert.deepEqual(subcommandsNeedingApproval("git -C ~/.dotfiles push origin main"), ["push"]);
  assert.deepEqual(subcommandsNeedingApproval("git -c user.name=x commit --amend"), ["commit"]);
  assert.deepEqual(subcommandsNeedingApproval("cd repo; git rm old.ts"), ["rm"]);
  assert.deepEqual(subcommandsNeedingApproval("git --no-pager stage a"), ["stage"]);
});

test("lets read-only git commands through", () => {
  for (const command of [
    "git status -sb",
    "git log --oneline -5",
    "git diff -- a.ts",
    "git -C repo show HEAD",
    "git fetch origin",
    "legit commit",
  ]) {
    assert.deepEqual(subcommandsNeedingApproval(command), [], command);
  }
});

// Same cases as ~/.agents/bin/git-skips-hooks.cases (Claude Code and OpenCode use that checker).
test("blocks git invocations that skip hooks", () => {
  for (const command of [
    'git commit --no-verify -m "wip"',
    "git push --no-verify",
    'git -C ~/repo commit -n -m "x"',
    'git commit -nm "x"',
    "cd repo && git commit --no-verify",
    "GIT_EDITOR=true git commit --no-verify",
    "git -c core.hooksPath=/dev/null commit -m x",
    "git merge --no-verify feature",
  ]) {
    assert.notEqual(hookSkipReason(command), null, command);
  }
});

test("ignores the flag outside a git invocation or inside quotes", () => {
  for (const command of [
    'echo "never use --no-verify with git"',
    'git commit -m "explain why --no-verify is banned"',
    "printf 'git commit --no-verify\\n' > notes.txt",
    "git push -n",
    'git commit -m "add n flag"',
    "git log --oneline -n 5",
    "grep -rn -- --no-verify . && git status",
    "npm publish --no-verify",
    "git status",
  ]) {
    assert.equal(hookSkipReason(command), null, command);
  }
});
