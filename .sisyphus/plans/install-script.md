# Work Plan: PickupRangeXpBoost Installer Script

## Overview
Create a PowerShell 5.1 compatible auto-installer/updater script for the PickupRangeXpBoost mod, including automatic UE4SS framework installation.

**Output files**: `install.ps1` (main script) + `install.cmd` (double-click launcher)

## Scope
- **IN**: Game directory auto-detection, UE4SS download+install, mod download+install, bilingual UI, proxy fallback, progress display, error handling, mods.txt management
- **OUT**: Uninstaller, auto-updater daemon, GUI installer, mod configuration editor

## Architecture

### Script Flow
```
1. Initialize-Environment (TLS 1.2, encoding, language detection)
2. Find-GameDirectory (registry scan → file picker fallback)
3. Get-UE4SSDownloadInfo (GitHub API with proxy fallback → asset URL/size/hash)
4. Download + Install UE4SS (backup configs → extract → verify → restore configs)
5. Download + Install Mod (extract → rename → verify)
6. Update-ModsConfig (register PickupRangeXpBoost in mods.txt)
7. Show completion message + pause
```

### Key Technical Decisions
- **Download method**: `System.Net.HttpWebRequest` + stream copy with manual `Write-Progress` (avoids PS 5.1 WebClient threading issues and Invoke-WebRequest slowness)
- **File encoding**: UTF-8 with BOM (required for PS 5.1 to read Chinese literals)
- **Proxy format**: `https://<proxy>/https://github.com/...` (double HTTPS prepend)
- **ZIP extraction**: `Expand-Archive` (built-in PS 5.1)
- **Integrity check**: SHA256 via `Get-FileHash` + file size comparison against GitHub API data
- **Language detection**: `(Get-Culture).Name -like 'zh-*'`
- **Error strategy**: `try/catch` per major step, `Read-Host` pause on error (never `exit` silently)

### Proxy Fallback Chain
```powershell
@(
    "",                              # Direct GitHub (try first)
    "https://ghfast.top/",
    "https://gh-proxy.com/",
    "https://github.moeyy.xyz/",
    "https://ghproxy.net/"
)
# Usage: "${proxy}https://github.com/..." or "${proxy}https://api.github.com/..."
```

### Critical Guardrails (from Metis)
1. **mods.txt preservation**: When UE4SS already installed, backup mods.txt before extraction, then merge custom entries back. `PickupRangeXpBoost : 1` must be inserted BEFORE `; Built-in keybinds` comment.
2. **UE4SS-settings.ini preservation**: Backup before extraction, restore after.
3. **TLS 1.2 MUST be first network line**: `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`
4. **Console encoding MUST be set before any Chinese output**: `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`
5. **Registry path MUST be validated with Test-Path** after extraction from MuiCache.
6. **UE4SS asset selection**: First asset where `name` starts with `UE4SS_` (not `zDEV-`, `zCustom-`, `zMap-`).
7. **UE4SS ZIP extracts FLAT** (no root folder): `dwmapi.dll` + `ue4ss/` at root level → extract directly to Win64 dir.
8. **Mod ZIP has root folder** `PickupRangeXpBoost-master/` → extract to temp, move+rename.
9. **No PS 7+ features**: No `??`, `?.`, ternary, `ForEach-Object -Parallel`.
10. **GitHub API requires User-Agent header**.
11. **PowerShell `-f` format operator precedence**: When using `Get-Msg` with `-f`, MUST wrap in extra parentheses: `((Get-Msg 'Key') -f $arg)` — NOT `(Get-Msg('Key') -f $arg)`. Without the extra parens, `-f $arg` is parsed as a parameter to `Get-Msg`, not the format operator. This applies to ALL message keys that contain `{0}`, `{1}`, etc. placeholders.
12. **`Invoke-RestMethod` does NOT support `-UseBasicParsing`** — that parameter is `Invoke-WebRequest`-only. Do not add it to `Invoke-RestMethod` calls.
13. **`Invoke-WebRequest -UseBasicParsing`**: MUST be used on every `Invoke-WebRequest` call to avoid dependency on Internet Explorer parsing engine (removed on some Windows versions).

## Atomic Commit Strategy

| # | Commit Message | Scope |
|---|---------------|-------|
| 1 | `feat: add installer skeleton with bilingual support and environment init` | Script header, TLS, encoding, language detection, full message dictionary, main flow skeleton, Read-Host pause |
| 2 | `feat: add game directory auto-detection via registry and file picker` | `Find-GameDirectory`, MuiCache scan, OpenFileDialog fallback, path validation |
| 3 | `feat: add download infrastructure with proxy fallback and progress` | `Download-FileWithProgress`, proxy chain, `Get-UE4SSDownloadInfo` API call, SHA256 verification |
| 4 | `feat: add UE4SS installation with config preservation` | `Install-UE4SS` — backup mods.txt/settings → extract → verify sentinels → restore config |
| 5 | `feat: add mod installation with mods.txt registration` | `Install-Mod` + `Update-ModsConfig` — extract → rename → register → verify |
| 6 | `feat: add install.cmd launcher` | `install.cmd` one-liner launcher for double-click execution |

