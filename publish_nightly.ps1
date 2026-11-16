# publish_nightly.ps1
param(
    [string]$CommitMessage = "",
    [switch]$AutoCommit,
    [switch]$SkipBuild,
    [switch]$SkipGit,
    [switch]$SkipGitHub,
    [switch]$SkipPlayStore,
    [string]$ServiceAccountJson = "",
    [string]$Track = "internal",
    [string]$PlayNotes = "",
    [string]$SinceVersion = "",
    [string]$GhNotesFilePath = "",
    [switch]$ChangesNotSentForReview,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BulletChar = [char]0x2022
$EllipsisChar = [char]0x2026
$EnDashChar = [char]0x2013
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ProjectRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-DryRun {
    param([string]$Message)
    Write-Host "[DRY-RUN] $Message" -ForegroundColor Yellow
}

function Resolve-Executable {
    param(
        [string]$Name,
        [string[]]$FallbackPaths = @()
    )
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    foreach ($candidate in $FallbackPaths) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)
    $b64 = [Convert]::ToBase64String($Bytes)
    return $b64.TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Read-Asn1Length {
    param(
        [byte[]]$Data,
        [ref]$Offset
    )
    $first = [int]$Data[$Offset.Value]
    $Offset.Value++
    if (($first -band 0x80) -eq 0) {
        return $first
    }
    $numBytes = $first -band 0x7F
    if ($numBytes -le 0 -or $numBytes -gt 4) {
        throw "Unsupported ASN.1 DER length byte count: $numBytes"
    }
    $len = 0
    for ($i = 0; $i -lt $numBytes; $i++) {
        $len = ($len -shl 8) -bor [int]$Data[$Offset.Value]
        $Offset.Value++
    }
    return $len
}

function Read-Asn1Element {
    param(
        [byte[]]$Data,
        [ref]$Offset,
        [byte]$ExpectedTag
    )
    $tag = $Data[$Offset.Value]
    if ($tag -ne $ExpectedTag) {
        throw ("Unexpected ASN.1 tag 0x{0:X2}; expected 0x{1:X2}" -f $tag, $ExpectedTag)
    }
    $Offset.Value++
    $len = Read-Asn1Length -Data $Data -Offset $Offset
    $start = $Offset.Value
    $Offset.Value += $len
    $slice = New-Object byte[] $len
    [Array]::Copy($Data, $start, $slice, 0, $len)
    return $slice
}

function ConvertTo-UnsignedBigIntBytes {
    param(
        [byte[]]$Raw,
        [int]$FixedLength = 0
    )
    $idx = 0
    while ($idx -lt ($Raw.Length - 1) -and $Raw[$idx] -eq 0) {
        $idx++
    }
    $trimmedLen = $Raw.Length - $idx
    if ($FixedLength -le 0) {
        $out = New-Object byte[] $trimmedLen
        [Array]::Copy($Raw, $idx, $out, 0, $trimmedLen)
        return $out
    }
    if ($trimmedLen -gt $FixedLength) {
        throw "ASN.1 integer length ($trimmedLen) exceeds expected RSA parameter size ($FixedLength)."
    }
    $padded = New-Object byte[] $FixedLength
    [Array]::Copy($Raw, $idx, $padded, ($FixedLength - $trimmedLen), $trimmedLen)
    return $padded
}

function ConvertFrom-Pkcs8PemToRsaParameters {
    param([string]$PemText)
    $clean = $PemText -replace "-----BEGIN PRIVATE KEY-----", "" `
                      -replace "-----END PRIVATE KEY-----", "" `
                      -replace "\s+", ""
    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "Service account private_key is empty or not in PKCS#8 PEM format."
    }
    $pkcs8 = [Convert]::FromBase64String($clean)
    $offset = 0
    $outerSeq = Read-Asn1Element -Data $pkcs8 -Offset ([ref]$offset) -ExpectedTag 0x30

    $innerOffset = 0
    $null = Read-Asn1Element -Data $outerSeq -Offset ([ref]$innerOffset) -ExpectedTag 0x02 # version
    $null = Read-Asn1Element -Data $outerSeq -Offset ([ref]$innerOffset) -ExpectedTag 0x30 # algorithmIdentifier
    $rsaKeyBytes = Read-Asn1Element -Data $outerSeq -Offset ([ref]$innerOffset) -ExpectedTag 0x04 # privateKey OCTET STRING

    $rsaOffset = 0
    $rsaSeq = Read-Asn1Element -Data $rsaKeyBytes -Offset ([ref]$rsaOffset) -ExpectedTag 0x30

    $seqOffset = 0
    $null = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02 # version
    $nRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02
    $eRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02
    $dRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02
    $pRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02
    $qRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02
    $dpRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02
    $dqRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02
    $iqRaw = Read-Asn1Element -Data $rsaSeq -Offset ([ref]$seqOffset) -ExpectedTag 0x02

    $modulus = ConvertTo-UnsignedBigIntBytes -Raw $nRaw
    $modLen = $modulus.Length
    $halfLen = [int]($modLen / 2)

    $params = New-Object System.Security.Cryptography.RSAParameters
    $params.Modulus = $modulus
    $params.Exponent = ConvertTo-UnsignedBigIntBytes -Raw $eRaw
    $params.D = ConvertTo-UnsignedBigIntBytes -Raw $dRaw -FixedLength $modLen
    $params.P = ConvertTo-UnsignedBigIntBytes -Raw $pRaw -FixedLength $halfLen
    $params.Q = ConvertTo-UnsignedBigIntBytes -Raw $qRaw -FixedLength $halfLen
    $params.DP = ConvertTo-UnsignedBigIntBytes -Raw $dpRaw -FixedLength $halfLen
    $params.DQ = ConvertTo-UnsignedBigIntBytes -Raw $dqRaw -FixedLength $halfLen
    $params.InverseQ = ConvertTo-UnsignedBigIntBytes -Raw $iqRaw -FixedLength $halfLen
    return $params
}

