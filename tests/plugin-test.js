// Unit tests for the pure parsing/summary functions of the Obsidian plugin.
// Usage: node tests/plugin-test.js
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { parseProject, summarize, filterTasks, splitCode, slugify, uniqueSlug, safeText, buildTaskBlock, addTask, removeTask, markDone, runCommand } = require("../plugin/main.js");
const { execFileSync, spawnSync } = require("child_process");
const os = require("os");

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

t("splitCode separates inline code from plain text", () => {
  assert.deepStrictEqual(splitCode("run `<branch-name>` now"), [
    { text: "run " }, { text: "<branch-name>", code: true }, { text: " now" },
  ]);
  assert.deepStrictEqual(splitCode("no code here"), [{ text: "no code here" }]);
  assert.deepStrictEqual(splitCode("`a` and `b`").filter((x) => x.code).map((x) => x.text), ["a", "b"]);
});

t("splitCode leaves an unmatched backtick as plain text", () => {
  assert.deepStrictEqual(splitCode("odd ` tick"), [{ text: "odd ` tick" }]);
  assert.deepStrictEqual(splitCode(""), []);
});

// ---- adding a personal task

t("slugify makes a short kebab-case slug", () => {
  assert.strictEqual(slugify("Fix the Café login!"), "fix-the-cafe-login");
  assert.strictEqual(slugify("one two three four five six seven"), "one-two-three-four-five");
  assert.strictEqual(slugify("¿¡!?"), "task");
});

t("uniqueSlug appends -2, -3 on collision", () => {
  assert.strictEqual(uniqueSlug("a-b", new Set()), "a-b");
  assert.strictEqual(uniqueSlug("a-b", new Set(["a-b"])), "a-b-2");
  assert.strictEqual(uniqueSlug("a-b", new Set(["a-b", "a-b-2"])), "a-b-3");
});

t("safeText wraps tag-like text and leaves the rest alone", () => {
  assert.strictEqual(safeText("use <branch-name> here"), "use `<branch-name>` here");
  assert.strictEqual(safeText("close </div> now"), "close `</div>` now");
  assert.strictEqual(safeText("already `<x>` ok"), "already `<x>` ok");
  assert.strictEqual(safeText("a < b and x <3"), "a < b and x <3");
  assert.strictEqual(safeText("see <https://example.com>"), "see <https://example.com>");
});

t("buildTaskBlock writes the exact protocol lines for a personal task", () => {
  const b = buildTaskBlock({ title: "Call the bank", description: "About the card", priority: "high", type: "chore", slug: "call-the-bank" });
  assert.strictEqual(
    b,
    "- [ ] #task owner::me status::backlog priority::high type::chore slug::call-the-bank\n" +
      "  **Title:** Call the bank\n  **Description:** About the card"
  );
});

t("buildTaskBlock sanitizes: one line, 80 chars, valid enums, safe text", () => {
  const b = buildTaskBlock({ title: "x".repeat(100) + "\nsecond", description: "", priority: "urgent", type: "weird", slug: "x" });
  const [head, title] = b.split("\n");
  assert.match(head, /priority::medium type::chore /);
  assert.strictEqual(title, "  **Title:** " + "x".repeat(80));
  assert.ok(!/Description/.test(b), "empty description is omitted");
  assert.match(buildTaskBlock({ title: "Fix <name>", slug: "f" }), /\*\*Title:\*\* Fix `<name>`/);
});

const base = fs.readFileSync(path.join(fx, "plugin/project.md"), "utf8");

t("addTask appends at the end of ## Tasks and round-trips through parseProject", () => {
  const before = parseProject(base, "atlas", "p");
  const r = addTask(base, { title: "Renew passport", description: "Before March", priority: "high", type: "chore" });
  assert.strictEqual(r.slug, "renew-passport");
  assert.ok(r.text.startsWith(base.replace(/\s+$/, "")), "existing text is untouched");
  const after = parseProject(r.text, "atlas", "p");
  assert.strictEqual(after.tasks.length, before.tasks.length + 1);
  const n = after.tasks[after.tasks.length - 1];
  assert.deepStrictEqual([n.owner, n.status, n.priority, n.type, n.title, n.description, n.checked],
    ["me", "backlog", "high", "chore", "Renew passport", "Before March", false]);
});

t("addTask avoids slug collisions and inserts before a following section", () => {
  const text = "---\nproject: p\n---\n# P\n\n## Tasks\n\n- [ ] #task owner::me status::backlog priority::low type::chore slug::buy-milk\n  **Title:** Buy milk\n\n## Notes\n\nhello\n";
  const r = addTask(text, { title: "Buy milk" });
  assert.strictEqual(r.slug, "buy-milk-2");
  assert.ok(r.text.indexOf("slug::buy-milk-2") < r.text.indexOf("## Notes"));
  assert.ok(r.text.endsWith("## Notes\n\nhello\n"));
});

