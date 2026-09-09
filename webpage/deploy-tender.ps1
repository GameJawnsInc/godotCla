# deploy-tender.ps1
# Uploads the TENDER Godot web export to jawnston.com/tender and fixes ownership.
#
# Mirrors JawnRPG's webpage/deploy-game.ps1 (same server, same ssh host, same
# resumable-upload approach); only the export preset and remote path differ.
#
# Usage:
#   .\deploy-tender.ps1                            # deploy whatever's in build/web
#   .\deploy-tender.ps1 -Export                    # re-export from Godot first, then deploy
#   .\deploy-tender.ps1 -ExportPath C:\my\folder   # custom path

param(
    [switch]$Export,
    [string]$GodotExe    = "C:\gd\Godot_v4.7-stable_win64_console.exe",
    [string]$ProjectPath = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$ExportPath  = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path "build\web"),
    [string]$SshHost     = "mygame",
    [string]$RemotePath  = "/var/www/jawnston/tender"
)

$ErrorActionPreference = "Stop"

# Common ssh/sftp options for resilience against mid-upload disconnects on
# residential links. ServerAliveInterval pings every 15s idle, failing after 8
# misses (~2 min) - long enough to ride out blips, short enough to fail fast on
# a dead socket. ConnectTimeout caps the initial handshake.
$SshOpts = @(
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=8",
    "-o", "TCPKeepAlive=yes",
    "-o", "ConnectTimeout=30"
)