function Get-GooglePlayAccessToken {
    param([string]$JsonPath)
    $saJson = [System.IO.File]::ReadAllText($JsonPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $saJson.client_email -or -not $saJson.private_key) {
        throw "Service account JSON at '$JsonPath' is missing 'client_email' or 'private_key'."
    }
    $tokenUri = if ($saJson.token_uri) { [string]$saJson.token_uri } else { "https://oauth2.googleapis.com/token" }
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $headerJson = '{"alg":"RS256","typ":"JWT"}'
    $claimsObj = @{
        iss   = [string]$saJson.client_email
        scope = "https://www.googleapis.com/auth/androidpublisher"
        aud   = $tokenUri
        iat   = $now
        exp   = ($now + 3600)
    }
    $claimsJson = $claimsObj | ConvertTo-Json -Compress

    $headerB64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($headerJson))
    $claimsB64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($claimsJson))
    $signingInput = "$headerB64.$claimsB64"

    $rsaParams = ConvertFrom-Pkcs8PemToRsaParameters -PemText ([string]$saJson.private_key)
    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportParameters($rsaParams)
        $sigBytes = $rsa.SignData(
            [System.Text.Encoding]::UTF8.GetBytes($signingInput),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    } finally {
        $rsa.Dispose()
    }

    $sigB64 = ConvertTo-Base64Url -Bytes $sigBytes
    $jwt = "$signingInput.$sigB64"
    $formBody = "grant_type=$([Uri]::EscapeDataString('urn:ietf:params:oauth:grant-type:jwt-bearer'))&assertion=$([Uri]::EscapeDataString($jwt))"

    $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUri `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $formBody
    if (-not $tokenResp.access_token) {
        throw "OAuth2 token response did not contain 'access_token'."
    }
    return [string]$tokenResp.access_token
}

function Get-HttpErrorDetail {
    param($ExceptionRecord)
    try {
        $resp = $ExceptionRecord.Exception.Response
        if ($resp) {
            $stream = $resp.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $body = $reader.ReadToEnd()
                $reader.Dispose()
                if (-not [string]::IsNullOrWhiteSpace($body)) {
                    return $body
                }
            }
        }
    } catch {}
    return $ExceptionRecord.Exception.Message
}

function Convert-MarkdownBulletToPlainText {
    param([string]$Text)
    $plain = $Text
    $plain = [regex]::Replace($plain, '\[([^\]]+)\]\([^)]+\)', '$1')
    $plain = $plain -replace '`([^`]+)`', '$1'
    $plain = $plain -replace '\*\*([^*]+)\*\*', '$1'
    $plain = $plain -replace '__([^_]+)__', '$1'
    $plain = $plain -replace '(?<!\w)\*([^*]+)\*(?!\w)', '$1'
    $plain = [regex]::Replace($plain, '\s+', ' ').Trim()
    return $plain
}

function Limit-AtWordBoundary {
    param(
        [string]$Text,
        [int]$MaxLength
    )
    if ($MaxLength -le 0) { return "" }
    if ($Text.Length -le $MaxLength) { return $Text }
    if ($MaxLength -le 1) { return $Text.Substring(0, $MaxLength) }
    $limit = $MaxLength - 1
    $slice = $Text.Substring(0, $limit)
    $lastSpace = $slice.LastIndexOf(' ')
    if ($lastSpace -ge [int]($limit * 0.5)) {
        $slice = $slice.Substring(0, $lastSpace)
    }
    return ($slice.TrimEnd() + $EllipsisChar)
}

function Extract-ChangelogSection {
    param(
        [string]$ChangelogPath,
        [string]$VersionName
    )
    if (-not (Test-Path $ChangelogPath)) {
        throw "CHANGELOG.md not found at '$ChangelogPath'."
    }
    $lines = Get-Content $ChangelogPath -Encoding UTF8
    $escapedVer = [regex]::Escape($VersionName)
    $startIdx = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^##\s+Update\s+$escapedVer\b" -or $lines[$i] -match "^##\s+.*\[$escapedVer\]") {
            $startIdx = $i
            break
        }
    }
    if ($startIdx -lt 0) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^##\s+") {
                $startIdx = $i
                break
            }
        }
    }
    if ($startIdx -lt 0) {
        throw "Could not find any '## ' release section in $ChangelogPath."
    }

    $sectionLines = New-Object System.Collections.Generic.List[string]
    for ($i = $startIdx; $i -lt $lines.Count; $i++) {
        if ($i -gt $startIdx -and $lines[$i] -match "^##\s+") {
            break
        }
        $sectionLines.Add($lines[$i])
    }
    while ($sectionLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($sectionLines[$sectionLines.Count - 1])) {
        $sectionLines.RemoveAt($sectionLines.Count - 1)
    }
    return ($sectionLines.ToArray())
}

