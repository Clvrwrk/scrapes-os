export type TaskStatus = "backlog" | "queued" | "running" | "review" | "done";
export type TaskLevel = "task" | "project" | "gsd";

// Human-friendly labels and hints for task levels now live in `@/lib/levels`
// to keep a single source of truth across the app.

export type GsdStep = "discuss" | "plan" | "execute" | "verify";
export type PermissionMode = "plan" | "default" | "acceptEdits" | "auto" | "bypassPermissions";
export type ClaudeModel = "opus" | "sonnet" | "haiku";
export type ClaudeThinkingEffort = "auto" | "low" | "medium" | "high" | "xhigh" | "max";

export interface Todo {
  content: string;
  status: "pending" | "in_progress" | "completed";
  activeForm?: string;
}

export const PERMISSION_MODE_LABELS: Record<PermissionMode, string> = {
  plan: "Plan",
  default: "Default",
  acceptEdits: "Auto-edit",
  auto: "Auto",
  bypassPermissions: "Full auto",
};

export const PERMISSION_MODE_HINTS: Record<PermissionMode, string> = {
  plan: "Claude plans first, then asks you to approve",
  default: "Claude asks before making big changes — set up in settings.json",
  acceptEdits: "File edits happen automatically, commands still need approval",
  auto: "Claude works independently with minimal check-ins",
  bypassPermissions: "Everything runs without asking — no safety net",
};

export type LogEntryType =
  | "text"
  | "tool_use"
  | "tool_result"
  | "question"
  | "structured_question"
  | "user_reply"
  | "system";

export interface LogEntry {
  id: string;
  type: LogEntryType;
  timestamp: string;
  content: string;
  toolName?: string;
  toolArgs?: string;
  toolResult?: string;
  isCollapsed?: boolean;
  /** JSON-serialised QuestionSpec[] when type === "structured_question" */
  questionSpec?: string;
  /** JSON-serialised QuestionAnswers once the user has replied */
  questionAnswers?: string;
  /** Task ID this entry came from (set when merging parent + subtask logs). */
  sourceTaskId?: string;
  /** Permission mode active when this user_reply was sent */
  permissionMode?: string;
}

export interface Task {
  id: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  level: TaskLevel;
  parentId: string | null;
  projectSlug: string | null;
  columnOrder: number;
  createdAt: string;
  updatedAt: string;
  costUsd: number | null;
  tokensUsed: number | null;
  durationMs: number | null;
  activityLabel: string | null;
  errorMessage: string | null;
  startedAt: string | null;
  completedAt: string | null;
  clientId: string | null;
  needsInput: boolean;
  phaseNumber: number | null;
  gsdStep: GsdStep | null;
  contextSources: string | null;
  cronJobSlug: string | null;
  claudeSessionId: string | null;
  claudePid?: number | null;
  permissionMode: PermissionMode;
  executionPermissionMode?: PermissionMode | null;
  model?: ClaudeModel | null;
  thinkingEffort?: ClaudeThinkingEffort | null;
  lastReplyAt: string | null;
  conversationId?: string | null;
  originMessageId?: string | null;
  teamId?: string | null;
  coordinationLevel?: "inject" | "shared_context" | "team" | null;
  goalGroup: string | null;
  tag: string | null;
  pinnedAt: string | null;
  dependsOnTaskIds?: string[] | null;
  /** Worktree isolation mode for parallel execution */
  isolation?: "none" | "worktree" | null;
  /** Absolute path to the git worktree when running in isolation */
  worktreePath?: string | null;
  /** Git branch name for the worktree */
  worktreeBranch?: string | null;
}

export interface OutputFile {
  id: string;
  taskId: string;
  fileName: string;
  filePath: string;
  relativePath: string;
  extension: string;
  sizeBytes: number | null;
  createdAt: string;
  diffStatus?: "added" | "modified" | "unchanged";
}

export interface TaskCreateInput {
  title: string;
  description?: string | null;
  level: TaskLevel;
  projectSlug?: string | null;
  clientId?: string | null;
  parentId?: string | null;
  phaseNumber?: number | null;
  gsdStep?: GsdStep | null;
  permissionMode?: PermissionMode;
  executionPermissionMode?: PermissionMode | null;
  model?: ClaudeModel | null;
  thinkingEffort?: ClaudeThinkingEffort | null;
  conversationId?: string | null;
  originMessageId?: string | null;
}

export type TaskUpdateInput = Partial<
  Pick<
    Task,
    | "title"
    | "description"
    | "status"
    | "level"
    | "parentId"
    | "projectSlug"
    | "columnOrder"
    | "costUsd"
    | "tokensUsed"
    | "durationMs"
    | "activityLabel"
    | "errorMessage"
    | "startedAt"
    | "completedAt"
    | "clientId"
    | "needsInput"
    | "phaseNumber"
    | "gsdStep"
    | "permissionMode"
    | "executionPermissionMode"
    | "model"
    | "thinkingEffort"
    | "conversationId"
    | "originMessageId"
    | "teamId"
    | "coordinationLevel"
    | "goalGroup"
    | "tag"
    | "pinnedAt"
    | "isolation"
    | "worktreePath"
    | "worktreeBranch"
  >
>;