---

## Tasks

<!-- TASKS_START -->

### Task 1: Create `install.ps1` skeleton with environment initialization and bilingual message system
**Commit**: 1
**File**: `install.ps1`
**Encoding**: UTF-8 with BOM (implementer MUST ensure BOM is present — first 3 bytes `EF BB BF`)

Create the script file with the following structure (in order):

1. **Script header comment block**:
   ```powershell
   <#
   .SYNOPSIS
       PickupRangeXpBoost Mod Installer / 模组安装器
   .DESCRIPTION
       Auto-installs UE4SS mod framework and PickupRangeXpBoost mod for Grind Survivors.
       自动安装 UE4SS 模组框架和 PickupRangeXpBoost 模组。
   .NOTES
       Requires: PowerShell 5.1+, Windows 10+
       Repository: https://github.com/abevol/PickupRangeXpBoost
   #>
   ```

2. **`Initialize-Environment` function**:
   - Set `$ErrorActionPreference = 'Stop'`
   - Set TLS 1.2: `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`
   - Set console encoding: `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8`
   - Return nothing, just configures the environment

3. **Language detection & message dictionary**:
   - Detect language: `$script:Lang = if ((Get-Culture).Name -like 'zh-*') { 'zh' } else { 'en' }`
   - Create `$script:Msg` as a hashtable. Every key has two sub-keys `zh` and `en`.
   - Helper function `function Get-Msg([string]$Key) { return $script:Msg[$Key][$script:Lang] }`
   - **Complete message dictionary** — ALL messages for the entire script must be defined here (not added later in other tasks). Include ALL of the following keys:

   | Key | EN | ZH |
   |-----|----|----|
   | `Welcome` | `PickupRangeXpBoost Mod Installer` | `PickupRangeXpBoost 模组安装器` |
   | `WelcomeDesc` | `This script will install UE4SS and PickupRangeXpBoost mod for Grind Survivors.` | `此脚本将为 Grind Survivors 安装 UE4SS 模组框架和 PickupRangeXpBoost 模组。` |
   | `StepFindGame` | `[Step 1/4] Finding game installation directory...` | `[步骤 1/4] 正在查找游戏安装目录...` |
   | `StepDownloadUE4SS` | `[Step 2/4] Downloading UE4SS mod framework...` | `[步骤 2/4] 正在下载 UE4SS 模组框架...` |
   | `StepInstallUE4SS` | `[Step 3/4] Installing UE4SS...` | `[步骤 3/4] 正在安装 UE4SS...` |
   | `StepInstallMod` | `[Step 4/4] Installing PickupRangeXpBoost mod...` | `[步骤 4/4] 正在安装 PickupRangeXpBoost 模组...` |
   | `FoundGameDir` | `Found game directory: {0}` | `找到游戏目录：{0}` |
   | `GameDirNotFound` | `Could not automatically find the game directory.` | `无法自动查找游戏安装目录。` |
   | `SelectExePrompt` | `Please select the game executable file (GrindSurvivors-Win64-Shipping.exe).` | `请选择游戏可执行文件（GrindSurvivors-Win64-Shipping.exe）。` |
   | `UserCancelled` | `Operation cancelled by user.` | `用户取消了操作。` |
   | `InvalidExe` | `The selected file is not GrindSurvivors-Win64-Shipping.exe.` | `选择的文件不是 GrindSurvivors-Win64-Shipping.exe。` |
   | `Downloading` | `Downloading` | `正在下载` |
   | `DownloadProgress` | `{0:F1} MB / {1:F1} MB ({2}%)` | `{0:F1} MB / {1:F1} MB ({2}%)` |
   | `DownloadComplete` | `Download complete: {0}` | `下载完成：{0}` |
   | `DownloadFailed` | `Download failed: {0}` | `下载失败：{0}` |
   | `DownloadFailedAllSources` | `All download sources failed. Please check your network connection.` | `所有下载源均失败，请检查网络连接。` |
   | `TryingSource` | `Trying download source {0}/{1}...` | `正在尝试下载源 {0}/{1}...` |
   | `TryingDirectSource` | `Trying direct connection to GitHub...` | `正在尝试直连 GitHub...` |
   | `TryingProxySource` | `Trying proxy: {0}` | `正在尝试加速源：{0}` |
   | `VerifyingFile` | `Verifying file integrity...` | `正在验证文件完整性...` |
   | `VerifyFailed` | `File integrity verification failed. Expected: {0}, Got: {1}` | `文件完整性验证失败。预期：{0}，实际：{1}` |
   | `VerifyPassed` | `File integrity verification passed.` | `文件完整性验证通过。` |
   | `UE4SSAlreadyInstalled` | `UE4SS is already installed. Reinstall/Update? [Y/N]` | `UE4SS 已安装。是否重新安装/更新？[Y/N]` |
   | `UE4SSSkipped` | `Skipped UE4SS installation.` | `已跳过 UE4SS 安装。` |
   | `BackingUpConfig` | `Backing up existing configuration...` | `正在备份现有配置...` |
   | `RestoringConfig` | `Restoring configuration...` | `正在恢复配置...` |
   | `Extracting` | `Extracting files...` | `正在解压文件...` |
   | `UE4SSInstallComplete` | `UE4SS installation complete.` | `UE4SS 安装完成。` |
   | `ModInstallComplete` | `PickupRangeXpBoost mod installation complete.` | `PickupRangeXpBoost 模组安装完成。` |
   | `ModRegistered` | `Mod registered in mods.txt successfully.` | `模组已成功注册到 mods.txt。` |
   | `AllComplete` | `All installations completed successfully! You can now launch the game.` | `所有安装已成功完成！现在可以启动游戏了。` |
   | `PressEnterToExit` | `Press Enter to exit...` | `按 Enter 键退出...` |
   | `ErrorOccurred` | `An error occurred: {0}` | `发生错误：{0}` |
   | `CleaningUp` | `Cleaning up temporary files...` | `正在清理临时文件...` |
   | `FetchingReleaseInfo` | `Fetching UE4SS release information...` | `正在获取 UE4SS 发布信息...` |
   | `ReleaseInfoFound` | `Found: {0} ({1:F1} MB)` | `找到：{0}（{1:F1} MB）` |
   | `ReleaseInfoFailed` | `Failed to fetch UE4SS release information.` | `获取 UE4SS 发布信息失败。` |
   | `APIRateLimited` | `GitHub API rate limit reached. Please wait a few minutes and try again.` | `GitHub API 请求频率超限，请等待几分钟后重试。` |
   | `ExistingModBackup` | `Backing up existing mod files...` | `正在备份现有模组文件...` |
   | `RemovingOldMod` | `Removing old mod files...` | `正在移除旧模组文件...` |

