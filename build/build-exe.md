# Converting BAT Scripts to EXE

This document explains several methods to convert your batch scripts to executable files (.exe) to protect the source code.

## Methods Overview

### 1. **IExpress (Built into Windows)** ⭐ Recommended for basic protection
- **Pros:** Free, built-in, no installation required, creates self-extracting archives
- **Cons:** Basic obfuscation only, BAT file is extracted to temp at runtime
- **Best for:** Simple distribution, preventing casual edits

### 2. **Bat To Exe Converter** (Free tool)
- **Pros:** Good obfuscation, includes icon support, version info, UAC manifest
- **Cons:** Requires download, some antivirus false positives
- **Download:** https://github.com/islamadel/bat2exe or http://www.f2ko.de/en/b2e.php
- **Best for:** Professional-looking EXE with metadata

### 3. **PowerShell to EXE** (Rewrite + Compile)
- **Pros:** True compilation, better security, native .NET performance
- **Cons:** Requires rewriting BAT logic in PowerShell
- **Tools:** PS2EXE (https://github.com/MScholtes/PS2EXE)
- **Best for:** Maximum protection and professional deployment

### 4. **Commercial Tools**
- **Advanced Installer**, **InstallShield**, **Inno Setup** with script embedding
- **Best for:** Enterprise distribution with installers

## Quick Start: Using IExpress (Windows Built-in)

IExpress creates a self-extracting archive that runs your BAT script. The script is temporarily extracted but quickly deleted.

### Step 1: Create IExpress Configuration

Run this PowerShell script to generate an IExpress configuration file:

```powershell
# Save as: create-iexpress-config.ps1
param(
    [string]$ScriptName = "backup-download-shutdown.bat",
    [string]$ExeName = "KohaBackup.exe",
    [string]$Title = "Koha Backup Tool"
)

$scriptDir = $PSScriptRoot
$batPath = Join-Path $scriptDir $ScriptName
$sedPath = Join-Path $scriptDir "$($ScriptName).sed"
$exePath = Join-Path $scriptDir $ExeName

if (-not (Test-Path $batPath)) {
    Write-Error "Script not found: $batPath"
    exit 1
}

# Create SED file for IExpress
@"
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
FriendlyName=$Title
AppLaunched=cmd.exe /c $ScriptName
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="$ScriptName"

[SourceFiles]
SourceFiles0=$scriptDir

[SourceFiles0]
%FILE0%=
"@ | Out-File -FilePath $sedPath -Encoding ASCII

Write-Host "IExpress config created: $sedPath"
Write-Host "Building EXE..."
& iexpress /N /Q $sedPath

if (Test-Path $exePath) {
    Write-Host "✓ EXE created successfully: $exePath" -ForegroundColor Green
    Remove-Item $sedPath -Force
} else {
    Write-Error "Failed to create EXE"
}
```

### Step 2: Build the EXE

Run the generator:

```powershell
& '.\create-iexpress-config.ps1' -ScriptName "backup-download-shutdown.bat" -ExeName "KohaBackup.exe"
& '.\create-iexpress-config.ps1' -ScriptName "setup-backup-user.bat" -ExeName "KohaSetup.exe"
```

## Using Bat To Exe Converter (Better Protection)

### Installation
1. Download from: https://github.com/islamadel/bat2exe/releases
2. Extract and run `Bat_To_Exe_Converter.exe`

### GUI Steps
1. Click **Open** → select your BAT file
2. Configure:
   - **Icon:** Choose an icon file (.ico) or leave default
   - **Version Info:** Company, product name, version
   - **Manifest:** Request admin rights if needed
   - **Encryption:** Enable for better obfuscation
3. Click **Compile** → save the EXE

### Command Line (for automation)
```powershell
& 'C:\Path\To\Bat_To_Exe_Converter.exe' /bat "backup-download-shutdown.bat" /exe "KohaBackup.exe" /icon "icon.ico" /encrypt
```

## PowerShell Alternative (Most Secure)

If you want maximum protection, I can convert your BAT scripts to PowerShell and compile them:

1. Rewrite BAT → PS1 (I can help with this)
2. Use PS2EXE to compile:

```powershell
# Install PS2EXE
Install-Module -Name ps2exe -Scope CurrentUser

# Compile
Invoke-PS2EXE -inputFile ".\backup-script.ps1" -outputFile ".\KohaBackup.exe" -noConsole -requireAdmin
```

## Security Considerations

**⚠ Important Notes:**

1. **Password Protection:** No method fully protects embedded passwords
   - Best practice: Use external config files or Windows Credential Manager
   - Consider SSH key-based auth instead of passwords

2. **Decompilation Risk:** All methods can be reversed with effort
   - IExpress: Easy to extract (unzip the EXE)
   - Bat2Exe: Moderate protection (requires specific tools)
   - PowerShell: Best protection but still decompilable

3. **Antivirus False Positives:** Self-compiled EXEs often trigger AV
   - Sign your EXE with a code-signing certificate (recommended for distribution)
   - Submit to antivirus vendors for whitelisting

## Recommended Approach for Your Scripts

For **maximum security** without exposing credentials:

1. **Compile to EXE** (using Bat2Exe or PS2EXE)
2. **Remove hardcoded passwords** from scripts
3. **Use config.txt** for settings (user edits this, not the script)
4. **Use Windows Credential Manager** for sensitive data:
   ```cmd
   cmdkey /generic:KohaBackup /user:backup /pass:YourPassword
   ```
   Then retrieve in script with PowerShell:
   ```powershell
   $cred = Get-StoredCredential -Target "KohaBackup"
   ```

Would you like me to:
- Generate the IExpress build script for you?
- Convert your BAT scripts to PowerShell for better compilation?
- Set up Windows Credential Manager integration?
