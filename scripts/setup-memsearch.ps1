# setup-memsearch.ps1 — Install and configure memsearch for semantic memory recall (Tier 1).
# Run once after cloning: powershell scripts/setup-memsearch.ps1
# Safe to re-run — skips steps already done.

$ErrorActionPreference = "Stop"

Write-Host "==> Checking Python..."
try {
    $pyVersion = python --version 2>&1
    Write-Host "    $pyVersion"
} catch {
    Write-Host "ERROR: Python not found. Install Python 3.8+ from https://python.org and re-run."
    exit 1
}

Write-Host "==> Checking memsearch..."
$memsearchInstalled = $false
try {
    $ver = memsearch --version 2>&1
    Write-Host "    $ver (already installed)"
    $memsearchInstalled = $true
} catch {}

if (-not $memsearchInstalled) {
    Write-Host "==> Installing memsearch[onnx]..."
    pip install "memsearch[onnx]"
    Write-Host "    Installed."
}

Write-Host "==> Configuring ONNX provider (local embeddings, no API key needed)..."
memsearch config set embedding.provider onnx | Out-Null

Write-Host "==> Running initial index (downloads ~200 MB model on first run)..."
Write-Host "    This may take a few minutes depending on your connection."
memsearch index context/memory/ context/transcripts/

Write-Host ""
Write-Host "==> Done. Run 'memsearch stats' to check the index."
Write-Host "    Semantic recall (Tier 1) is now active."