4. **Main flow skeleton** (the body that calls all functions):
   ```powershell
   # ===== Main Execution Flow =====
   $script:TempDir = Join-Path $env:TEMP "PickupRangeXpBoost_Install_$(Get-Date -Format 'yyyyMMddHHmmss')"

   try {
       Initialize-Environment

       # Display welcome banner
       Write-Host ""
       Write-Host "========================================" -ForegroundColor Cyan
       Write-Host "  $(Get-Msg 'Welcome')" -ForegroundColor Cyan
       Write-Host "========================================" -ForegroundColor Cyan
       Write-Host ""
       Write-Host (Get-Msg 'WelcomeDesc')
       Write-Host ""

       # Create temp directory
       New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

       # Step 1: Find game directory
       Write-Host (Get-Msg 'StepFindGame') -ForegroundColor Yellow
       $gameDir = Find-GameDirectory
       Write-Host (Get-Msg('FoundGameDir') -f $gameDir) -ForegroundColor Green
       Write-Host ""

       # Step 2: Download UE4SS
       Write-Host (Get-Msg 'StepDownloadUE4SS') -ForegroundColor Yellow
       $ue4ssInstalled = (Test-Path (Join-Path $gameDir "dwmapi.dll")) -and (Test-Path (Join-Path $gameDir "ue4ss\UE4SS.dll"))
       $skipUE4SS = $false
       if ($ue4ssInstalled) {
           $answer = Read-Host (Get-Msg 'UE4SSAlreadyInstalled')
           if ($answer -notmatch '^[Yy]') {
               Write-Host (Get-Msg 'UE4SSSkipped') -ForegroundColor DarkYellow
               $skipUE4SS = $true
           }
       }

       if (-not $skipUE4SS) {
           $ue4ssInfo = Get-UE4SSDownloadInfo
           Write-Host (Get-Msg('ReleaseInfoFound') -f $ue4ssInfo.Name, ($ue4ssInfo.Size / 1MB)) -ForegroundColor Green
           $ue4ssZip = Join-Path $script:TempDir $ue4ssInfo.Name
           Download-FileWithProgress -Url $ue4ssInfo.Url -OutputPath $ue4ssZip -ExpectedSize $ue4ssInfo.Size -ExpectedHash $ue4ssInfo.Hash

           # Step 3: Install UE4SS
           Write-Host ""
           Write-Host (Get-Msg 'StepInstallUE4SS') -ForegroundColor Yellow
           Install-UE4SS -ZipPath $ue4ssZip -GameDir $gameDir
           Write-Host (Get-Msg 'UE4SSInstallComplete') -ForegroundColor Green
       }
       Write-Host ""

       # Step 4: Install mod
       Write-Host (Get-Msg 'StepInstallMod') -ForegroundColor Yellow
       $modZipUrl = "https://github.com/abevol/PickupRangeXpBoost/archive/refs/heads/master.zip"
       $modZip = Join-Path $script:TempDir "PickupRangeXpBoost.zip"
       Download-FileWithProgress -Url $modZipUrl -OutputPath $modZip
       Install-Mod -ZipPath $modZip -GameDir $gameDir
       Write-Host (Get-Msg 'ModInstallComplete') -ForegroundColor Green
       Write-Host ""

       # Done
       Write-Host "========================================" -ForegroundColor Green
       Write-Host "  $(Get-Msg 'AllComplete')" -ForegroundColor Green
       Write-Host "========================================" -ForegroundColor Green
   }
   catch {
       Write-Host ""
       Write-Host (Get-Msg('ErrorOccurred') -f $_.Exception.Message) -ForegroundColor Red
       Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
   }
   finally {
       # Cleanup temp directory
       if (Test-Path $script:TempDir) {
           Write-Host (Get-Msg 'CleaningUp')
           Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
       }
       Write-Host ""
       Read-Host (Get-Msg 'PressEnterToExit')
   }
   ```

