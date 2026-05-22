import type { ClaudeModel, ClaudeThinkingEffort } from "@/types/task";

export const VALID_CLAUDE_MODELS: ClaudeModel[] = ["opus", "sonnet", "haiku"];
export const DEFAULT_CLAUDE_MODEL: ClaudeModel = "opus";

export const VALID_CLAUDE_THINKING_EFFORTS: ClaudeThinkingEffort[] = [
  "auto",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
];

export const CLAUDE_THINKING_EFFORTS_BY_MODEL: Record<ClaudeModel, ClaudeThinkingEffort[]> = {
  opus: ["auto", "low", "medium", "high", "xhigh", "max"],
  sonnet: ["auto", "low", "medium", "high", "max"],
  haiku: ["auto"],
};

export function isClaudeThinkingEffort(value: unknown): value is ClaudeThinkingEffort {
  return typeof value === "string" && VALID_CLAUDE_THINKING_EFFORTS.includes(value as ClaudeThinkingEffort);
}

export function isNullableClaudeThinkingEffort(value: unknown): value is ClaudeThinkingEffort | null {
  return value === null || isClaudeThinkingEffort(value);
}

export function getSupportedClaudeThinkingEfforts(model: ClaudeModel | null | undefined): ClaudeThinkingEffort[] {
  const effectiveModel = model && VALID_CLAUDE_MODELS.includes(model) ? model : DEFAULT_CLAUDE_MODEL;
  return CLAUDE_THINKING_EFFORTS_BY_MODEL[effectiveModel];
}

export function isClaudeThinkingEffortSupportedForModel(
  model: ClaudeModel | null | undefined,
  effort: ClaudeThinkingEffort | null | undefined,
): boolean {
  return effort == null || getSupportedClaudeThinkingEfforts(model).includes(effort);
}

export function normalizeClaudeThinkingEffortForModel(
  model: ClaudeModel | null | undefined,
  effort: ClaudeThinkingEffort | null | undefined,
): ClaudeThinkingEffort | null {
  if (effort == null) return null;
  if (isClaudeThinkingEffortSupportedForModel(model, effort)) return effort;
  const effectiveModel = model && VALID_CLAUDE_MODELS.includes(model) ? model : DEFAULT_CLAUDE_MODEL;
  if (effectiveModel === "sonnet" && effort === "xhigh") return "high";
  return "auto";
}