t("addTask creates the ## Tasks section when it is missing", () => {
  const r = addTask("---\nproject: p\n---\n# P\n", { title: "First thing" });
  assert.match(r.text, /\n## Tasks\n\n- \[ \] #task owner::me /);
  assert.strictEqual(parseProject(r.text, "p", "p").tasks.length, 1);
});

t("addTask rejects an empty title", () => {
  assert.throws(() => addTask(base, { title: "   " }), /title/i);
});

t("the written note passes mdn-lint.sh", () => {
  const lint = path.join(__dirname, "../scripts/mdn-lint.sh");
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mdn-plugin-"));
  const f = path.join(tmp, "project.md");
  const doc = "---\ntitle: P\nproject: p\nstatus: active\nrepo: /x\ntags:\n  - project\n---\n# P\n\n> one line\n\n---\n\n## Tasks\n";
  const r = addTask(addTask(doc, { title: "First thing", priority: "low" }).text, { title: "Use <branch-name> now", description: "With <x>" });
  fs.writeFileSync(f, r.text);
  const out = spawnSync("bash", [lint, f], { encoding: "utf8" });
  assert.strictEqual(out.status, 0, out.stdout + out.stderr);
  assert.strictEqual((out.stdout + out.stderr).trim(), "");
  fs.rmSync(tmp, { recursive: true });
});

const mine = "- [ ] #task owner::me status::backlog priority::low type::chore slug::buy-milk\n  **Title:** Buy milk\n  **Description:** Two litres\n";
const agentTask = "- [ ] #task owner::agent status::backlog priority::low type::chore slug::agent-job\n  **Title:** Agent job\n";

t("removeTask deletes a middle task and leaves a single blank line", () => {
  const text = "# P\n\n## Tasks\n\n" + mine + "\n" + agentTask + "\n## Notes\n\nhello\n";
  assert.strictEqual(removeTask(text, "buy-milk"), "# P\n\n## Tasks\n\n" + agentTask + "\n## Notes\n\nhello\n");
});

t("removeTask deletes the last task and the trailing blank line", () => {
  const text = "# P\n\n## Tasks\n\n" + agentTask + "\n" + mine;
  assert.strictEqual(removeTask(text, "buy-milk"), "# P\n\n## Tasks\n\n" + agentTask);
});

t("removeTask before a following section keeps one blank line", () => {
  const text = "# P\n\n## Tasks\n\n" + mine + "\n## Notes\n\nhello\n";
  assert.strictEqual(removeTask(text, "buy-milk"), "# P\n\n## Tasks\n\n## Notes\n\nhello\n");
});

t("removeTask refuses agent tasks and unknown slugs, and does not match prefixes", () => {
  const text = mine + "\n" + agentTask;
  assert.throws(() => removeTask(text, "agent-job"), /own tasks/);
  assert.throws(() => removeTask(text, "nope"), /not found/);
  assert.throws(() => removeTask(text, "buy"), /not found/);
});

t("removeTask round-trips with addTask and keeps CRLF notes intact", () => {
  const added = addTask(base, { title: "Renew passport" });
  assert.strictEqual(removeTask(added.text, added.slug), base.replace(/\s+$/, "") + "\n");
  const crlf = ("# P\n\n## Tasks\n\n" + mine + "\n" + agentTask).replace(/\n/g, "\r\n");
  const out = removeTask(crlf, "buy-milk");
  assert.ok(!/[^\r]\n/.test(out), "line endings stay CRLF");
  assert.deepStrictEqual(parseProject(out, "p", "p").tasks.map((x) => x.slug), ["agent-job"]);
});

t("removeTask refuses a task that is in progress", () => {
  const running = mine.replace("status::backlog", "status::in-progress");
  assert.throws(() => removeTask(running, "buy-milk"), /in progress/);
});

t("markDone closes a task of yours: checkbox and status, nothing else", () => {
  for (const from of ["backlog", "in-progress", "review"]) {
    const text = "# P\n\n## Tasks\n\n" + mine.replace("status::backlog", "status::" + from) + "\n" + agentTask;
    const out = markDone(text, "buy-milk");
    assert.strictEqual(out, text.replace("- [ ] #task owner::me status::" + from, "- [x] #task owner::me status::done"));
  }
});

t("markDone refuses agent tasks, closed tasks, blocked tasks and unknown slugs", () => {
  assert.throws(() => markDone(agentTask, "agent-job"), /own tasks/);
  assert.throws(() => markDone(mine, "nope"), /not found/);
  assert.throws(() => markDone(mine.replace("[ ]", "[x]").replace("status::backlog", "status::done"), "buy-milk"), /marked done/);
  assert.throws(() => markDone(mine.replace("status::backlog", "status::blocked"), "buy-milk"), /marked done/);
});

t("markDone round-trips through parseProject, keeps CRLF and passes mdn-lint.sh", () => {
  const crlf = ("# P\n\n## Tasks\n\n" + mine + "\n" + agentTask).replace(/\n/g, "\r\n");
  const out = markDone(crlf, "buy-milk");
  assert.ok(!/[^\r]\n/.test(out), "line endings stay CRLF");
  const task = parseProject(out, "p", "p").tasks.find((x) => x.slug === "buy-milk");
  assert.deepStrictEqual([task.status, task.checked, task.owner], ["done", true, "me"]);
  const lint = path.join(__dirname, "../scripts/mdn-lint.sh");
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mdn-plugin-"));
  const f = path.join(tmp, "project.md");
  const doc = "---\ntitle: P\nproject: p\nstatus: active\nrepo: /x\ntags:\n  - project\n---\n# P\n\n> one line\n\n---\n\n## Tasks\n";
  fs.writeFileSync(f, markDone(addTask(doc, { title: "First thing" }).text, "first-thing"));
  const res = spawnSync("bash", [lint, f], { encoding: "utf8" });
  assert.strictEqual(res.status, 0, res.stdout + res.stderr);
  fs.rmSync(tmp, { recursive: true });
});

t("runCommand gives the /mdn-run line only for tasks the agent can run", () => {
  assert.strictEqual(runCommand({ slug: "buy-milk", project: "atlas", status: "backlog" }), "/mdn-run task:buy-milk project:atlas");
  assert.strictEqual(runCommand({ slug: "a", project: "p", status: "in-progress" }), "/mdn-run task:a project:p");
  for (const status of ["review", "done", "blocked"]) assert.strictEqual(runCommand({ slug: "a", project: "p", status }), "");
});

console.log("plugin tests passed (" + n + ")");
