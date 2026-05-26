#!/usr/bin/env bash
# setup-memsearch.sh — Install and configure memsearch for semantic memory recall (Tier 1).
# Run once after cloning: bash scripts/setup-memsearch.sh
# Safe to re-run — skips steps already done.

set -e

echo "==> Checking Python..."
if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
  echo "ERROR: Python not found. Install Python 3.8+ and re-run."
  exit 1
fi
PYTHON=$(command -v python3 || command -v python)
echo "    $($PYTHON --version)"

echo "==> Checking memsearch..."
if command -v memsearch &>/dev/null; then
  echo "    $(memsearch --version) (already installed)"
else
  echo "==> Installing memsearch[onnx]..."
  pip install "memsearch[onnx]"
  echo "    Installed."
fi

echo "==> Configuring ONNX provider (local embeddings, no API key needed)..."
memsearch config set embedding.provider onnx > /dev/null

echo "==> Running initial index (downloads ~200 MB model on first run)..."
echo "    This may take a few minutes depending on your connection."
memsearch index context/memory/ context/transcripts/

echo ""
echo "==> Done. Run 'memsearch stats' to check the index."
echo "    Semantic recall (Tier 1) is now active."