function Extract-ChangelogSinceVersion {
    param(
        [string]$ChangelogPath,
        [string]$SinceVersion
    )
    if (-not (Test-Path $ChangelogPath)) {
        throw "CHANGELOG.md not found at '$ChangelogPath'."
    }
    $lines = Get-Content $ChangelogPath -Encoding UTF8
    $cleanSince = $SinceVersion.Trim().TrimStart('v', 'V')
    $escapedSince = [regex]::Escape($cleanSince)

    $startIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^##\s+") {
            $startIdx = $i
            break
        }
    }
    if ($startIdx -lt 0) {
        throw "Could not find any '## ' release section in $ChangelogPath."
    }

    $collected = New-Object System.Collections.Generic.List[string]
    $foundBoundary = $false
    $includedVersions = New-Object System.Collections.Generic.List[string]

    for ($i = $startIdx; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "^##\s+Update\s+$escapedSince\b" -or $line -match "^##\s+.*\[$escapedSince\]") {
            $foundBoundary = $true
            break
        }
        if ($line -match "^##\s+Update\s+([0-9]+(?:\.[0-9]+)*)") {
            $includedVersions.Add($Matches[1])
        }
        $collected.Add($line)
    }

    if (-not $foundBoundary) {
        throw "Could not find boundary '## Update $cleanSince' in $ChangelogPath."
    }
    while ($collected.Count -gt 0 -and [string]::IsNullOrWhiteSpace($collected[$collected.Count - 1])) {
        $collected.RemoveAt($collected.Count - 1)
    }
    if ($collected.Count -eq 0 -or $includedVersions.Count -eq 0) {
        throw "No changelog entries strictly newer than '$cleanSince' were found before '## Update $cleanSince'."
    }

    return [PSCustomObject]@{
        Lines           = $collected.ToArray()
        EarliestVersion = $includedVersions[$includedVersions.Count - 1]
        LatestVersion   = $includedVersions[0]
        EntryCount      = $includedVersions.Count
        SinceVersion    = $cleanSince
    }
}

function Build-ConsolidatedGitHubNotes {
    param(
        [string]$SinceVersion,
        [string]$EarliestVersion,
        [string]$VersionName,
        [string[]]$DetailedLines
    )
    $cleanSince = $SinceVersion.Trim().TrimStart('v', 'V')
    $rangeStart = if (-not [string]::IsNullOrWhiteSpace($EarliestVersion)) { $EarliestVersion } else { "1.2.0" }
    $headerLines = @(
        "## Everything New Since v$cleanSince",
        "",
        '- **Gemini Nano v4 + Thinking Mode**: Release channel (`Stable` / `Preview`) and preference (`Full` / `Fast`) switcher, live Thinking Mode with collapsible thought process bubbles, and `m3x_chat` schema integration.',
        '- **Assistant Overlay + Vision + Screen Context**: Material You floating sheet with 1:1 drag physics, Camera & Gallery photo attachments, multi-turn visual memory, Assist screen context, and AICore Policy Fallback Retry.',
        '- **Inter-App Agentic Mesh & Tools**: Dynamic `m3x_mesh` ContentProvider IPC, built-in offline/online extensions (Docs, Battery, Wikipedia, DuckDuckGo, Weather), and multi-turn tool chaining & synthesis.',
        '- **Multi-Model Manager & Onboarding Gate**: Unified Model Selector with native variant download tracking, dual-branch unsupported-device onboarding, in-app GenAI Docs Explorer, and Chat Archiving.',
        '- **Android 15/16 & Reliability**: 16 KB page-size alignment, Nano v3 auto-continuation & truncation fixes, non-blocking startup timeouts, and narrow-viewport/translator hardening.',
        "",
        "<details>",
        "<summary>Detailed changelog (v$rangeStart $EnDashChar v$VersionName)</summary>",
        ""
    )
    $footerLines = @(
        "",
        "</details>"
    )
    $all = New-Object System.Collections.Generic.List[string]
    foreach ($l in $headerLines) { $all.Add($l) }
    foreach ($l in $DetailedLines) { $all.Add($l) }
    foreach ($l in $footerLines) { $all.Add($l) }
    return (($all.ToArray() -join "`n") + "`n")
}

