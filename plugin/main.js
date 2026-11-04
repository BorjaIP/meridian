"use strict";

let obsidian;
try {
  obsidian = require("obsidian");
} catch (e) {
  // Outside Obsidian (unit tests) only the pure functions are used.
  obsidian = { Plugin: class {}, ItemView: class {}, PluginSettingTab: class {}, Setting: class {}, Notice: class {}, Modal: class {}, addIcon() {}, setIcon() {} };
}
const { Plugin, ItemView, PluginSettingTab, Setting, Modal, Notice, addIcon, setIcon } = obsidian;

const VIEW_TYPE = "meridian-board";
const ICON_ID = "meridian";
// Globe, tilted meridian axis and flow arcs, drawn after the Meridian icon (viewBox 0 0 100 100).
const ICON_SVG =
  '<g fill="none" stroke="currentColor" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round">' +
  '<circle cx="50" cy="52" r="19"/><ellipse cx="50" cy="52" rx="8" ry="19"/>' +
  '<path d="M31 52h38M34 42h32M34 62h32"/><path d="M60 8 41 94"/>' +
  '<path d="M26 30C12 44 12 62 28 78M74 30c14 14 14 32-2 48"/></g>';

const STATUSES = ["review", "in-progress", "backlog", "blocked", "done"];
const STATUS_LABEL = { review: "Review", "in-progress": "In progress", backlog: "Backlog", blocked: "Blocked", done: "Done" };
const PRIORITY_RANK = { high: 0, medium: 1, low: 2 };
const DEFAULTS = { root: "meridian", userName: "", owner: "agent", tab: "review", project: "all" };

// ---------------------------------------------------------------- parsing

