# Omarchy menu, ported to Windows.
#
# Omarchy funnels almost everything through one nested menu on SUPER+SPACE so
# you never have to remember where a setting lives.
#
#   SUPER+SPACE   -> root menu
#   SUPER+ESC     -> straight to the system section
#
# WHY THIS IS A WINDOW AND NOT A TERMINAL
#
# The first version drove fzf inside a small Alacritty window. It worked, but it
# read as "a terminal happened to open", which is exactly what Omarchy's does
# not: over there the menu is walker in dmenu mode, an overlay that belongs to
# the desktop. The Windows equivalent is a plain WPF window - already on every
# Windows 11 install, no extra package, and it can be centred, styled and driven
# with the mouse.
#
# So this is a real window: centred on the monitor the pointer is on, rows big
# enough to click, wheel scrolling, type-to-filter, and it closes when it loses
# focus the way a launcher should.
#
# Actions still shell out to the same helpers. The few that genuinely need a
# console - anything that prints a list, or asks a question - open a terminal on
# purpose; everything else runs silently.
#
# Add your own entries in Get-Menu below.

[CmdletBinding()]
param(
    [string]$Menu = "root",
    [switch]$Serve,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"

# The menu is slow to build - ~300ms of that is XAML parsing - and it sits on a
# keystroke. -Serve builds the window once, keeps it hidden, and shows it when
# a signal file appears, which turns 770ms into roughly the poll interval.
$SignalFile = Join-Path $env:USERPROFILE ".config\omarchy\menu.show"
$ServerPid  = Join-Path $env:USERPROFILE ".config\omarchy\menu-server.pid"

if ($Stop) {
    try {
        if (Test-Path -LiteralPath $ServerPid) {
            $old = [int](Get-Content -LiteralPath $ServerPid -Raw).Trim()
            Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $ServerPid -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    exit 0
}

if ($Serve) {
    # One server. A second would sit on the same signal file and both would pop
    # a window for every request.
    $mutex = $null
    try { $mutex = New-Object System.Threading.Mutex($false, "Local\omarchy-menu-server") } catch { $mutex = $null }
    if ($mutex -and -not $mutex.WaitOne(0)) { exit 0 }
    try { $PID | Set-Content -LiteralPath $ServerPid -Encoding ASCII } catch { }
    Remove-Item -LiteralPath $SignalFile -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# No Add-Type -MemberDefinition anywhere in here. It compiles C# at runtime and
# cost 288ms of the ~930ms it took this menu to appear - by far the largest
# single item. It was only being used to hide a console window that
# omarchy-menu.cmd already starts hidden.

$cfg = Join-Path $env:USERPROFILE ".config"
$bin = Join-Path $cfg "omarchy\bin"

# CLI tools: PATH is the right answer, plus a couple of known install spots.
function Resolve-Bin {
    param([string]$Name, [string[]]$Fallbacks = @())
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($f in $Fallbacks) {
        $expanded = [Environment]::ExpandEnvironmentVariables($f)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return $null
}

# GUI apps are a different problem, and getting it wrong is why picking
# "Browser" used to report that Brave was not installed when it plainly was:
# installers do not put GUI apps on PATH. Measured on this machine, of the apps
# this menu offers only explorer and nvim were on PATH at all.
#
# So resolve the way Windows itself does, cheapest first:
#
#   1. PATH                 - right for CLI tools, occasionally right for apps
#   2. App Paths registry   - what Win+R uses. Brave registers here; many do not
#   3. Start menu shortcut  - what the user would click. Found Brave, DBeaver,
#                             Bitwarden and Alacritty when the first two failed,
#                             and picks the real dbeaver.exe rather than the
#                             dbeaver-cli.exe that a directory scan turns up
#   4. explicit fallbacks   - last resort, machine-specific
#
# Enumerating the start menu is ~40ms and only happens when a lookup gets that
# far, so the common case costs nothing.
$script:LnkCache = $null

function Get-StartMenuTarget {
    param([string]$Name)
    if ($null -eq $script:LnkCache) {
        $script:LnkCache = @()
        foreach ($r in @([Environment]::GetFolderPath("Programs"),
                         [Environment]::GetFolderPath("CommonPrograms"))) {
            if ($r -and (Test-Path -LiteralPath $r)) {
                $script:LnkCache += Get-ChildItem $r -Filter *.lnk -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
    $needle = ($Name -replace "[^a-zA-Z0-9]", "")
    if (-not $needle) { return $null }
    $hit = $script:LnkCache |
        Where-Object { ($_.BaseName -replace "[^a-zA-Z0-9]", "") -like "*$needle*" } |
        Sort-Object { $_.BaseName.Length } |
        Select-Object -First 1
    if (-not $hit) { return $null }
    try {
        $sh = New-Object -ComObject WScript.Shell
        $t = $sh.CreateShortcut($hit.FullName).TargetPath
        if ($t -and (Test-Path -LiteralPath $t)) { return $t }
    } catch { }
    return $null
}

function Resolve-App {
    param([string]$Name, [string[]]$Fallbacks = @())

    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c -and $c.Source) { return $c.Source }

    foreach ($hive in @("HKLM:", "HKCU:")) {
        $k = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$Name.exe"
        if (Test-Path -LiteralPath $k) {
            $v = (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue)."(default)"
            if ($v) {
                $v = $v.Trim('"')
                if (Test-Path -LiteralPath $v) { return $v }
            }
        }
    }

    $sm = Get-StartMenuTarget $Name
    if ($sm) { return $sm }

    foreach ($f in $Fallbacks) {
        $expanded = [Environment]::ExpandEnvironmentVariables($f)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return $null
}

# Looked up on demand, not at startup: every menu open paid for this before,
# including the ones that never touch a terminal.
$script:Term = $null
function Get-Terminal {
    if ($null -eq $script:Term) {
        $script:Term = Resolve-App "alacritty" @(
            "%ProgramFiles%\Alacritty\alacritty.exe",
            "%LOCALAPPDATA%\Programs\Alacritty\alacritty.exe"
        )
        if (-not $script:Term) { $script:Term = "" }
    }
    if ($script:Term) { return $script:Term }
    return $null
}

function Start-InTerminal {
    param([Parameter(Mandatory)][string[]]$Command)
    $term = Get-Terminal
    if ($term) {
        Start-Process -FilePath $term -ArgumentList (@("-e") + $Command)
    } else {
        Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Count - 1)])
    }
}

# Run one of our own helpers in a terminal, for the handful that print something
# worth reading.
function Start-HelperInTerminal {
    param([string]$Script, [string[]]$Arguments = @())
    $ps = Resolve-Bin "pwsh" @("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
    Start-InTerminal (@($ps, "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Script) + $Arguments)
}

function Start-Helper {
    param([string]$Script, [string[]]$Arguments = @())
    $ps = Resolve-Bin "pwsh" @("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
    Start-Process -FilePath $ps -WindowStyle Hidden `
        -ArgumentList (@("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Script) + $Arguments)
}

function Show-Problem {
    param([string]$Message)
    [void][System.Windows.MessageBox]::Show($Message, "omarchy",
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
}

function Start-App {
    param([string]$Name, [string[]]$Arguments = @(), [string[]]$Fallbacks = @())
    $p = Resolve-App $Name $Fallbacks
    if (-not $p) {
        Show-Problem "Could not find $Name.`n`nLooked on PATH, in App Paths and in the Start menu."
        return
    }
    if ($Arguments.Count) { Start-Process -FilePath $p -ArgumentList $Arguments }
    else { Start-Process -FilePath $p }
}

function Edit-Config {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { Show-Problem "Not found: $Path"; return }

    $editor = Resolve-Bin "nvim"
    if (-not $editor) { $editor = Resolve-App "code" }
    if (-not $editor) { $editor = Resolve-Bin "notepad" @("%SystemRoot%\System32\notepad.exe") }
    if (-not $editor) { Show-Problem "No editor found (looked for nvim, code, notepad)."; return }

    # notepad is a GUI app - putting it inside a terminal gives you an empty
    # terminal and a detached notepad, so only terminal editors go via -e.
    if ($editor -match 'nvim|vim') { Start-InTerminal @($editor, $Path) }
    else { Start-Process -FilePath $editor -ArgumentList $Path }
}

function New-Entry {
    param([string]$Label, [string]$Desc = "", [string]$Sub = "",
          [scriptblock]$Action = $null, [scriptblock]$Prompt = $null)
    [pscustomobject]@{
        Label   = $Label
        Desc    = $Desc
        Sub     = $Sub
        Action  = $Action
        Prompt  = $Prompt
        Chevron = $(if ($Sub) { [string][char]0x203A } else { "" })
    }
}

function Get-Menu {
    param([string]$Name)

    switch ($Name) {

        "root" { @(
            (New-Entry "Apps"       "Launch an application"    -Sub "apps")
            (New-Entry "Agents"     "Coding agents"            -Sub "agents")
            (New-Entry "Windows"    "Layout and tiling"        -Sub "windows")
            (New-Entry "Workspaces" "Jump to a workspace"      -Sub "workspaces")
            (New-Entry "Capture"    "Screenshot and recording" -Sub "capture")
            (New-Entry "Toggle"     "Flip a desktop setting"   -Sub "toggle")
            (New-Entry "Setup"      "Edit a config file"       -Sub "setup")
            (New-Entry "Learn"      "Keybindings and docs"     -Sub "learn")
            (New-Entry "System"     "Lock, sleep, restart"     -Sub "system")
        ) }

        "apps" { @(
            # No -e: let Alacritty start its configured shell (pwsh).
            (New-Entry "Terminal" "Alacritty with PowerShell" -Action {
                $t = Get-Terminal
                if ($t) { Start-Process -FilePath $t } else { Show-Problem "Could not find Alacritty." } })
            (New-Entry "Terminal (WSL + tmux)" "AlmaLinux, attached to the main session" -Action {
                Start-InTerminal @("wsl.exe","-d","AlmaLinux-9","--","tmux","new-session","-A","-s","main") })
            (New-Entry "Neovim (WSL)" "Editor in AlmaLinux" -Action {
                Start-InTerminal @("wsl.exe","-d","AlmaLinux-9","--","nvim") })
            (New-Entry "Browser" "Brave" -Action { Start-App "brave" })
            (New-Entry "Browser (private)" "Brave, incognito window" -Action { Start-App "brave" @("--incognito") })
            (New-Entry "File manager" "Explorer" -Action { Start-App "explorer" })
            (New-Entry "Everything" "Instant file search" -Action { Start-App "everything" })
            (New-Entry "electerm" "SSH client" -Action { Start-App "electerm" })
            (New-Entry "DBeaver" "Database client" -Action { Start-App "dbeaver" })
            (New-Entry "Bitwarden" "Password manager and SSH agent" -Action { Start-App "bitwarden" })
            (New-Entry "btop" "Process and resource monitor" -Action { Start-InTerminal @("btop") })
            (New-Entry "lazygit" "Git TUI" -Action { Start-InTerminal @("lazygit") })
        ) }

        "agents" { @(
            (New-Entry "Launch default agent" "In a new terminal" -Action {
                Start-HelperInTerminal (Join-Path $bin "omarchy-agent.ps1") })
            (New-Entry "Launch default agent (WSL)" "Inside AlmaLinux" -Action {
                Start-HelperInTerminal (Join-Path $bin "omarchy-agent.ps1") @("-Wsl") })
            (New-Entry "Launch with a prompt" "Type the prompt, then Enter" -Prompt {
                param($text)
                if ($text) { Start-HelperInTerminal (Join-Path $bin "omarchy-agent.ps1") @("-Prompt", $text) } })
            (New-Entry "Launch unattended" "Skips every permission prompt" -Sub "agents-yolo")
            (New-Entry "Pick / change default" "Choose which agent SUPER+A runs" -Action {
                Start-HelperInTerminal (Join-Path $bin "omarchy-agent.ps1") @("-Pick") })
            (New-Entry "List agents" "Show what is installed" -Action {
                Start-HelperInTerminal (Join-Path $bin "omarchy-default-agent.ps1") @("-List") })
        ) }

        "agents-yolo" { @(
            (New-Entry "Cancel" "Go back without running anything" -Sub "agents")
            (New-Entry "Yes, run unattended" "The agent can run any command, including against your SSH agent and work trees" -Action {
                Start-HelperInTerminal (Join-Path $bin "omarchy-agent.ps1") @("-Yolo") })
        ) }

        "windows" { @(
            (New-Entry "Scrolling mode" "Toggle the horizontal strip" -Action {
                Start-Helper (Join-Path $bin "omarchy-scrolling.ps1") })
            (New-Entry "Scrolling: 2 columns" "Two windows side by side in the strip" -Action {
                komorebic change-layout scrolling; komorebic scrolling-layout-columns 2 })
            (New-Entry "Next layout" "Cycle forward" -Action { komorebic cycle-layout next })
            (New-Entry "Previous layout" "Cycle back" -Action { komorebic cycle-layout previous })
            (New-Entry "BSP" "Binary space partitioning" -Action { komorebic change-layout bsp })
            (New-Entry "Columns" "Equal vertical columns" -Action { komorebic change-layout columns })
            (New-Entry "Rows" "Equal horizontal rows" -Action { komorebic change-layout rows })
            (New-Entry "Grid" "Even grid" -Action { komorebic change-layout grid })
            (New-Entry "Ultrawide vertical stack" "Main window centred" -Action { komorebic change-layout ultrawide-vertical-stack })
            (New-Entry "Scrolling" "Horizontal strip" -Action { komorebic change-layout scrolling })
            (New-Entry "Flip horizontal" "Mirror the layout left to right" -Action { komorebic flip-layout horizontal })
            (New-Entry "Flip vertical" "Mirror the layout top to bottom" -Action { komorebic flip-layout vertical })
            (New-Entry "Promote window" "Make this the main window" -Action { komorebic promote })
            (New-Entry "Retile" "Re-apply the layout" -Action { komorebic retile })
            (New-Entry "Reload configuration" "Re-read komorebi.json" -Action { komorebic reload-configuration })
        ) }

        "capture" { @(
            (New-Entry "Region to clipboard" "Snip part of the screen" -Action { Start-Process "ms-screenclip:" })
            (New-Entry "Snipping Tool" "Full capture app" -Action { Start-Process "snippingtool:" })
            (New-Entry "Screen recording" "Xbox Game Bar" -Action { Start-Process "ms-gamebar:" })
            (New-Entry "Open Screenshots folder" "Pictures\Screenshots" -Action {
                Start-Process "explorer" -ArgumentList (Join-Path $env:USERPROFILE "Pictures\Screenshots") })
        ) }

        "toggle" { @(
            (New-Entry "Status bar" "Show or hide yasb" -Action { Start-Helper (Join-Path $bin "omarchy-toggle-bar.ps1") })
            (New-Entry "Pause tiling" "Stop managing windows" -Action { komorebic toggle-pause })
            (New-Entry "Tiling on this workspace" "Manage or leave windows alone" -Action { komorebic toggle-tiling })
            (New-Entry "Float this window" "Take it out of the layout" -Action { komorebic toggle-float })
            (New-Entry "Float override" "Float everything new" -Action { komorebic toggle-float-override })
            (New-Entry "Monocle" "Focused window fills the screen" -Action { komorebic toggle-monocle })
            (New-Entry "Transparency" "Dim unfocused windows" -Action { komorebic toggle-transparency })
            (New-Entry "Title bars" "Show or hide window title bars" -Action { komorebic toggle-title-bars })
            (New-Entry "Mouse follows focus" "Warp the pointer on focus" -Action { komorebic toggle-mouse-follows-focus })
            (New-Entry "Workspace layer" "Switch the workspace layer" -Action { komorebic toggle-workspace-layer })
        ) }

        "setup" { @(
            (New-Entry "whkd keybindings" "~/.config/whkdrc" -Action { Edit-Config (Join-Path $cfg "whkdrc") })
            (New-Entry "komorebi" "Window manager config" -Action { Edit-Config (Join-Path $cfg "komorebi\komorebi.json") })
            (New-Entry "yasb config" "Status bar widgets" -Action { Edit-Config (Join-Path $cfg "yasb\config.yaml") })
            (New-Entry "yasb styles" "Status bar CSS" -Action { Edit-Config (Join-Path $cfg "yasb\styles.css") })
            (New-Entry "Alacritty" "Terminal config" -Action { Edit-Config (Join-Path $env:APPDATA "alacritty\alacritty.toml") })
            (New-Entry "PowerShell profile" "Shell startup" -Action { Edit-Config $PROFILE.CurrentUserCurrentHost })
            (New-Entry "SSH config" "~/.ssh/config" -Action { Edit-Config (Join-Path $env:USERPROFILE ".ssh\config") })
            (New-Entry "Git config" "~/.gitconfig" -Action { Edit-Config (Join-Path $env:USERPROFILE ".gitconfig") })
            (New-Entry "WSL config" "~/.wslconfig" -Action { Edit-Config (Join-Path $env:USERPROFILE ".wslconfig") })
            (New-Entry "Restart desktop" "komorebi, whkd, yasb" -Action { Start-Helper (Join-Path $bin "omarchy-restart-desktop.ps1") })
        ) }

        "learn" { @(
            (New-Entry "Keybindings" "Every chord, searchable" -Action {
                Start-HelperInTerminal (Join-Path $bin "omarchy-keybindings.ps1") })
            (New-Entry "komorebi docs" "lgug2z.github.io/komorebi" -Action { Start-Process "https://lgug2z.github.io/komorebi/" })
            (New-Entry "yasb docs" "github.com/amnweb/yasb/wiki" -Action { Start-Process "https://github.com/amnweb/yasb/wiki" })
            (New-Entry "Omarchy (the original)" "omarchy.org" -Action { Start-Process "https://omarchy.org" })
        ) }

        "system" { @(
            (New-Entry "Lock" "Lock the session" -Action { rundll32.exe user32.dll,LockWorkStation })
            (New-Entry "Sleep" "Suspend to RAM" -Action { rundll32.exe powrprof.dll,SetSuspendState 0,1,0 })
            (New-Entry "Sign out" "End the session" -Action { shutdown.exe /l })
            (New-Entry "Restart" "Reboot now" -Action { shutdown.exe /r /t 0 })
            (New-Entry "Shut down" "Power off now" -Action { shutdown.exe /s /t 0 })
            (New-Entry "Restart desktop stack" "komorebi, whkd, yasb" -Action { Start-Helper (Join-Path $bin "omarchy-restart-desktop.ps1") })
            (New-Entry "Stop komorebi" "Leave windows unmanaged" -Action { komorebic stop --whkd })
            (New-Entry "WSL shutdown" "Stop every distribution" -Action { wsl.exe --shutdown })
        ) }

        "workspaces" {
            # Built from the live state so the names match komorebi.json rather
            # than a second copy of the list that can drift out of date.
            $items = @()
            try {
                $state = komorebic state 2>$null | ConvertFrom-Json
                $mon = $state.monitors.elements[$state.monitors.focused]
                for ($i = 0; $i -lt $mon.workspaces.elements.Count; $i++) {
                    $ws = $mon.workspaces.elements[$i]
                    $nm = if ($ws.name) { $ws.name } else { "workspace $($i + 1)" }
                    $n  = $ws.containers.elements.Count
                    $d  = if ($n -eq 0) { "empty" } elseif ($n -eq 1) { "1 window" } else { "$n windows" }
                    $items += (New-Entry "$($i + 1)  $nm" $d -Action ([scriptblock]::Create("komorebic focus-workspace $i")))
                }
            } catch {
                $items += (New-Entry "komorebi is not running" "Start it with start-desktop.ps1" -Action { })
            }
            $items
        }

        default { @() }
    }
}

# --- window -----------------------------------------------------------------

$xamlSource = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="omarchy" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" Width="780" Height="620"
        FontFamily="Segoe UI Variable Text, Segoe UI">
  <Border Background="{{background}}" CornerRadius="14" BorderBrush="{{muted}}" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Padding="24,18,24,16" BorderBrush="{{selection}}" BorderThickness="0,0,0,1">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBlock x:Name="Crumb" Grid.Column="0" Text="omarchy" Foreground="{{accent}}"
                     FontSize="21" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,16,0"/>
          <TextBox x:Name="Search" Grid.Column="1" Background="Transparent" Foreground="{{bright_foreground}}"
                   BorderThickness="0" FontSize="21" CaretBrush="{{accent}}"
                   VerticalContentAlignment="Center" Padding="0"/>
        </Grid>
      </Border>

      <ListBox x:Name="List" Grid.Row="1" Background="Transparent" BorderThickness="0"
               Foreground="{{bright_foreground}}" Padding="8,10,8,10"
               ScrollViewer.HorizontalScrollBarVisibility="Disabled"
               ScrollViewer.VerticalScrollBarVisibility="Auto">
        <ListBox.Resources>
          <!-- The stock scrollbar is light grey chrome and looks pasted on. -->
          <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="9"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ScrollBar">
                  <Grid Background="Transparent">
                    <Track x:Name="PART_Track" IsDirectionReversed="True">
                      <Track.Thumb>
                        <Thumb>
                          <Thumb.Template>
                            <ControlTemplate TargetType="Thumb">
                              <Border Background="{{muted}}" CornerRadius="4" Margin="2,0"/>
                            </ControlTemplate>
                          </Thumb.Template>
                        </Thumb>
                      </Track.Thumb>
                      <Track.IncreaseRepeatButton>
                        <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                      </Track.IncreaseRepeatButton>
                      <Track.DecreaseRepeatButton>
                        <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                      </Track.DecreaseRepeatButton>
                    </Track>
                  </Grid>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </ListBox.Resources>
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem">
            <Setter Property="Padding" Value="18,13"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                  <Border x:Name="Bd" Background="{TemplateBinding Background}"
                          Padding="{TemplateBinding Padding}" CornerRadius="9" Margin="12,2">
                    <ContentPresenter/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="Bd" Property="Background" Value="{{selection}}"/>
                    </Trigger>
                    <Trigger Property="IsSelected" Value="True">
                      <Setter TargetName="Bd" Property="Background" Value="{{muted}}"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Text="{Binding Label}" FontSize="17" Foreground="{{bright_foreground}}"
                           TextTrimming="CharacterEllipsis"/>
                <TextBlock Text="{Binding Desc}" FontSize="12.5" Foreground="{{dark_foreground}}"
                           Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <TextBlock Grid.Column="1" Text="{Binding Chevron}" FontSize="19" Foreground="{{dark_foreground}}"
                         VerticalAlignment="Center" Margin="14,0,4,0"/>
            </Grid>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>

      <Border Grid.Row="2" Padding="24,12,24,14" BorderBrush="{{selection}}" BorderThickness="0,1,0,0">
        <TextBlock x:Name="Hint" Foreground="{{dark_foreground}}" FontSize="12.5"
                   Text="Type to filter    Enter run    Esc back    click or scroll with the mouse"/>
      </Border>
    </Grid>
  </Border>
</Window>
'@

# Colours come from the active palette, not from literals in here - the whole
# desktop is themed from one file (see omarchy-theme.ps1). Falls back to Tokyo
# Night so the menu still renders on a machine that has never set a theme.
$fallback = @{
    background = "#1a1b26"; lighter_background = "#24283b"; selection = "#292e42"
    muted = "#414868"; accent = "#7aa2f7"
    bright_foreground = "#c0caf5"; dark_foreground = "#565f89"
}
$palette = $fallback.Clone()
try {
    $themeHome = Join-Path $cfg "omarchy\theme"
    $active = "tokyo-night"
    $activeFile = Join-Path $themeHome "active"
    if (Test-Path -LiteralPath $activeFile) {
        $n = (Get-Content -LiteralPath $activeFile -Raw).Trim()
        if ($n) { $active = $n }
    }
    $palFile = Join-Path $themeHome "palettes\$active.toml"
    if (Test-Path -LiteralPath $palFile) {
        foreach ($line in Get-Content -LiteralPath $palFile) {
            $mm = [regex]::Match($line, '^\s*(\w+)\s*=\s*"([^"]*)"')
            if ($mm.Success) { $palette[$mm.Groups[1].Value] = $mm.Groups[2].Value }
        }
    }
} catch { }

$xamlText = [regex]::Replace($xamlSource, '\{\{(\w+)\}\}', {
    param($mm)
    $k = $mm.Groups[1].Value
    if ($palette.ContainsKey($k)) { return $palette[$k] }
    return "#1a1b26"
})
[xml]$xamlDoc = $xamlText

$reader = New-Object System.Xml.XmlNodeReader $xamlDoc
$win    = [Windows.Markup.XamlReader]::Load($reader)

$crumb  = $win.FindName("Crumb")
$search = $win.FindName("Search")
$list   = $win.FindName("List")
$hint   = $win.FindName("Hint")

$script:Stack      = New-Object System.Collections.Generic.List[string]
$script:Current    = $Menu
$script:AllItems   = @()
$script:Pending    = $null
$script:PromptItem = $null
$script:DefaultHint = "Type to filter    Enter run    Esc back    click or scroll with the mouse"

function Set-Filter {
    if ($script:PromptItem) { return }
    $q = $search.Text
    if ([string]::IsNullOrWhiteSpace($q)) {
        $list.ItemsSource = $script:AllItems
    } else {
        $list.ItemsSource = @($script:AllItems | Where-Object {
            $_.Label -like "*$q*" -or $_.Desc -like "*$q*"
        })
    }
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
}

function Show-MenuPage {
    param([string]$Name)
    $script:Current    = $Name
    $script:PromptItem = $null
    $script:AllItems   = @(Get-Menu $Name)
    $crumb.Text        = $(if ($Name -eq "root") { "omarchy" } else { $Name })
    $hint.Text         = $script:DefaultHint
    $search.Text       = ""
    Set-Filter
}

function Enter-PromptMode {
    param($Item)
    $script:PromptItem = $Item
    $crumb.Text        = $Item.Label
    $list.ItemsSource  = @()
    $hint.Text         = "$($Item.Desc)    Enter to run    Esc to go back"
    $search.Text       = ""
}

# One-shot closes the window and lets the action run after ShowDialog returns.
# The server hides it instead and runs the action straight away - same visible
# behaviour, but the window survives to be shown again.
function Hide-Menu {
    if ($Serve) { $win.Hide() } else { $win.Close() }
}

function Complete-Entry {
    param([scriptblock]$Action)
    if ($Serve) {
        $win.Hide()
        # Let the hide actually paint before the new process steals focus.
        [System.Windows.Forms.Application]::DoEvents()
        try { & $Action } catch { Show-Problem $_.Exception.Message }
    } else {
        $script:Pending = $Action
        $win.Close()
    }
}

function Invoke-Entry {
    param($Item)
    if (-not $Item) { return }

    if ($Item.Sub) {
        $script:Stack.Add($script:Current)
        Show-MenuPage $Item.Sub
        return
    }
    if ($Item.Prompt) {
        Enter-PromptMode $Item
        return
    }
    if ($Item.Action) {
        Complete-Entry $Item.Action
    }
    }

function Step-Selection {
    param([int]$Delta)
    if ($list.Items.Count -eq 0) { return }
    $i = $list.SelectedIndex + $Delta
    if ($i -lt 0) { $i = $list.Items.Count - 1 }
    if ($i -ge $list.Items.Count) { $i = 0 }
    $list.SelectedIndex = $i
    $list.ScrollIntoView($list.SelectedItem)
}

function Step-Back {
    if ($script:PromptItem) { Show-MenuPage $script:Current; return }
    if ($script:Stack.Count -gt 0) {
        $prev = $script:Stack[$script:Stack.Count - 1]
        $script:Stack.RemoveAt($script:Stack.Count - 1)
        Show-MenuPage $prev
    } else {
        Hide-Menu
    }
}

$win.Add_PreviewKeyDown({
    # WPF hands the handler (sender, args) positionally. Taking the second off
    # $args avoids declaring a $sender parameter that is never used - and
    # $sender is an automatic variable, so binding it is asking for trouble.
    $e = $args[1]
    switch ([string]$e.Key) {
        "Escape" { Step-Back; $e.Handled = $true }
        "Return" {
            if ($script:PromptItem) {
                $text = $search.Text
                $blk  = $script:PromptItem.Prompt
                Complete-Entry ({ & $blk $text }.GetNewClosure())
            } else {
                Invoke-Entry $list.SelectedItem
            }
            $e.Handled = $true
        }
        "Down" { Step-Selection 1;  $e.Handled = $true }
        "Up"   { Step-Selection -1; $e.Handled = $true }
        "Tab"  { Step-Selection 1;  $e.Handled = $true }
        "Back" {
            # Backspace on an empty box is "go up a level", the way a file
            # manager treats it. With text in the box it edits normally.
            if ([string]::IsNullOrEmpty($search.Text)) { Step-Back; $e.Handled = $true }
        }
        "Right" {
            $sel = $list.SelectedItem
            if ($sel -and $sel.Sub -and [string]::IsNullOrEmpty($search.Text)) {
                Invoke-Entry $sel; $e.Handled = $true
            }
        }
        "Left" {
            if ([string]::IsNullOrEmpty($search.Text)) { Step-Back; $e.Handled = $true }
        }
    }
})

$search.Add_TextChanged({ Set-Filter })

# Single click runs, the way a launcher behaves. Resolve the row under the
# pointer rather than trusting SelectedItem, which has not updated yet at
# preview time.
$list.Add_PreviewMouseLeftButtonUp({
    $e = $args[1]
    $src = $e.OriginalSource
    while ($src -and -not ($src -is [System.Windows.Controls.ListBoxItem])) {
        $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src)
    }
    if ($src) {
        $list.SelectedItem = $src.DataContext
        $e.Handled = $true
        Invoke-Entry $src.DataContext
    }
})

# A launcher that stays open behind the window you just clicked is a bug, not a
# feature.
$win.Add_Deactivated({ Hide-Menu })

$win.Add_Loaded({
    Set-MenuPlacement
    [void]$win.Activate()
    [void]$search.Focus()
})

# Positioning has to happen on every show, not once at load: the pointer may be
# on a different monitor than it was last time.
function Set-MenuPlacement {
    try {
        $mouse  = [System.Windows.Forms.Cursor]::Position
        $screen = [System.Windows.Forms.Screen]::FromPoint($mouse)
        $wa     = $screen.WorkingArea
        $sx = 1.0; $sy = 1.0
        $src = [System.Windows.PresentationSource]::FromVisual($win)
        if ($src -and $src.CompositionTarget) {
            $sx = $src.CompositionTarget.TransformToDevice.M11
            $sy = $src.CompositionTarget.TransformToDevice.M22
        }
        if ($sx -le 0) { $sx = 1.0 }
        if ($sy -le 0) { $sy = 1.0 }
        $win.Left = ($wa.X / $sx) + ((($wa.Width  / $sx) - $win.Width)  / 2)
        $win.Top  = ($wa.Y / $sy) + ((($wa.Height / $sy) - $win.Height) / 2)
    } catch { }
}

if (-not $Serve) {
    Show-MenuPage $script:Current
    [void]$win.ShowDialog()

    # Actions run after the window is gone, so whatever they launch comes up in
    # front instead of behind a topmost menu.
    if ($script:Pending) { & $script:Pending }
    exit 0
}

# --- server ------------------------------------------------------------------
#
# A file rather than a pipe, on purpose. The window lives on this thread, and a
# blocking pipe read would either freeze the UI or need a second thread to hand
# work back across - which is exactly the shape that deadlocked the komorebi
# listener. A timer checking for a file cannot deadlock anything, and the cost
# is one File.Exists every 60ms.
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(60)
$timer.Add_Tick({
    if (-not (Test-Path -LiteralPath $SignalFile)) { return }
    $section = "root"
    try {
        $req = (Get-Content -LiteralPath $SignalFile -Raw -ErrorAction SilentlyContinue)
        if ($req) { $req = $req.Trim() }
        if ($req) { $section = $req }
    } catch { }
    Remove-Item -LiteralPath $SignalFile -Force -ErrorAction SilentlyContinue

    # Every show starts clean: no leftover search text, no half-walked stack.
    $script:Stack.Clear()
    Show-MenuPage $section
    Set-MenuPlacement
    $win.Show()
    [void]$win.Activate()
    [void]$search.Focus()
})
$timer.Start()

Show-MenuPage $script:Current
[System.Windows.Threading.Dispatcher]::Run()