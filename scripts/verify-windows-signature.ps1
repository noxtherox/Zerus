param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse)
if ($files.Count -ne 1 -or $files[0].Name -cne "Zerus_${Version}_x64-setup.exe") {
    throw "Expected exactly one Zerus_${Version}_x64-setup.exe in $Directory."
}

$file = $files[0]
$signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
if ($signature.Status -ne 'Valid') {
    throw "Invalid installer signature: $($signature.Status) — $($signature.StatusMessage)"
}
if ($null -eq $signature.SignerCertificate -or
    $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'SignPath Foundation') {
    throw 'The installer must be signed by SignPath Foundation.'
}
if ($null -eq $signature.TimeStamperCertificate) {
    throw 'The installer signature must have a timestamp.'
}
if ($file.VersionInfo.ProductName -cne 'Zerus' -or $file.VersionInfo.ProductVersion -cne $Version) {
    throw "Installer product metadata does not match Zerus $Version."
}

$hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
Write-Output "Verified $($file.Name), publisher SignPath Foundation, SHA256 $hash"
