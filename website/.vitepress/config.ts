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
  head: [
    ["link", { rel: "icon", type: "image/svg+xml", href: "/PeTTa/visuals/favicon.svg" }],
  ],
  // localhost examples in docstrings are unreachable at build time by nature
  ignoreDeadLinks: [/^https?:\/\/localhost/],
  cleanUrls: true,
  markdown: {
    languages: [mettaLanguage],
  },
  themeConfig: {
    nav: [
      { text: "Tutorials", link: "/tutorials/" },
      { text: "Guide", link: "/guide/" },
      { text: "Reasoning", link: "/reasoning/" },
      { text: "Integrations", link: "/integrations/" },
      { text: "Live systems", link: "/live/" },
      { text: "Reference", link: "/reference/" },
      { text: "GitHub", link: "https://github.com/trueagi-io/PeTTa" },
    ],
    sidebar: [
      {
        text: "Tutorials",
        link: "/tutorials/",
        items: [
          { text: "01. Atoms and expressions", link: "/tutorials/01-atoms-and-expressions" },
          { text: "02. Spaces and matching", link: "/tutorials/02-spaces-and-matching" },
          { text: "03. Equations and evaluation", link: "/tutorials/03-equations-and-evaluation" },
          { text: "04. The Python bridge", link: "/tutorials/04-python-bridge" },
          { text: "05. Writing MeTTa in Python", link: "/tutorials/05-writing-metta-in-python" },
          { text: "06. Types and casting", link: "/tutorials/06-types-and-casting" },
          { text: "07. Seeing your program", link: "/tutorials/07-seeing-your-program" },
          { text: "08. The graph view", link: "/tutorials/08-graph-view" },
        ],
      },
      {
        text: "Guide",
        link: "/guide/",
        items: [
          { text: "Install and first steps", link: "/guide/getting-started" },
          { text: "Concepts and names", link: "/guide/concepts" },
          { text: "Atoms, operators, and terms", link: "/guide/atoms-terms" },
          { text: "Run and query", link: "/guide/run-query" },
          { text: "Python functions in MeTTa", link: "/guide/python-functions" },
          { text: "Write MeTTa in Python", link: "/guide/define" },
          { text: "Spaces", link: "/guide/spaces" },
          { text: "Data structures", link: "/guide/structures" },
          { text: "Jupyter notebooks", link: "/guide/notebook" },
          { text: "Pettorch", link: "/guide/pettorch" },
        ],
      },
      {
        text: "Reasoning",
        link: "/reasoning/",
        items: [
          { text: "Custom matching", link: "/reasoning/matchers-measure" },
          { text: "Weighted relations", link: "/reasoning/weighted-relations" },
        ],
      },
      {
        text: "Integrations",
        link: "/integrations/",
        items: [
          { text: "Dataframes", link: "/integrations/dataframes" },
          { text: "DuckDB as a space", link: "/integrations/duckdb-space" },
          { text: "Pydantic models both ways", link: "/integrations/pydantic-models" },
          { text: "Arrays and embeddings", link: "/integrations/arrays-embeddings" },
          { text: "HTTP, routes, and solver loops", link: "/integrations/http-routes-solvers" },
        ],
      },
      {
        text: "Live systems",
        link: "/live/",
        items: [
          { text: "Standing queries", link: "/live/standing-queries" },
          { text: "Reflection and steering", link: "/live/reflection" },
          { text: "Web routes", link: "/live/web-routes" },
          { text: "Multi-shot solving", link: "/live/multishot" },
          { text: "Contexts and remotes", link: "/live/contexts" },
          { text: "The remote space protocol", link: "/live/remote-protocol" },
          { text: "The Distributed Atomspace", link: "/live/das" },
          { text: "The loop stays live", link: "/live/async" },
        ],
      },
      {
        text: "Reference",
        collapsed: true,
        items: [
          { text: "Module index", link: "/reference/" },
          {
            text: "Core",
            collapsed: true,
            items: [
              { text: "petta.atoms", link: "/reference/petta-atoms" },
              { text: "petta.space", link: "/reference/petta-space" },
              { text: "petta.results", link: "/reference/petta-results" },
            ],
          },
          {
            text: "Definition",
            collapsed: true,
            items: [
              { text: "petta.ops", link: "/reference/petta-ops" },
              { text: "petta.convert", link: "/reference/petta-convert" },
              { text: "petta.casting", link: "/reference/petta-casting" },
            ],
          },
          {
            text: "Diagnostics",
            collapsed: true,
            items: [
              { text: "petta.trace", link: "/reference/petta-trace" },
              { text: "petta.lint", link: "/reference/petta-lint" },
            ],
          },
          {
            text: "Data and stores",
            collapsed: true,
            items: [
              { text: "petta.persistent", link: "/reference/petta-persistent" },
              { text: "petta.structures", link: "/reference/petta-structures" },
              { text: "petta.arrays", link: "/reference/petta-arrays" },
              { text: "petta.testing", link: "/reference/petta-testing" },
            ],
          },
          {
            text: "Distribution",
            collapsed: true,
            items: [
              { text: "petta.remote", link: "/reference/petta-remote" },
              { text: "petta.spaces", link: "/reference/petta-spaces" },
              { text: "petta.das", link: "/reference/petta-das" },
              { text: "petta.aio", link: "/reference/petta-aio" },
              { text: "petta.subscribe", link: "/reference/petta-subscribe" },
              { text: "petta.foreign", link: "/reference/petta-foreign" },
              { text: "petta.integrate", link: "/reference/petta-integrate" },
            ],
          },
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
