# Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host "[1/5] Installing Ollama and PearAI via WinGet..." -ForegroundColor Cyan
winget install --id Ollama.Ollama -e --accept-package-agreements --accept-source-agreements
winget install --id PearAI.PearAI -e --accept-package-agreements --accept-source-agreements

# Refresh environment variables in current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "`n[2/5] Starting Ollama service..." -ForegroundColor Cyan
Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue

# Wait for Ollama to start responding
$retries = 0
while ($retries -lt 10) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:11434/" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) { break }
    } catch {
        Start-Sleep -Seconds 2
        $retries++
    }
}

Write-Host "`n[3/5] Pulling Ollama models..." -ForegroundColor Cyan
# Chat model
ollama pull gemma4
# Recommended fast model for inline tab completion
ollama pull qwen2.5-coder:1.5b
# Embedding model for local codebase search/indexing (@codebase)
ollama pull nomic-embed-text

Write-Host "`n[4/5] Injecting PearAI configuration..." -ForegroundColor Cyan
$pearAiDir = "$HOME\.pearai"
if (-not (Test-Path $pearAiDir)) {
    New-Item -ItemType Directory -Force -Path $pearAiDir | Out-Null
}

$configJson = @'
{
  "models": [
    {
      "title": "Gemma 4 (Local)",
      "provider": "ollama",
      "model": "gemma4",
      "apiBase": "http://localhost:11434",
      "contextLength": 16384
    }
  ],
  "tabAutocompleteModel": {
    "title": "Qwen2.5 Coder 1.5B (Local)",
    "provider": "ollama",
    "model": "qwen2.5-coder:1.5b",
    "apiBase": "http://localhost:11434"
  },
  "embeddingsProvider": {
    "provider": "ollama",
    "model": "nomic-embed-text",
    "apiBase": "http://localhost:11434"
  }
}
'@

$configJson | Out-File -Encoding utf8 "$pearAiDir\config.json"

Write-Host "`n[5/5] Setup Complete! Restart PearAI to start using your local setup." -ForegroundColor Green
