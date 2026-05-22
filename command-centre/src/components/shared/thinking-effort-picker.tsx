"use client";

import { useEffect, useRef, useState } from "react";
import { Brain, ChevronDown } from "lucide-react";
import {
  getSupportedClaudeThinkingEfforts,
  normalizeClaudeThinkingEffortForModel,
} from "@/lib/claude-options";
import type { ClaudeModel, ClaudeThinkingEffort } from "@/types/task";

interface Option {
  value: ClaudeThinkingEffort;
  label: string;
}

const OPTIONS: Option[] = [
  { value: "auto", label: "Auto" },
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "xhigh", label: "XHigh" },
  { value: "max", label: "Max" },
];

interface ThinkingEffortPickerProps {
  value: ClaudeThinkingEffort | null;
  model?: ClaudeModel | null;
  onChange: (value: ClaudeThinkingEffort) => void;
  disabled?: boolean;
}

export function ThinkingEffortPicker({ value, model, onChange, disabled }: ThinkingEffortPickerProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const supportedValues = getSupportedClaudeThinkingEfforts(model);
  const visibleOptions = OPTIONS.filter((option) => supportedValues.includes(option.value));
  const current = normalizeClaudeThinkingEffortForModel(model, value ?? "auto") ?? "auto";
  const currentLabel = visibleOptions.find((option) => option.value === current)?.label || "Auto";

  useEffect(() => {
    const rawCurrent = value ?? "auto";
    if (current !== rawCurrent) {
      onChange(current);
    }
  }, [current, onChange, value]);

  useEffect(() => {
    if (!open) return;
    const handler = (event: MouseEvent) => {
      if (ref.current && !ref.current.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  return (
    <div ref={ref} style={{ position: "relative" }}>
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((value) => !value)}
        title="Thinking effort"
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 5,
          height: 26,
          padding: "0 8px",
          borderRadius: 6,
          border: "none",
          background: "transparent",
          color: "#5E5E65",
          fontSize: 12,
          fontWeight: 500,
          fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
          cursor: disabled ? "default" : "pointer",
          opacity: disabled ? 0.5 : 1,
        }}
        onMouseEnter={(event) => {
          if (!disabled) event.currentTarget.style.background = "rgba(0,0,0,0.04)";
        }}
        onMouseLeave={(event) => {
          event.currentTarget.style.background = "transparent";
        }}
      >
        <Brain size={13} />
        {currentLabel}
        <ChevronDown size={11} />
      </button>
      {open && (
        <div
          style={{
            position: "absolute",
            left: 0,
            bottom: "100%",
            marginBottom: 6,
            backgroundColor: "#f3f0ee",
            border: "1px solid #e5e1dc",
            borderRadius: 10,
            boxShadow: "0 8px 24px rgba(0, 0, 0, 0.08)",
            zIndex: 60,
            minWidth: 150,
            padding: 6,
          }}
        >
          <div
            style={{
              padding: "4px 10px 8px",
              fontSize: 13,
              fontWeight: 600,
              color: "#5E5E65",
              fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
            }}
          >
            Thinking
          </div>
          {visibleOptions.map((option) => {
            const isSelected = option.value === current;
            return (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  onChange(option.value);
                  setOpen(false);
                }}
                style={{
                  display: "flex",
                  alignItems: "center",
                  width: "100%",
                  textAlign: "left",
                  padding: "8px 10px",
                  border: "none",
                  borderRadius: 6,
                  cursor: "pointer",
                  fontSize: 13,
                  fontWeight: 500,
                  fontFamily: "var(--font-space-grotesk), Space Grotesk, sans-serif",
                  color: "#1B1C1B",
                  backgroundColor: isSelected ? "rgba(0,0,0,0.05)" : "transparent",
                }}
                onMouseEnter={(event) => {
                  event.currentTarget.style.backgroundColor = "rgba(0,0,0,0.05)";
                }}
                onMouseLeave={(event) => {
                  event.currentTarget.style.backgroundColor = isSelected ? "rgba(0,0,0,0.05)" : "transparent";
                }}
              >
                {option.label}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
