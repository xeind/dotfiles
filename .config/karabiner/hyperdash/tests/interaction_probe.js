// Interaction probe, run inside the page by interaction.test.mjs with the clock frozen at NOW.
// 1. Every keyboard-focused button on every page keeps Enter and Space: the page's routing neither cancels
//    them nor acts on them, so the browser's own activation (the same as a click) runs.
// 2. A focused Activity bin takes Enter like a click.
// 3. After a keyboard-focused Activity control is used, focus stays on a control, not on the body.
// 4. On Activity, in every focus state, each key the footer names does what the footer says.
(() => {
  const NOW = "2026-10-16T22:20:00";
  const out = { routing: [], bins: [], focus: [], hints: [], heights: {}, footerOverflow: [] };
  const k = (key, target = document.activeElement || document) => {
    const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true });
    (target === document.body ? document : target).dispatchEvent(event);
    return event.defaultPrevented;
  };
  const S = () => JSON.stringify({ ...state, aboutOpen: state.aboutOpen, theme: document.documentElement.dataset.theme });
  const name = (n) => !n || n === document.body ? "body" : `${n.tagName.toLowerCase()}${n.id ? `#${n.id}` : ""}.${(n.getAttribute("class") || "").split(" ")[0]}${n.dataset.action || n.dataset.app || n.dataset.sec || n.dataset.bin || ""}`;
  const tabbables = () => [...document.querySelectorAll("#card button, #card [tabindex]")]
    .filter((n) => n.tabIndex >= 0 && !n.disabled && n.getClientRects().length && !n.closest("[hidden]") && getComputedStyle(n).visibility !== "hidden");
  const footer = () => [...document.querySelectorAll("#footer > span")].map((s) => [[...s.querySelectorAll("kbd")].map((x) => x.textContent).join(" "), s.lastChild.textContent]);

  // Fixture: two days, a recurring pair (so sequences show time chips), two apps in front.
  const bindings = [
    { layer: "v", key: "q", label: "Left click", category: "pointer" }, { layer: "v", key: "j", label: "Down arrow", category: "text-navigation" },
    { layer: "w", key: "u", label: "Previous Tab", category: "tab-navigation" }, { layer: "o", key: "t", label: "Ghostty", category: "app-launch", app: "Ghostty" },
  ];
  const lines = [];
  const pad = (n) => String(n).padStart(2, "0");
  const at = (day, sec) => `2026-10-${day}T${pad(Math.floor(sec / 3600))}:${pad(Math.floor(sec / 60) % 60)}:${pad(sec % 60)}`;
  for (const day of [15, 16]) {
    for (let s = 20 * 3600; s < 21 * 3600; s += 90) { lines.push(`${at(day, s)}\tv\tq`, `${at(day, s + 2)}\tw\tu`); if (s % 270 === 0) lines.push(`${at(day, s + 30)}\tv\tj`); }
  }
  lines.unshift("2026-09-20T10:00:00\tv\tq", "2026-09-20T10:00:02\tw\tu"); // a second month for the month arrows
  const text = lines.join("\n") + "\n";
  const context = ["2026-10-15T19:00:00.100\tstart\t-", "2026-10-15T19:00:00.500\tapp\tcom.mitchellh.ghostty", "2026-10-15T20:30:00.500\tapp\torg.mozilla.firefox",
    "2026-10-16T19:00:00.500\tapp\tcom.mitchellh.ghostty", "2026-10-16T20:30:00.500\tapp\torg.mozilla.firefox"].join("\n") + "\n";
  const health = { log: { status: "ok", bytes: text.length, modified: NOW }, bindings: { status: "ok" }, insights: { status: "ok", message: null }, context: { status: "ok" } };
  const insights = { version: 3, generated: NOW, month: "2026-10", recordingSince: "2026-10-15T20:00:00", rejectedLines: 0, insights: [
    { kind: "burst", title: "Keys", detail: "d", keys: [["v", "q"]], value: 1, dates: ["2026-10-15"], app: null },
    { kind: "peak", title: "Dates", detail: "d", keys: [], value: 1, dates: ["2026-10-15"], app: "com.mitchellh.ghostty" },
  ] };
  hyperdash.reset({ now: NOW, generation: 1, bindings, text, offset: text.length, insights, health });
  hyperdash.reset({ now: NOW, stream: "context", generation: 1, text: context, offset: 0 });
  hyperdash.setApps({ "com.mitchellh.ghostty": "Ghostty", "org.mozilla.firefox": "Firefox" });

  // A clean open, the keys that reach the scene, then one Tab press (which turns the header stops on).
  const SCENES = { overview: [], layer: ["v"], about: ["?"], insights: ["i"], day: ["a"], yesterday: ["a", "ArrowLeft"], interval: ["a", "bin"], month: ["a", "Enter"] };
  const enter = (scene) => {
    hyperdash.open({ now: NOW });
    for (const step of SCENES[scene]) {
      if (step === "bin") document.querySelector(".bin[tabindex='0']").dispatchEvent(new MouseEvent("click", { bubbles: true }));
      else k(step, document);
    }
    k("Tab", document);
  };

  // 1 and 3.
  for (const scene of Object.keys(SCENES)) {
    enter(scene);
    const count = tabbables().length;
    for (let i = 0; i < count; i++) {
      for (const key of ["Enter", " "]) {
        enter(scene);
        const node = tabbables()[i];
        if (node.tagName !== "BUTTON") continue;
        node.focus();
        const before = S();
        const prevented = k(key);
        out.routing.push({ scene, control: name(node), key, focusVisible: node.matches(":focus-visible"), hasFocus: document.hasFocus(), prevented, acted: S() !== before });
      }
      enter(scene);
      const node = tabbables()[i];
      if (node.tagName === "BUTTON" && node.closest("#activity")) {
        node.focus();
        node.click();
        out.focus.push({ scene, control: name(node), after: name(document.activeElement) });
      }
    }
  }

  // 2. Enter on the focused bin against a click on it, in the day view.
  for (const scene of ["day", "interval"]) {
    enter(scene);
    const bin = document.querySelector(".bin[tabindex='0']");
    bin.focus();
    k("Enter");
    const keyed = state.interval;
    enter(scene);
    document.querySelector(`.bin[data-bin="${bin.dataset.bin}"]`).dispatchEvent(new MouseEvent("click", { bubbles: true }));
    out.bins.push({ scene, bin: bin.dataset.bin, keyed, clicked: state.interval });
  }

  // 4. Focus states on Activity, then each named key against what it does.
  const FOCUS = { none: null, seg: '.seg[data-action="yesterday"]', month: '.seg[data-action="month"]', bin: ".bin[tabindex='0']", appchip: ".appchip", time: ".time-chip", back: "#header-icon" };
  const binOf = (n) => (n?.classList?.contains("bin") ? Number(n.dataset.bin) : null);
  for (const scene of ["day", "yesterday", "interval", "month"]) {
    for (const [focusName, selector] of Object.entries(FOCUS)) {
      const setup = () => { enter(scene); const n = selector && document.querySelector(`#card ${selector}`); if (selector && (!n || n.closest("[hidden]"))) return false; n?.focus(); return true; };
      if (!setup()) continue;
      for (const a of document.getAnimations()) a.finish(); // the height where a page change's motion ends
      (out.heights[`activity ${scene}`] ||= new Set()).add(document.body.scrollHeight);
      const card = document.getElementById("footer");
      if (card.scrollWidth > card.clientWidth) out.footerOverflow.push(`${scene} ${focusName}: ${card.scrollWidth}>${card.clientWidth}`);
      const hints = Object.fromEntries(footer().map(([keys, label]) => [keys, label]));
      for (const key of ["ArrowLeft", "ArrowRight", "Enter", "Escape"]) {
        setup();
        const focused = document.activeElement;
        const label = key === "Enter" ? hints["↵"] : key === "Escape" ? `esc ${hints.esc}` : hints["← →"];
        const before = { ...state };
        const fromBin = binOf(focused);
        const prevented = k(key);
        let ok;
        if (label === "day") {
          const step = key === "ArrowLeft" ? -1 : key === "ArrowRight" ? 1 : 0;
          ok = step ? (state.day !== before.day ? Date.parse(state.day) - Date.parse(before.day) === step * 864e5 : before.day === (step < 0 ? "2026-09-20" : "2026-10-16"))
            : state.activityMode === "day" && before.activityMode === "month";
        } else if (label === "month") ok = key === "Enter" ? state.activityMode === "month" && before.activityMode === "day"
          : key === "ArrowLeft" ? state.monthId === "2026-09" && before.monthId === "2026-10" : state.monthId === before.monthId && before.monthId === "2026-10";
        else if (label === "esc back") ok = state.page === null;
        else if (label === "esc clear") ok = state.page === "activity" && state.highlight === null && state.interval === null;
        else if (label === "bin") {
          // The next bin with presses in that direction takes focus; at the last one, focus stays.
          const bins = [...document.querySelectorAll(".bin")].map(binOf);
          const want = bins[bins.indexOf(fromBin) + (key === "ArrowLeft" ? -1 : 1)] ?? fromBin;
          ok = binOf(document.activeElement) === want && JSON.stringify(state) === JSON.stringify(before);
        }
        else if (label === "time") {
          // A focused time chip walks the timestamps of its own sequence; at the last one, focus stays.
          const chips = [...focused.closest(".seq-times").querySelectorAll(".time-chip")];
          const want = chips[chips.indexOf(focused) + (key === "ArrowLeft" ? -1 : 1)] ?? focused;
          ok = document.activeElement?.dataset.sec === want.dataset.sec && JSON.stringify(state) === JSON.stringify(before);
        }
        else if (label === "select") ok = state.interval === fromBin;
        else if (label === "clear") ok = state.interval === null && before.interval !== null;
        else if (label === "press") {
          // The routing must leave the key to the button; the browser then activates it like a click.
          const keyed = JSON.stringify(state);
          setup();
          document.activeElement.click();
          ok = !prevented && keyed === JSON.stringify(before) && document.activeElement !== null;
        } else ok = false;
        out.hints.push({ scene, focus: focusName, footer: footer().map((h) => h.join(" ")).join(" | "), key, label, ok });
      }
    }
  }
  for (const page of Object.keys(out.heights)) out.heights[page] = [...out.heights[page]];
  document.getElementById("probe-out").textContent = JSON.stringify(out);
})();