# Resumable single-file upload. The server resets long SSH transfers partway
# through, and scp can't resume (every retry restarts from zero and dies again).
# sftp `reput` continues from wherever the last attempt died. A hash check means:
#   - an already-correct remote file is skipped (cross-run resume), and
#   - a full-size-but-wrong file (stale build / corrupt) is cleared and redone
#     instead of reput appending current-build bytes onto stale ones.
# Matters most here: index.wasm is ~39 MB, the one file likely to get cut off.
# Returns $true once the remote SHA-256 matches local.
function Send-FileResumable {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$LocalFile,
        [Parameter(Mandatory)] [string]$RemoteDir,
        [int]$MaxAttempts = 30
    )
    # sftp/ssh write status ("Connected to ...") to stderr. Under the script's
    # ErrorActionPreference=Stop that surfaces as a terminating NativeCommandError,
    # so drop to Continue inside this function - we gate on $LASTEXITCODE and the
    # remote size/hash explicitly, not on stderr.
    $ErrorActionPreference = 'Continue'

    $remoteFile = "$RemoteDir/$($LocalFile.Name)"
    $localSize  = $LocalFile.Length
    $localHash  = (Get-FileHash -Algorithm SHA256 $LocalFile.FullName).Hash.ToLower()
    $localPath  = $LocalFile.FullName -replace '\\', '/'   # sftp wants forward slashes

    # Zero-byte files: reput/stat edge cases aren't worth it - one scp does it.
    if ($localSize -eq 0) {
        scp -O @SshOpts $LocalFile.FullName "${SshHost}:${remoteFile}"
        return ($LASTEXITCODE -eq 0)
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $sizeOut = ssh -n -o BatchMode=yes @SshOpts $SshHost "stat -c %s '$remoteFile' 2>/dev/null"
        $remoteSize = 0
        if ($LASTEXITCODE -eq 0 -and $sizeOut) { $remoteSize = [int64]($sizeOut.Trim()) }

        # Only hash when the remote file is already full-size; hashing a partial
        # every pass is wasted work (it can't match until the upload completes).
        if ($remoteSize -ge $localSize) {
            $remoteHash = (ssh -n -o BatchMode=yes @SshOpts $SshHost "sha256sum '$remoteFile'").Split()[0].ToLower()
            if ($remoteHash -eq $localHash) { return $true }
            ssh -n -o BatchMode=yes @SshOpts $SshHost "rm -f '$remoteFile'"
            $remoteSize = 0
        }

        if ($attempt -gt 1) {
            Write-Host ("      resume {0}/{1} @ {2:P0}" -f $attempt, $MaxAttempts, ($remoteSize / [math]::Max($localSize, 1))) -ForegroundColor DarkYellow
        }

        # reput resumes from the current remote offset; put starts fresh when the
        # remote file is absent / was just cleared. Driven by an sftp -b batch file
        # (UTF-8, no BOM, LF). sftp's exit code is unreliable across a reset, so we
        # ignore it; the size/hash check on the next pass is the real arbiter.
        $verb  = if ($remoteSize -gt 0) { "reput" } else { "put" }
        $batch = Join-Path $env:TEMP ("tender_sftp_" + $LocalFile.Name + ".txt")
        [IO.File]::WriteAllText($batch, "$verb `"$localPath`" `"$remoteFile`"`n")
        sftp -o BatchMode=yes @SshOpts -b $batch $SshHost 2>$null | Out-Null
        Remove-Item $batch -ErrorAction SilentlyContinue
    }
    return $false
}

# --- Optional: re-export from Godot before deploying ---
if ($Export) {
    # Editor open during headless export = file lock collisions. Fail fast with a
    # clear message instead of leaving a half-baked export folder.
    $running = @(Get-Process godot* -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $names = ($running | ForEach-Object { "$($_.ProcessName) PID $($_.Id)" }) -join ', '
        Write-Host "Godot editor is running ($names) - close it before -Export." -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $GodotExe)) {
        Write-Host "Godot executable not found: $GodotExe" -ForegroundColor Red
        exit 1
    }
    Write-Host "[Export] Running Godot CLI export of 'Web' preset..." -ForegroundColor Yellow
    & $GodotExe --headless --path $ProjectPath --export-release "Web"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Godot export failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

# --- Validate the export folder ---
if (-not (Test-Path $ExportPath)) {
    Write-Host "Export folder not found: $ExportPath" -ForegroundColor Red
    Write-Host "Run with -Export to build it first."
    exit 1
}

$files = Get-ChildItem $ExportPath -File
if ($files.Count -eq 0) {
    Write-Host "Export folder is empty: $ExportPath" -ForegroundColor Red
    exit 1
}

# --- Summary ---
Write-Host ""
Write-Host "Deploying $($files.Count) files" -ForegroundColor Cyan
Write-Host "  from:  $ExportPath"
Write-Host "  to:    ${SshHost}:${RemotePath}"
Write-Host ""

$startTime = Get-Date

# --- Ensure the remote directory exists ---
# Unlike /play (created by hand long ago), /tender is new, so the script owns
# creating it - otherwise every sftp put fails with "no such file".
ssh -n -o BatchMode=yes @SshOpts $SshHost "mkdir -p $RemotePath"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Could not create $RemotePath (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# --- Upload (resumable, per file) ---
Write-Host "[1/2] Uploading (resumable)..." -ForegroundColor Yellow
$failed = @()
foreach ($f in $files) {
    $sizeMb = [math]::Round($f.Length / 1MB, 2)
    Write-Host "  $($f.Name) (${sizeMb} MB)..." -ForegroundColor DarkGray
    if (-not (Send-FileResumable -LocalFile $f -RemoteDir $RemotePath)) {
        $failed += $f.Name
        Write-Host "    FAILED after retries" -ForegroundColor Red
    }
}
if ($failed.Count -gt 0) {
    Write-Host "Upload failed for: $($failed -join ', ')" -ForegroundColor Red
    Write-Host "Re-run the script - completed files are skipped, partials resume." -ForegroundColor Yellow
    exit 1
}

# --- Fix ownership ---
Write-Host "[2/2] Fixing ownership via ssh..." -ForegroundColor Yellow
ssh -n -o BatchMode=yes @SshOpts $SshHost "chown -R caddy:caddy $RemotePath"
if ($LASTEXITCODE -ne 0) {
    Write-Host "chown failed (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# --- Done ---
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Host ""
Write-Host "Deployed in ${elapsed}s" -ForegroundColor Green
Write-Host "Live at: https://jawnston.com/tender/" -ForegroundColor Green
Write-Host ""
