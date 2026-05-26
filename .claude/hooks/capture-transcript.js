#!/usr/bin/env node
// Stop hook — captures the full conversation as a markdown transcript
// when a Claude session ends. Reads the session JSONL from
// ~/.claude/projects/{hash}/{sessionId}.jsonl and saves to
// context/transcripts/{YYYY-MM-DD}_{sessionId}.md
//
// Stop fires after EVERY turn, so we wait to confirm the Claude
// process is gone before writing (same pattern as session-sync-stop.js).
// Fire-and-forget. Silent on any error.

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn } = require("child_process");

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

  const sessionId = data.session_id;
  if (!sessionId) return;

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const claudePid = process.ppid;

  const child = spawn(
    process.execPath,
    [
      "-e",
      `
    const fs = require("fs");
    const path = require("path");
    const os = require("os");

    const sessionId = ${JSON.stringify(sessionId)};
    const projectDir = ${JSON.stringify(projectDir)};
    const claudePid = ${claudePid};

    async function run() {
      // Wait 4s — if Claude process is still alive, this isn't the final turn
      await new Promise((r) => setTimeout(r, 4000));

      let processAlive = false;
      try { process.kill(claudePid, 0); processAlive = true; } catch {}
      if (processAlive) return;

      // Compute the project hash the same way Claude Code does:
      // replace colon with dash, replace path separators with dash
      const projectHash = projectDir
        .replace(/:/g, "-")
        .replace(/[/\\\\]+/g, "-");

      const jsonlPath = path.join(
        os.homedir(), ".claude", "projects", projectHash, sessionId + ".jsonl"
      );

      let raw;
      try { raw = fs.readFileSync(jsonlPath, "utf8"); } catch { return; }

      // Parse user + assistant text turns
      const turns = [];
      for (const line of raw.trim().split("\\n")) {
        if (!line.trim()) continue;
        let entry;
        try { entry = JSON.parse(line); } catch { continue; }

        const msg = entry.message;
        if (!msg || !["user", "assistant"].includes(msg.role)) continue;

        const content = msg.content;
        let text = "";
        if (typeof content === "string") {
          text = content.trim();
        } else if (Array.isArray(content)) {
          text = content
            .filter((c) => c && c.type === "text" && c.text)
            .map((c) => c.text.trim())
            .join("\\n")
            .trim();
        }
        if (text) turns.push({ role: msg.role, text });
      }

      if (turns.length === 0) return;

      // Format as markdown
      const dateStr = new Date().toISOString().slice(0, 10);
      const idPrefix = sessionId.slice(0, 8);
      let md = "# Session transcript — " + dateStr + "\\n\\n";
      for (const turn of turns) {
        md += (turn.role === "user" ? "## User" : "## Assistant") + "\\n\\n";
        md += turn.text + "\\n\\n";
      }

      // Write to context/transcripts/
      const transcriptDir = path.join(projectDir, "context", "transcripts");
      try { fs.mkdirSync(transcriptDir, { recursive: true }); } catch {}
      try {
        fs.writeFileSync(
          path.join(transcriptDir, dateStr + "_" + idPrefix + ".md"),
          md,
          "utf8"
        );
      } catch {}
    }

    run();
  `,
    ],
    {
      stdio: "ignore",
      windowsHide: true,
      detached: true,
    }
  );

  child.unref();
});

// Safety net — never block session exit
setTimeout(() => process.exit(0), 3000);
