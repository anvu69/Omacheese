# Local LLM, matched to what the machine can actually run.
#
#   ./scripts/install-localllm.ps1              detect and pick
#   ./scripts/install-localllm.ps1 -Tier ollama
#   ./scripts/install-localllm.ps1 -WhatIfOnly  print the plan
#
# Two tiers, because "run a model locally" means very different things on a
# 16 GB CUDA card and on a laptop with integrated graphics:
#
#   vllm    NVIDIA, >= 8 GB VRAM. Docker + NVIDIA Container Toolkit inside WSL,
#           then vLLM serving an OpenAI-compatible API. Fast, batched, and the
#           right choice when you have the VRAM.
#   ollama  Everything else. Runs on CPU, iGPU or a small NVIDIA card, pulls
#           GGUF quantisations, and needs no WSL, no Docker and no CUDA.
#
# vLLM was the original target of this repo, but most machines cannot run it.
# Nothing here assumes a GPU exists.

[CmdletBinding()]
param(
    [ValidateSet("auto", "vllm", "ollama")]
    [string]$Tier = "auto",
    [string]$Distro = "AlmaLinux-9",
    [switch]$WhatIfOnly
)

$ErrorActionPreference = "Continue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot "scripts\lib\detect.ps1")

function Info { param($m) Write-Host "  $m" -ForegroundColor Cyan }
function Good { param($m) Write-Host "  $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  $m" -ForegroundColor Yellow }
function Bad  { param($m) Write-Host "  $m" -ForegroundColor Red }

$machine = Get-MachineProfile

if ($Tier -eq "auto") { $Tier = $machine.LlmTier }

Write-Host "Local LLM setup" -ForegroundColor Green
Write-Host "  GPU  : $(if ($machine.Gpu.Name) { $machine.Gpu.Name } else { 'none detected' })"
Write-Host "  VRAM : $($machine.Gpu.VramGb) GB"
Write-Host "  RAM  : $($machine.RamGb) GB"
Write-Host "  tier : $Tier"
Write-Host ""

if ($Tier -eq "none") {
    Bad "This machine does not have the memory or GPU for a useful local model."
    Warn "Use a hosted API instead - the coding agents work fine that way."
    exit 0
}

# =============================================================================
# Ollama - the portable path
# =============================================================================
if ($Tier -eq "ollama") {
    Info "Installing Ollama (runs on CPU, iGPU or a small NVIDIA card)"

    if ($WhatIfOnly) {
        Write-Host "  would run: winget install --id Ollama.Ollama -e"
        exit 0
    }

    if (Get-Command ollama -ErrorAction SilentlyContinue) {
        Good "ollama already installed"
    } else {
        winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            Bad "winget failed (exit $LASTEXITCODE)"
            exit 1
        }
        Good "ollama installed"
    }

    # Suggest a model that fits, rather than a fixed one.
    $budget = $machine.Gpu.VramGb
    if ($budget -lt 4) { $budget = [math]::Floor($machine.RamGb / 3) }

    if     ($budget -ge 16) { $model = "qwen3:14b" }
    elseif ($budget -ge 8)  { $model = "qwen3:8b" }
    elseif ($budget -ge 5)  { $model = "qwen3:4b" }
    else                    { $model = "qwen3:1.7b" }

    Write-Host ""
    Good "Ready. Pull a model that fits this machine:"
    Write-Host "    ollama pull $model" -ForegroundColor Cyan
    Write-Host "    ollama run $model" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  OpenAI-compatible endpoint: http://localhost:11434/v1" -ForegroundColor DarkGray
    exit 0
}

# =============================================================================
# vLLM - the GPU path, via Docker in WSL
# =============================================================================
Info "Installing the vLLM stack (Docker + NVIDIA Container Toolkit, in WSL)"

if (-not $machine.HasWsl) {
    Bad "WSL is not installed. Run ./scripts/install-wsl.ps1 first."
    exit 1
}

