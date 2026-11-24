import assert from "node:assert/strict";
import { test } from "node:test";
import { subcommandsNeedingApproval, usesNoVerify } from "../git-command-guard.ts";

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

test("detects --no-verify only in git commands", () => {
  assert.equal(usesNoVerify("git commit --no-verify -m x"), true);
  assert.equal(usesNoVerify("git push --no-verify"), true);
  assert.equal(usesNoVerify("npm publish --no-verify"), false);
  assert.equal(usesNoVerify("git commit -m x"), false);
});
