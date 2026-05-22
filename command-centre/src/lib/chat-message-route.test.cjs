const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");

const { loadTsModule } = require("./test-utils/load-ts-module.cjs");

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

function createDb() {
  const state = {
    conversation: {
      id: "conversation-1",
      title: null,
      status: "active",
      clientId: null,
    },
    messages: [],
    insertedTask: null,
  };

  return {
    state,
    prepare(sql) {
      const normalized = sql.replace(/\s+/g, " ").trim();
      return {
        get(...args) {
          if (normalized === "SELECT * FROM conversations WHERE id = ?") {
            return args[0] === state.conversation.id ? state.conversation : undefined;
          }
          if (normalized === "SELECT COUNT(*) as count FROM messages WHERE conversationId = ? AND role = 'user'") {
            return { count: 1 };
          }
          if (normalized.startsWith("SELECT * FROM tasks WHERE conversationId = ?")) {
            return undefined;
          }
          throw new Error(`Unhandled get SQL: ${normalized}`);
        },
        run(...args) {
          if (normalized.startsWith("INSERT INTO messages")) {
            state.messages.push(args);
            return { changes: 1 };
          }
          if (normalized === "UPDATE conversations SET title = ?, updatedAt = ? WHERE id = ?") {
            state.conversation.title = args[0];
            state.conversation.updatedAt = args[1];
            return { changes: 1 };
          }
          if (normalized === "UPDATE conversations SET updatedAt = ? WHERE id = ?") {
            state.conversation.updatedAt = args[0];
            return { changes: 1 };
          }
          if (normalized.startsWith("INSERT INTO tasks")) {
            state.insertedTask = {
              id: args[0],
              title: args[1],
              description: args[2],
              status: args[3],
              model: args[14],
              thinkingEffort: args[15],
              conversationId: args[16],
              originMessageId: args[17],
            };
            return { changes: 1 };
          }
          throw new Error(`Unhandled run SQL: ${normalized}`);
        },
      };
    },
  };
}

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

function loadRoute(db = createDb()) {
  const routePath = path.resolve(__dirname, "../app/api/chat/message/route.ts");
  return {
    db,
    route: loadTsModule(routePath, {
      stubs: {
        "next/server": createNextServerStub(),
        "@/lib/db": { getDb: () => db },
        "@/lib/event-bus": { emitTaskEvent: () => {} },
        "@/lib/chat-attachment-service": {
          cleanupChatAttachmentStorage: () => {},
          copyChatAttachmentsToSent: () => [],
          deleteSourceDraftAttachments: () => {},
        },
        "@/lib/chat-message-content": {
          composeMessageWithAttachments: (message) => message,
          getMessageTitleSource: (message) => message,
        },
        "@/lib/permission-mode": {
          getActivePermissionMode: (requested, fallback) => requested ?? fallback,
          getExecutionPermissionMode: (requested, fallback) => requested ?? fallback,
        },
        "@/lib/claude-options": claudeOptionsStub,
        "@/types/chat": {},
        "@/types/chat-composer": {},
        "@/types/task": {},
      },
    }),
  };
}

test("POST /api/chat/message persists valid thinking effort on created task", async () => {
  const { db, route } = loadRoute();

  const response = await route.POST({
    url: "http://localhost/api/chat/message",
    json: async () => ({
      conversationId: "conversation-1",
      content: "Build the thing",
      model: "sonnet",
      thinkingEffort: "high",
    }),
  });

  assert.equal(response.status, 201);
  assert.equal(response.body.task.thinkingEffort, "high");
  assert.equal(db.state.insertedTask.thinkingEffort, "high");
});

test("POST /api/chat/message normalizes effort for the selected model", async () => {
  const { db, route } = loadRoute();

  const response = await route.POST({
    url: "http://localhost/api/chat/message",
    json: async () => ({
      conversationId: "conversation-1",
      content: "Build the thing",
      model: "sonnet",
      thinkingEffort: "xhigh",
    }),
  });

  assert.equal(response.status, 201);
  assert.equal(response.body.task.model, "sonnet");
  assert.equal(response.body.task.thinkingEffort, "high");
  assert.equal(db.state.insertedTask.thinkingEffort, "high");
});

test("POST /api/chat/message rejects invalid thinking effort", async () => {
  const { route } = loadRoute();

  const response = await route.POST({
    url: "http://localhost/api/chat/message",
    json: async () => ({
      conversationId: "conversation-1",
      content: "Build the thing",
      thinkingEffort: "turbo",
    }),
  });

  assert.equal(response.status, 400);
  assert.match(response.body.error, /thinkingEffort/);
});
