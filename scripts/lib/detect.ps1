# Machine capability detection.
#
# The setup TUI is meant to run on any clean Windows 11 box, not just the one
# it was written on. Every module that has a hardware or OS requirement asks
# this file first, so a laptop with no discrete GPU is offered a CPU-friendly
# local-LLM path instead of a vLLM container it could never run.
#
# PowerShell 5.1 compatible.

Set-StrictMode -Version 2.0

# Run a native command with a hard deadline, and never let it touch the console.
#
# `wsl.exe -l -q` is why this exists. On a machine that has never had WSL the
# inbox wsl.exe is still in System32 and still answers - but it can take a very
# long time to do it, because it goes looking for the Store package first. The
# setup's opening screen is "detecting hardware...", so the whole installer
# appeared to hang before printing anything a user could act on, on precisely
# the clean machine this repo is for. No answer is not a problem here: it just
# means there are no distros.
#
# Closing stdin matters as much as the timeout. A child that decides to prompt
# otherwise reads the installer's own console, and the run stops dead with no
# visible question - the "it only continues when I press Enter" failure.
function Invoke-BoundedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutMs = 6000,
        # NOT $OutputEncoding: that is a PowerShell automatic variable, and a
        # parameter of that name shadows it for the whole function, changing how
        # every native call inside encodes its arguments.
        $StdoutEncoding = $null
    )

    $result = [pscustomobject]@{ Output = ""; ExitCode = -1; TimedOut = $false; Failed = $false }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName              = $FilePath
        $psi.Arguments             = ($ArgumentList -join ' ')
        $psi.UseShellExecute       = $false
        $psi.CreateNoWindow        = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true
        if ($StdoutEncoding) { $psi.StandardOutputEncoding = $StdoutEncoding }

        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()

        # Read asynchronously, or a child that fills a pipe buffer deadlocks
        # against our own WaitForExit.
        $stdout = $p.StandardOutput.ReadToEndAsync()
        [void]$p.StandardError.ReadToEndAsync()

        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch { }
            $result.TimedOut = $true
            return $result
        }
        $result.ExitCode = $p.ExitCode
        $result.Output   = $stdout.Result
    } catch {
        $result.Failed = $true
    }
    return $result
}

