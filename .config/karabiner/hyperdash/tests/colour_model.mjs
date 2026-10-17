// Colour maths for tests/colour.test.mjs: reads the four theme blocks, resolves var() and color-mix(), and measures
// WCAG 2 contrast, APCA Lc, OKLab distance, OKLCH lightness and colour-vision-deficiency simulations.
// APCA is APCA-W3 0.1.9 (base algorithm 0.0.98G-4g), checked against the apca-w3 package's own results.

export const THEMES = ["manila", "kozo", "nightingale", "blueprint"];

// Theme name -> { token: raw value }. Tokens in the shared :root block are visible to every theme.
export function themeTokens(html) {
  const css = html.slice(html.indexOf("<style>") + 7, html.indexOf("</style>"));
  const shared = {};
  const sharedBlock = /\n  :root \{([\s\S]*?)\n  \}/.exec(css);
  if (sharedBlock) for (const m of sharedBlock[1].matchAll(/(--[\w-]+):\s*([^;]+);/g)) shared[m[1]] = m[2].trim();
  const out = {};
  for (const m of css.matchAll(/(?::root,\s*)?:root\[data-theme="(\w+)"\]\s*\{([\s\S]*?)\n  \}/g)) {
    const tokens = { ...shared };
    for (const d of m[2].replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/(--[\w-]+):\s*([^;]+);/g)) tokens[d[1]] = d[2].trim();
    out[m[1]] = tokens;
  }
  return out;
}

// --- sRGB parsing --------------------------------------------------------------------------------------------

function hsl(h, s, l) {
  s /= 100; l /= 100;
  const k = (n) => (n + h / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  return [0, 8, 4].map((n) => l - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1)));
}

// Splits "a, b, c" at top-level commas.
function args(text) {
  const out = []; let depth = 0; let start = 0;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "(") depth++;
    else if (text[i] === ")") depth--;
    else if (text[i] === "," && depth === 0) { out.push(text.slice(start, i).trim()); start = i + 1; }
  }
  out.push(text.slice(start).trim());
  return out;
}

// Resolves a CSS colour expression to { rgb: [r, g, b] in 0..1 sRGB, a }.
export function resolve(tokens, expr, depth = 0) {
  if (depth > 20) throw new Error(`var() loop at ${expr}`);
  expr = expr.trim();
  let m;
  if ((m = /^var\((--[\w-]+)(?:,\s*(.+))?\)$/.exec(expr))) {
    if (m[1] in tokens) return resolve(tokens, tokens[m[1]], depth + 1);
    if (m[2]) return resolve(tokens, m[2], depth + 1);
    throw new Error(`unknown token ${m[1]}`);
  }
  if (expr.startsWith("--")) return resolve(tokens, `var(${expr})`, depth);
  if (expr === "transparent") return { rgb: [0, 0, 0], a: 0 };
  if ((m = /^hsl\(([\d.]+)\s+([\d.]+)%\s+([\d.]+)%(?:\s*\/\s*([\d.]+))?\)$/.exec(expr)))
    return { rgb: hsl(+m[1], +m[2], +m[3]), a: m[4] === undefined ? 1 : +m[4] };
  if ((m = /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(expr))) {
    let x = m[1];
    if (x.length === 3) x = [...x].map((c) => c + c).join("");
    const v = [0, 2, 4].map((i) => parseInt(x.slice(i, i + 2), 16) / 255);
    return { rgb: v, a: x.length === 8 ? parseInt(x.slice(6, 8), 16) / 255 : 1 };
  }
  if ((m = /^color-mix\(in oklab,\s*(.+)\)$/.exec(expr))) {
    const [first, second] = args(m[1]);
    const part = (p) => { const x = /^(.*?)\s+([\d.]+)%$/.exec(p); return x ? [x[1], +x[2] / 100] : [p, null]; };
    let [ea, pa] = part(first); let [eb, pb] = part(second);
    if (pa === null && pb === null) { pa = 0.5; pb = 0.5; } else if (pa === null) pa = 1 - pb; else if (pb === null) pb = 1 - pa;
    const A = resolve(tokens, ea, depth + 1); const B = resolve(tokens, eb, depth + 1);
    // Premultiplied interpolation, as CSS Color 5 specifies.
    const a = A.a * pa + B.a * pb;
    if (a === 0) return { rgb: [0, 0, 0], a: 0 };
    const la = toOklab(A.rgb); const lb = toOklab(B.rgb);
    const lab = la.map((v, i) => (v * A.a * pa + lb[i] * B.a * pb) / a);
    return { rgb: fromOklab(lab), a };
  }
  throw new Error(`cannot parse colour ${expr}`);
}

// Source-over in gamma-encoded sRGB, as WebKit composites.
export const over = (top, bottom) => ({ rgb: top.rgb.map((c, i) => c * top.a + bottom.rgb[i] * (1 - top.a)), a: 1 });

