#requires -Version 5.1
# VCam watermark patch (Windows)
# Run from an elevated PowerShell (Admin):
#   powershell -ExecutionPolicy Bypass -File .\windows\apply.ps1
#   -AppDir <path>   install folder (where VCam.exe lives)
#   -Force           kill running VCam without asking
#   -Restore         restore last backup from originals\
param(
    [string]$AppDir,
    [switch]$Force,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$OrigDir   = Join-Path $RepoRoot 'originals'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-CanWrite {
    param([string]$Path)
    if (Test-IsAdmin) { return }
    # Program Files always needs elevation
    $pf = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($root in $pf) {
        if ($Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ''
            Write-Host 'ERROR: need Administrator to write under Program Files.'
            Write-Host 'Right-click PowerShell -> Run as administrator, then:'
            Write-Host '  powershell -ExecutionPolicy Bypass -File .\windows\apply.ps1'
            exit 1
        }
    }
}

function Find-VCamDir {
    $candidates = @()

    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $regRoots) {
        Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*VCam*' } |
            ForEach-Object {
                if ($_.InstallLocation) { $candidates += $_.InstallLocation }
                if ($_.DisplayIcon) {
                    $icon = ($_.DisplayIcon -replace '"', '' -split ',')[0]
                    $candidates += (Split-Path -Parent $icon)
                }
            }
    }

    foreach ($base in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) { $candidates += (Join-Path $base 'VCam') }
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\VCam')
    }

    Get-Process -Name 'VCam' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $candidates += (Split-Path -Parent $_.MainModule.FileName) } catch {}
    }

    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        $c = $c.TrimEnd('\')
        if (Test-Path (Join-Path $c 'resources')) {
            return (Resolve-Path $c).Path
        }
    }
    return $null
}

function Stop-VCam {
    $procs = Get-Process -Name 'VCam' -ErrorAction SilentlyContinue
    if (-not $procs) { return }
    if (-not $Force) {
        $ans = Read-Host 'VCam is running. Close it now? [y/N]'
        if ($ans -notmatch '^[yY]') {
            throw 'Close VCam before patching.'
        }
    }
    $procs | Stop-Process -Force
    Start-Sleep -Seconds 2
}

function Get-FunctionBody {
    param([string]$Data, [int]$StartIndex)
    $brace = $Data.IndexOf('{', $StartIndex)
    if ($brace -lt 0) { return $null }
    $depth = 0
    for ($i = $brace; $i -lt $Data.Length; $i++) {
        $ch = $Data[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return @{ Start = $StartIndex; End = $i + 1 }
            }
        }
    }
    return $null
}

function Write-PatchedFile {
    param([string]$Path, [string]$Content)
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.IsReadOnly) {
        $item.IsReadOnly = $false
        Write-Host '       cleared ReadOnly attribute'
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    try {
        [System.IO.File]::WriteAllText($Path, $Content, $utf8)
    } catch [System.UnauthorizedAccessException] {
        Write-Host ''
        Write-Host "ERROR: access denied writing $Path"
        Write-Host 'Run PowerShell as Administrator (right-click -> Run as administrator).'
        Write-Host 'Also make sure VCam is fully closed.'
        exit 1
    }
}

if (-not $AppDir) { $AppDir = Find-VCamDir }
if (-not $AppDir -or -not (Test-Path (Join-Path $AppDir 'resources'))) {
    Write-Error "VCam not found. Pass -AppDir 'C:\Program Files\VCam'"
    exit 1
}
$ResDir = Join-Path $AppDir 'resources'
Write-Host "[0/4] VCam install: $AppDir"
if (Test-IsAdmin) {
    Write-Host '       (running as Administrator)'
} else {
    Write-Host '       (NOT elevated - write to Program Files will fail)'
}

Assert-CanWrite -Path $AppDir

if ($Restore) {
    if (-not (Test-Path $OrigDir)) {
        Write-Error "No backup folder: $OrigDir"
        exit 1
    }
    $bk = Get-ChildItem $OrigDir -Filter '*.orig' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $bk) {
        Write-Error "No backups in $OrigDir"
        exit 1
    }
    $origName = $bk.Name -replace '\.\d{8}-\d{6}\.orig$', ''
    $target = Get-ChildItem $ResDir -Recurse -Filter $origName | Select-Object -First 1
    if (-not $target) {
        Write-Error "Target file for $($bk.Name) not found in install (different VCam version?)"
        exit 1
    }
    Stop-VCam
    Write-PatchedFile -Path $target.FullName -Content ([System.IO.File]::ReadAllText($bk.FullName))
    Write-Host "RESTORED: $($target.FullName) <- $($bk.Name)"
    exit 0
}

$js = Get-ChildItem $ResDir -Recurse -Filter 'App-*.js' -ErrorAction SilentlyContinue |
    Where-Object {
        Select-String -Path $_.FullName -Pattern 'changeWatermarkPath' -SimpleMatch -Quiet
    } |
    Select-Object -First 1

if (-not $js) {
    Write-Error @"
No App-*.js with changeWatermarkPath under $ResDir.
Maybe the bundle is inside app.asar now. Unpack and look manually:
  npx @electron/asar extract `"$ResDir\app.asar`" `"$env:TEMP\vcam-asar`"
See README.md.
"@
    exit 1
}
Write-Host "[1/4] target: $($js.Name)"

Stop-VCam

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Force -Path $OrigDir | Out-Null
$bkPath = Join-Path $OrigDir "$($js.Name).$stamp.orig"
Copy-Item $js.FullName $bkPath -Force
Write-Host "[2/4] backup: $bkPath"

$data = [System.IO.File]::ReadAllText($js.FullName)
$idx = $data.IndexOf('changeWatermarkPath')
if ($idx -lt 0) {
    Write-Error 'changeWatermarkPath not found'
    exit 1
}

$span = Get-FunctionBody -Data $data -StartIndex $idx
if (-not $span) {
    Write-Error 'Could not match function body braces'
    exit 1
}

$old = $data.Substring($span.Start, $span.End - $span.Start)
$open = $old.IndexOf('(')
$close = $old.IndexOf(')', $open)
if ($open -ge 0 -and $close -gt $open) {
    $param = $old.Substring($open + 1, $close - $open - 1)
} else {
    $param = 'e'
}
$new = "changeWatermarkPath($param){this.watermarkBuffer=void 0,this.watermarkMimeType=void 0}"

if ($old -eq $new) {
    Write-Host 'already patched, skip'
} else {
    $data2 = $data.Substring(0, $span.Start) + $new + $data.Substring($span.End)
    Write-PatchedFile -Path $js.FullName -Content $data2
    Write-Host "[3/4] patched. delta bytes: $($data2.Length - $data.Length)"
    $preview = if ($old.Length -gt 90) { $old.Substring(0, 90) + '...' } else { $old }
    Write-Host "       was:  $preview"
    Write-Host "       now:  $new"
}

$after = [System.IO.File]::ReadAllText($js.FullName)
$ok = $after.Contains('this.watermarkBuffer=void 0,this.watermarkMimeType=void 0')
if ($ok) {
    Write-Host '[4/4] ok, patch is in place'
} else {
    Write-Host '[4/4] FAIL: patch string not found in file'
}

Write-Host ''
Write-Host 'DONE. Restart VCam - watermark should be gone.'
Write-Host 'Rollback: powershell -ExecutionPolicy Bypass -File .\windows\apply.ps1 -Restore'