function Build-PlayStoreNotes {
    param(
        [string]$CustomNotes,
        [string[]]$SectionLines,
        [string]$VersionName,
        [string]$VersionCode,
        [string]$ReleaseUrl,
        [string]$SinceVersion = ""
    )
    if (-not [string]::IsNullOrWhiteSpace($CustomNotes)) {
        $normalized = ($CustomNotes -replace "`r`n", "`n").Trim()
        if ($normalized.Length -gt 500) {
            throw "Supplied -PlayNotes exceeds Google Play Store's 500-character limit ($($normalized.Length)/500 chars)."
        }
        return $normalized
    }

    if (-not [string]::IsNullOrWhiteSpace($SinceVersion)) {
        $cleanSince = $SinceVersion.Trim().TrimStart('v', 'V')
        $footer = "Full log: $ReleaseUrl"
        if ($footer.Length -ge 490) {
            $footer = $ReleaseUrl
        }
        $budget = 500 - $footer.Length - 2
        if ($budget -le 10) {
            return (Limit-AtWordBoundary -Text $ReleaseUrl -MaxLength 500)
        }

        $milestoneBullets = @(
            "What's new since v${cleanSince}:",
            "$BulletChar Nano v4 & Thinking Mode with collapsible thoughts",
            "$BulletChar Assistant Overlay with Camera, Vision & Screen Context",
            "$BulletChar Inter-App Agentic Mesh & built-in/online tools",
            "$BulletChar Multi-Model Manager, Docs Explorer & Android 15/16 fixes"
        )
        $chosen = New-Object System.Collections.Generic.List[string]
        $usedLen = 0
        foreach ($item in $milestoneBullets) {
            $sepLen = if ($chosen.Count -gt 0) { 1 } else { 0 }
            if (($usedLen + $sepLen + $item.Length) -le $budget) {
                $chosen.Add($item)
                $usedLen += $sepLen + $item.Length
            } elseif ($chosen.Count -eq 0) {
                $chosen.Add((Limit-AtWordBoundary -Text $item -MaxLength $budget))
                break
            } else {
                break
            }
        }

        $combined = ($chosen.ToArray() -join "`n") + "`n`n" + $footer
        if ($combined.Length -gt 500) {
            $combined = Limit-AtWordBoundary -Text $combined -MaxLength 500
        }
        return $combined
    }

    $bulletRegex = "^\s*[-*$BulletChar]\s+(.+)$"
    $bullets = New-Object System.Collections.Generic.List[string]
    foreach ($line in $SectionLines) {
        if ($line -match $bulletRegex) {
            $clean = Convert-MarkdownBulletToPlainText -Text $Matches[1]
            if (-not [string]::IsNullOrWhiteSpace($clean)) {
                $bullets.Add("$BulletChar $clean")
            }
        }
    }
    if ($bullets.Count -eq 0) {
        $bullets.Add("$BulletChar Nightly build v$VersionName ($VersionCode)")
    }

    $footer = "Full notes: $ReleaseUrl"
    if ($footer.Length -ge 490) {
        $footer = $ReleaseUrl
    }
    $budget = 500 - $footer.Length - 2
    if ($budget -le 10) {
        return (Limit-AtWordBoundary -Text $ReleaseUrl -MaxLength 500)
    }

    $chosen = New-Object System.Collections.Generic.List[string]
    $usedLen = 0
    foreach ($item in $bullets) {
        $sepLen = if ($chosen.Count -gt 0) { 1 } else { 0 }
        if (($usedLen + $sepLen + $item.Length) -le $budget) {
            $chosen.Add($item)
            $usedLen += $sepLen + $item.Length
        } elseif ($chosen.Count -eq 0) {
            $chosen.Add((Limit-AtWordBoundary -Text $item -MaxLength $budget))
            break
        } else {
            break
        }
    }

    $combined = ($chosen.ToArray() -join "`n") + "`n`n" + $footer
    if ($combined.Length -gt 500) {
        $combined = Limit-AtWordBoundary -Text $combined -MaxLength 500
    }
    return $combined
}

function Show-PlayConsoleSetupInstructions {
    param([string]$DefaultPath)
    Write-Host ""
    Write-Host "Google Play Console Service Account Setup:" -ForegroundColor Yellow
    Write-Host "  1. Open Google Cloud Console -> IAM & Admin -> Service Accounts and create a Service Account."
    Write-Host "  2. Create a JSON key for that Service Account and download it."
    Write-Host "  3. In Google Play Console -> Users and permissions -> Invite new users, add the service"
    Write-Host "     account email and grant App permissions (Release to testing tracks / Manage testing tracks)."
    Write-Host "  4. Save the JSON key to '$DefaultPath' (gitignored),"
    Write-Host "     OR set `$env:PLAY_SERVICE_ACCOUNT_JSON, OR pass -ServiceAccountJson <path>."
    Write-Host ""
}

# ==============================================================================
# Step 1: Parse pubspec.yaml & build identifiers
# ==============================================================================
Write-Step "1/7 Parsing version metadata from pubspec.yaml"
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
if (-not (Test-Path $PubspecPath)) {
    throw "pubspec.yaml not found at '$PubspecPath'."
}

