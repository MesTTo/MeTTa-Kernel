/*
Purpose: configure the MeTTa documentation site's navigation, rendering, and project URL.
Guarantees:
  - the top navigation offers five destinations, one per question a reader
    arrives with: learn it, build with it, connect it to something, look a
    signature up, or work on the engine
    [tested: npm run docs:build; commit=WORKTREE]
  - every page in the site is reachable from this navigation, so a written page
    cannot ship findable only by search
    [tested: test_every_site_page_is_reachable_from_the_navigation; commit=a7d2f292004fe06d7671b7931cfc2ce4620b7b35]
  - code renders in the theme pair ./highlighting.mjs builds, which is the most
    colourful bundled pair that still reads on the background VitePress paints
    a code block with, and which colours the two Python scopes no theme rules
    on [measured 2026-08-29: node scripts/measure_highlighting.mjs;
    commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
*/

import { readFileSync } from "node:fs";
import { defineConfig } from "vitepress";

import { darkTheme, lightTheme } from "./highlighting.mjs";

const mettaLanguage = {
  ...JSON.parse(readFileSync(new URL("./metta.tmLanguage.json", import.meta.url), "utf8")),
  name: "metta",
  displayName: "MeTTa",
  scopeName: "source.metta",
};

export default defineConfig({
  title: "MeTTa Kernel",
  description: "MeTTa, implemented in Prolog and C, with Python, TypeScript and C surfaces over one engine.",
  base: "/MeTTa-Kernel/",
  head: [
    ["link", { rel: "icon", type: "image/svg+xml", href: "/MeTTa-Kernel/visuals/favicon.svg" }],
  ],
  // localhost examples in docstrings are unreachable at build time by nature
  ignoreDeadLinks: [/^https?:\/\/localhost/],
  cleanUrls: true,
  // The four engine pages carry their source documents' own file names, so the
  // relative links those documents write between themselves (EXTENDING.md's
  // closing table links CODEC.md) resolve here with no edit to the sources.
  // The published URL follows this site's spelling instead of the repository's.
  rewrites: {
    "engine/EXTENDING.md": "engine/extending.md",
    "engine/KERNEL.md": "engine/kernel.md",
    "engine/CODEC.md": "engine/codec.md",
    "engine/DEVELOPING.md": "engine/developing.md",
  },
  markdown: {
    languages: [mettaLanguage],
    // ./highlighting.mjs carries the measurement these were chosen on and the
    // two Python scope rules it adds; `node scripts/measure_highlighting.mjs`
    // reprints the comparison, and with no arguments it measures the objects
    // rendered with rather than the themes they were built from.
    theme: { light: lightTheme, dark: darkTheme },
  },
  themeConfig: {
    nav: [
      { text: "Tutorials", link: "/tutorials/" },
      { text: "Guide", link: "/guide/" },
      { text: "Recipes", link: "/integrations/" },
      { text: "Reference", link: "/reference/" },
      { text: "Engine", link: "/engine/" },
      { text: "GitHub", link: "https://github.com/MesTTo/MeTTa-Kernel" },
    ],
    sidebar: [
      {
        text: "Tutorials",
        link: "/tutorials/",
        collapsed: true,
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
        collapsed: true,
        items: [
          { text: "Install and first steps", link: "/guide/getting-started" },
          { text: "Concepts and names", link: "/guide/concepts" },
          { text: "Atoms, operators, and terms", link: "/guide/atoms-terms" },
          { text: "Where code runs", link: "/guide/where-code-runs" },
          { text: "Run and query", link: "/guide/run-query" },
          { text: "Python functions in MeTTa", link: "/guide/python-functions" },
          { text: "Write MeTTa in Python", link: "/guide/define" },
          { text: "Spaces", link: "/guide/spaces" },
          { text: "The contract: how backends attach", link: "/guide/contract" },
          { text: "Data structures", link: "/guide/structures" },
          { text: "Threads, tasks, and pickling", link: "/guide/threads" },
          { text: "Observability", link: "/guide/observability" },
          { text: "Jupyter notebooks", link: "/guide/notebook" },
          { text: "Pettorch", link: "/guide/pettorch" },
        ],
      },
      // Reasoning, Integrations and Live systems asked the reader to guess
      // which of three lists held "connect MeTTa to X". They are one section
      // with three questions under it.
      {
        text: "Recipes",
        link: "/integrations/",
        collapsed: true,
        items: [
          {
            text: "Connect a data source",
            collapsed: true,
            items: [
              { text: "Overview", link: "/integrations/" },
              { text: "Dataframes", link: "/integrations/dataframes" },
              { text: "DuckDB as a space", link: "/integrations/duckdb-space" },
              { text: "SQLite BLOB images", link: "/integrations/sqlite-blobs" },
              { text: "Pydantic models both ways", link: "/integrations/pydantic-models" },
              { text: "Arrays and embeddings", link: "/integrations/arrays-embeddings" },
            ],
          },
          {
            text: "Serve it, and keep it live",
            collapsed: true,
            items: [
              { text: "Overview", link: "/live/" },
              { text: "Web routes", link: "/live/web-routes" },
              { text: "HTTP, routes, and solver loops", link: "/integrations/http-routes-solvers" },
              { text: "Standing queries", link: "/live/standing-queries" },
              { text: "Multi-shot solving", link: "/live/multishot" },
              { text: "Contexts and remotes", link: "/live/contexts" },
              { text: "Deployment as knowledge", link: "/live/boot" },
              { text: "The loop stays live", link: "/live/async" },
              { text: "The remote space protocol", link: "/live/remote-protocol" },
            ],
          },
          {
            text: "Reason with weights",
            collapsed: true,
            items: [
              { text: "Overview", link: "/reasoning/" },
              { text: "Custom matching", link: "/reasoning/matchers-measure" },
              { text: "Weighted relations", link: "/reasoning/weighted-relations" },
              { text: "Reflection and steering", link: "/live/reflection" },
            ],
          },
        ],
      },
      {
        text: "Reference",
        collapsed: true,
        items: [
          { text: "Module index", link: "/reference/" },
          { text: "The shrink ledger", link: "/reference/shrink-ledger" },
          {
            text: "Core",
            collapsed: true,
            items: [
              { text: "metta.atoms", link: "/reference/metta-atoms" },
              { text: "metta.paths", link: "/reference/metta-paths" },
              { text: "metta.Space", link: "/reference/metta-space" },
              { text: "metta.results", link: "/reference/metta-results" },
              { text: "metta.answer", link: "/reference/metta-answer" },
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
              { text: "metta.events", link: "/reference/metta-events" },
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
      // The engine and the languages sitting on it are one subject: you arrive
      // here either to change the engine or to put a fourth language on it.
      {
        text: "Engine",
        link: "/engine/",
        collapsed: true,
        items: [
          { text: "Overview", link: "/engine/" },
          { text: "Extending the engine", link: "/engine/extending" },
          { text: "The kernel", link: "/engine/kernel" },
          { text: "The wire codec", link: "/engine/codec" },
          { text: "Developing", link: "/engine/developing" },
          {
            text: "Language surfaces",
            collapsed: true,
            items: [
              { text: "Overview", link: "/extensions/" },
              { text: "Adding one", link: "/extensions/adding" },
              { text: "PyMeTTa (Python)", link: "/extensions/python/" },
              { text: "PyMeTTa tutorial", link: "/extensions/python/tutorial" },
              { text: "MeTTa-node (TypeScript)", link: "/extensions/node/" },
              { text: "MeTTa-node tutorial", link: "/extensions/node/tutorial" },
              { text: "CMeTTa (C)", link: "/extensions/cmetta/" },
              { text: "CMeTTa tutorial", link: "/extensions/cmetta/tutorial" },
              { text: "MORK (storage backend)", link: "/extensions/mork/" },
            ],
          },
        ],
      },
    ],
    search: { provider: "local" },
    socialLinks: [{ icon: "github", link: "https://github.com/MesTTo/MeTTa-Kernel" }],
    footer: {
      message: "Released under the MIT License.",
      copyright: "MesTTo",
    },
  },
});
