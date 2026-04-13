<#
.SYNOPSIS
    Pull a GGUF model from HuggingFace and register it in Ollama.

.DESCRIPTION
    Downloads the specified GGUF file from HuggingFace (with resume support)
    and imports it into the local Ollama instance as a named model.

.PARAMETER HfRepo
    HuggingFace repository ID (e.g. "Qwen/Qwen2.5-Coder-32B-Instruct-GGUF")

.PARAMETER HfFile
    Filename within the repository (e.g. "qwen2.5-coder-32b-instruct-q4_k_m.gguf")

.PARAMETER OllamaName
    Target name inside Ollama (e.g. "qwen2.5-coder:32b-instruct-q4_K_M")

.PARAMETER HfToken
    HuggingFace API token (required for gated models). Defaults to $env:HF_TOKEN.

.PARAMETER OllamaBaseUrl
    Ollama API base URL. Defaults to http://localhost:11434.

.PARAMETER CacheDir
    Local directory for GGUF cache. Defaults to $env:TEMP\hf-model-cache.

.EXAMPLE
    .\scripts\hf_pull_model.ps1 `
        -HfRepo "Qwen/Qwen2.5-Coder-32B-Instruct-GGUF" `
        -HfFile "qwen2.5-coder-32b-instruct-q4_k_m.gguf" `
        -OllamaName "qwen2.5-coder:32b-instruct-q4_K_M" `
        -HfToken $env:HF_TOKEN
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $HfRepo,

    [Parameter(Mandatory)]
    [string] $HfFile,

    [Parameter(Mandatory)]
    [string] $OllamaName,

    [string] $HfToken        = $env:HF_TOKEN,
    [string] $OllamaBaseUrl  = ($env:OLLAMA_BASE_URL ?? "http://localhost:11434"),
    [string] $CacheDir       = (Join-Path $env:TEMP "hf-model-cache")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HfBase   = "https://huggingface.co"
$SafeName = $HfRepo -replace "/", "__"
$LocalPath = Join-Path $CacheDir "${SafeName}__${HfFile}"

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

Write-Host "==> Model   : $OllamaName"
Write-Host "==> HF repo : $HfRepo"
Write-Host "==> HF file : $HfFile"
Write-Host "==> Ollama  : $OllamaBaseUrl"

# ── Download with resume support ──────────────────────────────────────────────
if (Test-Path $LocalPath) {
    Write-Host "==> Found cached GGUF at $LocalPath"
} else {
    $DownloadUrl = "$HfBase/$HfRepo/resolve/main/$HfFile"
    Write-Host "==> Downloading from HuggingFace: $DownloadUrl"
    $Headers = @{}
    if ($HfToken) { $Headers["Authorization"] = "Bearer $HfToken" }

    # Use BitsTransfer for resume, fall back to WebClient
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        $BitsArgs = @{
            Source      = $DownloadUrl
            Destination = $LocalPath
            Description = "Downloading $HfFile"
            Dynamic     = $true
        }
        Start-BitsTransfer @BitsArgs
    } catch {
        Write-Warning "BitsTransfer unavailable, using Invoke-WebRequest (no resume support)"
        $IwrArgs = @{
            Uri     = $DownloadUrl
            OutFile = $LocalPath
        }
        if ($HfToken) { $IwrArgs["Headers"] = $Headers }
        Invoke-WebRequest @IwrArgs
    }
}

# ── Check Ollama is up ────────────────────────────────────────────────────────
try {
    $null = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/tags" -TimeoutSec 5
} catch {
    Write-Error "Ollama not reachable at $OllamaBaseUrl"
    exit 1
}

# ── Already registered? ───────────────────────────────────────────────────────
$Tags = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/tags" -TimeoutSec 5
$Exists = $Tags.models | Where-Object { $_.name -eq $OllamaName }
if ($Exists) {
    Write-Host "==> $OllamaName already registered in Ollama — skipping import."
    exit 0
}

# ── Build transient Modelfile and create model ────────────────────────────────
$ModelfilePath = Join-Path $env:TEMP "agent-farm-$([System.IO.Path]::GetRandomFileName()).Modelfile"
try {
    @"
FROM $LocalPath
PARAMETER num_ctx 32768
PARAMETER stop "<|im_end|>"
PARAMETER stop "<|endoftext|>"
"@ | Set-Content -Path $ModelfilePath -Encoding UTF8

    Write-Host "==> Registering with Ollama: ollama create $OllamaName"
    & ollama create $OllamaName -f $ModelfilePath
    Write-Host "==> Done: $OllamaName is ready."
} finally {
    Remove-Item -Path $ModelfilePath -Force -ErrorAction SilentlyContinue
}