$VersionName = ""
$VersionCode = ""
foreach ($line in (Get-Content $PubspecPath -Encoding UTF8)) {
    if ($line -match "version:\s*([0-9\.]+)\+([0-9]+)") {
        $VersionName = $Matches[1]
        $VersionCode = $Matches[2]
        break
    }
}
if ([string]::IsNullOrWhiteSpace($VersionName) -or [string]::IsNullOrWhiteSpace($VersionCode)) {
    throw "Could not parse 'version: X.Y.Z+BUILD' from $PubspecPath."
}

$PackageName = "page.puzzak.paios"
$GradleKtsPath = Join-Path $ProjectRoot "android\app\build.gradle.kts"
if (Test-Path $GradleKtsPath) {
    $gradleContent = [System.IO.File]::ReadAllText($GradleKtsPath, [System.Text.Encoding]::UTF8)
    if ($gradleContent -match 'applicationId\s*=\s*"([^"]+)"') {
        $PackageName = $Matches[1]
    }
}

$Tag = "v$VersionName-nightly.$VersionCode"
$RepoUrl = "https://github.com/Puzzaks/PAIOS/releases/tag/$Tag"
$BuildDir = Join-Path $ProjectRoot "build"
$ApkPath = Join-Path $BuildDir "PAIOS_v${VersionName}_GitHub.apk"
$AabPath = Join-Path $BuildDir "PAIOS_v${VersionName}_PlayStore.aab"
$GhNotesFile = Join-Path $BuildDir "nightly_release_notes.md"
$PlayNotesFile = Join-Path $BuildDir "play_release_notes.txt"

Write-Host "Package: $PackageName | Version: $VersionName | Build: $VersionCode | Tag: $Tag"

# ==============================================================================
# Step 2: Extract CHANGELOG.md section for GitHub release notes
# ==============================================================================
Write-Step "2/7 Extracting release notes from CHANGELOG.md"
$ChangelogPath = Join-Path $ProjectRoot "CHANGELOG.md"
$SectionLines = @()
$GhNotesContent = ""

if (-not [string]::IsNullOrWhiteSpace($SinceVersion)) {
    $sinceData = Extract-ChangelogSinceVersion -ChangelogPath $ChangelogPath -SinceVersion $SinceVersion
    $SectionLines = $sinceData.Lines
    Write-Host "Extracted $($sinceData.EntryCount) changelog sections (v$($sinceData.EarliestVersion) $EnDashChar v$($sinceData.LatestVersion), since v$($sinceData.SinceVersion))"
    $GhNotesContent = Build-ConsolidatedGitHubNotes `
        -SinceVersion $sinceData.SinceVersion `
        -EarliestVersion $sinceData.EarliestVersion `
        -VersionName $VersionName `
        -DetailedLines $SectionLines
} else {
    $SectionLines = Extract-ChangelogSection -ChangelogPath $ChangelogPath -VersionName $VersionName
    $GhNotesContent = ($SectionLines -join "`n") + "`n"
    Write-Host "Extracted $($SectionLines.Count) lines from $($SectionLines[0])"
}

if (-not [string]::IsNullOrWhiteSpace($GhNotesFilePath)) {
    if (Test-Path $GhNotesFilePath) {
        $GhNotesContent = [System.IO.File]::ReadAllText((Resolve-Path $GhNotesFilePath).Path, [System.Text.Encoding]::UTF8)
        Write-Host "Using custom GitHub release notes from '$GhNotesFilePath' ($($GhNotesContent.Length) chars)."
    } else {
        Write-Host "Warning: -GhNotesFilePath '$GhNotesFilePath' not found; using CHANGELOG.md release notes." -ForegroundColor Yellow
    }
}

if ($DryRun) {
    Write-DryRun "Would write GitHub release notes to '$GhNotesFile' ($($GhNotesContent.Length) chars)."
} else {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($GhNotesFile, $GhNotesContent, $Utf8NoBom)
    Write-Host "Wrote GitHub release notes: $GhNotesFile"
}

# ==============================================================================
# Step 3: Build & validate Play Store "What's new" notes (<= 500 chars)
# ==============================================================================
Write-Step "3/7 Formatting Play Store release notes (en-US, <= 500 chars)"
$PlayNotesFinal = Build-PlayStoreNotes `
    -CustomNotes $PlayNotes `
    -SectionLines $SectionLines `
    -VersionName $VersionName `
    -VersionCode $VersionCode `
    -ReleaseUrl $RepoUrl `
    -SinceVersion $SinceVersion

Write-Host "Play Store notes length: $($PlayNotesFinal.Length)/500 chars"
Write-Host "--- Play Store What's New Preview ---"
Write-Host $PlayNotesFinal
Write-Host "-------------------------------------"

if (-not $DryRun) {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($PlayNotesFile, $PlayNotesFinal, $Utf8NoBom)
}

