# What the debloat step can be asked to do, in one place.
#
# Two scripts offer the same choice: debloat-windows.ps1 when it is run on its
# own, and setup.ps1 before it starts any step. They used to be one - the
# script asked for itself - but a setup started from an elevated terminal runs
# every step with stdin redirected, so the script saw no console, took its
# defaults, and removed 24 apps without anyone having been asked. The question
# has to be put where the person is, which is the setup; the list it is built
# from lives here so the two cannot drift.
#
# PowerShell 5.1 compatible. No StrictMode on purpose: this is dot-sourced by
# debloat-windows.ps1, which goes on to call Win11Debloat - code that is not
# written to StrictMode and breaks under an inherited one.

# Bundled consumer apps with no role in a dev setup. Keep it conservative:
# removing an app is the one thing here that cannot be undone.
function Get-DebloatAppsToRemove {
    return @(
        "Clipchamp.Clipchamp"
        "Microsoft.BingNews"
        "Microsoft.BingWeather"
        "Microsoft.BingSearch"
        "Microsoft.GamingApp"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.People"
        "Microsoft.PowerAutomateDesktop"
        "Microsoft.Todos"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.Xbox.TCUI"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
        "MicrosoftCorporationII.MicrosoftFamily"
        "MicrosoftTeams"
        "MSTeams"
    )
}

# The groups present in the profile, in the order they appear there.
function Get-DebloatGroups {
    param([Parameter(Mandatory = $true)]$DebloatConfig)
    return @($DebloatConfig.Tweaks | ForEach-Object { $_.Group } | Where-Object { $_ } | Select-Object -Unique)
}

# Checklist items for Show-TuiChecklist: one per group, plus "apps".
#
# tiling and apps come ticked: the first is what this desktop needs to work at
# all - komorebi cannot place a window Windows keeps snapping - and the second
# is what most people run a debloat for. Everything else is taste.
function Get-DebloatGroupItems {
    param([Parameter(Mandatory = $true)]$DebloatConfig)

    $blurbs = @{
        tiling   = "stop Windows fighting komorebi for window placement"
        taskbar  = "strip the Windows taskbar back - yasb is the real one"
        explorer = "real file extensions, hidden files, opens on This PC"
        privacy  = "telemetry, Bing in search, suggestion surfaces, ads"
        ai       = "Copilot, Recall, Click to Do, AI in Edge/Paint/Notepad"
        system   = "dark mode, mouse acceleration, fast start-up, updates"
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($g in (Get-DebloatGroups -DebloatConfig $DebloatConfig)) {
        $n = @($DebloatConfig.Tweaks | Where-Object { $_.Group -eq $g }).Count
        $blurb = $blurbs[$g]
        if (-not $blurb) { $blurb = "settings from configs/windows/debloat.json" }
        # Formatted out here: inside .Add( ... ) the comma in `-f $n, $blurb`
        # separates METHOD ARGUMENTS, and the hashtable literal fails to parse.
        $desc = "{0} setting(s) - {1}" -f $n, $blurb
        $items.Add([pscustomobject]@{
            Key         = $g
            Title       = $g
            Description = $desc
            Selected    = ($g -eq "tiling")
            Available   = $true
            Note        = ""
        })
    }
    $items.Add([pscustomobject]@{
        Key         = "apps"
        Title       = "apps"
        Description = "remove {0} bundled apps (Xbox, Solitaire, Teams, Bing News...) - NOT reversible" -f @(Get-DebloatAppsToRemove).Count
        Selected    = $true
        Available   = $true
        Note        = ""
    })
    return ,$items.ToArray()
}
