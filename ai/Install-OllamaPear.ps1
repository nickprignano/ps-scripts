<#
.SYNOPSIS
    Automated installer and local environment setup for Ollama and PearAI.

.DESCRIPTION
    This script automates the full setup of a local AI development environment on Windows:
    1. Installs Ollama and PearAI (via WinGet with a direct download fallback).
    2. Ensures the Ollama background service is running on port 11434.
    3. Pulls local AI models: Gemma 4 (Chat), Qwen 2.5 Coder 1.5B (Autocomplete), and Nomic Embed Text (Codebase Indexing).
    4. Automatically writes configuration to ~/.pearai/config.json.
    5. Launches PearAI upon completion.

.NOTES
    Script Name : Install-OllamaPear.ps1
    Repository  : https://github.com/nickprignano/ps-scripts
    Requires    : Windows 10/11, PowerShell 5.1+, WinGet

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Install-OllamaPear.ps1
#>

# Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host "====================================================" -ForegroundColor Direct
Write-Host "    PEARAI + OLLAMA LOCAL ENVIRONMENT SETUP        " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Direct
Write-Host ""

Write-Host "[1/5] Installing Ollama and PearAI..." -ForegroundColor Cyan

# Install Ollama via WinGet
winget install --id Ollama.Ollama -e --accept-package-agreements --accept-source-agreements

# Install PearAI via WinGet with direct download fallback
try {
    winget install --id PearAI.PearAI -e --accept-package-agreements --accept-source-agreements --error-action Stop
} catch {
    Write-Host "WinGet package link failed. Downloading PearAI installer directly..." -ForegroundColor Yellow
    $installerPath = "$env:TEMP\PearAISetup.exe"
    Invoke-WebRequest -Uri "https://github.com/trypear/pearai-app/releases/latest/download/PearAISetup.exe" -OutFile $installerPath
    
    Write-Host "Running PearAI installer..." -ForegroundColor Cyan
    Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
    Remove-Item $installerPath -ErrorAction SilentlyContinue
}

# Refresh environment variables for the current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Check if Ollama service is running on port 11434
Write-Host "`n[2/5] Checking Ollama service..." -ForegroundColor Cyan
$ollamaRunning = $false
try {
    $res = Invoke-WebRequest -Uri "http://localhost:11434/" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
    if ($res.StatusCode -eq 200) { $ollamaRunning = $true }
} catch {}

if (-not $ollamaRunning) {
    Write-Host "Starting Ollama service..." -ForegroundColor Cyan
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue
    
    $retries = 0
    while ($retries -lt 10) {
        try {
            $res = Invoke-WebRequest -Uri "http://localhost:11434/" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($res.StatusCode -eq 200) { break }
        } catch {
            Start-Sleep -Seconds 2
            $retries++
        }
    }
}

Write-Host "`n[3/5] Pulling Ollama models..." -ForegroundColor Cyan
ollama pull gemma4
ollama pull qwen2.5-coder:1.5b
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

Write-Host "`n[5/5] Launching PearAI..." -ForegroundColor Green

# Locate and launch PearAI
$pearExe = Get-Command "PearAI.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $pearExe) {
    $defaultPath = "$env:LocalAppData\Programs\PearAI\PearAI.exe"
    if (Test-Path $defaultPath) { $pearExe = $defaultPath }
}

if ($pearExe) {
    Start-Process -FilePath $pearExe
    Write-Host "PearAI launched successfully!" -ForegroundColor Green
} else {
    Write-Host "Setup complete. Please start PearAI from the Start Menu." -ForegroundColor Yellow
}
