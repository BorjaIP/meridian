// Unit tests for the pure parsing/summary functions of the Obsidian plugin.
// Usage: node tests/plugin-test.js
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { parseProject, summarize, filterTasks } = require("../plugin/main.js");

const fx = path.join(__dirname, "fixtures");
let n = 0;
const t = (name, fn) => { fn(); n++; console.log("ok   " + name); };

const demo = fs.readFileSync(path.join(fx, "plugin/project.md"), "utf8");
const atlas = parseProject(demo, "atlas", "meridian/atlas/project.md");

t("frontmatter and description", () => {
  assert.strictEqual(atlas.name, "Atlas Notes");
  assert.strictEqual(atlas.status, "active");
  assert.match(atlas.description, /Synthetic project/);
});

t("task fields, title and run", () => {
  const s = atlas.tasks.find((x) => x.slug === "sync-engine-rewrite");
  assert.strictEqual(s.status, "review");
  assert.strictEqual(s.owner, "agent");
  assert.strictEqual(s.priority, "high");
  assert.strictEqual(s.title, "Rewrite the sync engine around an append-only change log");
  assert.strictEqual(s.run.branch, "feat/change-log");
  assert.strictEqual(s.run.started, "2026-10-10 08:10");
  assert.strictEqual(s.run.ended, "2026-10-10 11:45");
  assert.deepStrictEqual(s.trace.commits, ["abc1234", "def5678"]);
});

t("continuation lines extend the previous field", () => {
  const s = atlas.tasks.find((x) => x.slug === "sync-engine-rewrite");
  assert.match(s.description, /change log\.\s+Keep the old protocol/);
});

t("task line numbers point at the checkbox line", () => {
  const lines = demo.split("\n");
  for (const x of atlas.tasks) assert.match(lines[x.line], /^- \[[ x]\] #task /);
});

t("every task line of the fixture is parsed", () => {
  const count = demo.split("\n").filter((l) => /^- \[[ x]\] #task /.test(l)).length;
  assert.strictEqual(atlas.tasks.length, count);
});

t("title falls back to the slug", () => {
  const p = parseProject("# X\n\n- [ ] #task owner::me status::backlog priority::low type::chore slug::no-title\n", "x", "x");
  assert.strictEqual(p.tasks[0].title, "no-title");
});

t("summarize counts by status and flags", () => {
  const s = summarize([atlas]);
  const total = Object.values(s.byStatus).reduce((a, b) => a + b, 0);
  assert.strictEqual(total, atlas.tasks.length);
  assert.strictEqual(s.projects, 1);
  assert.strictEqual(s.open, atlas.tasks.filter((x) => x.status !== "done").length);
});

t("filterTasks by owner, project and query", () => {
  const all = atlas.tasks;
  assert.ok(filterTasks(all, { owner: "agent", project: "all", query: "" }).every((x) => x.owner === "agent"));
  assert.strictEqual(filterTasks(all, { owner: "all", project: "other", query: "" }).length, 0);
  const q = filterTasks(all, { owner: "all", project: "all", query: "SYNC ENGINE" });
  assert.ok(q.length >= 1 && q.every((x) => /sync engine/i.test(x.title + x.slug)));
});

console.log("plugin tests passed (" + n + ")");