**QA for Task 1**:
- [ ] Script parses without syntax errors: `powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . '.\install.ps1' }"` (will fail on undefined functions, but NO parse errors)
- [ ] Every `$Msg` key used in the main flow exists in the dictionary with both `zh` and `en` values
- [ ] `Get-Msg` function returns correct language string based on system locale
- [ ] No PS 7+ features used
- [ ] File saved as UTF-8 with BOM

---

### Task 2: Implement `Find-GameDirectory` — registry scan and file picker fallback
**Commit**: 2
**File**: `install.ps1` (add function BEFORE main flow, AFTER message dictionary)

Implement `function Find-GameDirectory` with the following logic:

1. **Registry MuiCache scan**:
   ```powershell
   function Find-GameDirectory {
       # Try registry first
       $muiCachePath = "Registry::HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
       $targetSuffix = "\Grind Survivors\GrindSurvivors\Binaries\Win64\GrindSurvivors-Win64-Shipping.exe.FriendlyAppName"

       try {
           $muiCache = Get-Item -Path $muiCachePath -ErrorAction Stop
           foreach ($valueName in $muiCache.GetValueNames()) {
               if ($valueName.EndsWith($targetSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
                   # Strip ".FriendlyAppName" to get exe path, then get parent directory
                   $exePath = $valueName.Substring(0, $valueName.Length - ".FriendlyAppName".Length)
                   $win64Dir = Split-Path -Parent $exePath

                   # Validate path exists on disk
                   if (Test-Path (Join-Path $win64Dir "GrindSurvivors-Win64-Shipping.exe")) {
                       return $win64Dir
                   }
               }
           }
       }
       catch {
           # Registry key not found or access denied — fall through to file picker
       }

       # Fallback: file picker dialog
       return Select-GameExecutable
   }
   ```

2. **File picker fallback** — `function Select-GameExecutable`:
   ```powershell
   function Select-GameExecutable {
       Write-Host (Get-Msg 'GameDirNotFound') -ForegroundColor DarkYellow
       Write-Host (Get-Msg 'SelectExePrompt')

       Add-Type -AssemblyName System.Windows.Forms
       $dialog = New-Object System.Windows.Forms.OpenFileDialog
       $dialog.Title = Get-Msg 'SelectExePrompt'
       $dialog.Filter = "Game Executable (GrindSurvivors-Win64-Shipping.exe)|GrindSurvivors-Win64-Shipping.exe|All Files (*.*)|*.*"
       $dialog.CheckFileExists = $true

       $result = $dialog.ShowDialog()

       if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
           throw (Get-Msg 'UserCancelled')
       }

       $selectedFile = $dialog.FileName
       $fileName = [System.IO.Path]::GetFileName($selectedFile)
       if ($fileName -ne "GrindSurvivors-Win64-Shipping.exe") {
           throw (Get-Msg 'InvalidExe')
       }

       return Split-Path -Parent $selectedFile
   }
   ```

**Key details**:
- Registry path uses `Registry::` PSDrive prefix (compatible with PS 5.1)
- `GetValueNames()` returns all value names as strings — iterate and match suffix
- `EndsWith` with `OrdinalIgnoreCase` handles different path casing
- After extracting path: ALWAYS `Test-Path` to validate (handles uninstalled games with stale MuiCache entries)
- File dialog filter pre-selects the correct exe name
- If user selects wrong file → throw localized error (caught by main try/catch)
- If user cancels dialog → throw localized cancel message

