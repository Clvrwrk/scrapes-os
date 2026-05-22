const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");

const { loadTsModule } = require("./test-utils/load-ts-module.cjs");

const {
  getSupportedClaudeThinkingEfforts,
  normalizeClaudeThinkingEffortForModel,
} = loadTsModule(path.resolve(__dirname, "claude-options.ts"));

test("thinking effort options are filtered by Claude model", () => {
  assert.deepEqual(
    getSupportedClaudeThinkingEfforts("opus"),
    ["auto", "low", "medium", "high", "xhigh", "max"],
  );
  assert.deepEqual(
    getSupportedClaudeThinkingEfforts("sonnet"),
    ["auto", "low", "medium", "high", "max"],
  );
  assert.deepEqual(getSupportedClaudeThinkingEfforts("haiku"), ["auto"]);
});

test("thinking effort is normalized when switching models", () => {
  assert.equal(normalizeClaudeThinkingEffortForModel("sonnet", "xhigh"), "high");
  assert.equal(normalizeClaudeThinkingEffortForModel("haiku", "high"), "auto");
  assert.equal(normalizeClaudeThinkingEffortForModel("opus", "xhigh"), "xhigh");
  assert.equal(normalizeClaudeThinkingEffortForModel("sonnet", null), null);
});
