// Height probe, run inside the page by height.test.mjs. It walks every interaction on every page and records
// document.body.scrollHeight. The panel must keep one height per page: the host resizes the window on any change.
(() => {
  // A page change moves the card (motion.test.mjs); the height that counts is where it ends.
  const H = () => { for (const a of document.getAnimations()) a.finish(); return document.body.scrollHeight; };
  const seen = {}; // page -> { height -> [labels] }
  let page = "overview";
  const clipped = []; // steps where a legend cell is wider than its box (its text would be cut off)
  const titles = []; // steps where a native tooltip source exists inside the card: a title attribute or an SVG <title>
  const note = (label) => {
    const h = H(); ((seen[page] ||= {})[h] ||= []).push(label);
    for (const cell of document.querySelectorAll(".chart-legend > span, .chart-legend .row > span")) {
      if (cell.scrollWidth > cell.clientWidth && clipped.length < 10) clipped.push(`${label}: "${cell.textContent}" ${cell.scrollWidth}>${cell.clientWidth}`);
    }
    const t = document.querySelector("#card [title], #card svg title");
    if (t && titles.length < 10) titles.push(`${label}: <${t.tagName.toLowerCase()}> ${t.getAttribute?.("title") || t.textContent}`.slice(0, 120));
  };
  const k = (key, extra) => document.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, ...(extra || {}) }));
  const pad = (n) => String(n).padStart(2, "0");
  const stamp = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  const now = new Date();
  const at = (off, sec) => { const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + off, 0, 0, 0); d.setSeconds(sec); return d; };

  // Fixture: categorised bindings, a busy and a quiet pattern across several days and two months.
  const bindings = [
    ["v", "q", "Left click", "pointer"], ["v", "u", "Page down", "page-navigation"], ["v", "i", "Page up", "page-navigation"], ["v", "j", "Down arrow", "text-navigation"],
    ["w", "u", "Previous Tab", "tab-navigation"], ["w", "i", "Next Tab", "tab-navigation"], ["w", "n", "Next Window", "window-switching"], ["w", "f", "Maximize", "window-arrangement"],
    ["o", "t", "Ghostty", "app-launch"], ["o", "b", "Firefox", "app-launch"], ["b", "g", "github.com", "site-open"], ["c", "e", "Screenshot window", "capture"],
    ["s", "d", "Toggle Do Not Disturb", "system"], ["f", "i", "Open Downloads", "file"], ["r", "h", "Tinycast", "launcher"],
  ].map(([layer, key, label, category]) => ({ layer, key, label, category, ...(layer === "o" ? { app: label } : {}), ...(layer === "b" ? { site: label } : {}) }));
  const combos = bindings.map((b) => `${b.layer}\t${b.key}`);
  let seed = 7; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const lines = [];
  for (let off = -40; off <= 0; off++) {
    const busy = off === 0 || off === -1 || off % 7 === 0;
    for (const [from, to, density] of [[8.3, 11.7, busy ? 6 : 90], [12.5, 18, busy ? 5 : 120]]) {
      for (let s = from * 3600; s < to * 3600; s += density + Math.floor(rnd() * density)) {
        if (off === 0 && s > now.getHours() * 3600 + now.getMinutes() * 60 - 600) break;
        const c = combos[Math.floor(rnd() * combos.length)];
        lines.push(`${stamp(at(off, Math.floor(s)))}\t${c}`);
      }
    }
  }
  const text = lines.join("\n") + "\n";
  const ctx = [`${stamp(at(-40, 7 * 3600))}.100\tstart\t-`];
  const bundles = ["com.mitchellh.ghostty", "org.mozilla.firefox", "com.apple.finder", "com.apple.Safari"];
  for (let off = -40; off <= 0; off++) for (let h = 8; h < 18; h++) ctx.push(`${stamp(at(off, h * 3600 + 120))}.250\tapp\t${bundles[(h + off + 80) % 4]}`);
  ctx.push(`${stamp(at(-1, 12 * 3600))}.000\tlock\t-`, `${stamp(at(-1, 12 * 3600 + 1500))}.000\tunlock\t-`);
  const okHealth = (extra) => ({ log: { status: "ok", bytes: 9000, modified: stamp(now) }, bindings: { status: "ok" }, insights: { status: "ok", message: null }, context: { status: "ok" }, ...extra });
  const insights = (n) => ({ version: 3, generated: stamp(now), month: stamp(now).slice(0, 7), recordingSince: stamp(at(-40, 8 * 3600)), rejectedLines: 0,
    insights: Array.from({ length: n }, (_, i) => ({ kind: ["rising", "peak", "unused", "burst", "dormant"][i % 5], title: i % 2 ? "A much longer title that runs on to two lines on this card" : "Short title",
      detail: i % 2 ? "A long detail line that explains the finding in more words than fit on one single line of the card" : "Short detail", keys: i % 3 === 0 ? [["v", "q"], ["w", "u"], ["o", "t"]] : [], value: i, dates: i % 2 ? ["2026-10-14", "2026-10-15"] : [], app: i % 2 ? "org.mozilla.firefox" : null,
      windowStart: "2026-10-08", windowEnd: "2026-10-14", comparisonStart: i % 2 ? "2026-10-01" : null, comparisonEnd: i % 2 ? "2026-10-07" : null })),
    // Why the other rules have no card: one line and two-line reasons below the cards.
    rules: [{ rule: "trend", status: "not-ready", reason: "Week comparisons need 14 recorded days; 9 qualify." },
      { rule: "burst", status: "no-pattern", reason: "No shortcut came in bursts (5+ presses, each within 3 s) on 2+ days this month." }] });

  hyperdash.reset({ generation: 1, bindings, text, offset: text.length, insights: insights(3), health: okHealth() });
  hyperdash.reset({ stream: "context", generation: 1, text: ctx.join("\n") + "\n", offset: 0 });
  hyperdash.setApps({ "com.mitchellh.ghostty": "Ghostty", "org.mozilla.firefox": "Firefox", "com.apple.finder": "Finder", "com.apple.Safari": "Safari" });
  hyperdash.open({});
  const healths = {
    ok: okHealth(), stale: okHealth({ insights: { status: "stale", message: null } }), running: okHealth({ insights: { status: "running", message: null } }),
    off: okHealth({ context: { status: "disabled" } }),
    error: okHealth({ log: { status: "unreadable" }, bindings: { status: "invalid" }, insights: { status: "failed", message: "exit 1" }, context: { status: "unreadable" } }),
  };
  const healthSteps = (label) => { for (const [n, h] of Object.entries(healths)) { hyperdash.setHealth(h); note(`${label} health ${n}`); } hyperdash.setHealth(healths.ok); };

  // Overview
  page = "overview"; hyperdash.open({}); note("open");
  document.getElementById("about-toggle").click(); note("about on"); document.getElementById("about-toggle").click(); note("about off");
  for (const t of ["kozo", "nightingale", "blueprint", "manila"]) { hyperdash.setTheme(t); note(`theme ${t}`); }
  healthSteps("overview");
  for (const b of document.querySelectorAll("#groupbar button")) { b.click(); note(`group ${b.dataset.group}`); b.click(); }
  for (let i = 0; i < 3; i++) { k("ArrowLeft"); note("month back"); } for (let i = 0; i < 3; i++) { k("ArrowRight"); note("month forward"); }
  hyperdash.append({ generation: 1, from: text.length, to: text.length + 1, text: "\n" }); note("append");
  hyperdash.setBindings(bindings.slice(0, 5), healths.ok); note("fewer bindings"); hyperdash.setBindings(bindings, healths.ok); note("all bindings");
  k("t"); note("T"); k("t"); k("t"); k("t");

  // Layer pages
  for (const layer of ["v", "w", "o", "b", "s", "c", "f", "r"]) {
    page = "layer"; hyperdash.open({}); k(layer); note(`open ${layer}`);
    for (const key of ["q","w","e","r","t","y","u","i","o","p","a","s","d","f","g","h","j","k","l","z","x","c","v","b","n","m","1","3","ArrowUp","ArrowDown","ArrowLeft","ArrowRight","Enter","Backspace"," ",";","=","-"]) { k(key); note(`${layer}: select ${key}`); }
    k("Escape"); note(`${layer}: clear`);
    for (const b of document.querySelectorAll("#groupbar button")) { b.click(); note(`${layer}: group ${b.dataset.group}`); b.click(); }
    document.getElementById("about-toggle").click(); note(`${layer}: about on`); document.getElementById("about-toggle").click();
    healthSteps(`layer ${layer}`);
  }

  // Activity
  page = "activity"; hyperdash.open({}); k("a"); note("open activity");
  const bins = () => [...document.querySelectorAll(".bin")];
  for (let step = 0; step < 6; step++) {
    for (const b of bins()) { b.focus(); b.dispatchEvent(new MouseEvent("mouseover", { bubbles: true })); note(`day ${step}: focus bin ${b.dataset.bin}`); }
    for (const b of bins()) { b.dispatchEvent(new MouseEvent("click", { bubbles: true })); note(`day ${step}: select bin ${b.dataset.bin}`); }
    k("Escape"); note(`day ${step}: clear interval`);
    for (const chip of document.querySelectorAll(".appchip")) { chip.click(); note(`day ${step}: app ${chip.dataset.app}`); chip.click(); }
    for (const l of ["w", "v", "o", "b"]) { k(l); note(`day ${step}: highlight ${l}`); k(l); }
    for (const chip of document.querySelectorAll(".time-chip")) { chip.click(); note(`day ${step}: time chip`); k("Escape"); break; }
    k("ArrowLeft"); note(`day ${step}: previous day`);
  }
  k("Home"); note("today");
  for (const t of ["kozo", "nightingale", "blueprint", "manila"]) { hyperdash.setTheme(t); note(`theme ${t}`); }
  healthSteps("activity");
  k("Enter"); note("month mode");
  for (const b of bins()) { b.focus(); note(`month: focus bin ${b.dataset.bin}`); }
  k("ArrowLeft"); note("month back"); k("ArrowRight"); note("month forward");
  for (const l of ["w", "v"]) { k(l); note(`month highlight ${l}`); k(l); }
  k("Enter"); note("day mode again");
  hyperdash.reset({ generation: 2, bindings, text: "", offset: 0, insights: insights(0), health: okHealth() }); note("empty log");
  hyperdash.reset({ generation: 3, bindings, text, offset: text.length, insights: insights(3), health: okHealth() }); note("full log again");

  // Legend counts with five digits in every group must fit their cells, in every theme and in highlight mode.
  {
    const big = [["v", "q"], ["v", "u"], ["w", "f"], ["o", "t"], ["c", "e"], ["s", "d"]];
    const rows = [];
    for (const [layer, key] of big) for (let i = 0; i < 12345; i++) rows.push(`${stamp(at(0, 600 + (i % 3000)))}\t${layer}\t${key}`);
    hyperdash.reset({ generation: 4, bindings, text: rows.join("\n") + "\n", offset: 0, insights: insights(3), health: okHealth() });
    page = "activity"; hyperdash.open({}); k("a"); note("big counts");
    for (const t of ["kozo", "nightingale", "blueprint", "manila"]) { hyperdash.setTheme(t); note(`big counts ${t}`); }
    for (const l of ["w", "v", "o"]) { k(l); note(`big counts highlight ${l}`); k(l); }
    k("Enter"); note("big counts month"); k("Enter");
    hyperdash.reset({ generation: 5, bindings, text, offset: text.length, insights: insights(3), health: okHealth() });
  }

  // Insights
  page = "insights"; hyperdash.open({}); k("i"); note("open insights");
  for (const n of [0, 1, 2, 3, 4, 5]) { hyperdash.setInsights(insights(n), healths.ok); note(`insights ${n}`); }
  hyperdash.setInsights(null, healths.ok); note("insights null");
  hyperdash.setInsights(null, healths.running); note("insights running");
  hyperdash.setInsights(null, healths.error); note("insights failed");
  hyperdash.setInsights(insights(3), healths.ok);
  healthSteps("insights");
  document.getElementById("about-toggle")?.click(); note("insights about");
  document.getElementById("about-toggle")?.click();
  document.querySelector(".insight")?.click(); note("insights evidence");
  k("Escape"); note("insights evidence closed");
  hyperdash.open({});

  // Edge fades: top of the scroll, middle, bottom, and content that fits.
  const fades = {};
  const mask = (node) => getComputedStyle(node).webkitMaskImage;
  const readFade = (label, node) => { node.dispatchEvent(new Event("scroll")); fades[label] = [node.getAttribute("data-fade"), mask(node) !== "none"]; };
  hyperdash.open({});
  const list = document.getElementById("list");
  list.scrollTop = 0; readFade("list top", list);
  list.scrollTop = 90; readFade("list middle", list);
  list.scrollTop = list.scrollHeight; readFade("list bottom", list);
  document.querySelector('#groupbar button[data-group="capture"]').click();
  list.scrollTop = 0; readFade("list fits", list);
  document.querySelector('#groupbar button[data-group="capture"]').click();
  hyperdash.open({}); k("a");
  const busiest = [...document.querySelectorAll(".bin")].sort((x, y) => Number(y.getAttribute("aria-label").split(" · ")[1].split(" ")[0]) - Number(x.getAttribute("aria-label").split(" · ")[1].split(" ")[0]))[0];
  busiest.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  const cmds = document.querySelector(".cmds");
  cmds.scrollTop = 0; readFade("commands top", cmds);
  cmds.scrollTop = 60; readFade("commands middle", cmds);
  cmds.scrollTop = cmds.scrollHeight; readFade("commands bottom", cmds);
  k("Escape"); 
  const seqs = document.querySelector(".seqs");
  readFade("sequences", seqs);
  hyperdash.open({}); k("i");
  const insightBox = document.getElementById("insights");
  hyperdash.setInsights(insights(5), healths.ok);
  insightBox.scrollTop = 40; readFade("insights middle", insightBox);
  hyperdash.setInsights(insights(1), healths.ok);
  insightBox.scrollTop = 0; readFade("insights fits", insightBox);
  hyperdash.open({});

  const summary = {};
  for (const [p, hs] of Object.entries(seen)) summary[p] = Object.fromEntries(Object.entries(hs).map(([h, labels]) => [h, { count: labels.length, examples: labels.slice(0, 4) }]));
  document.getElementById("probe-out").textContent = JSON.stringify({ summary, titles, clipped, fades, steps: Object.values(seen).reduce((n, hs) => n + Object.values(hs).reduce((m, l) => m + l.length, 0), 0) });
})();