**QA for Task 2**:
- [ ] If game is installed and was launched: function returns valid Win64 directory path
- [ ] If registry entry exists but game uninstalled: falls through to file picker (path validation fails)
- [ ] If registry entry doesn't exist: falls through to file picker
- [ ] If user cancels file picker: throws error with localized message, caught by main flow
- [ ] If user selects wrong exe: throws error with localized message
- [ ] Returned path does NOT end with `\` (Split-Path behavior)

---

### Task 3: Implement `Download-FileWithProgress` — download engine with proxy fallback and progress display
**Commit**: 3
**File**: `install.ps1` (add functions BEFORE `Find-GameDirectory`)

1. **Define proxy chain as script-level variable** (at top of script, after message dictionary):
   ```powershell
   $script:ProxyList = @(
       "",                                  # Direct GitHub
       "https://ghfast.top/",               # Proxy 1
       "https://gh-proxy.com/",             # Proxy 2
       "https://github.moeyy.xyz/",         # Proxy 3
       "https://ghproxy.net/"               # Proxy 4
   )
   ```

2. **`Download-FileWithProgress` function**:
   ```powershell
   function Download-FileWithProgress {
       param(
           [Parameter(Mandatory=$true)]
           [string]$Url,
           [Parameter(Mandatory=$true)]
           [string]$OutputPath,
           [long]$ExpectedSize = 0,
           [string]$ExpectedHash = ""
       )

       $fileName = [System.IO.Path]::GetFileName($OutputPath)
       $downloaded = $false

       for ($i = 0; $i -lt $script:ProxyList.Count; $i++) {
           $proxy = $script:ProxyList[$i]
           $actualUrl = if ($proxy) { "${proxy}${Url}" } else { $Url }

           # Display which source we're trying
           if ($proxy) {
               Write-Host ("  " + (Get-Msg('TryingProxySource') -f $proxy)) -ForegroundColor DarkGray
           } else {
               Write-Host ("  " + (Get-Msg 'TryingDirectSource')) -ForegroundColor DarkGray
           }

           try {
               Invoke-DownloadWithProgress -Url $actualUrl -OutputPath $OutputPath -ActivityName $fileName
               $downloaded = $true
               break
           }
           catch {
               Write-Host ("  " + (Get-Msg('DownloadFailed') -f $_.Exception.Message)) -ForegroundColor DarkYellow
               # Remove partial file
               if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }
               continue
           }
       }

       if (-not $downloaded) {
           throw (Get-Msg 'DownloadFailedAllSources')
       }

       # Verify file integrity
       if ($ExpectedSize -gt 0 -or $ExpectedHash) {
           Write-Host ("  " + (Get-Msg 'VerifyingFile')) -ForegroundColor DarkGray
           $actualSize = (Get-Item $OutputPath).Length
           if ($ExpectedSize -gt 0 -and $actualSize -ne $ExpectedSize) {
               Remove-Item $OutputPath -Force
               throw (Get-Msg('VerifyFailed') -f "size=$ExpectedSize", "size=$actualSize")
           }
           if ($ExpectedHash) {
               $actualHash = (Get-FileHash $OutputPath -Algorithm SHA256).Hash
               if ($actualHash -ne $ExpectedHash) {
                   Remove-Item $OutputPath -Force
                   throw (Get-Msg('VerifyFailed') -f $ExpectedHash, $actualHash)
               }
           }
           Write-Host ("  " + (Get-Msg 'VerifyPassed')) -ForegroundColor Green
       }

       Write-Host ("  " + (Get-Msg('DownloadComplete') -f $fileName)) -ForegroundColor Green
   }
   ```

3. **`Invoke-DownloadWithProgress` function** — low-level download using `HttpWebRequest` + stream copy:
   ```powershell
   function Invoke-DownloadWithProgress {
       param(
           [Parameter(Mandatory=$true)]
           [string]$Url,
           [Parameter(Mandatory=$true)]
           [string]$OutputPath,
           [string]$ActivityName = "file"
       )

       $request = [System.Net.HttpWebRequest]::Create($Url)
       $request.UserAgent = "PickupRangeXpBoost-Installer/1.0"
       $request.Timeout = 30000          # 30 second connection timeout
       $request.ReadWriteTimeout = 30000 # 30 second read timeout
       $request.AllowAutoRedirect = $true
       $request.MaximumAutomaticRedirections = 10

       $response = $null
       $responseStream = $null
       $fileStream = $null

       try {
           $response = $request.GetResponse()
           $totalBytes = $response.ContentLength
           $responseStream = $response.GetResponseStream()
           $fileStream = [System.IO.File]::Create($OutputPath)

           $buffer = New-Object byte[] 65536   # 64KB buffer
           $totalRead = [long]0
           $lastProgressUpdate = [DateTime]::MinValue
           $sw = [System.Diagnostics.Stopwatch]::StartNew()

           while ($true) {
               $bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)
               if ($bytesRead -le 0) { break }

               $fileStream.Write($buffer, 0, $bytesRead)
               $totalRead += $bytesRead

               # Throttle progress updates to every 200ms
               $now = [DateTime]::Now
               if (($now - $lastProgressUpdate).TotalMilliseconds -ge 200) {
                   $lastProgressUpdate = $now
                   if ($totalBytes -gt 0) {
                       $percent = [math]::Floor($totalRead / $totalBytes * 100)
                       $downloadedMB = $totalRead / 1MB
                       $totalMB = $totalBytes / 1MB
                       $status = Get-Msg('DownloadProgress') -f $downloadedMB, $totalMB, $percent
                       Write-Progress -Activity (Get-Msg('Downloading') + ": $ActivityName") -Status $status -PercentComplete $percent
                   } else {
                       $downloadedMB = $totalRead / 1MB
                       Write-Progress -Activity (Get-Msg('Downloading') + ": $ActivityName") -Status ("{0:F1} MB" -f $downloadedMB)
                   }
               }
           }

           Write-Progress -Activity (Get-Msg('Downloading') + ": $ActivityName") -Completed
       }
       finally {
           if ($fileStream) { $fileStream.Close() }
           if ($responseStream) { $responseStream.Close() }
           if ($response) { $response.Close() }
       }
   }
   ```

4. **`Get-UE4SSDownloadInfo` function** — GitHub API with proxy fallback:
   ```powershell
   function Get-UE4SSDownloadInfo {
       Write-Host ("  " + (Get-Msg 'FetchingReleaseInfo')) -ForegroundColor DarkGray

       $apiUrl = "https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest"
       $releaseData = $null

       for ($i = 0; $i -lt $script:ProxyList.Count; $i++) {
           $proxy = $script:ProxyList[$i]
           $actualUrl = if ($proxy) { "${proxy}${apiUrl}" } else { $apiUrl }

           try {
               $headers = @{
                   "User-Agent" = "PickupRangeXpBoost-Installer/1.0"
                   "Accept" = "application/vnd.github+json"
               }
                # Use Invoke-RestMethod for JSON parsing (OK for small API responses)
               # NOTE: Invoke-RestMethod does NOT support -UseBasicParsing (that's Invoke-WebRequest only)
               $releaseData = Invoke-RestMethod -Uri $actualUrl -Headers $headers -TimeoutSec 15
               break
           }
           catch {
               # Check for rate limiting
               if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 403) {
                   throw (Get-Msg 'APIRateLimited')
               }
               continue
           }
       }

       if (-not $releaseData) {
           throw (Get-Msg 'ReleaseInfoFailed')
       }

       # Find asset starting with "UE4SS_"
       $asset = $null
       foreach ($a in $releaseData.assets) {
           if ($a.name -like "UE4SS_*") {
               $asset = $a
               break
           }
       }

       if (-not $asset) {
           throw (Get-Msg 'ReleaseInfoFailed')
       }

       # Parse SHA256 from digest field (format: "sha256:HEXHASH")
       $hash = ""
       if ($asset.digest -and $asset.digest.StartsWith("sha256:")) {
           $hash = $asset.digest.Substring(7).ToUpper()
       }

       return @{
           Name = $asset.name
           Url  = $asset.browser_download_url
           Size = [long]$asset.size
           Hash = $hash
       }
   }
   ```

**Key details**:
- `Invoke-DownloadWithProgress` uses 64KB buffer for optimal throughput
- Progress throttled to 200ms intervals (avoids PS console I/O bottleneck)
- `HttpWebRequest.AllowAutoRedirect = $true` handles GitHub's CDN redirects
- Proxy fallback: empty string = direct, otherwise prepend proxy URL to full GitHub URL
- `Invoke-RestMethod` is acceptable for small API JSON (only slow for large file downloads)
- `-UseBasicParsing` avoids dependency on Internet Explorer parsing engine
- SHA256 hash from API `digest` field is parsed (strip `sha256:` prefix, uppercase)
- File verification is optional (mod ZIP has no API metadata) via `$ExpectedSize` / `$ExpectedHash` defaults of 0/""
- Partial files are cleaned up on failure before trying next proxy

**QA for Task 3**:
- [ ] Download from direct GitHub URL works (when accessible)
- [ ] Download falls back to proxies when direct fails (timeout 30s per attempt)
- [ ] Progress bar displays correctly with MB/total and percentage
- [ ] SHA256 hash verification catches corrupted files
- [ ] File size verification catches truncated downloads
- [ ] Partial files are deleted before retrying with next proxy
- [ ] API rate limit (403) produces a clear localized message, not a generic error
- [ ] API call works through proxies (proxy prepended to api.github.com URL)
- [ ] `Get-UE4SSDownloadInfo` returns correct asset (starts with `UE4SS_`, not `zDEV-`)

---

### Task 4: Implement `Install-UE4SS` — extraction with config preservation
**Commit**: 4
**File**: `install.ps1` (add function AFTER download functions, BEFORE `Find-GameDirectory`)

Implement `function Install-UE4SS` with the following logic:

```powershell
function Install-UE4SS {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ZipPath,
        [Parameter(Mandatory=$true)]
        [string]$GameDir   # Win64 directory
    )

    $modsDir = Join-Path $GameDir "ue4ss\Mods"
    $modsTxtPath = Join-Path $modsDir "mods.txt"
    $settingsPath = Join-Path $GameDir "ue4ss\UE4SS-settings.ini"

    # --- Backup existing configs ---
    $backedUpModsTxt = $null
    $backedUpSettings = $null

    if (Test-Path $modsTxtPath) {
        Write-Host ("  " + (Get-Msg 'BackingUpConfig')) -ForegroundColor DarkGray
        $backedUpModsTxt = Get-Content -Path $modsTxtPath -Raw -Encoding UTF8
    }
    if (Test-Path $settingsPath) {
        $backedUpSettings = Get-Content -Path $settingsPath -Raw -Encoding UTF8
    }

    # --- Extract UE4SS ZIP ---
    Write-Host ("  " + (Get-Msg 'Extracting')) -ForegroundColor DarkGray
    # UE4SS ZIP is FLAT: dwmapi.dll + ue4ss/ at root → extract directly to Win64 dir
    Expand-Archive -Path $ZipPath -DestinationPath $GameDir -Force

    # --- Verify sentinel files ---
    $dwmapiPath = Join-Path $GameDir "dwmapi.dll"
    $ue4ssDllPath = Join-Path $GameDir "ue4ss\UE4SS.dll"
    if (-not (Test-Path $dwmapiPath) -or -not (Test-Path $ue4ssDllPath)) {
        throw "UE4SS extraction verification failed: sentinel files not found."
    }

    # --- Restore UE4SS-settings.ini ---
    if ($backedUpSettings) {
        Write-Host ("  " + (Get-Msg 'RestoringConfig')) -ForegroundColor DarkGray
        [System.IO.File]::WriteAllText($settingsPath, $backedUpSettings, [System.Text.Encoding]::UTF8)
    }

    # --- Merge mods.txt ---
    if ($backedUpModsTxt) {
        # Parse backed up entries (format: "ModName : 0|1")
        $customEntries = @{}
        foreach ($line in ($backedUpModsTxt -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -and -not $trimmed.StartsWith(";") -and $trimmed -match '^(.+?)\s*:\s*(\d+)$') {
                $customEntries[$Matches[1].Trim()] = $Matches[2]
            }
        }

        # Read new default mods.txt
        $newModsTxt = Get-Content -Path $modsTxtPath -Encoding UTF8
        $defaultMods = @{}
        foreach ($line in $newModsTxt) {
            $trimmed = $line.Trim()
            if ($trimmed -and -not $trimmed.StartsWith(";") -and $trimmed -match '^(.+?)\s*:\s*\d+$') {
                $defaultMods[$Matches[1].Trim()] = $true
            }
        }

        # Find custom entries not in default list
        $extraEntries = @()
        foreach ($modName in $customEntries.Keys) {
            if (-not $defaultMods.ContainsKey($modName)) {
                $extraEntries += "$modName : $($customEntries[$modName])"
            }
        }

        # Insert extra entries before "; Built-in keybinds" comment or "Keybinds : 1" line
        if ($extraEntries.Count -gt 0) {
            $lines = [System.Collections.ArrayList]@($newModsTxt)
            $insertIndex = $lines.Count  # default: end of file
            for ($j = 0; $j -lt $lines.Count; $j++) {
                if ($lines[$j].Trim().StartsWith("; Built-in keybinds") -or $lines[$j].Trim() -match '^Keybinds\s*:\s*\d+$') {
                    $insertIndex = $j
                    break
                }
            }
            foreach ($entry in $extraEntries) {
                $lines.Insert($insertIndex, $entry)
                $insertIndex++
            }
            $lines | Set-Content -Path $modsTxtPath -Encoding UTF8
        }
    }
}
```

**Key details**:
- `Expand-Archive -Force` overwrites existing files but preserves files not in the ZIP (existing custom mods are safe)
- `UE4SS-settings.ini` is restored byte-for-byte from backup (preserves user customizations)
- `mods.txt` merge logic: reads both old and new, identifies custom entries not in the default list, inserts them before the `Keybinds` section
- Sentinel verification after extraction: checks `dwmapi.dll` and `ue4ss/UE4SS.dll` exist
- The merge uses string matching `^(.+?)\s*:\s*(\d+)$` to parse mod entries — handles whitespace variations
- Comments (lines starting with `;`) and blank lines are preserved from the new file

**QA for Task 4**:
- [ ] Fresh install (no existing UE4SS): ZIP extracts correctly, `dwmapi.dll` + `ue4ss/UE4SS.dll` exist
- [ ] Update install (existing UE4SS): `UE4SS-settings.ini` preserved unchanged
- [ ] Update install: custom mod entries in mods.txt are preserved after extraction
- [ ] Update install: `Keybinds : 1` remains the last non-comment entry
- [ ] Extraction failure: meaningful error message if sentinel files not found

---

### Task 5: Implement `Install-Mod` and `Update-ModsConfig` — mod extraction and registration
**Commit**: 5
**File**: `install.ps1` (add functions AFTER `Install-UE4SS`)

1. **`Install-Mod` function**:
   ```powershell
   function Install-Mod {
       param(
           [Parameter(Mandatory=$true)]
           [string]$ZipPath,
           [Parameter(Mandatory=$true)]
           [string]$GameDir
       )

       $modsDir = Join-Path $GameDir "ue4ss\Mods"
       $modTargetDir = Join-Path $modsDir "PickupRangeXpBoost"
       $tempExtractDir = Join-Path $script:TempDir "mod_extract"

       # Extract to temp directory
       Write-Host ("  " + (Get-Msg 'Extracting')) -ForegroundColor DarkGray
       Expand-Archive -Path $ZipPath -DestinationPath $tempExtractDir -Force

       # Find the extracted root folder (should be PickupRangeXpBoost-master)
       $extractedRoot = Get-ChildItem -Path $tempExtractDir -Directory | Select-Object -First 1
       if (-not $extractedRoot -or -not (Test-Path (Join-Path $extractedRoot.FullName "Scripts\main.lua"))) {
           throw "Mod archive structure unexpected: Scripts\main.lua not found."
       }

       # Remove old mod directory if exists
       if (Test-Path $modTargetDir) {
           Write-Host ("  " + (Get-Msg 'RemovingOldMod')) -ForegroundColor DarkGray
           Remove-Item -Path $modTargetDir -Recurse -Force
       }

       # Move and rename: PickupRangeXpBoost-master → PickupRangeXpBoost
       # Ensure Mods directory exists
       if (-not (Test-Path $modsDir)) {
           New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
       }
       Move-Item -Path $extractedRoot.FullName -Destination $modTargetDir -Force

       # Verify
       $mainLuaPath = Join-Path $modTargetDir "Scripts\main.lua"
       if (-not (Test-Path $mainLuaPath)) {
           throw "Mod installation verification failed: Scripts\main.lua not found at $modTargetDir"
       }

       # Register in mods.txt
       $modsTxtPath = Join-Path $modsDir "mods.txt"
       if (Test-Path $modsTxtPath) {
           Update-ModsConfig -ModsTxtPath $modsTxtPath -ModName "PickupRangeXpBoost" -Enabled 1
           Write-Host ("  " + (Get-Msg 'ModRegistered')) -ForegroundColor Green
       }
   }
   ```

2. **`Update-ModsConfig` function**:
   ```powershell
   function Update-ModsConfig {
       param(
           [Parameter(Mandatory=$true)]
           [string]$ModsTxtPath,
           [Parameter(Mandatory=$true)]
           [string]$ModName,
           [int]$Enabled = 1
       )

       $lines = [System.Collections.ArrayList]@(Get-Content -Path $ModsTxtPath -Encoding UTF8)

       # Check if mod entry already exists
       $existingIndex = -1
       for ($i = 0; $i -lt $lines.Count; $i++) {
           if ($lines[$i] -match "^\s*$([regex]::Escape($ModName))\s*:\s*\d+") {
               $existingIndex = $i
               break
           }
       }

       $entry = "$ModName : $Enabled"

       if ($existingIndex -ge 0) {
           # Update existing entry
           $lines[$existingIndex] = $entry
       }
       else {
           # Insert before "; Built-in keybinds" comment or "Keybinds : 1"
           $insertIndex = $lines.Count
           for ($j = 0; $j -lt $lines.Count; $j++) {
               $trimmed = $lines[$j].Trim()
               if ($trimmed.StartsWith("; Built-in keybinds") -or $trimmed -match '^Keybinds\s*:\s*\d+$') {
                   $insertIndex = $j
                   break
               }
           }
           $lines.Insert($insertIndex, $entry)
       }

       $lines | Set-Content -Path $ModsTxtPath -Encoding UTF8
   }
   ```

**Key details**:
- Mod ZIP extracts to temp first (because it has a root folder that needs renaming)
- Old mod directory is completely removed before placing new one (clean update)
- `Update-ModsConfig` handles three cases: (a) entry exists and enabled, (b) entry exists but disabled → enable it, (c) entry doesn't exist → insert before Keybinds
- Uses `[regex]::Escape()` to safely match mod name in regex
- `Get-ChildItem -Directory | Select-Object -First 1` finds the single root folder in the extracted archive
- Verification checks `Scripts\main.lua` exists after move

**QA for Task 5**:
- [ ] Fresh mod install: `ue4ss/Mods/PickupRangeXpBoost/Scripts/main.lua` exists
- [ ] Mod update: old files completely replaced (no stale files from previous version)
- [ ] mods.txt: `PickupRangeXpBoost : 1` appears in file
- [ ] mods.txt: `Keybinds : 1` remains last non-comment entry
- [ ] mods.txt: if entry already exists as `PickupRangeXpBoost : 0`, it's changed to `1`
- [ ] mods.txt: if entry already exists as `PickupRangeXpBoost : 1`, no duplicate added
- [ ] Mod archive with unexpected structure: clear error message

---

### Task 6: Create `install.cmd` launcher
**Commit**: 6
**File**: `install.cmd` (new file, in project root alongside install.ps1)

Create a minimal `.cmd` launcher for double-click execution:

```batch
@echo off
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
popd
pause
```

**Key details**:
- `pushd "%~dp0"` ensures working directory is the script's location
- `-NoProfile` avoids user's PS profile interfering
- `-ExecutionPolicy Bypass` allows the .ps1 to run without policy changes
- `pause` at the end keeps the window open (redundant with `Read-Host` in the PS script, but provides a safety net if the PS script crashes before reaching its own pause)
- File encoding: ANSI (standard for .cmd files)

**QA for Task 6**:
- [ ] Double-clicking `install.cmd` opens PowerShell and runs `install.ps1`
- [ ] Window stays open after script completes or errors
- [ ] Works from any directory (uses `%~dp0` for absolute path)

<!-- TASKS_END -->

## Final Verification Wave

After ALL tasks are complete, the implementer MUST verify:

1. **Syntax check**: `powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $ErrorActionPreference='Stop'; . '.\install.ps1' }"` parses without syntax errors
2. **File encoding**: `install.ps1` is saved as UTF-8 with BOM (first 3 bytes are `EF BB BF`)
3. **No PS 7+ features used**: grep for `??`, `?.`, ternary patterns
4. **All message keys exist in both languages**: every `$Msg.xxx` reference has both zh and en entries
5. **Temp file cleanup**: `finally` block removes all temp files/dirs
6. **mods.txt handling**: verify Keybinds stays last line, PickupRangeXpBoost inserted correctly
7. **Error UX**: every `catch` block displays localized error AND calls `Read-Host` to pause

**DO NOT mark work as complete until user explicitly confirms "okay" after reviewing the verification results.**