function parseFrontmatter(lines) {
  const fm = {};
  if (lines[0] !== "---") return { fm, end: 0 };
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === "---") return { fm, end: i + 1 };
    const m = lines[i].match(/^(\w[\w-]*):\s*([^#]*?)\s*(?:#.*)?$/);
    if (m && m[2]) fm[m[1]] = m[2];
  }
  return { fm, end: 0 };
}

function parseRun(text) {
  const run = {};
  const s = text.match(/started (\d{4}-\d\d-\d\d(?: \d\d:\d\d)?)/);
  const e = text.match(/ended (\d{4}-\d\d-\d\d(?: \d\d:\d\d)?)/);
  const b = text.match(/branch (\S+)/);
  if (s) run.started = s[1];
  if (e) run.ended = e[1];
  if (b) run.branch = b[1];
  return run;
}

function parseTrace(text) {
  const trace = { commits: [], pr: null, engram: null };
  const c = text.match(/commits? ([0-9a-f, ]+?)(?: ·|$)/);
  if (c) trace.commits = c[1].split(/[,\s]+/).filter(Boolean);
  const pr = text.match(/PR #(\d+)/);
  if (pr) trace.pr = pr[1];
  const en = text.match(/engram (\S+)/);
  if (en) trace.engram = en[1];
  return trace;
}

function parseProject(text, slug, path) {
  const lines = text.split(/\r?\n/);
  const { fm, end } = parseFrontmatter(lines);
  const project = { slug, path, name: fm.title || slug, status: fm.status || "active", repo: fm.repo || "", description: "", tasks: [] };
  const quote = lines.slice(end).find((l) => l.startsWith("> "));
  if (quote) project.description = quote.slice(2).trim();

  let cur = null;
  let field = null;
  const finish = () => {
    if (!cur) return;
    cur.title = (cur.fields.title || "").trim() || cur.slug;
    cur.description = (cur.fields.description || "").trim();
    cur.acceptance = (cur.fields.acceptance || "").trim();
    cur.note = (cur.fields.note || "").trim();
    cur.run = parseRun(cur.fields.run || "");
    cur.trace = parseTrace(cur.fields.trace || "");
    delete cur.fields;
    project.tasks.push(cur);
    cur = null;
  };

  for (let i = end; i < lines.length; i++) {
    const line = lines[i];
    const head = line.match(/^- \[( |x|X)\] #task\b(.*)$/);
    if (head) {
      finish();
      cur = { project: slug, path, line: i, checked: head[1] !== " ", fields: {} };
      for (const m of head[2].matchAll(/([\w-]+)::(\S+)/g)) cur[m[1]] = m[2];
      cur.owner = cur.owner || "agent";
      cur.status = cur.status || "backlog";
      cur.priority = cur.priority || "medium";
      cur.type = cur.type || "";
      cur.slug = cur.slug || "task-" + i;
      field = null;
      continue;
    }
    if (!cur) continue;
    if (/^\S/.test(line)) { finish(); field = null; continue; }
    const f = line.match(/^\s+\*\*(\w+):\*\*\s*(.*)$/);
    if (f) {
      field = f[1].toLowerCase();
      cur.fields[field] = f[2];
    } else if (field && line.trim()) {
      cur.fields[field] += "\n" + line.trim();
    }
  }
  finish();
  return project;
}

function summarize(projects) {
  const byStatus = Object.fromEntries(STATUSES.map((s) => [s, 0]));
  let open = 0;
  for (const p of projects) {
    for (const t of p.tasks) {
      byStatus[t.status] = (byStatus[t.status] || 0) + 1;
      if (t.status !== "done") open++;
    }
  }
  return { projects: projects.filter((p) => p.status === "active").length, open, byStatus };
}

function filterTasks(tasks, f) {
  const q = (f.query || "").trim().toLowerCase();
  return tasks.filter(
    (t) =>
      (f.owner === "all" || t.owner === f.owner) &&
      (f.project === "all" || t.project === f.project) &&
      (!q || (t.title + " " + t.slug + " " + t.type).toLowerCase().includes(q))
  );
}

function sortTasks(tasks, status) {
  const stamp = (t) => t.run.ended || t.run.started || "";
  return tasks.slice().sort((a, b) => {
    if (status === "review" || status === "done") return stamp(b).localeCompare(stamp(a));
    return (PRIORITY_RANK[a.priority] ?? 1) - (PRIORITY_RANK[b.priority] ?? 1) || a.line - b.line;
  });
}

function toDate(s) {
  const m = s && s.match(/^(\d{4})-(\d\d)-(\d\d)(?: (\d\d):(\d\d))?$/);
  return m ? new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0)) : null;
}

function ago(s, now) {
  const d = toDate(s);
  if (!d) return "";
  const mins = Math.max(0, Math.round(((now || new Date()) - d) / 60000));
  if (mins < 60) return mins + "m ago";
  if (mins < 1440) return Math.round(mins / 60) + "h ago";
  return Math.round(mins / 1440) + "d ago";
}

// Splits free text into plain and inline-code parts. Meridian wraps tag-like text in backticks,
// so the board shows those parts as code instead of printing the backticks.
function splitCode(text) {
  const parts = [];
  const re = /`([^`\n]+)`/g;
  let last = 0;
  let m;
  while ((m = re.exec(text))) {
    if (m.index > last) parts.push({ text: text.slice(last, m.index) });
    parts.push({ text: m[1], code: true });
    last = m.index + m[0].length;
  }
  if (last < text.length) parts.push({ text: text.slice(last) });
  return parts;
}

function richText(el, text) {
  for (const p of splitCode(text)) {
    if (p.code) el.createEl("code", { text: p.text });
    else el.appendText(p.text);
  }
}

function hue(slug) {
  let h = 0;
  for (const c of slug) h = (h * 31 + c.charCodeAt(0)) % 360;
  return h;
}

// ---------------------------------------------------------------- adding a personal task

const PRIORITIES = ["high", "medium", "low"];
const TYPES = ["feature", "fix", "research", "chore"];
const TAG_LIKE = /<\/?[A-Za-z][A-Za-z0-9._:-]*(?:\s[^<>`]*)?\/?>/g;

