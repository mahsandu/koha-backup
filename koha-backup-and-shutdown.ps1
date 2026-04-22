param(
  [string]$Host = "45.114.85.234",
  [int]$Port = 3022,
  [string]$User = "root",
  [string]$Instance = "mubassir",
  [string]$LocalRoot = "J:\\koha-backup",
  [string]$RemoteOutDir = "/root/koha-backups",
  [switch]$ShutdownAfter = $true
)

# Ensure local paths
$now = Get-Date -Format "yyyyMMddTHHmmssZ"
$dailyDir = Join-Path $LocalRoot (Join-Path $Instance "daily")
$monthlyDir = Join-Path $LocalRoot (Join-Path $Instance "monthly")
New-Item -ItemType Directory -Path $dailyDir -Force | Out-Null
New-Item -ItemType Directory -Path $monthlyDir -Force | Out-Null

# Step 1: request remote to create backup and print path+sha256
$createCmd = "bash /usr/local/bin/koha-shutdown-backup.sh --instance $Instance --outdir $RemoteOutDir --keep-days 7 --keep-months 12"
Write-Host "Requesting remote backup..."
$sshCreate = & ssh -p $Port $User@$Host $createCmd 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Remote backup command failed: $sshCreate"; exit 2 }

# Expect output: /root/koha-backups/daily/<file> <sha256>
$line = $sshCreate | Where-Object { $_ -match '\S+\s+[0-9a-f]{64}' } | Select-Object -First 1
if (-not $line) { Write-Error "Could not parse remote backup info from: $sshCreate"; exit 3 }
$parts = $line -split '\s+'
$remotePath = $parts[0]
$remoteSha = $parts[1]
Write-Host "Remote backup created: $remotePath (sha256: $remoteSha)"

# Step 2: download via scp
$localPath = Join-Path $dailyDir ([IO.Path]::GetFileName($remotePath))
Write-Host "Downloading to $localPath..."
& scp -P $Port $User@$Host:`"$remotePath`" `"$localPath`"
if ($LASTEXITCODE -ne 0) { Write-Error "scp failed"; exit 4 }

# Step 3: verify checksum
Write-Host "Verifying checksum..."
$localShaObj = Get-FileHash -Algorithm SHA256 -Path $localPath
$localSha = $localShaObj.Hash.ToLower()
if ($localSha -ne $remoteSha) { Write-Error "Checksum mismatch: local $localSha vs remote $remoteSha"; exit 5 }
Write-Host "Checksum verified."

# Step 4: monthly snapshot if first of month
if ((Get-Date).Day -eq 1) {
  Write-Host "First day of month: copying to monthly folder"
  Copy-Item -Path $localPath -Destination $monthlyDir -Force
  # prune monthly keeping 12 most recent
  Get-ChildItem -Path $monthlyDir -Filter *.tar.gz | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 | Remove-Item -Force -ErrorAction SilentlyContinue
}

# Step 5: prune daily backups to keep last 7
Get-ChildItem -Path $dailyDir -Filter *.tar.gz | Sort-Object LastWriteTime -Descending | Select-Object -Skip 7 | Remove-Item -Force -ErrorAction SilentlyContinue

# Step 6: if verified, shutdown remote safely
if ($ShutdownAfter) {
  Write-Host "Shutting down remote host..."
  & ssh -p $Port $User@$Host "nohup systemctl poweroff >/dev/null 2>&1 &"
}

Write-Host "Done."
