param(
    [Parameter(Mandatory = $true)][string]$Staging,
    [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) {
    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        $Hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [System.BitConverter]::ToString($Hasher.ComputeHash($Stream)).Replace('-', '')
        }
        finally {
            $Hasher.Dispose()
        }
    }
    finally {
        $Stream.Dispose()
    }
}

$SdkBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$MakeAppx = Get-ChildItem $SdkBin -Directory |
    Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64\makeappx.exe' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $MakeAppx) { throw 'Install the Windows 10/11 SDK, including MakeAppx.exe.' }
# Keep SDK manifest and payload validation enabled (do not use /nv).
& $MakeAppx pack /d $Staging /p $Output /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx pack failed: $LASTEXITCODE" }
$Unpacked = Join-Path (Split-Path $Output) 'verified'
& $MakeAppx unpack /p $Output /d $Unpacked /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx unpack failed: $LASTEXITCODE" }
foreach ($File in @('AppxManifest.xml', 'Zerus.exe', 'binaries\zerus.exe', 'Assets\StoreLogo.png', 'Assets\Square150x150Logo.png', 'Assets\Square44x44Logo.png')) {
    if (-not (Test-Path (Join-Path $Unpacked $File))) { throw "Missing MSIX payload: $File" }
    if ((Get-Sha256 (Join-Path $Staging $File)) -ne (Get-Sha256 (Join-Path $Unpacked $File))) {
        throw "MSIX payload mismatch: $File"
    }
}
Remove-Item $Unpacked -Recurse -Force
Write-Host "MSIX manifest validation and payload round-trip passed: $Output"
