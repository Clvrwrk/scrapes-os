"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { ArrowUp, Paperclip } from "lucide-react";
import type { LogEntry, PermissionMode, ClaudeModel, ClaudeThinkingEffort, Todo } from "@/types/task";
import type { ChatAttachment } from "@/types/chat-composer";
import { useTaskStore } from "@/store/task-store";
import { SlashCommandMenu } from "@/components/shared/slash-command-menu";
import type { TagItem } from "@/components/shared/slash-command-menu";
import { PermissionPicker } from "@/components/shared/permission-picker";
import { ModelPicker } from "@/components/shared/model-picker";
import { ThinkingEffortPicker } from "@/components/shared/thinking-effort-picker";
import { ComposerAssetTray } from "@/components/shared/composer-asset-tray";
import { ComposerDraftAssetCollection } from "@/components/shared/composer-draft-asset-collection";
import { TasksPopover, type SubtaskSummary } from "@/components/shared/tasks-popover";
import { ContextUsageRing } from "./context-usage-ring";
import { parseTodosFromInput } from "@/lib/claude-parser";
import { useChatComposer } from "@/hooks/use-chat-composer";
import { composeMessageWithAttachments } from "@/lib/chat-message-content";
import {
  getExecutionPermissionMode,
  getPermissionStateForPickerChange,
  getPickerPermissionMode,
  normalizePermissionMode,
} from "@/lib/permission-mode";
import { normalizeClaudeThinkingEffortForModel } from "@/lib/claude-options";
import type { SlashCommand } from "@/lib/slash-commands";
import { recordTagUsage } from "@/components/board/goal-chips";
import { syncComposerTextareaHeight } from "@/lib/composer";
import { useComposerResize } from "@/hooks/use-composer-resize";
import { getChatAttachmentExtension } from "@/lib/chat-attachment-policy";

/** Renders a highlight mirror behind a transparent textarea so @tags and
 *  /commands appear colored while the user types normally. */
export function HighlightMirror({
  text,
  style,
  scrollTop = 0,
  scrollLeft = 0,
}: {
  text: string;
  style: React.CSSProperties;
  scrollTop?: number;
  scrollLeft?: number;
}) {
  // Split text into segments: @tag, /command, or plain text
  const parts: { text: string; kind: "tag" | "command" | "plain" }[] = [];
  const re = /((?:^|\s)(@[\w\/-]+))|((?:^|\s)(\/[\w:.-]+))/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = re.exec(text)) !== null) {
    const fullMatch = match[0];
    const start = match.index;
    if (start > lastIndex) {
      parts.push({ text: text.slice(lastIndex, start), kind: "plain" });
    }
    if (match[2]) {
      // Leading whitespace stays plain
      const leading = fullMatch.slice(0, fullMatch.indexOf("@"));
      if (leading) parts.push({ text: leading, kind: "plain" });
      parts.push({ text: match[2], kind: "tag" });
    } else if (match[4]) {
      const leading = fullMatch.slice(0, fullMatch.indexOf("/"));
      if (leading) parts.push({ text: leading, kind: "plain" });
      parts.push({ text: match[4], kind: "command" });
    }
    lastIndex = start + fullMatch.length;
  }
  if (lastIndex < text.length) {
    parts.push({ text: text.slice(lastIndex), kind: "plain" });
  }

  return (
    <div
      aria-hidden
      style={{
        position: "absolute",
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        pointerEvents: "none",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          ...style,
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          whiteSpace: "pre-wrap",
          overflow: "hidden",
          overflowWrap: "anywhere",
          wordBreak: "break-word",
          wordWrap: "break-word",
          maxWidth: "100%",
          color: "#1B1C1B",
          transform: `translate(${-scrollLeft}px, ${-scrollTop}px)`,
        }}
      >
        {parts.map((p, i) =>
          p.kind === "tag" ? (
            <span key={i} style={{ color: "#93452A" }}>{p.text}</span>
          ) : p.kind === "command" ? (
            <span key={i} style={{ color: "#6D28D9" }}>{p.text}</span>
          ) : (
            <span key={i}>{p.text}</span>
          )
        )}
        {/* Trailing space to match textarea line height */}
        {"\u200B"}
      </div>
    </div>
  );
}

