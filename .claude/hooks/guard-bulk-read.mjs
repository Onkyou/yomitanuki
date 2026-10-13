#!/usr/bin/env node
/**
 * PreToolUse guard: keep bulk file contents out of a long-lived context.
 *
 * Claude Code port of `.opencode/plugins/check-file-size.ts`, with two
 * differences the harness makes possible:
 *
 *   1. The hook payload carries `agent_type` (present inside a subagent,
 *      absent on a session's main thread), so there is no sessionID -> agent
 *      bookkeeping to maintain.
 *   2. A denial can carry a payload. Instead of only refusing the read, the
 *      guard returns a symbol outline of the file, so the very next read is a
 *      targeted `offset`/`limit` window rather than a wasted turn.
 *
 * SCOPE, stated honestly: this is a guard against accidental bulk reads, not a
 * seal against deliberate ones. It understands the reader commands below; a
 * determined caller can still use `awk 1`, `grep ''`, `perl -pe`, or a
 * here-doc. Two gaps are deliberate: `awk`/`grep`/`perl` are left alone because
 * narrowing them would block the filtered reads the guard exists to encourage,
 * and a path written relative to an earlier `cd` in the same command line
 * cannot be resolved, because the hook runs in the session's cwd and does not
 * execute the `cd`. An absolute path after a `cd` IS caught. The Read tool path
 * is comprehensive; only the Bash path is advisory.
 *
 * Fails open: any unexpected condition exits 0 with no output, and the read
 * proceeds. A broken guard must never be able to block work.
 *
 * Env (read from the hook PROCESS's environment — settings.json's `env` block
 * does not reach it, so these must be exported before launching Claude Code):
 *   SHUNT=0             disable the guard entirely
 *   SHUNT_MIN_LINES=N       code threshold in lines (default 350; invalid ignored)
 *   SHUNT_DOC_MIN_LINES=N   threshold for .md/.mdx/.txt/.rst/.adoc (default 1200)
 *   SHUNT_MAIN=0        exempt the session's main thread
 *   SHUNT_AGENTS=a,b    override the guarded subagent list ("" = no subagents)
 */
import fs from "node:fs";
import path from "node:path";

const DEFAULT_THRESHOLD = 350;
const DEFAULT_DOC_THRESHOLD = 1200;

/** An unparseable threshold must not silently disable the guard. */
function envThreshold(name, fallback) {
  const n = parseInt(process.env[name] ?? "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
const THRESHOLD = envThreshold("SHUNT_MIN_LINES", DEFAULT_THRESHOLD);
const DOC_THRESHOLD = envThreshold("SHUNT_DOC_MIN_LINES", DEFAULT_DOC_THRESHOLD);

/**
 * Prose is read linearly; code is looked up. A spec, plan, ADR or skill exists
 * to be held whole by whoever is planning from it, and 41% of this repo's specs
 * and plans exceed the code threshold — so applying one number to both makes the
 * guard fight the orchestrator's actual job. Documents get their own, larger
 * limit. Above even that, a heading outline is the right affordance anyway.
 */
const DOC_EXTS = new Set([".md", ".mdx", ".txt", ".rst", ".adoc"]);

function isDoc(filePath) {
  return DOC_EXTS.has(path.extname(filePath).toLowerCase());
}

function thresholdFor(filePath) {
  return isDoc(filePath) ? DOC_THRESHOLD : THRESHOLD;
}

/**
 * Subagents whose bulk reads are blocked. These are the agent_type values this
 * harness actually produces — the `.opencode/agents/reviewer-*` names are NOT
 * reachable here and listing them would only misrepresent coverage.
 *
 * Reviewers are guarded: a reviewer that spends its budget on I/O returns an
 * empty verdict, which the pipeline has historically misread as approval (see
 * .opencode/retros/2026-08-11-subagent-token-silence.md). Implementation and
 * search agents (builder, bulk-reader, Explore, general-purpose) are exempt --
 * they need whole files, and their contexts are short-lived and isolated.
 */
const DEFAULT_SHUNT_AGENTS = [
  "agent-skills:code-reviewer",
  "agent-skills:security-auditor",
  "agent-skills:test-engineer",
];

/** Emit nothing and let the tool call through. */
function allow() {
  process.exit(0);
}

function deny(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    }),
    // Exit only once stdout has drained, or a large payload can be truncated.
    () => process.exit(0),
  );
}

function guardedAgents() {
  const raw = process.env.SHUNT_AGENTS;
  if (raw === undefined) return new Set(DEFAULT_SHUNT_AGENTS);
  return new Set(raw.split(",").map((s) => s.trim()).filter(Boolean));
}

