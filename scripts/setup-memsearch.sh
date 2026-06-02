#!/usr/bin/env bash
# setup-memsearch.sh — Install and configure memsearch for semantic memory recall (Tier 1).
# Run once after cloning: bash scripts/setup-memsearch.sh
# Safe to re-run — skips steps already done.
# Works on macOS, Linux, and Windows (Git Bash).
#
# Backends chosen automatically:
#   Windows (Git Bash)  → Zilliz Cloud (ZILLIZ_URI required in .env)
#   macOS / Linux       → Milvus Lite local (zero config)
#
# Embedding provider chosen automatically:
#   OPENAI_API_KEY set  → openai (no download)
#   otherwise           → onnx (downloads ~558 MB model on first run)

set -e

# Load .env if present
if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

echo "==> Checking Python..."
if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
  echo "ERROR: Python not found. Install Python 3.8+ and re-run."
  exit 1
fi
PYTHON=$(command -v python3 2>/dev/null || command -v python)
echo "    $($PYTHON --version)"

echo "==> Checking memsearch..."
if command -v memsearch &>/dev/null; then
  echo "    $(memsearch --version) (already installed)"
else
  echo "==> Installing memsearch..."
  pip install memsearch
  echo "    Installed."
fi

# Detect OS
OS="$(uname -s)"
IS_WINDOWS=false
case "$OS" in
  MINGW*|CYGWIN*|MSYS*) IS_WINDOWS=true ;;
esac

# Windows (Git Bash): memsearch hooks call python3 but Windows only has python.
# Create a shim in ~/bin so hooks work when spawned by Claude Code.
if [ "$IS_WINDOWS" = true ] && ! command -v python3 &>/dev/null; then
  mkdir -p "$HOME/bin"
  printf '#!/usr/bin/env bash\nexec python "$@"\n' > "$HOME/bin/python3"
  chmod +x "$HOME/bin/python3"
  echo "    Created ~/bin/python3 shim (memsearch hooks require python3 in PATH)."
fi

# Configure Milvus backend
if [ "$IS_WINDOWS" = true ]; then
  echo "==> Configuring Milvus backend (Windows: Zilliz Cloud)..."
  if [ -z "$ZILLIZ_URI" ]; then
    echo ""
    echo "    Milvus Lite does not support Windows. A free Zilliz Cloud cluster is required."
    echo "    Sign up at https://cloud.zilliz.com, create a free cluster, then add to .env:"
    echo "      ZILLIZ_URI=https://in03-xxx.api.gcp-us-west1.zillizcloud.com"
    echo "      ZILLIZ_TOKEN=your-token"
    exit 1
  fi
  memsearch config set milvus.uri "$ZILLIZ_URI"
  memsearch config set milvus.token "$ZILLIZ_TOKEN"
  echo "    Zilliz Cloud configured."
else
  echo "==> Milvus backend: Milvus Lite (local, zero config)."
  # Do not set milvus.uri — memsearch uses ~/.memsearch/milvus.db by default
fi

# Choose embedding provider
echo "==> Configuring embedding provider..."
if [ -n "$OPENAI_API_KEY" ]; then
  memsearch config set embedding.provider openai
  echo "    Using OpenAI (OPENAI_API_KEY detected — no model download needed)."
else
  memsearch config set embedding.provider onnx
  echo "    Using ONNX (local CPU inference — downloads ~558 MB model on first use)."
fi

echo "==> Running initial index..."
echo "    This may take a few minutes on first run."
INDEX_PATHS="context/memory/ context/transcripts/ context/learnings.md brand_context/"
# Include auto-captured session logs if they already exist (re-runs and updates)
if [ -d ".memsearch/memory" ]; then
  INDEX_PATHS="$INDEX_PATHS .memsearch/memory/"
fi
# shellcheck disable=SC2086
memsearch index $INDEX_PATHS

echo ""
echo "==> Done. Run 'memsearch stats' to check the index."
echo "    Semantic recall (Tier 1) is now active."
