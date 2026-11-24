// Masks secret values in every tool result before the model sees it:
// assignments such as API_KEY=..., credential fields in JSON, tokens with
// a known prefix, and private key blocks. Write and edit calls that would
// put the mask back into a file are blocked, so a redacted read can't
// overwrite a real secret.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const REDACTION_MARK = "[REDACTED]";

// A bare `key` is a keyboard key in Rex, Karabiner and editor configs, so KEY
// counts only with a qualifier such as API_KEY or SECRET_KEY.
const SECRET_NAME = String.raw`[A-Za-z0-9_.-]*(?:(?:API|SECRET|PRIVATE|ACCESS|CLIENT|MASTER|LICENSE|ENCRYPTION|SIGNING|AUTH)[_.-]?KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL)[A-Za-z0-9_.-]*`;

const RULES: ReadonlyArray<{ pattern: RegExp; replace: string }> = [
  // -----BEGIN ... PRIVATE KEY----- blocks, whole.
  {
    pattern: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
    replace: REDACTION_MARK,
  },
  // NAME=value and NAME: value, as in .env files, shell exports and YAML.
  {
    pattern: new RegExp(String.raw`(\b${SECRET_NAME}\s*[=:]\s*)(["']?)[^\s"'#]{6,}\2`, "gi"),
    replace: `$1$2${REDACTION_MARK}$2`,
  },
  // "field": "value" in JSON, for the credential field names apps use.
  {
    pattern: /("(?:[A-Za-z_]*(?:token|secret|password|apiKey|api_key|clientSecret|authorization)|access|refresh)"\s*:\s*")[^"]{6,}(")/gi,
    replace: `$1${REDACTION_MARK}$2`,
  },
  // Tokens with a published prefix, wherever they appear.
  {
    pattern: /\b(?:sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|hf_[A-Za-z0-9]{30,})\b/g,
    replace: REDACTION_MARK,
  },
];

export function redactSecrets(text: string): string {
  let result = text;
  for (const rule of RULES) result = result.replace(rule.pattern, rule.replace);
  return result;
}

function redactValue(value: unknown): unknown {
  if (typeof value === "string") return redactSecrets(value);
  if (Array.isArray(value)) return value.map(redactValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, redactValue(item)]));
  }
  return value;
}

/** True when a write or edit call would store the redaction mark in a file. */
export function writesRedactionMark(toolName: string, input: Record<string, unknown>): boolean {
  if (!/(^|__)(write|edit)$/.test(toolName)) return false;
  return JSON.stringify(input).includes(REDACTION_MARK);
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", (event) => {
    let changed = false;
    const content = event.content.map((part) => {
      if (part.type !== "text") return part;
      const text = redactSecrets(part.text);
      if (text === part.text) return part;
      changed = true;
      return { ...part, text };
    });
    if (!changed) return undefined;
    // Replacing content alone drops structuredContent, which codemode scripts read.
    const structuredContent = event.structuredContent === undefined
      ? undefined
      : (redactValue(event.structuredContent) as typeof event.structuredContent);
    return structuredContent === undefined ? { content } : { content, structuredContent };
  });

  pi.on("tool_call", (event) => {
    if (!writesRedactionMark(event.toolName, event.input as Record<string, unknown>)) return undefined;
    return {
      block: true,
      reason: `BLOCKED: the content contains ${REDACTION_MARK}, the mask secret-redaction puts over secret values. ` +
        "Writing it would replace a real secret. Edit around the secret instead, or ask the user to change it.",
    };
  });
}
