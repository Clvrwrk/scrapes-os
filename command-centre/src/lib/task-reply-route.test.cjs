const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");

const { loadTsModule } = require("./test-utils/load-ts-module.cjs");

const claudeOptionsStub = {
  VALID_CLAUDE_MODELS: ["opus", "sonnet", "haiku"],
  isNullableClaudeThinkingEffort: (value) => value === null || ["auto", "low", "medium", "high", "xhigh", "max"].includes(value),
  normalizeClaudeThinkingEffortForModel: (model, effort) => {
    if (effort == null) return null;
    if (model === "haiku") return "auto";
    if (model === "sonnet" && effort === "xhigh") return "high";
    return effort;
  },
};

function createNextServerStub() {
  return {
    NextRequest: class {},
    NextResponse: {
      json(body, init = {}) {
        return {
          status: init.status ?? 200,
          body,
          async json() {
            return body;
          },
        };
      },
    },
  };
}

function createDb(task, logRows) {
  return {
    prepare(sql) {
      return {
        get(id) {
          if (sql.includes("SELECT * FROM tasks WHERE id = ?")) {
            return id === task.id ? task : undefined;
          }
          throw new Error(`Unhandled get SQL: ${sql}`);
        },
        run(...args) {
          if (sql.startsWith("INSERT INTO task_logs")) {
            logRows.push({
              id: args[0],
              taskId: args[1],
              type: args[2],
              content: args[4],
              permissionMode: args[11],
            });
            return;
          }
          if (sql.startsWith("UPDATE tasks SET permissionMode = ?, executionPermissionMode = ? WHERE id = ?")) {
            task.permissionMode = args[0];
            task.executionPermissionMode = args[1];
            return;
          }
          if (sql.startsWith("UPDATE tasks SET status = 'running'")) {
            task.status = "running";
            task.updatedAt = args[0];
            task.lastReplyAt = args[1];
            task.activityLabel = args[2];
            task.startedAt = task.startedAt ?? args[3];
            task.needsInput = 0;
            task.errorMessage = null;
            return;
          }
          throw new Error(`Unhandled run SQL: ${sql}`);
        },
      };
    },
  };
}

test("task reply route composes attachment paths into the Claude message and cleans up drafts", async () => {
  const insertedLogs = [];
  const emittedEvents = [];
  const copyCalls = [];
  const deleteCalls = [];
  const cleanupCalls = [];
  const replyCalls = [];
  const task = {
    id: "task-1",
    status: "review",
    needsInput: 0,
    permissionMode: "bypassPermissions",
    executionPermissionMode: "bypassPermissions",
    startedAt: null,
    updatedAt: "2026-04-20T10:00:00.000Z",
    lastReplyAt: null,
    activityLabel: null,
    errorMessage: null,
  };

  const incomingAttachments = [{
    id: "draft-1",
    fileName: "notes.md",
    relativePath: ".tmp/chat-drafts/drafts/conversation/conv-1/draft-1/notes.md",
    surface: "conversation",
    scopeId: "conv-1",
    draftKey: "draft-1",
    state: "draft",
  }];
  const sentAttachments = [{
    ...incomingAttachments[0],
    relativePath: ".tmp/chat-drafts/sent/task/task-1/reply-1/notes.md",
    surface: "task",
    scopeId: "task-1",
    draftKey: null,
    state: "sent",
  }];

  const routePath = path.resolve(__dirname, "../app/api/tasks/[id]/reply/route.ts");
  const route = loadTsModule(routePath, {
    stubs: {
      "next/server": createNextServerStub(),
      "@/lib/db": { getDb: () => createDb(task, insertedLogs) },
      "@/lib/event-bus": { emitTaskEvent: (event) => emittedEvents.push(event) },
      "@/lib/chat-attachment-service": {
        cleanupChatAttachmentStorage: (args) => cleanupCalls.push(args),
        copyChatAttachmentsToSent: (args) => {
          copyCalls.push(args);
          return sentAttachments;
        },
        deleteSourceDraftAttachments: (args) => deleteCalls.push(args),
      },
      "@/lib/chat-message-content": {
        composeMessageWithAttachments: (message, attachments) => {
          const trimmed = (message || "").trim();
          const lines = attachments.map((attachment) => `- ${attachment.relativePath}`).join("\n");
          return trimmed ? `${trimmed}\n\nAttached files:\n${lines}` : `Attached files:\n${lines}`;
        },
      },
      "@/lib/plan-brief.server": {
        saveApprovedPlanToBrief: () => null,
      },
      "@/lib/permission-mode": {
        getActivePermissionMode: (requested, fallback) => requested ?? fallback,
        getExecutionPermissionMode: (requested, fallback) => requested ?? fallback,
        VALID_PERMISSION_MODES: ["bypassPermissions", "default", "plan"],
      },
      "@/lib/claude-options": claudeOptionsStub,
      "@/lib/process-manager": {
        processManager: {
          async replyToTask(id, message) {
            replyCalls.push({ id, message });
            return true;
          },
          async spawnContinueTurn() {
            throw new Error("spawnContinueTurn should not run when replyToTask succeeds");
          },
        },
      },
      "@/types/chat-composer": {},
      "@/types/task": {},
      "@/types/question-spec": {
        parseQuestionSpecs: () => [],
        serializeAnswersToProse: () => "",
      },
    },
  });

  const response = await route.POST(
    {
      async json() {
        return {
          message: "Please use the attached notes",
          attachments: incomingAttachments,
          permissionMode: "default",
        };
      },
    },
    { params: Promise.resolve({ id: "task-1" }) },
  );

  assert.equal(response.status, 200);
  assert.deepEqual(copyCalls, [{
    surface: "task",
    scopeId: "task-1",
    referenceId: insertedLogs[0].id,
    attachments: incomingAttachments,
  }]);
  assert.equal(
    insertedLogs[0].content,
    "Please use the attached notes\n\nAttached files:\n- .tmp/chat-drafts/sent/task/task-1/reply-1/notes.md",
  );
  assert.deepEqual(replyCalls, [{
    id: "task-1",
    message: "Please use the attached notes\n\nAttached files:\n- .tmp/chat-drafts/sent/task/task-1/reply-1/notes.md",
  }]);
  assert.deepEqual(deleteCalls, [incomingAttachments]);
  assert.deepEqual(cleanupCalls, [{ surface: "task", scopeId: "task-1" }]);
  assert.equal(task.status, "running");
  assert.equal(task.needsInput, 0);
  assert.equal(emittedEvents.length >= 2, true);
});
