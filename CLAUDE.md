<!--
Claude Code only. AGENTS.md is the harness-neutral source of truth and is imported below.
Put here ONLY what is specific to the Claude Code harness: its hooks, its Agent tool, its agents.
-->
@AGENTS.md

# Claude Code specifics

## Bulk reads are guarded

A `PreToolUse` hook, [`.claude/hooks/guard-bulk-read.mjs`](.claude/hooks/guard-bulk-read.mjs),
blocks any read that would put too much into a guarded context. **Two thresholds: 350 lines
for code, 1200 for prose** (`.md`, `.mdx`, `.txt`, `.rst`, `.adoc`). Code is looked up; prose is
read linearly, and a plan, spec or skill exists to be held whole by whoever is planning from it.
What is blocked: `Read` with no `limit` or a `limit` above the threshold, and `cat`/`less`/
`more`/`nl`/`tac`, `head`/`tail`, or a numeric-range `sed -n`, in a statement whose output is
not piped onward. Guarded: the main session, plus the `agent-skills:*` reviewer subagents.
`bulk-reader`, `builder`, `Explore` and the rest read freely.

Two honest limits. **The `Read` path is comprehensive; the Bash path is a guard against
accidents, not a seal.** A pipe opts a statement out entirely, `awk`, `grep -A99999` and `perl`
are not inspected at all, deliberately, and a path relative to an earlier `cd` in the same
command line is not resolved. The threshold is **per call, not a budget**: six allowed 350-line
windows still import 2,100 lines. Don't launder a bulk read through a loop.

Work this way and you will rarely meet it:

1. `Grep` with `-n`/`-C` for what you actually need.
2. `Read(file_path, offset: N, limit: <= 350)`, always allowed on any file (`<= 1200` for a
   document; the refusal states which limit applied).
3. `Agent(subagent_type: "bulk-reader", prompt: "<question>\nFiles: …")` for a whole-file or
   cross-file question. Reads on Haiku in its own context, returns bullets with `file:line`
   citations, never the contents.

The refusal is self-contained: it carries the threshold, the alternatives and, for a file type
it recognises (Dart, Python, TS/JS, Markdown, SQL, shell, YAML), a `line: symbol` outline. Use
the outline to pick a window. Never retry a blocked read; it will be blocked again.

Human escape hatches, documented in the hook's header: `SHUNT=0`, `SHUNT_MAIN=0`,
`SHUNT_MIN_LINES=N`, `SHUNT_DOC_MIN_LINES=N`, `SHUNT_AGENTS=a,b`. They are read from the hook
process's own environment, so they must be exported before launching Claude Code.

## When to delegate to `bulk-reader` without being asked

The guard is a floor, not the rule. Reach for `bulk-reader` whenever the *answer* is small but
the *reading* is large: tracing a call chain across files, discovering how a pattern is applied
across a module, answering a question about a whole large file. Give it a specific question and
the paths. Read files yourself when you are about to edit them.

## Subagent model choice is reviewed

Spawning a subagent goes past a judge: a `PreToolUse` **agent hook** on the `Agent` tool, wired
in `.claude/settings.json`. It reads the model you asked for against the task you described and
blocks a spawn that pays for reasoning the work does not need. `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`
sets the floor, because an `Agent` call that names no `model` otherwise inherits the parent's.
Resolution order: explicit `model:` > agent frontmatter `model:` > `CLAUDE_CODE_SUBAGENT_MODEL`
> parent. `bulk-reader`'s pinned `model: haiku` still wins.

It blocks work that is mechanical or retrieval-shaped however large it is, allows genuine
frontier reasoning (architecture, adversarial review, open-ended debugging, code that must be
right first time), and is told to allow when unsure. If it blocks a spawn you believe needs the
stronger model, the refusal itself tells you how to proceed.

## The main session orchestrates; `builder` implements

Spend the main session on interviewing, specifying, planning, reviewing and deciding, and hand
substantial implementation to the `builder` subagent (Sonnet, own context). This is a threshold,
not a prohibition: a spawn pays tens of thousands of tokens of cold context before it does any
work, so do small, local edits inline and delegate whole work packages, multi-file changes, or
anything that would silt up this context. Never delegate what you cannot specify; `builder`
halts rather than guesses. `builder` is not a reviewer: review its diff yourself, or spawn one.
