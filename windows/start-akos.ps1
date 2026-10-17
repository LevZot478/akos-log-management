$disk = "$env:USERPROFILE\akos-disks\logs.vhdx"

if (-not (Test-Path $disk)) {
    Write-Error "VHDX file not found"
    exit 1
}

# Check whether the Linux partition is already visible
& wsl.exe -d Ubuntu -u root -- blkid -U 6834094c-5588-4558-acff-f0d17d0e42a2 *> $null
$found = ($LASTEXITCODE -eq 0)

if (-not $found) {
    & wsl.exe --mount $disk --vhd --bare

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to attach VHDX"
        exit 1
    }
}

& wsl.exe -d Ubuntu -u root -- /home/lev/akos-lab/mount_logs.sh

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to mount LOGS"
    exit 1
}

Write-Host "SUCCESS: VHDX attached, /LOGS ready."