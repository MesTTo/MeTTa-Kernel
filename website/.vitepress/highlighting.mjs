/**
 * Purpose: build the theme pair the site highlights code with, and give Python
 *   method calls and attribute reads a colour that no bundled theme gives them.
 *
 * Two separate problems, measured 2026-08-29 with scripts/measure_highlighting.mjs.
 *
 * The FIRST is the theme pair. VitePress defaults to github-light and
 * github-dark; light-plus and dark-plus are VS Code's own defaults. Over one
 * fence per language from the seat tutorials:
 *
 *   theme          colours   buckets   worst contrast   below 4.5:1
 *   github-light       5         4         4.24:1           19%
 *   light-plus         9         5         4.19:1            4%
 *   github-dark        5         4         6.80:1            0%
 *   dark-plus          9         5         6.13:1            0%
 *
 * Read the last column rather than the one before it. light-plus's WORST token
 * is a hair darker than github-light's, 4.19:1 against 4.24:1, and both sit
 * just under the AA bar; what changes is how much of the page is down there,
 * 4% of coloured tokens against 19%. The dark pair is comfortable either way
 * and is chosen for matching its light half rather than for contrast.
 *
 * Contrast is against `--vp-c-bg-alt`, #f6f6f7 and #161618, because
 * `.vp-doc [class*='language-'] pre` is `background: transparent` and the
 * theme's own background is never on screen.
 *
 * The SECOND is Python, and it is why a page of `m.add(S.Parent(S.Tom))` used
 * to render in one flat colour. MagicPython, the grammar Shiki ships, scopes a
 * called name `meta.function-call.generic.python` and an attribute read
 * `meta.attribute.python`, and NO bundled theme carries a rule for either:
 * VS Code colours both from Pylance's SEMANTIC tokens, which a statically
 * rendered site has no equivalent of. With nothing matching, Shiki coalesces
 * the whole expression into a single uncoloured token. Measured on
 * `m.add(S.Parent(1))`: one token before, ten after.
 *
 * The two rules below take each colour FROM THE THEME rather than naming a hex
 * value, so a theme change carries them: a called name gets whatever that theme
 * gives `entity.name.function`, and an attribute gets its `variable`. TypeScript
 * and C need none of this; their grammars already emit `entity.name.function`
 * and `variable.other.property`, which every theme rules on.
 */

import { bundledThemes } from "shiki";

/** The scopes MagicPython emits that no bundled theme colours. */
export const PYTHON_SCOPES = [
  "meta.function-call.generic.python",
  "meta.attribute.python",
];

/** One theme rule's foreground, read out of the theme's own token colours. */
function foreground(theme, scope) {
  const rule = (theme.tokenColors ?? []).find((entry) =>
    []
      .concat(entry.scope ?? [])
      .some((value) =>
        String(value)
          .split(",")
          .map((part) => part.trim())
          .includes(scope),
      ),
  );
  return rule?.settings?.foreground;
}

async function withPythonScopes(name) {
  const theme = structuredClone(await bundledThemes[name]().then((m) => m.default));
  const called = foreground(theme, "entity.name.function");
  const attribute = foreground(theme, "variable");
  theme.tokenColors = [
    ...(theme.tokenColors ?? []),
    // Appended, so these lose to any rule the theme states itself: this adds a
    // colour where there was none rather than overriding a decision.
    ...(called
      ? [{ scope: "meta.function-call.generic.python", settings: { foreground: called } }]
      : []),
    ...(attribute
      ? [{ scope: "meta.attribute.python", settings: { foreground: attribute } }]
      : []),
  ];
  return theme;
}

export const lightTheme = await withPythonScopes("light-plus");
export const darkTheme = await withPythonScopes("dark-plus");