/**
 * `agent_type` is absent on a session's main thread and set to the agent name
 * inside a subagent. The main thread is the longest-lived context in the
 * harness, so it is guarded by default.
 */
function isGuarded(agentType) {
  if (process.env.SHUNT === "0") return false;
  if (!agentType) return process.env.SHUNT_MAIN !== "0";
  return guardedAgents().has(agentType);
}

/**
 * Files whose contents must never be summarised into a denial message.
 *
 * The guard reads with plain `fs.readFileSync`, inside a hook that the
 * permission layer does not mediate. Whether `permissions.deny` happens to be
 * evaluated first is an ordering detail, not a guarantee we control, so the
 * guard refuses these itself rather than relying on it.
 */
const SENSITIVE = /(^\.env($|\.)|secret|credential|password|token|\.pem$|\.key$|\.p12$|^id_(rsa|ed25519)|\.pfx$)/i;

function isSensitive(filePath) {
  return SENSITIVE.test(path.basename(filePath));
}

/** Outline patterns per extension: the lines worth knowing a file contains. */
const OUTLINE_PATTERNS = [
  { ext: [".go"], re: /^(func|type|const|var|package)\s/ },
  { ext: [".ts", ".tsx", ".js", ".jsx", ".mjs"], re: /^\s*(export\s+)?(async\s+)?(function|class|interface|type|const|enum)\s/ },
  { ext: [".md", ".mdx"], re: /^#{1,4}\s/ },
  { ext: [".sql"], re: /^\s*(CREATE|ALTER|DROP|INSERT INTO|--\s*\+goose)/i },
  { ext: [".py"], re: /^\s*(def|class|@)\s*/ },
  { ext: [".dart"], re: /^(abstract |sealed |final |base |interface |mixin )*(class|enum|mixin|extension|typedef)\s|^(void|Future|Stream|[A-Z][\w<>?,\s]*)\s+\w+\(|^(@\w+|part |library |import )/ },
  { ext: [".sh", ".bash"], re: /^\s*(function\s+\w+|\w+\s*\(\)\s*\{|#\s)/ },
  { ext: [".yaml", ".yml"], re: /^[A-Za-z_][\w-]*:/ },
  { ext: [".tf"], re: /^(resource|module|variable|output|data|locals)\s/ },
];

const MAX_OUTLINE_ENTRIES = 60;
const MAX_ENTRY_CHARS = 90;

/**
 * Reduce a matched line to its declaration, dropping any value.
 *
 * `const apiKey = "sk-live-..."` and `db_password: hunter2` both match an
 * outline pattern, and emitting the whole line would put the secret into the
 * very context the guard exists to protect. Everything from the first `=` or
 * `:` is a value, not a name, so it is cut.
 */
function declarationOnly(line) {
  const trimmed = line.trim();
  const cut = trimmed.search(/[=:]/);
  const head = cut === -1 ? trimmed : trimmed.slice(0, cut).trim();
  return head.length > MAX_ENTRY_CHARS ? `${head.slice(0, MAX_ENTRY_CHARS)}…` : head;
}

/**
 * Build a compact `line: declaration` index of a file. Costs ~60 lines of
 * context in place of the hundreds the blocked read would have cost, and tells
 * the model which window to ask for next.
 */
function outline(filePath, lines) {
  const ext = path.extname(filePath).toLowerCase();
  const pattern = OUTLINE_PATTERNS.find((p) => p.ext.includes(ext));
  if (!pattern) return null;

  let hits = [];
  for (let i = 0; i < lines.length; i++) {
    if (pattern.re.test(lines[i])) {
      const decl = declarationOnly(lines[i]);
      if (decl) hits.push(`${i + 1}: ${decl}`);
    }
  }
  if (hits.length === 0) return null;

  // Too many symbols would reintroduce the cost we are avoiding: sample evenly.
  let truncated = false;
  if (hits.length > MAX_OUTLINE_ENTRIES) {
    const step = hits.length / MAX_OUTLINE_ENTRIES;
    const sampled = [];
    for (let i = 0; i < MAX_OUTLINE_ENTRIES; i++) sampled.push(hits[Math.floor(i * step)]);
    hits = sampled;
    truncated = true;
  }
  return { hits, truncated };
}

function denialFor(filePath, totalLines, what) {
  const limit = thresholdFor(filePath);
  // A document this large is past the point where holding it whole helps, but
  // its outline is a heading tree — so the remedy is to pick sections, NOT to
  // delegate. A digest of a spec is not something you can plan or build from.
  const remedies = isDoc(filePath)
    ? [
        `  1. Read the sections you need: Read(file_path, offset: <line>, limit: <= ${limit}). The outline below is this document's heading tree — use it to choose.`,
        "  2. Grep for the specific heading or term if you only need one passage.",
        `  3. Only if your question is a lookup rather than the basis for work: Agent(subagent_type: "bulk-reader", …). Never plan or implement from a digest of a spec.`,
      ]
    : [
        `  1. Read a targeted window: Read(file_path, offset: <line>, limit: <= ${limit}) — always allowed, even on a large file.`,
        "  2. Grep for what you actually need (with -n and -C) rather than reading the file.",
        `  3. Delegate the whole-file question: Agent(subagent_type: "bulk-reader", prompt: "<specific question>\\nFiles: ${filePath}"). It reads on a cheap model in its own context and returns only the answer, with file:line citations.`,
      ];
  const parts = [
    `BLOCK: ${what} would put ${totalLines} lines of '${filePath}' into your context (threshold ${limit}${isDoc(filePath) ? ", the document limit" : ""}).`,
    "",
    "Do ONE of these instead:",
    ...remedies,
    "",
    "Do not retry this read — it will be blocked again.",
  ];

  let body = null;
  try {
    if (!isSensitive(filePath)) {
      body = outline(filePath, readTextLines(filePath));
    }
  } catch {
    /* unreadable — the denial still stands, just without an outline */
  }
  if (body) {
    parts.push(
      "",
      `Outline of '${filePath}'${body.truncated ? " (sampled)" : ""} — pick a window from this:`,
      ...body.hits,
    );
  }
  return parts.join("\n");
}

/** True for a buffer that is not text — binary reads are none of our business. */
function isBinary(buf) {
  const n = Math.min(buf.length, 8000);
  for (let i = 0; i < n; i++) if (buf[i] === 0) return true;
  return false;
}

/**
 * Line count as `wc -l` means it: a trailing newline terminates the last line,
 * it does not start a new empty one. Splitting the raw text would report N+1
 * for every normal file and block a file with exactly THRESHOLD lines.
 * Returns null for a binary file.
 */
function countLines(filePath) {
  const buf = fs.readFileSync(filePath);
  if (isBinary(buf)) return null;
  const text = buf.toString("utf-8");
  if (text === "") return 0;
  return (text.endsWith("\n") ? text.slice(0, -1) : text).split("\n").length;
}

function readTextLines(filePath) {
  const buf = fs.readFileSync(filePath);
  if (isBinary(buf)) throw new Error("binary");
  const text = buf.toString("utf-8");
  return (text.endsWith("\n") ? text.slice(0, -1) : text).split("\n");
}

/* ------------------------------ Bash path ------------------------------- */

/** Readers that emit the whole file regardless of flags. */
const WHOLE_FILE_READERS = new Set(["cat", "less", "more", "nl", "tac"]);
/** Readers whose emitted line count depends on flags. */
const WINDOWED_READERS = new Set(["head", "tail", "sed"]);

/**
 * Lines head/tail will emit. Returns Infinity for the forms that mean "most of
 * the file": `tail -n +N` streams from N to EOF, `head -n -N` prints all but
 * the last N, and `-c/--bytes` is not a line count at all.
 */
function headTailLines(tokens) {
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === "-c" || t === "--bytes" || t.startsWith("-c") || t.startsWith("--bytes=")) {
      return Infinity;
    }
    let raw = null;
    if ((t === "-n" || t === "--lines") && i + 1 < tokens.length) raw = tokens[i + 1];
    else if (t.startsWith("-n") && t.length > 2) raw = t.slice(2);
    else if (t.startsWith("--lines=")) raw = t.slice(8);
    else if (/^-\d+$/.test(t)) raw = t.slice(1);
    if (raw === null) continue;
    if (raw.startsWith("+") || raw.startsWith("-")) return Infinity;
    const n = parseInt(raw, 10);
    if (Number.isFinite(n)) return n;
  }
  return 10;
}

/**
 * Lines `sed` will emit. Without -n sed echoes everything. With -n we only
 * understand explicit numeric ranges (`-n '12,80p'`), which is the windowed
 * form this project's own instructions recommend; any other -n script is
 * assumed to be a filter and allowed.
 */
function sedLines(tokens) {
  if (!tokens.some((t) => t === "-n" || (/^-[a-z]*n[a-z]*$/.test(t) && !t.startsWith("--")))) {
    return Infinity;
  }
  let total = 0;
  let sawRange = false;
  for (const t of tokens) {
    const m = /(\d+)\s*,\s*(\d+)\s*p/.exec(t.replace(/^['"]|['"]$/g, ""));
    if (m) {
      sawRange = true;
      total += Math.max(0, parseInt(m[2], 10) - parseInt(m[1], 10) + 1);
    }
  }
  return sawRange ? total : 0;
}

/**
 * Split a command line into statements whose output reaches the context.
 *
 * `;`, `&&` and `||` each start a new statement, so a reader that follows a
 * `cd` is caught. A statement containing a pipe is skipped: its output goes to
 * the next stage, which is the filtering the guard wants to encourage.
 *
 * A here-doc body is data, not commands. Everything from the first `<<` is
 * dropped before splitting — otherwise prose inside a here-doc gets split on
 * `&&` and a sentence that happens to mention a reader is read as a command.
 * That is not hypothetical: it blocked this file's own last edit.
 */
function contextBearingStatements(command) {
  const heredoc = command.indexOf("<<");
  return (heredoc === -1 ? command : command.slice(0, heredoc))
    .split(/;|&&|\|\|/)
    .filter((s) => !s.includes("|"))
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Strip env assignments and wrappers, returning [readerName, argTokens]. */
function readerOf(statement) {
  const tokens = statement.split(/\s+/).filter(Boolean);
  let i = 0;
  while (i < tokens.length && (/^[A-Za-z_][\w]*=/.test(tokens[i]) || tokens[i] === "command" || tokens[i] === "builtin")) {
    i++;
  }
  if (i >= tokens.length) return null;
  const name = path.basename(tokens[i]);
  if (!WHOLE_FILE_READERS.has(name) && !WINDOWED_READERS.has(name)) return null;
  return [name, tokens.slice(i + 1)];
}

/**
 * Every file operand a reader targets, and whether an operand looked like a
 * path we could not resolve (an unexpanded glob, which would otherwise let a
 * whole directory through unexamined).
 */
function resolveTargets(tokens) {
  const files = [];
  let unresolvedGlob = false;
  for (const rawToken of tokens) {
    const token = rawToken.replace(/^['"]|['"]$/g, "");
    if (!token || token.startsWith("-")) continue;
    if (/[*?\[]/.test(token)) {
      unresolvedGlob = true;
      continue;
    }
    try {
      if (fs.statSync(token).isFile()) files.push(token);
    } catch {
      /* not a regular file — a sed script, a pattern, a missing path */
    }
  }
  return { files, unresolvedGlob };
}

async function main() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const payload = JSON.parse(Buffer.concat(chunks).toString("utf-8"));

  if (!isGuarded(payload.agent_type)) allow();

  const tool = payload.tool_name;
  const args = payload.tool_input || {};

  if (tool === "Read") {
    const filePath = args.file_path;
    if (!filePath || !fs.existsSync(filePath)) allow();
    const total = countLines(filePath);
    // Binary: not our business, and none of the remedies would help.
    if (total === null) allow();
    const limit = args.limit;
    // Block only bulk reads: whole-file, or a window larger than the
    // threshold. A targeted window is allowed on any file, however large.
    const applicable = thresholdFor(filePath);
    if (total > applicable && (limit == null || limit > applicable)) {
      deny(denialFor(filePath, total, "This read"));
      return;
    }
    allow();
  }

  if (tool === "Bash") {
    const command = args.command || "";
    for (const statement of contextBearingStatements(command)) {
      const reader = readerOf(statement);
      if (!reader) continue;
      const [name, tokens] = reader;
      const { files, unresolvedGlob } = resolveTargets(tokens);

      if (unresolvedGlob && WHOLE_FILE_READERS.has(name)) {
        deny(
          `BLOCK: '${statement.trim()}' expands a glob, so the guard cannot tell how much it would emit.\n` +
          `Name the files explicitly, or pipe the output through a filter.`,
        );
        return;
      }
      if (files.length === 0) continue;

      // Every operand's output lands in the context, so they sum.
      let emit = 0;
      let biggest = files[0];
      let biggestLines = -1;
      for (const f of files) {
        const fileLines = countLines(f);
        if (fileLines === null) continue; // binary operand
        const perFile = WHOLE_FILE_READERS.has(name)
          ? fileLines
          : Math.min(fileLines, name === "sed" ? sedLines(tokens) : headTailLines(tokens));
        emit += perFile;
        if (fileLines > biggestLines) { biggestLines = fileLines; biggest = f; }
      }

      // Mixed operands fall back to the stricter code limit: one .go file in
      // the list means this is not a document read.
      const applicable = files.every(isDoc) ? DOC_THRESHOLD : THRESHOLD;
      if (emit > applicable) {
        deny(denialFor(biggest, emit, `'${statement.trim()}'`));
        return;
      }
    }
  }

  allow();
}

main().catch(() => process.exit(0));
