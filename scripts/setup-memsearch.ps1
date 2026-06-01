# setup-memsearch.ps1 — Install and configure memsearch for semantic memory recall (Tier 1).
# Run once after cloning: powershell scripts/setup-memsearch.ps1
# Safe to re-run — skips steps already done.
# Windows uses Zilliz Cloud (Milvus Lite has no Windows wheel on PyPI).
# macOS/Linux users: run setup-memsearch.sh instead (uses Milvus Lite locally).

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

# Windows: Milvus Lite has no PyPI wheel — Zilliz Cloud free tier is required.
Write-Host "==> Configuring Milvus backend (Windows requires Zilliz Cloud)..."

$zillizUri = $env:ZILLIZ_URI
$zillizToken = $env:ZILLIZ_TOKEN

# Try to read from .env if not already in environment
if ((-not $zillizUri) -and (Test-Path ".env")) {
    $envContent = Get-Content ".env" -Raw
    if ($envContent -match '(?m)^ZILLIZ_URI=(.+)') { $zillizUri = $Matches[1].Trim() }
    if ($envContent -match '(?m)^ZILLIZ_TOKEN=(.+)') { $zillizToken = $Matches[1].Trim() }
}

if (-not $zillizUri) {
    Write-Host ""
    Write-Host "    Milvus Lite does not support Windows. You need a free Zilliz Cloud cluster."
    Write-Host "    Opening signup page in your browser..."
    Start-Process "https://cloud.zilliz.com"
    Write-Host ""
    $zillizUri   = Read-Host "    Paste your cluster URI (e.g. https://in03-xxx.api.gcp-us-west1.zillizcloud.com)"
    $zillizToken = Read-Host "    Paste your API Token"

    # Persist to .env for future runs
    if (Test-Path ".env") {
        Add-Content ".env" "`nZILLIZ_URI=$zillizUri"
        Add-Content ".env" "ZILLIZ_TOKEN=$zillizToken"
        Write-Host "    Saved to .env."
    }
} else {
    Write-Host "    ZILLIZ_URI found — skipping browser signup."
}

memsearch config set milvus.uri   $zillizUri   | Out-Null
memsearch config set milvus.token $zillizToken | Out-Null
Write-Host "    Zilliz Cloud configured."

Write-Host "==> Configuring ONNX provider (local embeddings, no API key needed)..."
memsearch config set embedding.provider onnx | Out-Null

Write-Host "==> Running initial index (downloads ~558 MB model on first run)..."
Write-Host "    This may take a few minutes depending on your connection."
memsearch index context/memory/ context/transcripts/

Write-Host ""
Write-Host "==> Done. Run 'memsearch stats' to check the index."
Write-Host "    Semantic recall (Tier 1) is now active."