// Resolves a stack of expressions, bottom first, to one opaque sRGB colour.
export function flatten(tokens, stack) {
  const layers = (Array.isArray(stack) ? stack : [stack]).map((e) => resolve(tokens, e));
  let out = layers[0];
  if (out.a < 1) out = over(out, resolve(tokens, "var(--card)"));
  for (const layer of layers.slice(1)) out = over(layer, out);
  return out.rgb;
}

// --- Spaces ----------------------------------------------------------------------------------------------------

const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const enc = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055);
const clamp = (c) => Math.min(1, Math.max(0, c));

export function linearToOklab([r, g, b]) {
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s];
}
export const toOklab = (rgb) => linearToOklab(rgb.map(lin));

export function fromOklab([L, A, B]) {
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3;
  return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s].map((c) => clamp(enc(c)));
}

export function oklch(rgb) {
  const [L, a, b] = toOklab(rgb);
  return [L, Math.hypot(a, b), ((Math.atan2(b, a) * 180) / Math.PI + 360) % 360];
}

// OKLab Euclidean distance, x100.
export const distance = (x, y) => { const [a, b] = [toOklab(x), toOklab(y)]; return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]) * 100; };

// --- Contrast --------------------------------------------------------------------------------------------------

const luminance = (rgb) => rgb.map(lin).reduce((s, v, i) => s + v * [0.2126, 0.7152, 0.0722][i], 0);
export function wcag(fg, bg) {
  const [x, y] = [luminance(fg), luminance(bg)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

// APCA-W3 0.1.9, constants 0.0.98G-4g. Returns signed Lc: positive is dark text on light, negative light on dark.
const SA = { trc: 2.4, r: 0.2126729, g: 0.7151522, b: 0.072175, normBG: 0.56, normTXT: 0.57, revTXT: 0.62, revBG: 0.65,
  blkThrs: 0.022, blkClmp: 1.414, scale: 1.14, offset: 0.027, deltaYmin: 0.0005, loClip: 0.1 };
const apcaY = (rgb) => SA.r * rgb[0] ** SA.trc + SA.g * rgb[1] ** SA.trc + SA.b * rgb[2] ** SA.trc;
export function apca(fg, bg) {
  let t = apcaY(fg); let b = apcaY(bg);
  t = t > SA.blkThrs ? t : t + (SA.blkThrs - t) ** SA.blkClmp;
  b = b > SA.blkThrs ? b : b + (SA.blkThrs - b) ** SA.blkClmp;
  if (Math.abs(b - t) < SA.deltaYmin) return 0;
  if (b > t) { const s = (b ** SA.normBG - t ** SA.normTXT) * SA.scale; return s < SA.loClip ? 0 : (s - SA.offset) * 100; }
  const s = (b ** SA.revBG - t ** SA.revTXT) * SA.scale;
  return s > -SA.loClip ? 0 : (s + SA.offset) * 100;
}

// APCA font lookup, apca-w3 0.1.9 fontMatrixAscend (Public Beta 0.1.7 G, May 28 2022), weights 400 and 500.
// Row: [Lc, min px at 400, min px at 500]. 999 = prohibited, 777 = non-text only.
const LOOKUP = [[25, 120, 120], [30, 108, 108], [35, 96, 72], [40, 60, 48], [45, 42, 32], [50, 32, 28], [55, 28, 24],
  [60, 24, 21], [65, 21.75, 19], [70, 19.5, 18], [75, 18, 16], [80, 17.25, 15.81], [85, 16.5, 15.625], [90, 16, 15.5],
  [95, 15.5, 15], [100, 15, 14.5], [105, 14.5, 14], [110, 14, 13], [115, 12.5, 11.875], [120, 11, 10.75], [125, 10, 10]];

// The Lc a font needs for fluent reading, by linear interpolation between table rows. Infinity: below the table.
export function lookupLc(px, weight) {
  const col = weight >= 500 ? 2 : 1;
  if (px >= LOOKUP[0][col]) return LOOKUP[0][0];
  for (let i = 1; i < LOOKUP.length; i++) {
    const [lc, size] = [LOOKUP[i][0], LOOKUP[i][col]];
    if (px >= size) { const [lc0, size0] = [LOOKUP[i - 1][0], LOOKUP[i - 1][col]]; return lc0 + ((lc - lc0) * (size0 - px)) / (size0 - size); }
  }
  return Infinity;
}

// --- Colour vision deficiency ----------------------------------------------------------------------------------

// Machado, Oliveira and Fernandes 2009, severity 1.0, applied to linear RGB.
export const MACHADO = {
  protan: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
  deutan: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.01182, 0.04294, 0.968881]],
  tritan: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.3039]],
};
export function simulate(rgb, kind) {
  if (kind === "normal") return rgb;
  const v = rgb.map(lin);
  return MACHADO[kind].map((row) => clamp(enc(clamp(row[0] * v[0] + row[1] * v[1] + row[2] * v[2]))));
}
