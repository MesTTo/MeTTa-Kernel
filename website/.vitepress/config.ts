import { readFileSync } from "node:fs";
import { defineConfig } from "vitepress";

const mettaLanguage = {
  ...JSON.parse(readFileSync(new URL("./metta.tmLanguage.json", import.meta.url), "utf8")),
  name: "metta",
  displayName: "MeTTa",
  scopeName: "source.metta",
};

export default defineConfig({
  title: "PeTTa Python",
  description: "Use PeTTa as a Python library and compose integrations through MeTTa.",
  base: "/PeTTa/",
  cleanUrls: true,
  markdown: {
    languages: [mettaLanguage],
  },
  themeConfig: {
    nav: [
      { text: "Guide", link: "/guide/getting-started" },
      { text: "Reasoning", link: "/reasoning/matchers-measure" },
      { text: "Live systems", link: "/live/standing-queries" },
      { text: "Reference", link: "/reference/" },
      { text: "GitHub", link: "https://github.com/trueagi-io/PeTTa" },
    ],
    sidebar: [
      {
        text: "Guide",
        items: [
          { text: "Install and first steps", link: "/guide/getting-started" },
          { text: "Atoms, operators, and terms", link: "/guide/atoms-terms" },
          { text: "Run and query", link: "/guide/run-query" },
          { text: "Python functions in MeTTa", link: "/guide/python-functions" },
          { text: "Write MeTTa in Python", link: "/guide/define" },
          { text: "Spaces", link: "/guide/spaces" },
        ],
      },
      {
        text: "Reasoning",
        items: [
          { text: "Matchers and measures", link: "/reasoning/matchers-measure" },
          { text: "Soft unification and proving", link: "/reasoning/soft" },
          { text: "Weighted relations", link: "/reasoning/weighted-relations" },
        ],
      },
      {
        text: "Live systems",
        items: [
          { text: "Standing queries", link: "/live/standing-queries" },
          { text: "Reflection and steering", link: "/live/reflection" },
          { text: "Web routes", link: "/live/web-routes" },
          { text: "Multi-shot solving", link: "/live/multishot" },
          { text: "Contexts and remotes", link: "/live/contexts" },
          { text: "The loop stays live", link: "/live/async" },
        ],
      },
            {
        text: "Reference",
        collapsed: true,
        items: [
          { text: "Module index", link: "/reference/" },
          { text: "petta.atoms", link: "/reference/petta-atoms" },
          { text: "petta.space", link: "/reference/petta-space" },
          { text: "petta.ops", link: "/reference/petta-ops" },
          { text: "petta.convert", link: "/reference/petta-convert" },
          { text: "petta.matching", link: "/reference/petta-matching" },
          { text: "petta.measure", link: "/reference/petta-measure" },
          { text: "petta_soft", link: "/reference/petta-soft" },
          { text: "petta.subscribe", link: "/reference/petta-subscribe" },
          { text: "petta.remote", link: "/reference/petta-remote" },
          { text: "petta.aio", link: "/reference/petta-aio" },
          { text: "petta.persistent", link: "/reference/petta-persistent" },
          { text: "petta.testing", link: "/reference/petta-testing" },
          { text: "petta.foreign", link: "/reference/petta-foreign" },
          { text: "petta.integrate", link: "/reference/petta-integrate" },
          { text: "petta.arrays", link: "/reference/petta-arrays" },
          { text: "petta.results", link: "/reference/petta-results" },
        ],
      },
    ],
    search: { provider: "local" },
    socialLinks: [{ icon: "github", link: "https://github.com/trueagi-io/PeTTa" }],
    footer: {
      message: "Released under the MIT License.",
      copyright: "MesTTo",
    },
  },
});