interface ReplyInputProps {
  taskId: string;
  isVisible: boolean;
  needsInput?: boolean;
  taskStatus?: string;
  onOptimisticReply?: (entry: LogEntry) => void;
  /** Initial permission mode (sourced from the task row). */
  initialPermissionMode?: PermissionMode;
  /** Execution mode staged while the task is in plan mode. */
  initialExecutionPermissionMode?: PermissionMode | null;
  /** Initial model selection (sourced from the task row). */
  initialModel?: ClaudeModel | null;
  /** Initial thinking effort selection (sourced from the task row). */
  initialThinkingEffort?: ClaudeThinkingEffort | null;
  /** Real child subtasks for the Subtasks popover. */
  subtasks?: SubtaskSummary[];
  /** Click handler for a subtask row. */
  onSelectSubtask?: (id: string) => void;
  /** Execute a subtask — POST /api/tasks/:id/execute */
  onRunSubtask?: (id: string) => void;
  /** Execute a subtask in a new chat pane */
  onRunSubtaskInNewChat?: (id: string, title: string) => void;
  /** Execute all backlog subtasks */
  onRunAll?: () => void;
  /** Mark a subtask as done */
  onMarkDone?: (id: string) => void;
  /** Available chat panes for "Add to existing chat" picker */
  availablePanes?: Array<{ id: string; label: string; isMain?: boolean }>;
  /** Run a subtask in a specific existing pane */
  onRunSubtaskInPane?: (subtaskId: string, paneId: string) => void;
  /** When set, the first message creates a new pane task instead of replying.
   *  Returns the new task ID on success, null on failure. */
  onCreatePaneTask?: (message: string, permissionMode: string, model: ClaudeModel | null, thinkingEffort: ClaudeThinkingEffort | null, attachments: ChatAttachment[]) => Promise<string | null>;
  /** Compact mode — shrink toolbar elements (for multi-pane layouts) */
  compact?: boolean;
  /** Project slug — used to pin the relevant brief at the top of the @ menu */
  projectSlug?: string | null;
  /** Hide the tasks/todos popover (e.g. for single tasks without a plan) */
  hideTasksPopover?: boolean;
}

