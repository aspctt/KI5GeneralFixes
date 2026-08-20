<#
    KI5 General Fixes test runner.

    Boots Project Zomboid's own Kahlua VM outside the game, stubs the parts of the
    game API the fixes touch, and runs the specs in tests/specs against the real mod
    source. No game launch, no manual clicking.

    Usage:  pwsh tests/run-tests.ps1
#>

$ErrorActionPreference = 'Stop'

function Find-GameDir {
    # An explicit override wins, for an install this does not know about.
    if ($env:KI5GF_PZ_DIR) { return $env:KI5GF_PZ_DIR }

    # Otherwise walk every Steam library listed in libraryfolders.vdf, then fall
    # back to the usual suspects. Beats hardcoding one machine's drive letter.
    $candidates = @()
    foreach ($steam in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s*"([^"]+)"')) {
                $candidates += Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common\ProjectZomboid'
            }
        }
    }
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem).Name) {
        $candidates += "${drive}:\SteamLibrary\steamapps\common\ProjectZomboid"
        $candidates += "${drive}:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
    }

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'projectzomboid.jar')) { return $c }
    }
    throw "Could not find a Project Zomboid install. Set KI5GF_PZ_DIR to its folder."
}

$GameDir  = Find-GameDir
$Jar      = Join-Path $GameDir 'projectzomboid.jar'
$Root     = Split-Path -Parent $PSScriptRoot
# The repository is laid out the way Steam expects a Workshop item, so the mod itself is
# several levels down. Everything below, and TestRunner, works from this one path.
$ModRoot  = Join-Path $Root 'KI5GeneralFixes\Contents\mods\KI5GeneralFixes'
$Harness  = Join-Path $PSScriptRoot 'harness'
$Specs    = Join-Path $PSScriptRoot 'specs'
$Build    = Join-Path $PSScriptRoot 'build'

# The unpacked mods this one patches. Other people's work, so it is local only and not in
# the repository. Checks that need it stand down when it is not there rather than
# reporting a clean clone as a failure.
$Reference = Join-Path $Root 'other-mods'

function Find-Jdk {
    $candidates = @(
        'C:\Program Files\Eclipse Adoptium\jdk-*\bin',
        'C:\Program Files\*\jdk*\bin',
        'C:\Program Files\JetBrains\*\jbr\bin'
    )
    foreach ($pattern in $candidates) {
        $hit = Get-ChildItem $pattern -ErrorAction SilentlyContinue |
               Where-Object { Test-Path (Join-Path $_.FullName 'javac.exe') } |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw "No JDK with javac found. The JRE bundled with the game cannot compile the runner."
}

# --- preflight -------------------------------------------------------------

if (-not (Test-Path $Jar)) { throw "Game jar not found at $Jar" }
$JdkBin = Find-Jdk
$Javac  = Join-Path $JdkBin 'javac.exe'
$Java   = Join-Path $JdkBin 'java.exe'

$VersionFile = Join-Path $env:USERPROFILE 'Zomboid\version.txt'
$Build42 = if (Test-Path $VersionFile) { (Get-Content $VersionFile | Select-Object -First 1) } else { 'unknown' }

Write-Host "Game    $GameDir"
Write-Host "Build   $Build42"
Write-Host "JDK     $JdkBin"
Write-Host "Ref     $(if (Test-Path $Reference) { $Reference } else { 'not present, reference checks stand down' })"
Write-Host ""

# --- compile the runner ----------------------------------------------------

New-Item -ItemType Directory -Force -Path $Build | Out-Null
$RunnerSrc = Join-Path $Harness 'TestRunner.java'
$RunnerCls = Join-Path $Build 'TestRunner.class'

if (-not (Test-Path $RunnerCls) -or (Get-Item $RunnerSrc).LastWriteTime -gt (Get-Item $RunnerCls).LastWriteTime) {
    Write-Host "Compiling test runner..."
    & $Javac -nowarn -cp $Jar -d $Build $RunnerSrc
    if ($LASTEXITCODE -ne 0) { throw "Failed to compile TestRunner.java" }
}

# --- assemble the load order -----------------------------------------------
# Stubs first, then translations, then the real PZAPI, then the assertions, then the mod
# under test, then the specs. Order matters: each layer depends on the last.

$LoadFiles = @()
$LoadFiles += Join-Path $Harness 'pz_stubs.lua'

$TranslateDir = Join-Path $ModRoot '42\media\lua\shared\Translate\EN'
if (Test-Path $TranslateDir) {
    $LoadFiles += Get-ChildItem $TranslateDir -Filter *.json | ForEach-Object { $_.FullName }
}

$LoadFiles += Join-Path $GameDir 'media\lua\client\PZAPI\ModOptions.lua'
$LoadFiles += Join-Path $Harness 'test_lib.lua'

# shared before client before server, the order the game itself uses. Translate holds
# .json so it is excluded by the .lua filter and loaded earlier.
#
# Singleplayer loads all three trees, so the harness does too. In a multiplayer client
# the server tree would not load, which is exactly why where a file lives is a decision
# rather than a detail.
foreach ($tree in @('shared', 'client', 'server')) {
    $dir = Join-Path $ModRoot "42\media\lua\$tree"
    if (-not (Test-Path $dir)) { continue }
    $LoadFiles += Get-ChildItem $dir -Filter *.lua -Recurse | Sort-Object Name |
                  ForEach-Object { $_.FullName }
}

# The mod source is common to every pass. Only the specs and the mod list change.
$ModFiles = $LoadFiles

foreach ($f in $ModFiles) {
    if (-not (Test-Path $f)) { throw "Missing file in load order: $f" }
}

# --- run -------------------------------------------------------------------
# Kahlua resolves stdlib.lua against the working directory, so run from the game dir.

# The exit code comes back through a script variable rather than the return value,
# because everything a PowerShell function writes to the output stream is part of what it
# returns. Returning the code would swallow the whole test report into it.
$script:PassCode = 0

function Invoke-Pass {
    param([string]$SpecDir, [string]$OtherMods)

    $files = $ModFiles
    if (Test-Path $SpecDir) {
        $files += Get-ChildItem $SpecDir -Filter *_spec.lua | Sort-Object Name |
                  ForEach-Object { $_.FullName }
    }

    $env:KI5GF_MODS = $OtherMods
    if (Test-Path $Reference) { $env:KI5GF_REFERENCE = $Reference }
    Push-Location $GameDir
    try {
        & $Java -cp "$Jar;$Build" TestRunner $GameDir $ModRoot @files
        $script:PassCode = $LASTEXITCODE
    } finally {
        Pop-Location
        $env:KI5GF_MODS = $null
        $env:KI5GF_REFERENCE = $null
    }
}

Invoke-Pass -SpecDir $Specs -OtherMods ''
$code = $script:PassCode

# Some guards decide at file scope whether a fix installs itself at all, so they can only
# be exercised by loading the whole mod again beside the mod they stand down for. One
# pass per such mod, each with its own specs.
$ConflictRoot = Join-Path $PSScriptRoot 'specs-conflicts'
if (Test-Path $ConflictRoot) {
    foreach ($dir in Get-ChildItem $ConflictRoot -Directory | Sort-Object Name) {
        Write-Host ""
        Write-Host "--- second pass, also loaded: $($dir.Name) ---"
        Write-Host ""

        Invoke-Pass -SpecDir $dir.FullName -OtherMods $dir.Name
        if ($script:PassCode -ne 0) { $code = $script:PassCode }
    }
}

exit $code