# ==============================================================================
# Step 4: Build APK & AAB via build_releases.ps1
# ==============================================================================
Write-Step "4/7 Building release artifacts"
$BuildScript = Join-Path $ProjectRoot "build_releases.ps1"
if ($SkipBuild) {
    Write-Host "Skipping build (-SkipBuild specified)."
} elseif ($DryRun) {
    Write-DryRun "Would invoke: `"$BuildScript`" (producing $ApkPath and $AabPath)"
} else {
    if (-not (Test-Path $BuildScript)) {
        throw "Build script not found at '$BuildScript'."
    }
    & $BuildScript
    if ($LASTEXITCODE -ne 0) {
        throw "build_releases.ps1 failed with exit code $LASTEXITCODE."
    }
}

# ==============================================================================
# Step 5: Git dev branch workflow
# ==============================================================================
Write-Step "5/7 Git 'dev' branch & tag workflow"
if ($SkipGit) {
    Write-Host "Skipping Git workflow (-SkipGit specified)."
} else {
    $GitExe = Resolve-Executable -Name "git" -FallbackPaths @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "$env:ProgramFiles\Git\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )
    if (-not $GitExe) {
        throw "'git' was not found on PATH or standard install locations."
    }

    $currentBranch = (& $GitExe -C $ProjectRoot branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to determine current git branch."
    }
    $dirtyLines = @(& $GitExe -C $ProjectRoot status --short)
    $isDirty = ($dirtyLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($dirtyLines -join "")))

    if ($currentBranch -ne "dev") {
        & $GitExe -C $ProjectRoot show-ref --verify --quiet refs/heads/dev
        $hasLocalDev = ($LASTEXITCODE -eq 0)
        & $GitExe -C $ProjectRoot show-ref --verify --quiet refs/remotes/origin/dev
        $hasRemoteDev = ($LASTEXITCODE -eq 0)

        if (-not $hasLocalDev -and -not $hasRemoteDev) {
            throw "Current branch is '$currentBranch', and neither local 'dev' nor 'origin/dev' exists. Create 'dev' first or pass -SkipGit."
        }

        if ($DryRun) {
            if ($hasLocalDev) {
                Write-DryRun "Would switch from '$currentBranch' to existing local branch 'dev'."
            } else {
                Write-DryRun "Would create and switch to 'dev' tracking 'origin/dev'."
            }
            if ($isDirty) {
                Write-DryRun "Note: working tree currently has uncommitted changes on '$currentBranch'; non-dry-run will abort if checkout would conflict."
            }
        } else {
            if ($hasLocalDev) {
                $checkoutOut = & $GitExe -C $ProjectRoot checkout dev 2>&1
            } else {
                $checkoutOut = & $GitExe -C $ProjectRoot checkout -b dev origin/dev 2>&1
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Host ($checkoutOut -join "`n") -ForegroundColor Red
                throw "Failed to safely switch from '$currentBranch' to 'dev' (likely due to uncommitted changes on '$currentBranch'). Commit or stash them first; no files were clobbered."
            }
        }
    } else {
        Write-Host "Already on 'dev' branch."
    }

    $dirtyAfter = @(& $GitExe -C $ProjectRoot status --short)
    $isDirtyAfter = ($dirtyAfter.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($dirtyAfter -join "")))
    $resolvedCommitMsg = if (-not [string]::IsNullOrWhiteSpace($CommitMessage)) {
        $CommitMessage
    } else {
        "chore(release): nightly v$VersionName+$VersionCode"
    }

    if ($isDirtyAfter) {
        if ($DryRun) {
            Write-DryRun "Working tree is dirty ($($dirtyAfter.Count) entries). Would stage all ('git add -A') and commit with message: '$resolvedCommitMsg'"
        } else {
            Write-Host "Uncommitted changes detected:"
            $dirtyAfter | ForEach-Object { Write-Host "  $_" }
            if (-not $AutoCommit) {
                $answer = Read-Host "Stage all changes and commit as '$resolvedCommitMsg'? [y/N]"
                if ($answer -notin @("y", "Y", "yes", "YES")) {
                    throw "Aborted by user due to uncommitted changes (pass -AutoCommit to commit non-interactively)."
                }
            }
            & $GitExe -C $ProjectRoot add -A
            if ($LASTEXITCODE -ne 0) { throw "git add -A failed." }

            $stagedFiles = @(& $GitExe -C $ProjectRoot diff --cached --name-only)
            foreach ($sf in $stagedFiles) {
                if ($sf -match "service-account.*\.json$" -or $sf -match "(^|[\\/])gen-lang-client-.*\.json$") {
                    & $GitExe -C $ProjectRoot reset HEAD -- $sf | Out-Null
                    throw "Refusing to commit potential credential file '$sf'. Ensure it is gitignored."
                }
            }

            & $GitExe -C $ProjectRoot commit -m $resolvedCommitMsg
            if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
        }
    } else {
        Write-Host "Working tree is clean."
    }

    if ($DryRun) {
        Write-DryRun "Would ensure tag '$Tag' exists at HEAD, push 'origin dev', and push 'origin $Tag'."
    } else {
        & $GitExe -C $ProjectRoot rev-parse -q --verify "refs/tags/$Tag" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & $GitExe -C $ProjectRoot tag -a $Tag -m "PAIOS v$VersionName Nightly ($VersionCode)"
            if ($LASTEXITCODE -ne 0) { throw "git tag '$Tag' failed." }
        } else {
            Write-Host "Tag '$Tag' already exists locally."
        }

        $env:GIT_TERMINAL_PROMPT = "0"
        $env:GCM_INTERACTIVE = "never"
        $step5GhExe = Resolve-Executable -Name "gh" -FallbackPaths @(
            "$env:ProgramFiles\GitHub CLI\gh.exe",
            "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
        )
        if ($step5GhExe) {
            $prevPref = $ErrorActionPreference
            try {
                $ErrorActionPreference = "Continue"
                $null = & $step5GhExe auth status 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $null = & $step5GhExe auth setup-git 2>&1
                }
            } finally {
                $ErrorActionPreference = $prevPref
            }
        }

        & $GitExe -C $ProjectRoot push origin dev
        if ($LASTEXITCODE -ne 0) { throw "git push origin dev failed." }
        & $GitExe -C $ProjectRoot push origin $Tag
        if ($LASTEXITCODE -ne 0) { throw "git push origin $Tag failed." }
    }
}