// Same rule as the skills and mdn-log.sh: a bare tag-like token breaks Obsidian's rendering,
// so it is wrapped in backticks unless it is already inside inline code.
function safeText(text) {
  return text
    .split(/(`[^`]*`)/)
    .map((part, i) => (i % 2 ? part : part.replace(TAG_LIKE, (m) => "`" + m + "`")))
    .join("");
}

function slugify(title) {
  const words = title
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean)
    .slice(0, 5);
  return words.join("-") || "task";
}

function uniqueSlug(base, taken) {
  let slug = base;
  for (let n = 2; taken.has(slug); n++) slug = base + "-" + n;
  return slug;
}

const oneLine = (text, max) => String(text || "").replace(/\s+/g, " ").trim().slice(0, max);

// The protocol lines of a task owned by the human (always backlog, unchecked).
function buildTaskBlock(t) {
  const title = oneLine(t.title, 80);
  if (!title) throw new Error("A task needs a title");
  const priority = PRIORITIES.includes(t.priority) ? t.priority : "medium";
  const type = TYPES.includes(t.type) ? t.type : "chore";
  const lines = [
    "- [ ] #task owner::me status::backlog priority::" + priority + " type::" + type + " slug::" + t.slug,
    "  **Title:** " + safeText(title),
  ];
  const description = oneLine(t.description, 500);
  if (description) lines.push("  **Description:** " + safeText(description));
  return lines.join("\n");
}

// Returns the project note text with the new task at the end of `## Tasks`, plus its slug.
function addTask(text, input) {
  const eol = text.includes("\r\n") ? "\r\n" : "\n";
  const taken = new Set([...text.matchAll(/slug::(\S+)/g)].map((m) => m[1]));
  const slug = uniqueSlug(slugify(input.title), taken);
  const block = buildTaskBlock(Object.assign({}, input, { slug })).split("\n");
  const lines = text.split(/\r?\n/);
  const head = lines.findIndex((l) => /^## Tasks\s*$/.test(l));
  if (head < 0) {
    const body = text.replace(/\s+$/, "");
    return { slug, text: body + eol + eol + "## Tasks" + eol + eol + block.join(eol) + eol };
  }
  let end = lines.findIndex((l, i) => i > head && /^## /.test(l));
  if (end < 0) end = lines.length;
  let last = head;
  for (let i = head + 1; i < end; i++) if (lines[i].trim()) last = i;
  lines.splice(last + 1, 0, "", ...block);
  return { slug, text: lines.join(eol) };
}

function runCommand(t) {
  return t.status === "backlog" || t.status === "in-progress" ? "/mdn-run task:" + t.slug + " project:" + t.project : "";
}

function removeTask(text, slug) {
  const eol = text.includes("\r\n") ? "\r\n" : "\n";
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => /^- \[( |x|X)\] #task\b/.test(l) && l.split(/\s+/).includes("slug::" + slug));
  if (start < 0) throw new Error("Task not found: " + slug);
  if (!lines[start].split(/\s+/).includes("owner::me")) throw new Error("Only your own tasks can be deleted");
  if (lines[start].split(/\s+/).includes("status::in-progress")) throw new Error("A task in progress cannot be deleted");
  let end = start + 1;
  while (end < lines.length && !/^\S/.test(lines[end])) end++;
  while (end - 1 > start && !lines[end - 1].trim()) end--;
  lines.splice(start, end - start);
  if (start > 0 && !lines[start - 1].trim() && (start >= lines.length || !lines[start].trim())) lines.splice(start, 1);
  return lines.join(eol);
}

// ---------------------------------------------------------------- plugin

class MeridianPlugin extends Plugin {
  async onload() {
    this.settings = Object.assign({}, DEFAULTS, await this.loadData());
    addIcon(ICON_ID, ICON_SVG);
    this.registerView(VIEW_TYPE, (leaf) => new BoardView(leaf, this));
    this.addRibbonIcon(ICON_ID, "Open Meridian board", () => this.activate());
    this.addCommand({ id: "open-board", name: "Open board", callback: () => this.activate() });
    this.addSettingTab(new MeridianSettings(this.app, this));

    let timer = null;
    const touch = (file) => {
      const p = file && file.path;
      if (!p || !p.startsWith(this.settings.root + "/")) return;
      clearTimeout(timer);
      timer = setTimeout(() => this.refreshViews(), 400);
    };
    for (const ev of ["modify", "create", "delete", "rename"]) this.registerEvent(this.app.vault.on(ev, touch));
  }

  onunload() {
    this.app.workspace.detachLeavesOfType(VIEW_TYPE);
  }

  saveSettings() {
    return this.saveData(this.settings);
  }

  async activate() {
    let leaf = this.app.workspace.getLeavesOfType(VIEW_TYPE)[0];
    if (!leaf) {
      leaf = this.app.workspace.getLeaf("tab");
      await leaf.setViewState({ type: VIEW_TYPE, active: true });
    }
    this.app.workspace.revealLeaf(leaf);
  }

  refreshViews() {
    for (const leaf of this.app.workspace.getLeavesOfType(VIEW_TYPE)) leaf.view.refresh && leaf.view.refresh();
  }

  async loadProjects() {
    const root = this.settings.root.replace(/\/+$/, "");
    const files = this.app.vault.getMarkdownFiles().filter((f) => new RegExp("^" + root.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "/[^/]+/project\\.md$").test(f.path));
    const projects = [];
    for (const f of files) {
      const slug = f.path.split("/")[root.split("/").length];
      projects.push(parseProject(await this.app.vault.read(f), slug, f.path));
    }
    projects.sort((a, b) => a.name.localeCompare(b.name));
    return projects;
  }
}

// ---------------------------------------------------------------- view

class BoardView extends ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
    this.projects = [];
    this.expanded = new Set();
    this.query = "";
  }
  getViewType() { return VIEW_TYPE; }
  getDisplayText() { return "Meridian"; }
  getIcon() { return ICON_ID; }

  async onOpen() {
    this.contentEl.addClass("mdn-root");
    await this.refresh();
  }

  async refresh() {
    this.projects = await this.plugin.loadProjects();
    this.render();
  }

  set(key, value) {
    this.plugin.settings[key] = value;
    this.plugin.saveSettings();
    this.render();
  }

  render() {
    const el = this.contentEl;
    const scroll = el.scrollTop;
    const focus = el.querySelector(".mdn-search input:focus");
    const caret = focus ? focus.selectionStart : 0;
    el.empty();
    const s = this.plugin.settings;
    const now = new Date();
    const filters = { owner: s.owner, project: s.project, query: this.query };
    const all = this.projects.flatMap((p) => p.tasks);
    const tasks = filterTasks(all, filters);
    const scoped = this.projects.filter((p) => s.project === "all" || p.slug === s.project);
    const stats = summarize(scoped.map((p) => Object.assign({}, p, { tasks: filterTasks(p.tasks, { owner: s.owner, project: "all", query: "" }) })));

    const page = el.createDiv({ cls: "mdn-page" });
    this.header(page, now);
    this.statCards(page, stats);
    const grid = page.createDiv({ cls: "mdn-grid" });
    const main = grid.createDiv({ cls: "mdn-main" });
    const side = grid.createDiv({ cls: "mdn-side" });
    this.taskCard(main, tasks);
    this.progressCard(main);
    this.reviewCard(side, filterTasks(all, { owner: "all", project: s.project, query: "" }));
    this.activityCard(side, filterTasks(all, { owner: "all", project: s.project, query: "" }), now);

    el.scrollTop = scroll;
    if (focus) {
      const input = el.querySelector(".mdn-search input");
      input.focus();
      input.setSelectionRange(caret, caret);
    }
  }

  header(parent, now) {
    const s = this.plugin.settings;
    const h = parent.createDiv({ cls: "mdn-header" });
    const left = h.createDiv({ cls: "mdn-header-left" });
    const hour = now.getHours();
    const greet = hour < 12 ? "Good morning" : hour < 20 ? "Good afternoon" : "Good evening";
    left.createEl("h1", { text: s.userName ? greet + ", " + s.userName : greet });
    const date = now.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
    left.createDiv({ cls: "mdn-sub", text: date + " · here is what is happening across your Meridian projects" });

    const right = h.createDiv({ cls: "mdn-controls" });
    const sel = right.createEl("select", { cls: "dropdown mdn-select" });
    sel.createEl("option", { value: "all", text: "All projects" });
    for (const p of this.projects) sel.createEl("option", { value: p.slug, text: p.name });
    sel.value = s.project;
    sel.onchange = () => this.set("project", sel.value);

    const seg = right.createDiv({ cls: "mdn-seg" });
    for (const [v, label] of [["agent", "Agent"], ["me", "Me"], ["all", "All"]]) {
      const b = seg.createEl("button", { text: label, cls: s.owner === v ? "is-on" : "" });
      b.onclick = () => this.set("owner", v);
    }
    const search = right.createDiv({ cls: "mdn-search" });
    setIcon(search.createSpan({ cls: "mdn-search-icon" }), "search");
    const input = search.createEl("input", { type: "search", placeholder: "Search tasks…" });
    input.value = this.query;
    input.oninput = () => { this.query = input.value; this.render(); };
    const add = right.createEl("button", { cls: "mod-cta mdn-add" });
    setIcon(add.createSpan(), "plus");
    add.createSpan({ text: "Add task" });
    add.onclick = () => this.addTask();
    const refresh = right.createEl("button", { cls: "mdn-icon-btn", attr: { "aria-label": "Refresh" } });
    setIcon(refresh, "refresh-cw");
    refresh.onclick = () => this.refresh();
  }

  addTask() {
    if (!this.projects.length) {
      new Notice("No Meridian project found under “" + this.plugin.settings.root + "/”.");
      return;
    }
    const current = this.plugin.settings.project;
    const start = this.projects.find((p) => p.slug === current) || this.projects.find((p) => p.status === "active") || this.projects[0];
    new AddTaskModal(this.app, this.projects, start.slug, async (input) => {
      const file = this.app.vault.getAbstractFileByPath(input.project.path);
      if (!file) throw new Error("Project note not found: " + input.project.path);
      let slug = "";
      await this.app.vault.process(file, (data) => {
        const r = addTask(data, input);
        slug = r.slug;
        return r.text;
      });
      // Show it right away: it is a task of yours, in the backlog of that project.
      Object.assign(this.plugin.settings, { owner: "me", tab: "backlog", project: input.project.slug });
      await this.plugin.saveSettings();
      new Notice("Task added: " + slug);
      await this.refresh();
    }).open();
  }

  deleteTask(t) {
    new ConfirmDeleteModal(this.app, t.title, async () => {
      const file = this.app.vault.getAbstractFileByPath(t.path);
      if (!file) throw new Error("Project note not found: " + t.path);
      await this.app.vault.process(file, (data) => removeTask(data, t.slug));
      this.expanded.delete(t.path + "#" + t.slug);
      new Notice("Task deleted: " + t.slug);
      await this.refresh();
    }).open();
  }

  statCards(parent, stats) {
    const row = parent.createDiv({ cls: "mdn-stats" });
    const card = (label, value, sub, tone, icon) => {
      const c = row.createDiv({ cls: "mdn-stat" });
      const l = c.createDiv({ cls: "mdn-stat-label" });
      setIcon(l.createSpan(), icon);
      l.createSpan({ text: label });
      c.createDiv({ cls: "mdn-stat-value " + (tone || ""), text: String(value) });
      c.createDiv({ cls: "mdn-stat-sub " + (tone || ""), text: sub });
    };
    const b = stats.byStatus;
    card("Active projects", stats.projects, this.projects.length - stats.projects + " paused", "", "folder-kanban");
    card("Open tasks", stats.open, b["in-progress"] + " in progress", "", "circle-dashed");
    card("In review", b.review, "waiting for you", b.review ? "is-warn" : "", "eye");
    card("Blocked", b.blocked, b.blocked ? "need attention" : "all clear", b.blocked ? "is-bad" : "is-good", "octagon-alert");
  }

  taskCard(parent, tasks) {
    const s = this.plugin.settings;
    const card = parent.createDiv({ cls: "mdn-card" });
    const head = card.createDiv({ cls: "mdn-card-head" });
    head.createEl("h2", { text: s.owner === "all" ? "Tasks" : s.owner === "me" ? "My tasks" : "Agent tasks" });
    const tabs = head.createDiv({ cls: "mdn-tabs" });
    for (const st of STATUSES) {
      const n = tasks.filter((t) => t.status === st).length;
      const b = tabs.createEl("button", { cls: s.tab === st ? "is-on" : "" });
      b.createSpan({ text: STATUS_LABEL[st] });
      b.createSpan({ cls: "mdn-count", text: String(n) });
      b.onclick = () => this.set("tab", st);
    }
    const list = card.createDiv({ cls: "mdn-list" });
    const rows = sortTasks(tasks.filter((t) => t.status === s.tab), s.tab);
    if (!rows.length) list.createDiv({ cls: "mdn-empty", text: "Nothing in " + STATUS_LABEL[s.tab].toLowerCase() + "." });
    for (const t of rows) this.taskRow(list, t, true);
  }

  taskRow(parent, t, showProject) {
    const key = t.path + "#" + t.slug;
    const row = parent.createDiv({ cls: "mdn-row" + (this.expanded.has(key) ? " is-open" : "") });
    const line = row.createDiv({ cls: "mdn-row-line" });
    line.createSpan({ cls: "mdn-status is-" + t.status });
    richText(line.createSpan({ cls: "mdn-title" }), t.title);
    if (t.type) line.createSpan({ cls: "mdn-chip", text: t.type });
    if (t.owner === "me") line.createSpan({ cls: "mdn-chip is-me", text: "me" });
    const meta = line.createDiv({ cls: "mdn-meta" });
    if (showProject) {
      const p = meta.createSpan({ cls: "mdn-proj" });
      p.createSpan({ cls: "mdn-dot", attr: { style: "background:hsl(" + hue(t.project) + " 60% 55%)" } });
      p.createSpan({ text: t.project });
    }
    const bars = meta.createSpan({ cls: "mdn-prio", attr: { "aria-label": t.priority } });
    const lvl = { high: 3, medium: 2, low: 1 }[t.priority] || 2;
    for (let i = 1; i <= 3; i++) bars.createSpan({ cls: i <= lvl ? "on" : "" });
    meta.createSpan({ cls: "mdn-when", text: ago(t.run.ended || t.run.started, new Date()) || "—" });
    line.onclick = () => {
      this.expanded.has(key) ? this.expanded.delete(key) : this.expanded.add(key);
      row.toggleClass("is-open", this.expanded.has(key));
    };

    const d = row.createDiv({ cls: "mdn-detail" });
    const field = (label, text) => {
      if (!text) return;
      const f = d.createDiv({ cls: "mdn-field" });
      f.createDiv({ cls: "mdn-field-label", text: label });
      richText(f.createDiv({ cls: "mdn-field-text" }), text);
    };
    field("Description", t.description);
    field("Acceptance", t.acceptance);
    field("Note", t.note);
    const command = runCommand(t);
    if (command) {
      const f = d.createDiv({ cls: "mdn-field" });
      f.createDiv({ cls: "mdn-field-label", text: "Command" });
      const cmd = f.createDiv({ cls: "mdn-cmd-row" });
      const input = cmd.createEl("input", { cls: "mdn-cmd", attr: { type: "text", readonly: "" } });
      input.value = command;
      input.onfocus = () => input.select();
      const copy = cmd.createEl("button", { text: "Copy" });
      copy.onclick = async (e) => {
        e.stopPropagation();
        await navigator.clipboard.writeText(command);
        new Notice("Command copied");
      };
    }
    const facts = [];
    if (t.run.branch) facts.push("branch " + t.run.branch);
    if (t.run.started) facts.push("started " + t.run.started);
    if (t.run.ended) facts.push("ended " + t.run.ended);
    if (t.trace.commits.length) facts.push(t.trace.commits.length + " commits");
    if (t.trace.pr) facts.push("PR #" + t.trace.pr);
    if (facts.length) d.createDiv({ cls: "mdn-facts", text: facts.join(" · ") });
    const open = d.createEl("button", { cls: "mdn-open", text: "Open in note" });
    open.onclick = async (e) => {
      e.stopPropagation();
      const file = this.app.vault.getAbstractFileByPath(t.path);
      if (file) await this.app.workspace.getLeaf("tab").openFile(file, { eState: { line: t.line } });
    };
    if (t.owner === "me" && t.status !== "in-progress") {
      const del = d.createEl("button", { cls: "mdn-delete", text: "Delete task" });
      del.onclick = (e) => {
        e.stopPropagation();
        this.deleteTask(t);
      };
    }
  }

  progressCard(parent) {
    const s = this.plugin.settings;
    const card = parent.createDiv({ cls: "mdn-card" });
    const head = card.createDiv({ cls: "mdn-card-head" });
    head.createEl("h2", { text: "Project progress" });
    if (s.project !== "all") {
      const b = head.createEl("button", { cls: "mdn-link", text: "All projects" });
      b.onclick = () => this.set("project", "all");
    }
    const table = card.createDiv({ cls: "mdn-table" });
    const hd = table.createDiv({ cls: "mdn-tr is-head" });
    for (const c of ["Project", "Status", "Progress", "Review", "Open"]) hd.createDiv({ text: c });
    for (const p of this.projects) {
      const done = p.tasks.filter((t) => t.status === "done").length;
      const pct = p.tasks.length ? Math.round((100 * done) / p.tasks.length) : 0;
      const tr = table.createDiv({ cls: "mdn-tr is-click" + (s.project === p.slug ? " is-on" : "") });
      const name = tr.createDiv({ cls: "mdn-td-name" });
      name.createSpan({ cls: "mdn-dot", attr: { style: "background:hsl(" + hue(p.slug) + " 60% 55%)" } });
      name.createSpan({ text: p.name });
      tr.createDiv().createSpan({ cls: "mdn-pill", text: p.status });
      const bar = tr.createDiv({ cls: "mdn-bar-cell" });
      bar.createDiv({ cls: "mdn-bar" }).createDiv({ cls: "mdn-bar-fill", attr: { style: "width:" + pct + "%" } });
      bar.createSpan({ text: pct + "%" });
      tr.createDiv({ text: String(p.tasks.filter((t) => t.status === "review").length) });
      tr.createDiv({ text: String(p.tasks.filter((t) => t.status !== "done").length) });
      tr.onclick = () => this.set("project", s.project === p.slug ? "all" : p.slug);
    }
    if (!this.projects.length) table.createDiv({ cls: "mdn-empty", text: "No project.md found under “" + s.root + "/”." });
  }

  reviewCard(parent, tasks) {
    const card = parent.createDiv({ cls: "mdn-card" });
    const head = card.createDiv({ cls: "mdn-card-head" });
    head.createEl("h2", { text: "Waiting for your review" });
    const rows = sortTasks(tasks.filter((t) => t.status === "review"), "review");
    head.createSpan({ cls: "mdn-count", text: String(rows.length) });
    const list = card.createDiv({ cls: "mdn-side-list" });
    if (!rows.length) list.createDiv({ cls: "mdn-empty", text: "Nothing to review." });
    for (const t of rows.slice(0, 8)) {
      const r = list.createDiv({ cls: "mdn-side-row" });
      r.createSpan({ cls: "mdn-dot", attr: { style: "background:hsl(" + hue(t.project) + " 60% 55%)" } });
      richText(r.createSpan({ cls: "mdn-side-title" }), t.title);
      r.createSpan({ cls: "mdn-when", text: ago(t.run.ended, new Date()) });
      r.onclick = async () => {
        const file = this.app.vault.getAbstractFileByPath(t.path);
        if (file) await this.app.workspace.getLeaf("tab").openFile(file, { eState: { line: t.line } });
      };
    }
    if (rows.length > 8) list.createDiv({ cls: "mdn-more", text: "+" + (rows.length - 8) + " more" });
  }

  activityCard(parent, tasks, now) {
    const card = parent.createDiv({ cls: "mdn-card" });
    card.createDiv({ cls: "mdn-card-head" }).createEl("h2", { text: "Recent activity" });
    const events = [];
    for (const t of tasks) {
      if (t.run.ended) events.push({ at: t.run.ended, verb: "finished", t });
      else if (t.run.started) events.push({ at: t.run.started, verb: "started", t });
    }
    events.sort((a, b) => b.at.localeCompare(a.at));
    const list = card.createDiv({ cls: "mdn-side-list" });
    if (!events.length) list.createDiv({ cls: "mdn-empty", text: "No runs recorded yet." });
    for (const e of events.slice(0, 6)) {
      const r = list.createDiv({ cls: "mdn-side-row is-activity" });
      const text = r.createDiv({ cls: "mdn-side-title" });
      text.createSpan({ cls: "mdn-verb", text: "Agent " + e.verb + " " });
      richText(text.createSpan(), e.t.title);
      r.createSpan({ cls: "mdn-when", text: ago(e.at, now) });
    }
  }
}

// ---------------------------------------------------------------- add-task modal

class AddTaskModal extends Modal {
  constructor(app, projects, startSlug, onSubmit) {
    super(app);
    this.projects = projects;
    this.onSubmit = onSubmit;
    this.values = { title: "", description: "", project: startSlug, priority: "medium", type: "chore" };
  }

  onOpen() {
    const { contentEl } = this;
    contentEl.addClass("mdn-modal");
    contentEl.createEl("h2", { text: "Add a task for yourself" });
    contentEl.createDiv({ cls: "mdn-modal-hint", text: "It is written to the project note as your own backlog task. No AI involved." });

    new Setting(contentEl).setName("Title").addText((t) => {
      t.setPlaceholder("What do you need to do?").onChange((v) => (this.values.title = v));
      t.inputEl.maxLength = 80;
      t.inputEl.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); this.submit(); } });
      setTimeout(() => t.inputEl.focus(), 0);
    });
    new Setting(contentEl).setName("Description").setDesc("Optional.").addTextArea((t) => {
      t.onChange((v) => (this.values.description = v));
      t.inputEl.rows = 3;
    });
    new Setting(contentEl).setName("Project").addDropdown((d) => {
      for (const p of this.projects) d.addOption(p.slug, p.name);
      d.setValue(this.values.project).onChange((v) => (this.values.project = v));
    });
    new Setting(contentEl).setName("Priority").addDropdown((d) => {
      for (const v of PRIORITIES) d.addOption(v, v);
      d.setValue(this.values.priority).onChange((v) => (this.values.priority = v));
    });
    new Setting(contentEl).setName("Type").addDropdown((d) => {
      for (const v of TYPES) d.addOption(v, v);
      d.setValue(this.values.type).onChange((v) => (this.values.type = v));
    });

    this.error = contentEl.createDiv({ cls: "mdn-modal-error" });
    const row = contentEl.createDiv({ cls: "modal-button-container" });
    const ok = row.createEl("button", { cls: "mod-cta", text: "Add task" });
    ok.onclick = () => this.submit();
    row.createEl("button", { text: "Cancel" }).onclick = () => this.close();
  }

  async submit() {
    const title = this.values.title.trim();
    if (!title) {
      this.error.setText("Write a title first.");
      return;
    }
    const project = this.projects.find((p) => p.slug === this.values.project);
    try {
      await this.onSubmit(Object.assign({}, this.values, { title, project }));
      this.close();
    } catch (e) {
      this.error.setText(String(e && e.message ? e.message : e));
    }
  }

  onClose() {
    this.contentEl.empty();
  }
}

