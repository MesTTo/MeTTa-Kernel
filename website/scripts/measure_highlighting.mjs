/**
 * Purpose: measure how much colour a Shiki theme actually puts on this site's
 *   code, and whether that colour is readable, so the theme pair in
 *   .vitepress/config.ts is a measured choice rather than a taste.
 *
 * Contrast is measured against `--vp-c-bg-alt`, not against the theme's own
 * declared background. VitePress paints the wrapper with
 * `--vp-code-block-bg: var(--vp-c-bg-alt)` and then sets
 * `.vp-doc [class*='language-'] pre { background: transparent }`, so a theme's
 * background colour is never on screen and measuring against it would score
 * the wrong pair of colours [source:
 * node_modules/vitepress/dist/client/theme-default/styles/components/vp-doc.css
 * and styles/vars.css].
 *
 * Usage:
 *   node website/scripts/measure_highlighting.mjs                 the shipped pair
 *   node website/scripts/measure_highlighting.mjs light-plus …    named themes
 */

import { createHighlighter } from "shiki";

import { PYTHON_SCOPES } from "../.vitepress/highlighting.mjs";

// What VitePress actually paints behind a code block, light and dark.
const BACKGROUND = { light: "#f6f6f7", dark: "#161618" };

// One fence per language the site ships, taken from the seat tutorials so the
// measurement is over the code a reader meets rather than a synthetic sample.
const SAMPLES = {
  python: `from metta import MeTTa, S, V\n\nm = MeTTa().space()\nm.add(S.parent(S.tom, S.bob))\nrows = m.match(S.parent(S.tom, V.child))\nassert rows.to_dicts() == [{"child": "Bob"}]\n`,
  typescript: `import { metta, S, V, fn } from "metta-node";\n\nconst m = await metta();\nm.add(S.parent(S.tom, S.bob));\nconsole.log(String(await m.eval(fn.add(1, 2)).one()));\nm.dispose();\n`,
  c: `#include "cmetta.h"\n\nint main(void) {\n  mt_engine *e = mt_init(NULL);\n  mt_term t = mt_eval(e, "(+ 1 2)");\n  printf("%s\\n", mt_text(t));\n  return 0;\n}\n`,
  bash: `sudo apt install swi-prolog\npip install 'pymetta[engine]'\n`,
};

const hex = (value) => {
  const n = value.replace("#", "");
  const full = n.length === 3 ? [...n].map((c) => c + c).join("") : n.slice(0, 6);
  return [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16));
};

/** WCAG 2.1 relative luminance. */
const luminance = (rgb) => {
  const [r, g, b] = rgb.map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

const contrast = (a, b) => {
  const [x, y] = [luminance(hex(a)), luminance(hex(b))].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
};

/** Which sixth of the colour wheel a colour sits in, or "grey". */
const bucket = (colour) => {
  const [r, g, b] = hex(colour).map((v) => v / 255);
  const [max, min] = [Math.max(r, g, b), Math.min(r, g, b)];
  if (max - min < 0.08) return "grey";
  let h;
  if (max === r) h = ((g - b) / (max - min) + 6) % 6;
  else if (max === g) h = (b - r) / (max - min) + 2;
  else h = (r - g) / (max - min) + 4;
  return String(Math.floor(h));
};

async function measure(theme, mode) {
  const highlighter = await createHighlighter({
    themes: [theme],
    langs: Object.keys(SAMPLES),
  });
  const tokens = [];
  for (const [lang, code] of Object.entries(SAMPLES)) {
    for (const line of highlighter.codeToTokens(code, { lang, theme }).tokens) {
      for (const token of line) {
        if (token.content.trim()) tokens.push(token);
      }
    }
  }
  highlighter.dispose();
  const colours = tokens.map((t) => t.color).filter(Boolean);
  const distinct = [...new Set(colours.map((c) => c.toLowerCase().slice(0, 7)))];
  const failing = colours.filter(
    (c) => contrast(c, BACKGROUND[mode]) < 4.5
  ).length;
  return {
    theme,
    colours: distinct.length,
    buckets: new Set(distinct.map(bucket)).size,
    worst: Math.min(...distinct.map((c) => contrast(c, BACKGROUND[mode]))),
    below: colours.length ? (failing / colours.length) * 100 : 0,
    tokens: tokens.length,
    coloured: colours.length,
  };
}

const named = process.argv.slice(2);
const plan = named.length
  ? named.map((t) => [t, t.includes("dark") ? "dark" : "light"])
  : [
      ["github-light", "light"],
      ["light-plus", "light"],
      ["github-dark", "dark"],
      ["dark-plus", "dark"],
    ];

console.log(
  "theme".padEnd(16),
  "colours".padStart(8),
  "buckets".padStart(8),
  "worst".padStart(8),
  "below 4.5:1".padStart(12),
  "coloured/total".padStart(16),
);
for (const [theme, mode] of plan) {
  const r = await measure(theme, mode);
  console.log(
    r.theme.padEnd(16),
    String(r.colours).padStart(8),
    String(r.buckets).padStart(8),
    `${r.worst.toFixed(2)}:1`.padStart(8),
    `${r.below.toFixed(0)}%`.padStart(12),
    `${r.coloured}/${r.tokens}`.padStart(16),
  );
}
console.log(
  `\nagainst ${BACKGROUND.light} (light) and ${BACKGROUND.dark} (dark), which is`,
  "\nwhat VitePress paints behind a code block; the theme's own background is",
  "\nnever shown because .vp-doc sets the <pre> transparent.",
);
console.log(
  `\nthe Python scope rules in highlighting.mjs cover: ${PYTHON_SCOPES.join(", ")}`,
);
