"use client";

import { useState, useCallback } from "react";
import { Terminal, Copy, CheckCircle2, RotateCcw } from "lucide-react";
import type { Task, LogEntry, OutputFile } from "@/types/task";
import { useTaskStore } from "@/store/task-store";
import { ModalChat } from "./modal-chat";
import { ReplyInput } from "./reply-input";
import type { SubtaskSummary } from "@/components/shared/tasks-popover";

interface ChatPaneProps {
  task: Task;
  logEntries: LogEntry[];
  isFocused: boolean;
  onFocus: () => void;
  onClose: () => void;
  onPreviewFile: (file: OutputFile) => void;
  /** Compact mode for when split with another pane */
  compact?: boolean;
  /** Parent's planned subtasks — shown in the subtasks popover */
  subtasks?: SubtaskSummary[];
  /** Handler when a subtask is selected from the popover */
  onSelectSubtask?: (id: string) => void;
  /** Execute a subtask */
  onRunSubtask?: (id: string) => void;
  /** Execute a subtask in a new chat pane */
  onRunSubtaskInNewChat?: (id: string, title: string) => void;
  /** Execute all backlog subtasks */
  onRunAll?: () => void;
  /** Mark a subtask as done */
  onMarkSubtaskDone?: (id: string) => void;
  /** Available chat panes for "Add to existing chat" picker */
  availablePanes?: Array<{ id: string; label: string; isMain?: boolean }>;
  /** Run a subtask in a specific existing pane */
  onRunSubtaskInPane?: (subtaskId: string, paneId: string) => void;
}

