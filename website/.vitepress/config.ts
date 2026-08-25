/*
Purpose: configure the PeTTa documentation site's navigation, rendering, and project URL.
Guarantees: navigation advertises only live public Python modules and API pages.
[tested: npm run docs:build; commit=WORKTREE]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
*/

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
          { text: "Where code runs", link: "/guide/where-code-runs" },
          { text: "Run and query", link: "/guide/run-query" },
          { text: "Python functions in MeTTa", link: "/guide/python-functions" },
          { text: "Write MeTTa in Python", link: "/guide/define" },
          { text: "Spaces", link: "/guide/spaces" },
          { text: "Data structures", link: "/guide/structures" },
          { text: "Threads, tasks, and pickling", link: "/guide/threads" },
          { text: "Observability", link: "/guide/observability" },
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
          { text: "Deployment as knowledge", link: "/live/boot" },
          { text: "The remote space protocol", link: "/live/remote-protocol" },
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
              { text: "metta.atoms", link: "/reference/metta-atoms" },
              { text: "metta.Space", link: "/reference/metta-space" },
              { text: "metta.results", link: "/reference/metta-results" },
            ],
          },
          {
            text: "Definition",
            collapsed: true,
            items: [
              { text: "metta.ops", link: "/reference/metta-ops" },
              { text: "metta.convert", link: "/reference/metta-convert" },
              { text: "metta.casting", link: "/reference/metta-casting" },
            ],
          },
          {
            text: "Diagnostics",
            collapsed: true,
            items: [
              { text: "metta.trace", link: "/reference/metta-trace" },
              { text: "metta.derivation", link: "/reference/metta-derivation" },
              { text: "metta.lint", link: "/reference/metta-lint" },
            ],
          },
          {
            text: "Data and stores",
            collapsed: true,
            items: [
              { text: "metta.structures", link: "/reference/metta-structures" },
              { text: "metta.tables", link: "/reference/metta-tables" },
              { text: "metta.arrays", link: "/reference/metta-arrays" },
              { text: "metta.testing", link: "/reference/metta-testing" },
            ],
          },
          {
            text: "Distribution",
            collapsed: true,
            items: [
              { text: "metta.remote", link: "/reference/metta-remote" },
              { text: "metta.spaces", link: "/reference/metta-spaces" },
              { text: "metta.aio", link: "/reference/metta-aio" },
              { text: "metta.subscribe", link: "/reference/metta-subscribe" },
              { text: "metta.foreign", link: "/reference/metta-foreign" },
              { text: "metta.integrate", link: "/reference/metta-integrate" },
              { text: "metta.manifest", link: "/reference/metta-manifest" },
            ],
          },
          {
            text: "MeTTa libraries",
            collapsed: true,
            items: [
              { text: "The library reference", link: "/reference/metta-libraries" },
              { text: "The standard library, in Python", link: "/reference/stdlib-phrasebook" },
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
