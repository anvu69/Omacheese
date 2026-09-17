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

    # Pull the model too. "Ollama installed, now type this" is not a local LLM,
    # and the confirmation screen already priced the download in - the same
    # thing the vLLM half of this script got wrong.
    $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
    $ollama = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollama) {
        Warn "ollama is not on PATH yet - open a new terminal, then: ollama pull $model"
        exit 0
    }

    $have = @(& $ollama.Source list 2>$null | Select-String -SimpleMatch $model)
    if ($have.Count) {
        Good "$model already pulled"
    } else {
        Info "pulling $model (sized for this machine - several GB)"
        & $ollama.Source pull $model
        if ($LASTEXITCODE -ne 0) {
            Bad "ollama pull $model failed (exit $LASTEXITCODE)"
            exit 1
        }
    }

    # Ollama runs as a background service, so the endpoint is the check.
    $ready = $false
    try {
        # 127.0.0.1, not localhost: localhost tries ::1 first and the wait is
        # not free if nothing listens there.
        $ready = (Invoke-WebRequest -Uri "http://127.0.0.1:11434/v1/models" `
                  -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200
    } catch { }

    Write-Host ""
    if ($ready) { Good "ollama is serving $model at http://127.0.0.1:11434/v1" }
    else        { Warn "ollama is installed but not answering on :11434 - start it from the Start menu" }
    Write-Host ""
    Write-Host "  chat      ollama run $model" -ForegroundColor Cyan
    Write-Host "  endpoint  http://127.0.0.1:11434/v1   (OpenAI-compatible)" -ForegroundColor DarkGray
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

# --- the compose files the closing instructions need -------------------------
# bootstrap-almalinux.sh copies these into ~/.config/ai, and nothing in
# setup.ps1 runs it - it is documented as a manual step for the WSL side. So
# this script installed Docker, wrote a .env, printed
#   cd ~/.config/ai && docker compose -f docker-compose.vllm.yml up -d
# and left that directory holding one .env and no compose file. Measured:
#   compose file "/root/.config/ai/docker-compose.vllm.yml" is invalid:
#   open ...: no such file or directory
Info "installing the compose files into ~/.config/ai"
& wsl.exe -d $Distro -- bash -lc "mkdir -p ~/.config/ai && cp -f '$repoLinux/configs/ai/'docker-compose.*.yml ~/.config/ai/"
if ($LASTEXITCODE -ne 0) {
    Bad "could not copy the compose files from $repoLinux/configs/ai"
    exit 1
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

# --- start it ----------------------------------------------------------------
# "Stack ready" used to mean "here are three commands to type". The module's
# own confirmation screen promises a ~10 GB image and several GB of weights and
# says 10-30 minutes, so pulling them is this step's job, not the user's.
Write-Host ""
Info "starting vLLM - the first run pulls the image and the weights (several GB)"
& wsl.exe -d $Distro -- bash -lc "cd ~/.config/ai && docker compose -f docker-compose.vllm.yml up -d"
if ($LASTEXITCODE -ne 0) {
    Bad "docker compose up failed - see the output above."
    exit 1
}

# The container is up long before the API is: vLLM pulls the weights and loads
# them onto the GPU first, and only then binds the port. Ask the endpoint
# instead of claiming success because a container started.
$deadline = (Get-Date).AddMinutes(30)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        # 127.0.0.1, not localhost: localhost tries ::1 first, and WSL forwards
        # this port on IPv4 only, so the v6 attempt hangs to the timeout rather
        # than being refused. Measured: ::1 still waiting at 20s, v4 at 85ms.
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:8000/v1/models" -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 15
}

Write-Host ""
if ($ready) {
    $served = if ($hint) { $hint.Model } else { "the model in ~/.config/ai/.env" }
    Good "vLLM is serving $served at http://127.0.0.1:8000/v1"
} else {
    Warn "vLLM did not answer within 30 min - it is most likely still pulling weights."
    Write-Host "    wsl -d $Distro -- docker logs -f vllm" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  endpoint  http://127.0.0.1:8000/v1   (OpenAI-compatible, model name: local)" -ForegroundColor Cyan
Write-Host "  model     edit ~/.config/ai/.env, then: docker compose -f docker-compose.vllm.yml up -d" -ForegroundColor DarkGray
Write-Host "  vLLM serves models; it does not train them. See docs/ai-stack.md." -ForegroundColor DarkGray
