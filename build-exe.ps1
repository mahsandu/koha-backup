# Build EXE files from BAT scripts using IExpress (built into Windows)
# Usage: .\build-exe.ps1 [-ScriptName backup-download-shutdown.bat] [-ExeName KohaBackup.exe]

param(
    [string[]]$Scripts = @(
        "backup-download-shutdown.bat",
        "backup-download-no-shutdown.bat",
        "setup-backup-user.bat"
    ),
    [switch]$CleanTemp
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

Write-Host "=== Building EXE files from BAT scripts ===" -ForegroundColor Cyan
Write-Host ""

foreach ($scriptName in $Scripts) {
    $batPath = Join-Path $scriptDir $scriptName
    
    if (-not (Test-Path $batPath)) {
        Write-Warning "Skipping $scriptName (not found)"
        continue
    }

    # Generate EXE name from script name
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)
    $exeName = "$baseName.exe"
    $sedPath = Join-Path $scriptDir "$scriptName.sed"
    $exePath = Join-Path $scriptDir $exeName

    Write-Host "Processing: $scriptName -> $exeName" -ForegroundColor Yellow

    # Create IExpress SED configuration
    $sedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles

[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$exePath
FriendlyName=Koha Backup - $baseName
AppLaunched=cmd.exe /c $scriptName
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="$scriptName"

[SourceFiles]
SourceFiles0=$scriptDir

[SourceFiles0]
%FILE0%=
"@

    # Write SED file with ASCII encoding (required by iexpress)
    $sedContent | Out-File -FilePath $sedPath -Encoding ASCII -Force

    # Build EXE using IExpress
    Write-Host "  Building with IExpress..." -NoNewline
    $output = & iexpress /N /Q $sedPath 2>&1
    
    if (Test-Path $exePath) {
        $size = (Get-Item $exePath).Length
        $sizeKB = [math]::Round($size / 1KB, 1)
        Write-Host " Success ($sizeKB KB)" -ForegroundColor Green
    } else {
        Write-Host " Failed" -ForegroundColor Red
        Write-Warning "IExpress output: $output"
    }

    # Clean up temp SED file
    if ($CleanTemp -and (Test-Path $sedPath)) {
        Remove-Item $sedPath -Force
    }
}

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Generated EXE files can be distributed without exposing BAT source code."
Write-Host "Note: IExpress provides basic obfuscation. For stronger protection, see build-exe.md"
Write-Host ""

# List generated EXEs
$exeFiles = Get-ChildItem -Path $scriptDir -Filter "*.exe" -File
if ($exeFiles.Count -gt 0) {
    Write-Host "Available EXE files:" -ForegroundColor Green
    foreach ($exe in $exeFiles) {
        $sizeKB = [math]::Round($exe.Length / 1KB, 1)
        Write-Host "  - $($exe.Name) ($sizeKB KB)"
    }
}