export function ReplyInput({
  taskId,
  isVisible,
  needsInput,
  taskStatus,
  onOptimisticReply,
  initialPermissionMode = "bypassPermissions",
  initialExecutionPermissionMode = null,
  initialModel = null,
  initialThinkingEffort = null,
  subtasks,
  onSelectSubtask,
  onRunSubtask,
  onRunSubtaskInNewChat,
  onRunAll,
  onMarkDone,
  availablePanes,
  onRunSubtaskInPane,
  onCreatePaneTask,
  compact,
  projectSlug,
  hideTasksPopover,
}: ReplyInputProps) {
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showSlashMenu, setShowSlashMenu] = useState(false);
  const [slashQuery, setSlashQuery] = useState("");
  const [showTagMenu, setShowTagMenu] = useState(false);
  const [tagQuery, setTagQuery] = useState("");
  const [promptTags, setPromptTags] = useState<TagItem[]>([]);
  const [activePermissionMode, setActivePermissionMode] = useState<PermissionMode>(
    normalizePermissionMode(initialPermissionMode, "bypassPermissions"),
  );
  const [executionPermissionMode, setExecutionPermissionMode] = useState<PermissionMode>(
    getExecutionPermissionMode(
      initialExecutionPermissionMode ?? initialPermissionMode,
      "bypassPermissions",
    ),
  );
  const [model, setModel] = useState<ClaudeModel | null>(initialModel);
  const [thinkingEffort, setThinkingEffort] = useState<ClaudeThinkingEffort | null>(initialThinkingEffort ?? "auto");
  const composer = useChatComposer({
    surface: "task",
    scopeId: taskId,
  });
  const createTask = useTaskStore((s) => s.createTask);
  const updateTask = useTaskStore((s) => s.updateTask);
  const logEntries = useTaskStore((s) => s.logEntries[taskId]) ?? [];
  const hasAssets =
    composer.attachments.length > 0 ||
    composer.uploads.length > 0 ||
    composer.pastedBlocks.length > 0;
  const [mirrorScroll, setMirrorScroll] = useState({ top: 0, left: 0 });
  const minComposerHeight = compact ? 44 : 60;
  const maxComposerHeight = compact ? 220 : 320;
  const { composerHeight, hasUserResized, handleResizePointerDown } = useComposerResize({
    minHeight: minComposerHeight,
    maxHeight: maxComposerHeight,
    initialHeight: minComposerHeight,
  });

  const permissionMode = useMemo(
    () => getPickerPermissionMode(activePermissionMode, executionPermissionMode, taskStatus),
    [activePermissionMode, executionPermissionMode, taskStatus],
  );

  // Fetch prompt tags on mount
  useEffect(() => {
    fetch("/api/prompt-tags")
      .then((r) => r.json())
      .then((data) => setPromptTags((data.tags ?? []).map((t: { name: string; body: string; category?: string; description?: string }) => ({ name: t.name, body: t.body, category: t.category, description: t.description }))))
      .catch(() => {});
  }, []);

  // Re-sync when switching tasks
  useEffect(() => {
    setActivePermissionMode(normalizePermissionMode(initialPermissionMode, "bypassPermissions"));
    setExecutionPermissionMode(
      getExecutionPermissionMode(
        initialExecutionPermissionMode ?? initialPermissionMode,
        "bypassPermissions",
      ),
    );
    setModel(initialModel);
    setThinkingEffort(initialThinkingEffort ?? "auto");
  }, [taskId, initialPermissionMode, initialExecutionPermissionMode, initialModel, initialThinkingEffort]);

  useEffect(() => {
    syncComposerTextareaHeight(composer.textareaRef.current, {
      minHeight: minComposerHeight,
      maxHeight: maxComposerHeight,
      targetHeight: hasUserResized ? composerHeight : null,
    });
  }, [composer.message, composer.textareaRef, composerHeight, hasUserResized, maxComposerHeight, minComposerHeight]);

  const syncMirrorScroll = useCallback(() => {
    const textarea = composer.textareaRef.current;
    if (!textarea) return;
    setMirrorScroll((current) => {
      const next = { top: textarea.scrollTop, left: textarea.scrollLeft };
      return current.top === next.top && current.left === next.left ? current : next;
    });
  }, [composer.textareaRef]);

  useEffect(() => {
    requestAnimationFrame(() => syncMirrorScroll());
  }, [composer.message, syncMirrorScroll]);

  const latestTodos: Todo[] = useMemo(() => {
    for (let i = logEntries.length - 1; i >= 0; i--) {
      const entry = logEntries[i];
      if (entry.type === "tool_use" && entry.toolName === "TodoWrite" && entry.toolArgs) {
        try {
          const parsed = parseTodosFromInput(JSON.parse(entry.toolArgs));
          if (parsed) return parsed;
        } catch {
          // ignore
        }
      }
    }
    return [];
  }, [logEntries]);

  const handlePermissionModeChange = useCallback((nextMode: "bypassPermissions" | "default" | "plan") => {
    const nextState = getPermissionStateForPickerChange(
      nextMode,
      activePermissionMode,
      executionPermissionMode,
      "bypassPermissions",
    );
    setActivePermissionMode(nextState.permissionMode);
    setExecutionPermissionMode(nextState.executionPermissionMode);
    if (!onCreatePaneTask) {
      void updateTask(taskId, nextState);
    }
  }, [activePermissionMode, executionPermissionMode, onCreatePaneTask, taskId, updateTask]);

  const handleModelChange = useCallback((nextModel: ClaudeModel | null) => {
    const nextThinkingEffort = normalizeClaudeThinkingEffortForModel(nextModel, thinkingEffort);
    setModel(nextModel);
    setThinkingEffort(nextThinkingEffort);
    if (!onCreatePaneTask) {
      void updateTask(taskId, { model: nextModel, thinkingEffort: nextThinkingEffort });
    }
  }, [onCreatePaneTask, taskId, thinkingEffort, updateTask]);

  const handleThinkingEffortChange = useCallback((nextThinkingEffort: ClaudeThinkingEffort) => {
    setThinkingEffort(nextThinkingEffort);
    if (!onCreatePaneTask) {
      void updateTask(taskId, { thinkingEffort: nextThinkingEffort });
    }
  }, [onCreatePaneTask, taskId, updateTask]);

  const handleSubmit = useCallback(async () => {
    const submission = composer.buildSubmission();
    if (!submission.message && submission.attachments.length === 0) return;
    if (isSending) return;
    const finalMessage = composeMessageWithAttachments(submission.message, submission.attachments);

    setIsSending(true);

    // If this is an empty pane, create a new task instead of replying
    if (onCreatePaneTask) {
      try {
        await onCreatePaneTask(
          submission.message,
          activePermissionMode === "plan" ? "plan" : permissionMode,
          model,
          thinkingEffort,
          submission.attachments,
        );
        composer.clearComposer();
      } catch {
        setError("Failed to start conversation");
        setTimeout(() => setError(null), 3000);
      } finally {
        setIsSending(false);
      }
      return;
    }

    // Optimistic: add user_reply entry locally
    if (onOptimisticReply) {
      const entry: LogEntry = {
        id: "local-" + crypto.randomUUID(),
        type: "user_reply",
        timestamp: new Date().toISOString(),
        content: finalMessage,
        permissionMode: activePermissionMode === "plan" ? "plan" : permissionMode,
      };
      onOptimisticReply(entry);
    }

    // Optimistic: mark task as running (clears needsInput so card lights up purple)
    useTaskStore.getState().setTaskFields(taskId, {
      status: "running",
      needsInput: false,
      activityLabel: null,
      lastReplyAt: new Date().toISOString(),
    });

    composer.clearComposer();

    try {
      const res = await fetch(`/api/tasks/${taskId}/reply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: submission.message,
          attachments: submission.attachments,
          permissionMode: activePermissionMode === "plan" ? "plan" : permissionMode,
          executionPermissionMode,
          model,
          thinkingEffort,
        }),
      });
      if (!res.ok) {
        console.error(`[reply-input] Reply failed: ${res.status}`);
        setError("Reply failed — try again");
        setTimeout(() => setError(null), 3000);
      }
    } catch {
      setError("Reply failed — try again");
      setTimeout(() => setError(null), 3000);
    } finally {
      setIsSending(false);
    }
  }, [
    composer,
    isSending,
    taskId,
    onOptimisticReply,
    onCreatePaneTask,
    activePermissionMode,
    permissionMode,
    executionPermissionMode,
    model,
    thinkingEffort,
  ]);

  const handleSlashSelect = useCallback(async (cmd: SlashCommand) => {
    setShowSlashMenu(false);
    setSlashQuery("");
    composer.setMessage("");

    // Create a new task from the slash command and auto-queue it
    const taskTitle = cmd.label;
    const taskDesc = `Run ${cmd.command}`;
    await createTask(taskTitle, taskDesc, "task");
    const tasks = useTaskStore.getState().tasks;
    const newTask = tasks.find(
      (t) => t.title === taskTitle && t.status === "backlog"
    );
    if (newTask) {
      await updateTask(newTask.id, { status: "queued" });
    }
  }, [composer, createTask, updateTask]);

  const handleChange = useCallback((value: string) => {
    composer.setMessage(value);
    if (value.startsWith("/")) {
      setShowSlashMenu(true);
      setSlashQuery(value);
      setShowTagMenu(false);
    } else {
      setShowSlashMenu(false);
      setSlashQuery("");
    }
    // Detect @tag trigger
    const el = composer.textareaRef.current;
    if (el && !value.startsWith("/")) {
      const cursor = el.selectionStart ?? value.length;
      const before = value.slice(0, cursor);
      const match = before.match(/(^|[\s])@([\w\/-]*)$/);
      if (match) {
        setShowTagMenu(true);
        setTagQuery(match[2]);
        setShowSlashMenu(false);
      } else {
        setShowTagMenu(false);
        setTagQuery("");
      }
    }
  }, [composer]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if ((showSlashMenu || showTagMenu) && ["ArrowDown", "ArrowUp", "Enter", "Tab", "Escape"].includes(e.key)) return;
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        handleSubmit();
      }
    },
    [handleSubmit, showSlashMenu, showTagMenu]
  );

  if (!isVisible) return null;

  const placeholder = needsInput
    ? "Reply to Claude...  Type / for commands or skills, @ for tags"
    : taskStatus === "review" || taskStatus === "done"
      ? "Send a follow-up or type / for commands or skills..."
      : "Send a message...  Type / for commands or skills, @ for tags";
  const canSubmit =
    composer.message.trim().length > 0 ||
    composer.attachments.length > 0 ||
    composer.pastedBlocks.length > 0;
  const contextRingTaskId = taskId === "empty" ? null : taskId;

  return (
    <div
      onDragEnter={composer.handleDragEnter}
      onDragOver={composer.handleDragOver}
      onDragLeave={composer.handleDragLeave}
      onDrop={composer.handleDrop}
      style={{
        padding: compact ? "6px 12px 8px 12px" : "12px 24px 16px 24px",
        borderTop: "1px solid #EAE8E6",
        flexShrink: 0,
      }}
    >
      {error && (
        <div style={{ fontSize: 12, color: "#C04030", marginBottom: 6, fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif" }}>
          {error}
        </div>
      )}
      <div
        style={{
          background: "#f3f0ee",
          border: composer.isDragging ? "1px solid rgba(147, 69, 42, 0.45)" : "1px solid #e5e1dc",
          borderRadius: 10,
          overflow: "visible",
          position: "relative",
          boxShadow: composer.isDragging ? "0 0 0 3px rgba(147, 69, 42, 0.08)" : "none",
        }}
      >
        <div style={{ display: "flex", justifyContent: "center", padding: compact ? "6px 10px 0" : "8px 14px 0" }}>
          <button
            type="button"
            aria-label="Drag to resize input"
            onPointerDown={handleResizePointerDown}
            style={{
              width: compact ? 36 : 44,
              height: compact ? 6 : 8,
              border: "none",
              borderRadius: 999,
              backgroundColor: "rgba(156, 156, 160, 0.32)",
              cursor: "ns-resize",
            }}
          />
        </div>
        {hasAssets ? (
          <ComposerAssetTray compact={compact}>
            <ComposerDraftAssetCollection
              pastedBlocks={composer.pastedBlocks}
              attachmentItems={[
                ...composer.attachments.map((attachment) => ({
                  id: attachment.id,
                  fileName: attachment.fileName,
                  extension: attachment.extension,
                  sizeBytes: attachment.sizeBytes,
                  contentType: attachment.contentType ?? null,
                  previewPath: attachment.relativePath,
                  previewSurface: attachment.surface,
                  previewScopeId: attachment.scopeId,
                  status: "ready" as const,
                })),
                ...composer.uploads.map((upload) => ({
                  id: upload.id,
                  fileName: upload.fileName,
                  extension: getChatAttachmentExtension(upload.fileName),
                  status: upload.status,
                  error: upload.error,
                })),
              ]}
              compact={compact}
              padding="0"
              onInsertPastedBlock={composer.insertPastedTextBlock}
              onRemovePastedBlock={composer.removePastedTextBlock}
              onRemoveAttachmentItem={(itemId) => {
                const attachment = composer.attachments.find((candidate) => candidate.id === itemId);
                if (attachment) {
                  void composer.removeAttachment(attachment);
                  return;
                }
                composer.removeUpload(itemId);
              }}
              onRetryAttachmentItem={(itemId) => { void composer.retryUpload(itemId); }}
            />
          </ComposerAssetTray>
        ) : null}
        <div style={{ position: "relative", padding: compact ? "6px 10px 4px" : "12px 14px 8px", minWidth: 0 }}>
          {showSlashMenu && (
            <SlashCommandMenu
              query={slashQuery}
              onSelect={handleSlashSelect}
              onClose={() => { setShowSlashMenu(false); setSlashQuery(""); }}
              anchor="above"
            />
          )}
          {showTagMenu && promptTags.length > 0 && (
            <SlashCommandMenu
              query={tagQuery}
              onSelect={() => {}}
              onClose={() => { setShowTagMenu(false); setTagQuery(""); }}
              anchor="above"
              mode="tag"
              tagItems={promptTags
                .filter((t) => !tagQuery || t.name.toLowerCase().includes(tagQuery.toLowerCase()))
                .sort((a, b) => {
                  // Pin the current project's brief to the top
                  if (projectSlug) {
                    const aIsBrief = a.name === `brief/${projectSlug}`;
                    const bIsBrief = b.name === `brief/${projectSlug}`;
                    if (aIsBrief && !bIsBrief) return -1;
                    if (!aIsBrief && bIsBrief) return 1;
                  }
                  return 0;
                })}
              onTagSelect={(tag) => {
                const el = composer.textareaRef.current;
                if (el) {
                  const cursor = el.selectionStart ?? composer.message.length;
                  const before = composer.message.slice(0, cursor);
                  const after = composer.message.slice(cursor);
                  const replaced = before.replace(/(^|[\s])@[\w\/-]*$/, `$1@${tag.name} `);
                  composer.setMessage(replaced + after);
                } else {
                  composer.setMessage((prev) => prev + `@${tag.name} `);
                }
                recordTagUsage(tag.name);
                setShowTagMenu(false);
                setTagQuery("");
                composer.textareaRef.current?.focus();
              }}
            />
          )}
          {/* Inner wrapper — position:relative so the highlight mirror
              aligns exactly with the textarea (not offset by parent padding). */}
          <div style={{ position: "relative", minWidth: 0, overflow: "hidden" }}>
            {(composer.message.includes("@") || composer.message.includes("/")) && (
              <HighlightMirror
                text={composer.message}
                scrollTop={mirrorScroll.top}
                scrollLeft={mirrorScroll.left}
                style={{
                  fontSize: 14,
                  fontFamily: "var(--font-inter), Inter, sans-serif",
                  padding: "4px 0",
                  lineHeight: 1.5,
                }}
              />
            )}
            <textarea
              ref={composer.textareaRef}
              value={composer.message}
              onChange={(e) => handleChange(e.target.value)}
              onKeyDown={handleKeyDown}
              onPaste={composer.handlePaste}
              onScroll={syncMirrorScroll}
              placeholder={placeholder}
              rows={compact ? 1 : 3}
              style={{
                width: "100%",
                fontSize: compact ? 13 : 14,
                fontFamily: "var(--font-inter), Inter, sans-serif",
                padding: compact ? "2px 0" : "4px 0",
                boxSizing: "border-box" as const,
                minHeight: minComposerHeight,
                maxHeight: hasUserResized ? composerHeight : maxComposerHeight,
                maxWidth: "100%",
                backgroundColor: "transparent",
                outline: "none",
                border: "none",
                resize: "none",
                lineHeight: 1.5,
                whiteSpace: "pre-wrap",
                overflowWrap: "anywhere",
                wordBreak: "break-word",
                color: (composer.message.includes("@") || composer.message.includes("/")) ? "transparent" : "#1B1C1B",
                caretColor: "#1B1C1B",
                position: "relative",
                zIndex: 1,
                overflowX: "hidden",
                overflowY: "auto",
              }}
            />
          </div>
        </div>
        {/* Hidden file input */}
        <input
          ref={composer.fileInputRef}
          type="file"
          multiple
          onChange={composer.handleFileInputChange}
          style={{ display: "none" }}
          accept={composer.accept}
        />

        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 2,
            padding: compact ? "4px 6px" : "6px 8px",
            borderTop: "1px solid #e5e1dc",
          }}
        >
          {/* Attach file */}
          <button
            type="button"
            onClick={composer.openFilePicker}
            disabled={composer.isUploading}
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              padding: "4px 6px",
              border: "none",
              borderRadius: 5,
              backgroundColor: "transparent",
              color: composer.isUploading ? "#bbb" : "#5E5E65",
              cursor: composer.isUploading ? "not-allowed" : "pointer",
            }}
            onMouseEnter={(e) => { if (!composer.isUploading) e.currentTarget.style.backgroundColor = "rgba(0,0,0,0.04)"; }}
            onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = "transparent"; }}
            title="Attach file"
          >
            <Paperclip size={14} />
          </button>
          {composer.hasDraft && (
            <button
              type="button"
              onClick={() => { void composer.discardDraft(); }}
              style={{
                border: "none",
                backgroundColor: "transparent",
                color: "#9C9CA0",
                fontSize: 11,
                fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
                cursor: "pointer",
                padding: "4px 6px",
              }}
            >
              Discard draft
            </button>
          )}
          <ContextUsageRing taskId={contextRingTaskId} />
          <ModelPicker value={model} onChange={handleModelChange} />
          <ThinkingEffortPicker value={thinkingEffort} model={model} onChange={handleThinkingEffortChange} />
          <PermissionPicker value={permissionMode} onChange={handlePermissionModeChange} />
          {!hideTasksPopover && (
          <TasksPopover
            todos={latestTodos}
            subtasks={subtasks}
            onSelectSubtask={onSelectSubtask}
            onRunSubtask={onRunSubtask}
            onRunSubtaskInNewChat={onRunSubtaskInNewChat}
            onRunAll={onRunAll}
            onMarkDone={onMarkDone}
            availablePanes={availablePanes}
            onRunSubtaskInPane={onRunSubtaskInPane}
            compact={compact}
          />
          )}
          <div style={{ flex: 1 }} />
          <button
            type="button"
            onClick={handleSubmit}
            disabled={!canSubmit || isSending}
            style={{
              width: 28,
              height: 26,
              borderRadius: 6,
              border: "none",
              background:
                canSubmit && !isSending
                  ? "linear-gradient(135deg, #93452A, #B25D3F)"
                  : "#e8e4df",
              color: canSubmit && !isSending ? "#FFFFFF" : "#5E5E65",
              cursor: canSubmit && !isSending ? "pointer" : "default",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              transition: "background 150ms ease",
            }}
          >
            <ArrowUp size={14} />
          </button>
        </div>
      </div>
    </div>
  );
}