class ConfirmDeleteModal extends Modal {
  constructor(app, title, onConfirm) {
    super(app);
    this.title = title;
    this.onConfirm = onConfirm;
  }

  onOpen() {
    const { contentEl } = this;
    contentEl.addClass("mdn-modal");
    contentEl.createEl("h2", { text: "Delete this task?" });
    richText(contentEl.createDiv({ cls: "mdn-modal-hint" }), this.title);
    contentEl.createDiv({ cls: "mdn-modal-hint", text: "It is removed from the project note. This cannot be undone from the board." });
    this.error = contentEl.createDiv({ cls: "mdn-modal-error" });
    const row = contentEl.createDiv({ cls: "modal-button-container" });
    const ok = row.createEl("button", { cls: "mod-warning", text: "Delete" });
    ok.onclick = async () => {
      try {
        await this.onConfirm();
        this.close();
      } catch (e) {
        this.error.setText(String(e && e.message ? e.message : e));
      }
    };
    row.createEl("button", { text: "Cancel" }).onclick = () => this.close();
  }

  onClose() {
    this.contentEl.empty();
  }
}

// ---------------------------------------------------------------- settings

class MeridianSettings extends PluginSettingTab {
  constructor(app, plugin) {
    super(app, plugin);
    this.plugin = plugin;
  }
  display() {
    const { containerEl } = this;
    containerEl.empty();
    new Setting(containerEl)
      .setName("Meridian folder")
      .setDesc("Vault folder that holds one subfolder per project, each with a project.md.")
      .addText((t) => t.setValue(this.plugin.settings.root).onChange(async (v) => {
        this.plugin.settings.root = v.trim() || DEFAULTS.root;
        await this.plugin.saveSettings();
        this.plugin.refreshViews();
      }));
    new Setting(containerEl)
      .setName("Your name")
      .setDesc("Used in the greeting. Optional.")
      .addText((t) => t.setValue(this.plugin.settings.userName).onChange(async (v) => {
        this.plugin.settings.userName = v.trim();
        await this.plugin.saveSettings();
        this.plugin.refreshViews();
      }));
  }
}

module.exports = MeridianPlugin;
Object.assign(module.exports, { default: MeridianPlugin, parseProject, summarize, filterTasks, sortTasks, ago, splitCode, slugify, uniqueSlug, safeText, buildTaskBlock, addTask, removeTask, runCommand });
