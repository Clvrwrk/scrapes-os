#!/usr/bin/env node
// PostToolUse hook — auto-commits SKILL.md changes immediately after Claude writes them.
// Ensures skill customisations are durable without depending on the user running wrap-up.
// Fire-and-forget: spawns a background process so it never blocks Claude.

const path = require("path");
const { spawn, spawnSync } = require("child_process");

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => (input += chunk));
process.stdin.on("end", () => {
  let data;
  try {
    data = JSON.parse(input);
  } catch {
    return;
  }

  const toolName = data.tool_name || "";
  const filePath = (data.tool_input || {}).file_path || "";

  // Only fire for Write or Edit tools targeting a SKILL.md
  if (!["Write", "Edit", "MultiEdit"].includes(toolName)) return;
  if (!filePath) return;

  const normalized = filePath.replace(/\\/g, "/");

  let skillFile, commitMsg;
  const skillMatch = normalized.match(/\.claude\/skills\/([^/]+)\/SKILL\.local\.md$/);
  const claudeMatch = normalized.match(/(?:^|\/)CLAUDE\.local\.md$/);

  if (skillMatch) {
    const skillName = skillMatch[1];
    if (skillName === "_catalog") return;
    const today = new Date().toISOString().slice(0, 10);
    commitMsg = `chore: update local skill rules -- ${skillName} [${today}]`;
    skillFile = `.claude/skills/${skillName}/SKILL.local.md`;
  } else if (claudeMatch) {
    const today = new Date().toISOString().slice(0, 10);
    commitMsg = `chore: update CLAUDE.local.md [${today}]`;
    skillFile = `CLAUDE.local.md`;
  } else {
    return;
  }

  const repoRoot = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, "../..");
  const workerPath = path.join(__dirname, "skill-auto-commit-worker.js");

  const child = spawn(process.execPath, [workerPath, repoRoot, skillFile, commitMsg], {
    stdio: "ignore",
    windowsHide: true,
    detached: true,
  });

  child.unref();
});