# ==============================================================================
# Step 6: GitHub Prerelease via gh CLI
# ==============================================================================
Write-Step "6/7 Publishing GitHub Prerelease"
if ($SkipGitHub) {
    Write-Host "Skipping GitHub release (-SkipGitHub specified)."
} else {
    $GhExe = Resolve-Executable -Name "gh" -FallbackPaths @(
        "$env:ProgramFiles\GitHub CLI\gh.exe",
        "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
    )
    $ghReady = $true
    if (-not $GhExe) {
        $ghReady = $false
        Write-Host "GitHub CLI ('gh') not found. Install and authenticate with:" -ForegroundColor Yellow
        Write-Host "  winget install GitHub.cli"
        Write-Host "  gh auth login"
    } else {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $null = & $GhExe auth status 2>&1
        $authCode = $LASTEXITCODE
        $ErrorActionPreference = $prevPref
        if ($authCode -ne 0) {
            $ghReady = $false
            Write-Host "GitHub CLI ('gh') is not authenticated. Run:" -ForegroundColor Yellow
            Write-Host "  gh auth login"
        }
    }

    if ($DryRun) {
        if (-not $ghReady) {
            Write-DryRun "gh CLI is not ready on this host (would fail in live mode)."
        }
        Write-DryRun "Would execute: gh release create `"$Tag`" `"$ApkPath`" --title `"PAIOS v$VersionName Nightly ($VersionCode)`" --notes-file `"$GhNotesFile`" --prerelease --target dev"
    } else {
        if (-not $ghReady) {
            throw "GitHub CLI is missing or unauthenticated. See setup instructions above."
        }
        if (-not (Test-Path $ApkPath)) {
            throw "GitHub APK artifact not found at '$ApkPath'."
        }
        & $GhExe release create $Tag $ApkPath `
            --title "PAIOS v$VersionName Nightly ($VersionCode)" `
            --notes-file $GhNotesFile `
            --prerelease `
            --target dev
        if ($LASTEXITCODE -ne 0) {
            throw "gh release create failed with exit code $LASTEXITCODE."
        }
    }
}

# ==============================================================================
# Step 7: Google Play Store Open Testing upload (androidpublisher/v3)
# ==============================================================================
Write-Step "7/7 Publishing AAB to Google Play Store (track: '$Track')"
if ($SkipPlayStore) {
    Write-Host "Skipping Play Store upload (-SkipPlayStore specified)."
} else {
    $DefaultSaPath = Join-Path $ProjectRoot "android\play-service-account.json"
    $ResolvedSaPath = if (-not [string]::IsNullOrWhiteSpace($ServiceAccountJson)) {
        $ServiceAccountJson
    } elseif (-not [string]::IsNullOrWhiteSpace($env:PLAY_SERVICE_ACCOUNT_JSON)) {
        $env:PLAY_SERVICE_ACCOUNT_JSON
    } else {
        $DefaultSaPath
    }

    $saExists = (-not [string]::IsNullOrWhiteSpace($ResolvedSaPath) -and (Test-Path $ResolvedSaPath))
    if (-not $saExists) {
        Write-Host "Play Store Service Account JSON not found at: $ResolvedSaPath" -ForegroundColor Yellow
        Show-PlayConsoleSetupInstructions -DefaultPath $DefaultSaPath
        if ($DryRun) {
            Write-DryRun "Would authenticate with RS256 JWT, upload '$AabPath', update track '$Track' (en-US releaseNotes: $($PlayNotesFinal.Length)/500 chars), and commit edit for '$PackageName'."
        } else {
            exit 1
        }
    } elseif ($DryRun) {
        Write-DryRun "Found service account JSON at '$ResolvedSaPath'."
        Write-DryRun "Would run Play Developer API v3 pipeline for '$PackageName':"
        Write-DryRun "  1. POST edits.insert"
        Write-DryRun "  2. POST edits.bundles.upload ($AabPath)"
        Write-DryRun "  3. PUT  edits.tracks.update (track='$Track', versionCode='$VersionCode', language='en-US', notesLength=$($PlayNotesFinal.Length))"
        Write-DryRun "  4. POST edits.commit$(if ($ChangesNotSentForReview) { ' (changesNotSentForReview=true)' } else { ' (with automatic changesNotSentForReview=true fallback)' })"
    } else {
        if (-not (Test-Path $AabPath)) {
            throw "Play Store AAB artifact not found at '$AabPath'."
        }

        Write-Host "Obtaining Google Play OAuth2 access token..."
        $accessToken = Get-GooglePlayAccessToken -JsonPath $ResolvedSaPath
        $authHeaders = @{ Authorization = "Bearer $accessToken" }
        $baseApiUrl = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PackageName/edits"
        $uploadApiUrl = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$PackageName/edits"

        $editId = $null
        try {
            Write-Host "Creating Play Developer API edit..."
            $editResp = Invoke-RestMethod -Method Post -Uri $baseApiUrl `
                -Headers $authHeaders `
                -ContentType "application/json" `
                -Body "{}"
            $editId = [string]$editResp.id
            if ([string]::IsNullOrWhiteSpace($editId)) {
                throw "Play API edits.insert returned empty edit id."
            }

            Write-Host "Uploading AAB bundle ($AabPath)..."
            $bundleResp = Invoke-RestMethod -Method Post `
                -Uri "$uploadApiUrl/$editId/bundles?uploadType=media" `
                -Headers $authHeaders `
                -ContentType "application/octet-stream" `
                -InFile $AabPath `
                -TimeoutSec 600
            $uploadedVersionCode = [string]$bundleResp.versionCode
            if ([string]::IsNullOrWhiteSpace($uploadedVersionCode)) {
                $uploadedVersionCode = $VersionCode
            }
            Write-Host "Uploaded bundle versionCode: $uploadedVersionCode"

            Write-Host "Updating track '$Track' with en-US release notes..."
            $trackPayload = @{
                track    = $Track
                releases = @(
                    @{
                        name         = "$VersionName ($VersionCode)"
                        versionCodes = @($uploadedVersionCode)
                        status       = "completed"
                        releaseNotes = @(
                            @{
                                language = "en-US"
                                text     = $PlayNotesFinal
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $trackBytes = $Utf8NoBom.GetBytes($trackPayload)

            $null = Invoke-RestMethod -Method Put `
                -Uri "$baseApiUrl/$editId/tracks/$Track" `
                -Headers $authHeaders `
                -ContentType "application/json; charset=utf-8" `
                -Body $trackBytes

            $commitUri = if ($ChangesNotSentForReview) {
                "${baseApiUrl}/${editId}:commit?changesNotSentForReview=true"
            } else {
                "${baseApiUrl}/${editId}:commit"
            }
            $usedChangesNotSentForReview = [bool]$ChangesNotSentForReview
            Write-Host "Committing Play Store edit ($editId)..."
            try {
                $commitResp = Invoke-RestMethod -Method Post `
                    -Uri $commitUri `
                    -Headers $authHeaders `
                    -ContentType "application/json" `
                    -Body "{}"
            } catch {
                $commitErrorDetail = Get-HttpErrorDetail -ExceptionRecord $_
                if (-not $ChangesNotSentForReview -and $commitErrorDetail -match "changesNotSentForReview") {
                    Write-Host "WARNING: Play Console refused auto-submission to review ($commitErrorDetail). Retrying commit with changesNotSentForReview=true..." -ForegroundColor Yellow
                    $usedChangesNotSentForReview = $true
                    $commitResp = Invoke-RestMethod -Method Post `
                        -Uri "${baseApiUrl}/${editId}:commit?changesNotSentForReview=true" `
                        -Headers $authHeaders `
                        -ContentType "application/json" `
                        -Body "{}"
                } else {
                    throw
                }
            }

            if ($usedChangesNotSentForReview) {
                Write-Host "Play Store edit committed with changesNotSentForReview=true! Edit ID: $($commitResp.id)" -ForegroundColor Green
                Write-Host "Edit is committed and ready in Google Play Console (check Publishing Overview / Track '$Track' if Play Console requires a manual 'Send for review' click)." -ForegroundColor Yellow
            } else {
                Write-Host "Play Store release committed! Edit ID: $($commitResp.id)" -ForegroundColor Green
            }
        } catch {
            $detail = Get-HttpErrorDetail -ExceptionRecord $_
            if ($editId) {
                try {
                    Invoke-RestMethod -Method Delete -Uri "$baseApiUrl/$editId" -Headers $authHeaders | Out-Null
                } catch {}
            }
            throw "Google Play Store upload failed: $detail"
        }
    }
}

Write-Host ""
Write-Host "Nightly publish pipeline finished successfully." -ForegroundColor Green
exit 0
