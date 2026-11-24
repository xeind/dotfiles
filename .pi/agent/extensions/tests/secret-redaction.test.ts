import assert from "node:assert/strict";
import { test } from "node:test";
import { REDACTION_MARK, redactSecrets, writesRedactionMark } from "../secret-redaction.ts";

test("masks env-style assignments and keeps the name", () => {
  assert.equal(redactSecrets("OPENAI_API_KEY=abc123def456"), `OPENAI_API_KEY=${REDACTION_MARK}`);
  assert.equal(redactSecrets('export GH_TOKEN="ghx1234567890"'), `export GH_TOKEN="${REDACTION_MARK}"`);
  assert.equal(redactSecrets("db_password: hunter22hunter"), `db_password: ${REDACTION_MARK}`);
  assert.equal(redactSecrets("AWS_SECRET_ACCESS_KEY=abcdef123456"), `AWS_SECRET_ACCESS_KEY=${REDACTION_MARK}`);
  assert.equal(redactSecrets("apiKey: abcdef123456"), `apiKey: ${REDACTION_MARK}`);
});

test("masks credential fields in JSON", () => {
  const input = '{"type":"oauth","access":"eyJhbGciOiJIUzI1NiJ9.x","refresh":"rt-1234567","expires":1}';
  const output = redactSecrets(input);
  assert.ok(!output.includes("eyJhbGci"));
  assert.ok(!output.includes("rt-1234567"));
  assert.ok(output.includes('"expires":1'));
  assert.ok(redactSecrets('{"password": "example-password-value"}').includes(REDACTION_MARK));
});

test("masks tokens with a known prefix anywhere", () => {
  const output = redactSecrets("token is sk-ant-" + "x".repeat(24) + " here");
  assert.equal(output, `token is ${REDACTION_MARK} here`);
  assert.equal(redactSecrets("ghp_" + "a".repeat(36)), REDACTION_MARK);
});

test("masks private key blocks", () => {
  const key = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\ndef\n-----END OPENSSH PRIVATE KEY-----";
  assert.equal(redactSecrets(`before\n${key}\nafter`), `before\n${REDACTION_MARK}\nafter`);
});

test("leaves ordinary text alone", () => {
  for (const text of [
    "const tokenCount = 42;",
    "KEY=abc",
    "the password field is required",
    "git log --oneline -5",
    'rex.bind(P .. "ctrl+;", "pane.send_key", { key = "ctrl+;" })',
    'key: "shift+command+space"',
    "monkey = bananas-for-all",
  ]) {
    assert.equal(redactSecrets(text), text);
  }
});

test("detects a write or edit that carries the mask", () => {
  assert.equal(writesRedactionMark("write", { path: ".env", content: `KEY=${REDACTION_MARK}` }), true);
  assert.equal(writesRedactionMark("mcp__custom-tools__edit", { edits: [{ newText: REDACTION_MARK }] }), true);
  assert.equal(writesRedactionMark("write", { path: "a.txt", content: "plain" }), false);
  assert.equal(writesRedactionMark("bash", { command: `echo ${REDACTION_MARK}` }), false);
});
