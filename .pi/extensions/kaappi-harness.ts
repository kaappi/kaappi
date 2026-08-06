/**
 * Kaappi harness for pi — a port of the repo's Claude Code harness
 * (`.claude/hooks/*`) to pi extensions, plus the DCO commit rule that the
 * Claude harness only documents.
 *
 * Provided:
 *  - `zig fmt` on every edit/write of a `.zig` file     (zig-fmt-post.sh)
 *  - destructive bash command gate                      (bash-guard-pre.sh)
 *  - DCO: every `git commit` gets `-s` automatically    (commit convention)
 *  - `zig build test` when the agent settles, only if a
 *    `.zig` file changed this session                   (test-on-stop.sh)
 *
 * Drop-in at `.pi/extensions/`; hot-reload with `/reload`. Note that the
 * repo's Claude skills are already discovered by pi through the
 * `.agents/skills -> .claude/skills` symlink, so no skills wiring is needed
 * here.
 *
 * Extension ideas, all doable with the same API:
 *  - auto-tag issues with one `priority:` label (the triage rule) via a
 *    `gh issue edit` wrapper or a `/triage` command
 *  - fail-fast guards: block `git push`/`gh pr create` when the unit suite
 *    is red (the Stop-hook philosophy, moved to the write-path)
 *  - `kaappi --coverage` gate before landing an ecosystem-library change
 */

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  // ── zig-fmt-post.sh: auto-format .zig after every edit/write ──────────
  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    const file = (event.input as { path?: unknown }).path;
    if (typeof file !== "string" || !file.endsWith(".zig")) return;
    if (file.includes("vendor/") || file.includes(".zig-cache/")) return;
    try {
      const { code } = await pi.exec("zig", ["fmt", file], { cwd: ctx.cwd });
      if (code !== 0 && ctx.hasUI) {
        ctx.ui.notify(`zig fmt failed on ${file} (exit ${code})`, "error");
      }
    } catch {
      // No zig on PATH — nothing to format with; stay quiet.
    }
  });

  // ── bash-guard-pre.sh: destructive command gate ───────────────────────
  // Same patterns as .claude/hooks/bash-guard-pre.sh, but pi can ask the
  // user instead of hard-blocking (and falls back to blocking when there is
  // no UI, e.g. `-p` / `--mode json`).
  const destructive = [
    /\brm\s+-rf\s+\//, // rm -rf with a root path
    /(^|\s|;|&&|\|\|)sudo\s/, // sudo usage
    /\bgit\s+push\s.*--force/, // git push --force
    /\bgit\s+tag\s+-d/, // git tag deletion
    /\bgit\s+reset\s+--hard/, // git reset --hard
  ];
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;
    if (!destructive.some((re) => re.test(event.input.command))) return;
    if (!ctx.hasUI) {
      return { block: true, reason: "Destructive command blocked (no UI for confirmation)" };
    }
    const ok = await ctx.ui.confirm("Dangerous command", event.input.command);
    return ok ? undefined : { block: true, reason: "Blocked by user" };
  });

  // ── DCO: every commit carries Signed-off-by (git commit -s) ───────────
  // The repo enforces DCO via the DCO2 app, so `-s` is mandatory. pi lets us
  // rewrite the tool input before execution — no user prompt needed, no
  // forgetting.
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;
    const cmd = event.input.command;
    if (!/\bgit\s+commit\b/.test(cmd)) return;
    if (/(^|\s)-s(\s|$)|--signoff/.test(cmd)) return; // already signed off
    event.input.command = cmd.replace(
      /(^|&&|\|\||;)(\s*)git\s+commit\b/g,
      "$1$2git commit -s",
    );
  });

  // ── test-on-stop.sh: run the unit suite when the agent settles ────────
  // agent_settled fires only when nothing is left — no retry, compaction, or
  // queued follow-up — which is a closer match to "the agent is done" than a
  // Stop hook. Only runs when a .zig file changed since session start.
  let zigDirtyAtStart = new Set<string>();
  pi.on("session_start", async (_event, ctx) => {
    zigDirtyAtStart = await modifiedZigFiles(pi, ctx.cwd);
  });
  pi.on("agent_settled", async (_event, ctx) => {
    if (!fs.existsSync(path.join(ctx.cwd, "build.zig"))) return; // not the kaappi repo
    const now = await modifiedZigFiles(pi, ctx.cwd);
    const changed = [...now].some((f) => !zigDirtyAtStart.has(f));
    if (!changed) return;
    if (ctx.hasUI) ctx.ui.notify("Running zig build test…", "info");
    try {
      const { code } = await pi.exec("zig", ["build", "test"], { cwd: ctx.cwd });
      if (ctx.hasUI) {
        ctx.ui.notify(
          code === 0 ? "Unit tests pass" : `Unit tests FAILED (exit ${code})`,
          code === 0 ? "info" : "error",
        );
      }
    } catch {
      if (ctx.hasUI) ctx.ui.notify("zig build test could not run (zig missing?)", "error");
    }
  });
}

/** The repo's currently modified `.zig` files (git status --porcelain). */
async function modifiedZigFiles(pi: ExtensionAPI, cwd: string): Promise<Set<string>> {
  try {
    const { stdout, code } = await pi.exec("git", ["status", "--porcelain"], { cwd });
    if (code !== 0) return new Set();
    const files = new Set<string>();
    for (const line of stdout.split("\n")) {
      const f = line.slice(3).trim();
      if (f.endsWith(".zig")) files.add(f);
    }
    return files;
  } catch {
    return new Set();
  }
}
