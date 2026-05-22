const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");

function readSource(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf-8");
}

test("context usage ring is rendered in the reply toolbar instead of the modal header", () => {
  const replyInput = readSource("components/modal/reply-input.tsx");
  const modalHeader = readSource("components/modal/modal-header.tsx");

  assert.match(replyInput, /import \{ ContextUsageRing \} from "\.\/context-usage-ring";/);
  assert.match(replyInput, /<ContextUsageRing taskId=\{contextRingTaskId\} \/>/);
  assert.doesNotMatch(modalHeader, /ContextUsageRing/);
});

test("context usage ring is hidden for empty chat panes", () => {
  const replyInput = readSource("components/modal/reply-input.tsx");
  const contextUsageRing = readSource("components/modal/context-usage-ring.tsx");

  assert.match(replyInput, /const contextRingTaskId = taskId === "empty" \? null : taskId;/);
  assert.match(contextUsageRing, /if \(!taskId\) return null;/);
});