# Bounded, like the probe in detect.ps1: this is the last place that should
# stall, and "wsl did not answer" means the same thing as "no distro" here.
$r = Invoke-BoundedCommand -FilePath "wsl.exe" -ArgumentList @("-l", "-q") `
     -TimeoutMs 8000 -StdoutEncoding ([System.Text.Encoding]::Unicode)
$installed = @((($r.Output -replace "`0", "") -split "`r?`n") |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($installed -notcontains $Distro) {
    Bad "$Distro is not installed. Run: wsl --install -d $Distro"
    Warn "If WSL was just enabled, Windows has to restart before any distro can start."
    exit 1
}

if ($WhatIfOnly) {
    Write-Host "  would run, inside ${Distro}:"
    Write-Host "    bash scripts/install-docker-wsl.sh"
    Write-Host "    write ~/.config/ai/.env for $($machine.Gpu.VramGb) GB VRAM"
    exit 0
}

# --- run the Linux-side installer -------------------------------------------
$repoLinux = (& wsl.exe -d $Distro -- wslpath -a ($RepoRoot -replace '\\', '/') 2>$null)
$repoLinux = ($repoLinux -replace "`0", "").Trim()

if (-not $repoLinux) {
    Bad "Could not map $RepoRoot into $Distro."
    exit 1
}

Info "running install-docker-wsl.sh inside $Distro..."
& wsl.exe -d $Distro -- bash "$repoLinux/scripts/install-docker-wsl.sh"
$code = $LASTEXITCODE
if ($code -ne 0) {
    Warn "install-docker-wsl.sh exited $code - check the output above."
}

# --- write a .env sized for this GPU ----------------------------------------
# This is the part that makes the repo portable: the compose file has generic
# defaults, and the model choice comes from the detected VRAM.
$hint = $machine.ModelHint
if ($hint) {
    Info "sizing vLLM for $($machine.Gpu.VramGb) GB VRAM: $($hint.Model) @ $($hint.Quant)"

    $envBody = @(
        "# Generated by install-localllm.ps1 for $($machine.Gpu.Name) ($($machine.Gpu.VramGb) GB)."
        "# Edit freely; see docs/ai-stack.md for what fits."
        "HF_TOKEN="
        "MODEL=$($hint.Model)"
        "SERVED_NAME=local"
        "QUANT=$($hint.Quant)"
        "MAX_LEN=$($hint.MaxLen)"
        "GPU_UTIL=0.90"
        "WORKSPACE=./workspace"
        "WANDB_API_KEY="
    ) -join "`n"

    $tmp = Join-Path $env:TEMP "vllm.env"
    Set-Content -LiteralPath $tmp -Value $envBody -Encoding ascii -NoNewline
    $tmpLinux = (& wsl.exe -d $Distro -- wslpath -a ($tmp -replace '\\', '/') 2>$null)
    $tmpLinux = ($tmpLinux -replace "`0", "").Trim()

    # Never clobber an existing .env: it holds the HF token.
    & wsl.exe -d $Distro -- bash -lc "mkdir -p ~/.config/ai && if [ ! -f ~/.config/ai/.env ]; then cp '$tmpLinux' ~/.config/ai/.env; echo written; else echo 'kept existing .env'; fi"
} else {
    Warn "No model recommendation for this GPU - edit ~/.config/ai/.env by hand."
}

Write-Host ""
Good "vLLM stack ready."
Write-Host ""
Write-Host "  wsl -d $Distro" -ForegroundColor Cyan
Write-Host "  cd ~/.config/ai && docker compose -f docker-compose.vllm.yml up -d" -ForegroundColor Cyan
Write-Host "  curl http://localhost:8000/v1/models" -ForegroundColor Cyan
Write-Host ""
Write-Host "  First start downloads the weights - expect several GB." -ForegroundColor DarkGray
Write-Host "  vLLM serves models; it does not train them. See docs/ai-stack.md." -ForegroundColor DarkGray