function Get-MachineProfile {
    [CmdletBinding()]
    param()

    $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs  = Get-CimInstance Win32_ComputerSystem  -ErrorAction SilentlyContinue
    $cpu = @(Get-CimInstance Win32_Processor     -ErrorAction SilentlyContinue)[0]

    $ramGb = 0
    if ($cs -and $cs.TotalPhysicalMemory) { $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 0) }

    $threads = 0
    if ($cs -and $cs.NumberOfLogicalProcessors) { $threads = [int]$cs.NumberOfLogicalProcessors }

    $build = 0
    if ($os -and $os.BuildNumber) { $build = [int]$os.BuildNumber }

    # --- GPU ------------------------------------------------------------------
    # Win32_VideoController.AdapterRAM is a 32-bit field and lies about
    # anything over 4 GB, so ask nvidia-smi when it is available and only fall
    # back to WMI for the name.
    $gpu = [pscustomobject]@{
        Vendor     = "none"
        Name       = ""
        VramGb     = 0
        CudaCap    = ""
        DriverOk   = $false
    }

    $controllers = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -and $_.Name -notmatch "Virtual|Parsec|Remote|Basic Display|Meta|IDD" })

    $nvidia = $controllers | Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
    $amd    = $controllers | Where-Object { $_.Name -match "AMD|Radeon" } | Select-Object -First 1
    $intel  = $controllers | Where-Object { $_.Name -match "Intel" } | Select-Object -First 1

    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) {
        $p = Join-Path $env:SystemRoot "System32\nvidia-smi.exe"
        if (Test-Path -LiteralPath $p) { $smi = $p }
    } else {
        $smi = $smi.Source
    }

    if ($smi) {
        try {
            $line = & $smi --query-gpu=name,memory.total,compute_cap --format=csv,noheader 2>$null | Select-Object -First 1
            if ($line) {
                $parts = $line -split ',\s*'
                $gpu.Vendor   = "nvidia"
                $gpu.Name     = $parts[0].Trim()
                $gpu.DriverOk = $true
                if ($parts.Count -gt 1) {
                    $mib = ($parts[1] -replace '[^\d]', '')
                    if ($mib) { $gpu.VramGb = [math]::Round([double]$mib / 1024, 0) }
                }
                if ($parts.Count -gt 2) { $gpu.CudaCap = $parts[2].Trim() }
            }
        } catch { }
    }

    if ($gpu.Vendor -eq "none") {
        if ($nvidia)     { $gpu.Vendor = "nvidia"; $gpu.Name = $nvidia.Name }
        elseif ($amd)    { $gpu.Vendor = "amd";    $gpu.Name = $amd.Name }
        elseif ($intel)  { $gpu.Vendor = "intel";  $gpu.Name = $intel.Name }
        elseif ($controllers.Count) { $gpu.Vendor = "other"; $gpu.Name = $controllers[0].Name }
    }

    # --- Virtualisation / WSL -------------------------------------------------
    $virtOk = $false
    if ($cpu -and $cpu.PSObject.Properties.Name -contains "VirtualizationFirmwareEnabled") {
        $virtOk = [bool]$cpu.VirtualizationFirmwareEnabled
    }
    # Hyper-V being present already implies virtualisation is on and usable.
    if (-not $virtOk -and $cs -and $cs.PSObject.Properties.Name -contains "HypervisorPresent") {
        $virtOk = [bool]$cs.HypervisorPresent
    }

    $wslExe      = [bool](Get-Command wsl -ErrorAction SilentlyContinue)
    $wslDistros  = @()
    $wslProbeSlow = $false

    # wsl.exe sitting in System32 says nothing: it ships with Windows whether or
    # not the feature was ever enabled. One of these two services exists only
    # once WSL is actually installed, and asking is instant, so it decides
    # whether running wsl.exe is worth the wait at all.
    $wslInstalled = $false
    if ($wslExe) {
        $svc = @(Get-Service -Name "LxssManager", "WSLService" -ErrorAction SilentlyContinue)
        $wslInstalled = ($svc.Count -gt 0)
    }

    if ($wslInstalled) {
        # wsl -l -q emits UTF-16; ask for it, and strip stray nulls anyway.
        $r = Invoke-BoundedCommand -FilePath "wsl.exe" -ArgumentList @("-l", "-q") `
             -TimeoutMs 6000 -StdoutEncoding ([System.Text.Encoding]::Unicode)
        if ($r.TimedOut) {
            $wslProbeSlow = $true
        } else {
            $wslDistros = @((($r.Output -replace "`0", "") -split "`r?`n") |
                ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    # --- Disk -----------------------------------------------------------------
    $freeGb = 0
    try {
        $sys = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
        if ($sys) { $freeGb = [math]::Round($sys.FreeSpace / 1GB, 0) }
    } catch { }

    # --- Local-LLM tier -------------------------------------------------------
    # What this machine can realistically do locally. Drives which AI module
    # the TUI offers, and which model it suggests.
    $llm = "none"
    $llmNote = ""
    if ($gpu.Vendor -eq "nvidia" -and $gpu.VramGb -ge 8) {
        $llm = "vllm"
        $llmNote = "$($gpu.VramGb) GB VRAM - vLLM in a GPU container"
    } elseif ($gpu.Vendor -eq "nvidia" -and $gpu.VramGb -ge 4) {
        $llm = "ollama"
        $llmNote = "$($gpu.VramGb) GB VRAM - small models via Ollama"
    } elseif ($gpu.Vendor -in @("amd", "intel") -or $ramGb -ge 16) {
        $llm = "ollama"
        $llmNote = "no CUDA GPU - Ollama on CPU/iGPU, small models only"
    } else {
        $llm = "none"
        $llmNote = "not enough RAM or GPU for local models"
    }

    # Which quantisation and size actually fits, for the vLLM .env.
    $modelHint = $null
    if ($gpu.Vendor -eq "nvidia" -and $gpu.VramGb -gt 0) {
        $fp8Capable = $false
        if ($gpu.CudaCap) {
            $capNum = 0.0
            [void][double]::TryParse($gpu.CudaCap, [ref]$capNum)
            $fp8Capable = ($capNum -ge 8.9)
        }
        if     ($gpu.VramGb -ge 40) { $modelHint = @{ Model = "Qwen/Qwen3-32B";  Quant = "fp8";  MaxLen = 32768 } }
        elseif ($gpu.VramGb -ge 22) { $modelHint = @{ Model = "Qwen/Qwen3-14B";  Quant = "fp8";  MaxLen = 32768 } }
        elseif ($gpu.VramGb -ge 14) { $modelHint = @{ Model = "Qwen/Qwen3-8B";   Quant = "fp8";  MaxLen = 16384 } }
        elseif ($gpu.VramGb -ge 10) { $modelHint = @{ Model = "Qwen/Qwen3-8B";   Quant = "awq";  MaxLen = 8192  } }
        elseif ($gpu.VramGb -ge 8)  { $modelHint = @{ Model = "Qwen/Qwen3-4B";   Quant = "fp8";  MaxLen = 8192  } }
        if ($modelHint -and -not $fp8Capable -and $modelHint.Quant -eq "fp8") {
            # Pre-Ada cards have no native FP8; AWQ is the portable fallback.
            $modelHint.Quant = "awq"
        }
    }

    return [pscustomobject]@{
        OsCaption     = $(if ($os) { $os.Caption } else { "Windows" })
        Build         = $build
        IsWin11       = ($build -ge 22000)
        RamGb         = $ramGb
        Threads       = $threads
        CpuName       = $(if ($cpu) { $cpu.Name.Trim() } else { "" })
        FreeGb        = $freeGb
        Gpu           = $gpu
        VirtEnabled   = $virtOk
        HasWsl        = $wslInstalled
        WslProbeSlow  = $wslProbeSlow
        WslDistros    = $wslDistros
        HasAlmaLinux  = [bool]($wslDistros | Where-Object { $_ -match "AlmaLinux" })
        HasWinget     = [bool](Get-Command winget -ErrorAction SilentlyContinue)
        IsElevated    = (New-Object Security.Principal.WindowsPrincipal(
                            [Security.Principal.WindowsIdentity]::GetCurrent())
                        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        PsMajor       = $PSVersionTable.PSVersion.Major
        LlmTier       = $llm
        LlmNote       = $llmNote
        ModelHint     = $modelHint
    }
}

function Format-MachineSummary {
    param([Parameter(Mandatory = $true)]$Machine, $Palette)

    $T = $Palette
    $lines = @()

    $lines += "{0}{1}{2}  build {3}   {4} GB RAM   {5} threads   {6} GB free" -f `
        $T.Bright, $Machine.OsCaption, $T.Reset, $Machine.Build, $Machine.RamGb, $Machine.Threads, $Machine.FreeGb

    if ($Machine.Gpu.Vendor -eq "none") {
        $gpuText = "{0}no dedicated GPU detected{1}" -f $T.Dim, $T.Reset
    } elseif ($Machine.Gpu.VramGb -gt 0) {
        $gpuText = "{0}{1}{2}  {3} GB VRAM{4}" -f `
            $T.Fg, $Machine.Gpu.Name, $T.Reset, $Machine.Gpu.VramGb, $(if ($Machine.Gpu.CudaCap) { "  CUDA $($Machine.Gpu.CudaCap)" } else { "" })
    } else {
        $gpuText = "{0}{1}{2}" -f $T.Fg, $Machine.Gpu.Name, $T.Reset
    }
    $lines += "GPU  $gpuText"

    $wslText = "not installed"
    if ($Machine.WslProbeSlow) {
        $wslText = "installed, but 'wsl -l' did not answer in 6s"
    } elseif ($Machine.HasWsl) {
        if ($Machine.WslDistros.Count) { $wslText = ($Machine.WslDistros -join ", ") }
        else { $wslText = "installed, no distro" }
    }
    $lines += "WSL  {0}{1}{2}    local LLM  {3}{4}{2}" -f `
        $T.Fg, $wslText, $T.Reset, $T.Dim, $Machine.LlmNote

    return $lines
}