export function ChatPane({
  task,
  logEntries,
  isFocused,
  onFocus,
  onClose,
  onPreviewFile,
  compact = false,
  subtasks,
  onSelectSubtask,
  onRunSubtask,
  onRunSubtaskInNewChat,
  onRunAll,
  onMarkSubtaskDone,
  availablePanes,
  onRunSubtaskInPane,
}: ChatPaneProps) {
  const appendLogEntry = useTaskStore((s) => s.appendLogEntry);
  const fetchLogEntries = useTaskStore((s) => s.fetchLogEntries);
  const updateTask = useTaskStore((s) => s.updateTask);
  const allTasks = useTaskStore((s) => s.tasks);
  const [resumeCopied, setResumeCopied] = useState(false);
  const children = allTasks.filter((t) => t.parentId === task.id);
  const hasChildren = children.length > 0;
  const hasRunningChildren = children.some((c) => c.status === "running" || c.status === "queued");
  // For parent tasks with children: the parent's own session is done (scoping).
  // The parent should only appear "running" if it has no children and is itself running.
  const isRunning = hasChildren ? false : task.status === "running";
  const directNeedsInput = task.needsInput === true
    || task.status === "review"
    || (task.status === "running" && !!task.activityLabel?.trimEnd().endsWith("?"));
  const childNeedsInput = (c: typeof children[0]) =>
    c.needsInput === true || c.status === "review"
    || (c.status === "running" && !!c.activityLabel?.trimEnd().endsWith("?"));
  const allChildrenNeedInput = hasChildren
    && children.filter((c) => c.status === "running").every(childNeedsInput)
    && !children.some((c) => c.status === "queued");
  const needsInput = directNeedsInput || (task.status === "running" && allChildrenNeedInput && hasRunningChildren);
  const sessionId = task.claudeSessionId;

  const isDone = task.status === "done";

  const handleMarkDone = useCallback(() => {
    updateTask(task.id, { status: "done", needsInput: false });
  }, [updateTask, task.id]);

  const handleReopen = useCallback(() => {
    updateTask(task.id, { status: "review" });
  }, [updateTask, task.id]);

  const showDoneToggle = task.status !== "backlog" && !isDone;

  return (
    <div
      onClick={() => {
        onFocus();
      }}
      style={{
        flex: 1,
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
        minWidth: 0,
        minHeight: 0,
        border: isDone ? "1px solid #E5E3E0" : "1px solid #e8e4df",
        borderRadius: 8,
        background: isDone ? "#F9F8F7" : "#fff",
        opacity: isDone ? 0.7 : 1,
        transition: "opacity 200ms ease, background 200ms ease",
      }}
    >
      {/* Action bar — mark done + resume */}
      {(sessionId || showDoneToggle || isDone) && (
        <div style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "flex-end",
          gap: 6,
          padding: "4px 10px",
          borderBottom: "1px solid #EAE8E6",
          flexShrink: 0,
          backgroundColor: isDone ? "#F4F3F1" : "#FCFBFA",
          borderTopLeftRadius: 8,
          borderTopRightRadius: 8,
        }}>
          {sessionId && !isDone && (
            <>
              <span style={{
                fontSize: 10,
                fontFamily: "'DM Mono', monospace",
                color: "#9C9CA0",
                flexShrink: 0,
              }}>
                {task.claudeSessionId?.slice(0, 12)}...
              </span>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  navigator.clipboard.writeText(`claude --resume ${sessionId}`);
                  setResumeCopied(true);
                  setTimeout(() => setResumeCopied(false), 2000);
                }}
                title={resumeCopied ? "Copied!" : `claude --resume ${sessionId}`}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 3,
                  padding: "2px 8px",
                  border: "none",
                  borderRadius: 4,
                  backgroundColor: resumeCopied ? "rgba(107, 142, 107, 0.1)" : "rgba(147, 69, 42, 0.06)",
                  color: resumeCopied ? "#6B8E6B" : "#93452A",
                  fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
                  fontSize: 10,
                  fontWeight: 600,
                  cursor: "pointer",
                  flexShrink: 0,
                }}
                onMouseEnter={(e) => {
                  if (!resumeCopied) e.currentTarget.style.backgroundColor = "rgba(147, 69, 42, 0.12)";
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.backgroundColor = resumeCopied
                    ? "rgba(107, 142, 107, 0.1)"
                    : "rgba(147, 69, 42, 0.06)";
                }}
              >
                {resumeCopied ? <Copy size={10} /> : <Terminal size={10} />}
                {resumeCopied ? "Copied" : "Resume"}
              </button>
            </>
          )}
          {showDoneToggle && (
            <button
              onClick={(e) => { e.stopPropagation(); handleMarkDone(); }}
              title="Mark conversation as complete"
              style={{
                display: "flex",
                alignItems: "center",
                gap: 3,
                padding: "2px 8px",
                border: "none",
                borderRadius: 4,
                backgroundColor: "rgba(107, 142, 107, 0.08)",
                color: "#6B8E6B",
                fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
                fontSize: 10,
                fontWeight: 600,
                cursor: "pointer",
                flexShrink: 0,
              }}
              onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = "rgba(107, 142, 107, 0.22)"; }}
              onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = "rgba(107, 142, 107, 0.08)"; }}
            >
              <CheckCircle2 size={10} />
              Done
            </button>
          )}
          {isDone && (
            <button
              onClick={(e) => { e.stopPropagation(); handleReopen(); }}
              title="Reopen this conversation"
              style={{
                display: "flex",
                alignItems: "center",
                gap: 3,
                padding: "2px 8px",
                border: "none",
                borderRadius: 4,
                backgroundColor: "rgba(147, 69, 42, 0.06)",
                color: "#93452A",
                fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
                fontSize: 10,
                fontWeight: 600,
                cursor: "pointer",
                flexShrink: 0,
              }}
              onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = "rgba(147, 69, 42, 0.12)"; }}
              onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = "rgba(147, 69, 42, 0.06)"; }}
            >
              <RotateCcw size={10} />
              Reopen
            </button>
          )}
        </div>
      )}

      {/* Done overlay banner */}
      {isDone && (
        <div style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 6,
          padding: "8px 12px",
          backgroundColor: "rgba(107, 142, 107, 0.06)",
          borderBottom: "1px solid #EAE8E6",
          flexShrink: 0,
        }}>
          <CheckCircle2 size={12} style={{ color: "#6B8E6B" }} />
          <span style={{
            fontSize: 11,
            fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
            fontWeight: 500,
            color: "#6B8E6B",
          }}>
            Complete
          </span>
        </div>
      )}
      <ModalChat
        taskId={task.id}
        logEntries={logEntries}
        isRunning={isRunning}
        needsInput={needsInput}
        status={task.status}
        activePreviewPath={null}
        onPreviewFile={(f) => {
          onPreviewFile({
            id: `pane-preview-${f.relativePath}`,
            taskId: task.id,
            fileName: f.fileName,
            filePath: f.relativePath,
            relativePath: f.relativePath,
            extension: f.extension,
            sizeBytes: null,
            createdAt: new Date().toISOString(),
          });
        }}
        activityLabel={hasChildren ? null : task.activityLabel}
        startedAt={task.startedAt}
        lastReplyAt={task.lastReplyAt}
        costUsd={task.costUsd}
        tokensUsed={task.tokensUsed}
        errorMessage={task.errorMessage}
        durationMs={task.durationMs}
        onRefresh={() => fetchLogEntries(task.id)}
      />

      {/* Reply input — hidden when done */}
      {!isDone && (
        <ReplyInput
          taskId={task.id}
          isVisible={true}
          needsInput={needsInput}
          taskStatus={task.status}
          initialPermissionMode={task.permissionMode ?? "bypassPermissions"}
          initialExecutionPermissionMode={task.executionPermissionMode ?? null}
          initialModel={task.model ?? null}
          initialThinkingEffort={task.thinkingEffort ?? null}
          onOptimisticReply={(entry: LogEntry) => appendLogEntry(task.id, entry)}
          subtasks={subtasks}
          onSelectSubtask={onSelectSubtask}
          onRunSubtask={onRunSubtask}
          onRunSubtaskInNewChat={onRunSubtaskInNewChat}
          onRunAll={onRunAll}
          onMarkDone={onMarkSubtaskDone}
          availablePanes={availablePanes}
          onRunSubtaskInPane={onRunSubtaskInPane}
          compact={compact}
          hideTasksPopover={task.level === "task"}
        />
      )}
    </div>
  );
}
