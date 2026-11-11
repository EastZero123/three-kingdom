# Windows 배포 묶음을 만든다.
# 실행: 프로젝트 폴더에서  powershell -ExecutionPolicy Bypass -File build_windows.ps1
#       버전 지정:          powershell -ExecutionPolicy Bypass -File build_windows.ps1 -Version 0.2.0
#       exe 다시 만들기:    powershell -ExecutionPolicy Bypass -File build_windows.ps1 -RebuildExe
# 결과:
#   build\dist\                        배포 폴더 (samgukji.exe + samgukji.pck + README.txt + licenses\)
#   build\samgukji-<버전>-windows.zip  배포용 압축 파일 (남에게는 이것을 준다)
#
# 순서: 1) 테스트 → 실패하면 멈춤  2) 리소스 가져오기  3) 실행 파일(exe) 준비  4) 게임 데이터(pck) 내보내기
#       5) 라이선스·안내문  6) zip
#
# exe와 pck를 나눈 이유
#   exe를 만들려면 내보내기 템플릿(약 100MB exe)을 읽고 새 exe를 써야 해서 느리고, 파일 문제로 실패하기 쉽다.
#   그래서 exe는 처음 한 번(또는 Godot 버전·아이콘·내보내기 설정이 바뀌었을 때)만 만들고 재사용한다.
#   평소 빌드는 게임 코드와 데이터가 든 samgukji.pck만 새로 만들며, 이때는 템플릿이 필요 없다.
#   Godot는 실행할 때 exe 옆의 같은 이름 .pck를 자동으로 읽는다.
#   템플릿이 %APPDATA%에 없으면 스크립트가 직접 준비한다 (Ensure-ExportTemplates 참고).
#
# Windows PowerShell 5.1(Rider 기본)과 PowerShell 7 모두에서 동작하도록 작성했다.
#   - 이 파일은 BOM이 있는 UTF-8로 저장한다 (5.1이 한글을 바르게 읽도록).
#   - Godot는 진행 메시지와 테스트가 일부러 내는 오류를 표준 오류로 출력한다.
#     5.1은 이것을 오류로 취급하므로 ErrorActionPreference를 Stop으로 두지 않고, 종료 코드로 성공 여부를 판단한다.

param(
    [string]$Version = "0.1.0",
    [switch]$RebuildExe
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

function Fail([string]$message) {
    Write-Host "실패: $message" -ForegroundColor Red
    exit 1
}

## Godot를 실행하고 출력 줄과 종료 코드를 돌려준다. 표준 오류도 일반 글자로 받는다.
function Invoke-Godot([string[]]$arguments) {
    $lines = & $script:godot @arguments 2>&1 | ForEach-Object { "$_" }
    return @{ Lines = $lines; Code = $LASTEXITCODE }
}

## 같은 작업을 최대 attempts번, 점점 길게 기다리며 다시 시도한다. 성공하면 true.
function Invoke-WithRetry([string]$label, [int]$attempts, [scriptblock]$action) {
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $result = & $action
        if ($result.Ok) { return $true }
        if ($attempt -lt $attempts) {
            $wait = 3 * $attempt
            Write-Host "  $label 실패 ($attempt/$attempts), ${wait}초 뒤 다시 시도: $($result.Reason)" -ForegroundColor Yellow
            Start-Sleep -Seconds $wait
        } else {
            Write-Host "  $label 실패 ($attempt/$attempts): $($result.Reason)" -ForegroundColor Yellow
        }
    }
    return $false
}

function First-Error([string[]]$lines) {
    return ($lines | Where-Object { $_ -match '^ERROR|템플릿|열 수 없습니다' } | Select-Object -First 1)
}

## 내보내기 템플릿(exe를 만드는 바탕 파일)이 %APPDATA%\Godot\export_templates\<버전>에 있는지 확인하고, 없으면 준비한다.
##   1) 패키지 앱(예: Claude 데스크톱 앱)이 설치해 그 앱 전용 폴더로 옮겨진 템플릿이 있으면 거기서 복사한다.
##      패키지 앱이 AppData\Roaming에 쓴 파일은 %LOCALAPPDATA%\Packages\<앱>\LocalCache\Roaming 아래로 옮겨져
##      다른 프로그램(Rider, 일반 터미널)에는 보이지 않는다.
##   2) 어디에도 없으면 공식 GitHub 릴리스에서 받아 SHA-512를 확인하고 Windows용 파일만 푼다 (약 1.2GB 다운로드).
function Ensure-ExportTemplates([string]$templateVersion) {
    $needed = @('windows_release_x86_64.exe', 'windows_debug_x86_64.exe', 'version.txt')
    $target = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
    $missing = $needed | Where-Object { -not (Test-Path (Join-Path $target $_)) }
    if (-not $missing) { return $true }

    Write-Host "  내보내기 템플릿이 없어 준비합니다: $target"
    New-Item -ItemType Directory -Force $target | Out-Null

    $sources = Get-ChildItem "$env:LOCALAPPDATA\Packages\*\LocalCache\Roaming\Godot\export_templates\$templateVersion" -Directory -ErrorAction SilentlyContinue
    foreach ($source in $sources) {
        $complete = -not ($needed | Where-Object { -not (Test-Path (Join-Path $source.FullName $_)) })
        if (-not $complete) { continue }
        Write-Host "  다른 앱 전용 폴더에서 복사: $($source.FullName)"
        $copied = Invoke-WithRetry "템플릿 복사" 5 {
            try {
                foreach ($name in $needed) { Copy-Item (Join-Path $source.FullName $name) (Join-Path $target $name) -Force -ErrorAction Stop }
                @{ Ok = $true; Reason = "" }
            } catch {
                @{ Ok = $false; Reason = $_.Exception.Message }
            }
        }
        if ($copied) { return $true }
    }

    # 공식 릴리스에서 받기
    $release = $templateVersion -replace '\.stable$', '-stable'  # 4.7.2.stable → 4.7.2-stable
    $base = "https://github.com/godotengine/godot/releases/download/$release"
    $tpzName = "Godot_v${release}_export_templates.tpz"
    $download = Join-Path $env:TEMP "godot_templates_$release"
    New-Item -ItemType Directory -Force $download | Out-Null
    $tpz = Join-Path $download $tpzName
    Write-Host "  공식 GitHub 릴리스에서 받습니다 (약 1.2GB): $base/$tpzName"
    & curl.exe -sSL -o (Join-Path $download 'SHA512-SUMS.txt') "$base/SHA512-SUMS.txt"
    & curl.exe -sSL -o $tpz "$base/$tpzName"
    $expected = (Get-Content (Join-Path $download 'SHA512-SUMS.txt') | Where-Object { $_ -match [regex]::Escape($tpzName) + '$' } | Select-Object -First 1) -replace '\s.*$', ''
    $actual = if (Test-Path $tpz) { (Get-FileHash $tpz -Algorithm SHA512).Hash.ToLower() } else { "" }
    if ([string]::IsNullOrEmpty($expected) -or $actual -ne $expected.ToLower()) {
        Remove-Item -Recurse -Force $download -ErrorAction SilentlyContinue
        Write-Host "  받은 파일의 체크섬이 공식 값과 다릅니다." -ForegroundColor Red
        return $false
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($tpz)
    try {
        foreach ($name in $needed) {
            $entry = $archive.GetEntry("templates/$name")
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $target $name), $true)
        }
    } finally {
        $archive.Dispose()
    }
    Remove-Item -Recurse -Force $download -ErrorAction SilentlyContinue
    return $true
}

$project = $PSScriptRoot
$godotFile = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v*_win64_console.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $godotFile) {
    Fail "Godot 실행 파일을 찾지 못했습니다. winget으로 GodotEngine.GodotEngine을 설치하세요."
}
$script:godot = $godotFile.FullName

$build = Join-Path $project 'build'
$dist = Join-Path $build 'dist'
$stage = Join-Path $build 'exe_stage'
$exe = Join-Path $dist 'samgukji.exe'
$pck = Join-Path $dist 'samgukji.pck'
$marker = Join-Path $dist 'runtime.txt'
$zip = Join-Path $build "samgukji-$Version-windows.zip"

Write-Host "1/6 테스트 실행"
$test = Invoke-Godot @('--headless', '--path', $project, '-s', 'addons/gut/gut_cmdln.gd')
$test.Lines | Select-String -Pattern 'Passing Tests|Failing Tests|All tests passed' | ForEach-Object { Write-Host "  $_" }
if ($test.Code -ne 0) {
    $test.Lines | Select-String -Pattern '\[Failed\]' -Context 0, 1 | ForEach-Object { Write-Host "  $_" }
    Fail "테스트가 실패해 빌드를 멈춥니다."
}

Write-Host "2/6 리소스 가져오기"
$null = Invoke-Godot @('--headless', '--path', $project, '--import')
New-Item -ItemType Directory -Force $dist | Out-Null
# Godot 편집기가 빌드 결과물을 리소스로 읽지 않도록 표시 파일을 둔다 (build/는 .gitignore 대상이라 여기서 만든다).
$gdignore = Join-Path $build '.gdignore'
if (-not (Test-Path $gdignore)) { New-Item -ItemType File $gdignore | Out-Null }

Write-Host "3/6 실행 파일(exe) 준비"
# exe를 다시 만들어야 하는 조건: Godot 버전, 아이콘, 내보내기 설정 중 하나라도 바뀌었을 때.
$godotVersion = ((Invoke-Godot @('--version')).Lines | Select-Object -Last 1).Trim()
$iconHash = (Get-FileHash (Join-Path $project 'ui\icon.ico') -Algorithm SHA256).Hash.Substring(0, 12)
$presetHash = (Get-FileHash (Join-Path $project 'export_presets.cfg') -Algorithm SHA256).Hash.Substring(0, 12)
$wanted = "godot=$godotVersion icon=$iconHash preset=$presetHash"
$current = if (Test-Path $marker) { (Get-Content $marker -Raw -Encoding UTF8).Trim() } else { "" }

if ($RebuildExe -or -not (Test-Path $exe) -or ($current -ne $wanted -and $current -ne "$wanted fallback")) {
    Write-Host "  exe를 새로 만듭니다 (처음이거나 Godot 버전·아이콘·설정이 바뀜)"
    $templateVersion = $godotVersion -replace '\.official.*$', ''
    if (-not (Ensure-ExportTemplates $templateVersion)) {
        Fail "내보내기 템플릿을 준비하지 못했습니다."
    }
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Force $stage | Out-Null
    $stageExe = Join-Path $stage 'samgukji.exe'
    # 1차: Godot 내보내기로 아이콘·버전 정보가 들어간 exe를 만든다.
    #      큰 exe를 쓰는 중 파일이 잠깐 잠기면(백신 검사 등) 실패할 수 있어 몇 번 다시 시도한다.
    $made = Invoke-WithRetry "exe 만들기" 5 {
        $r = Invoke-Godot @('--headless', '--path', $project, '--export-release', 'Windows Desktop', $stageExe)
        @{ Ok = ($r.Code -eq 0 -and (Test-Path $stageExe)); Reason = (First-Error $r.Lines) }
    }
    if ($made) {
        if (Test-Path $exe) { Remove-Item -Force $exe }
        Move-Item $stageExe $exe
        Set-Content $marker $wanted -Encoding UTF8
        Write-Host "  아이콘·버전 정보가 들어간 exe를 만들었습니다"
    } else {
        # 2차: 기본 템플릿 exe를 그대로 복사한다. 게임은 정상이고, 탐색기의 exe 아이콘만 기본 Godot 아이콘이 된다.
        $template = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion\windows_release_x86_64.exe"
        $copied = Invoke-WithRetry "기본 exe 복사" 5 {
            try {
                Copy-Item $template $exe -Force -ErrorAction Stop
                @{ Ok = $true; Reason = "" }
            } catch {
                @{ Ok = $false; Reason = $_.Exception.Message }
            }
        }
        if (-not $copied) {
            Fail "exe를 준비하지 못했습니다. 잠시 뒤 다시 실행하거나 -RebuildExe 로 다시 시도하세요."
        }
        Set-Content $marker "$wanted fallback" -Encoding UTF8
        Write-Host "  기본 템플릿 exe를 사용합니다 (exe 아이콘은 기본값). 나중에 -RebuildExe 로 다시 만들 수 있습니다." -ForegroundColor Yellow
    }
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
} else {
    Write-Host "  기존 exe를 재사용합니다 ($current)"
}

Write-Host "4/6 게임 데이터(pck) 내보내기"
if (Test-Path $pck) { Remove-Item -Force $pck }
$packed = Invoke-WithRetry "pck 내보내기" 3 {
    $r = Invoke-Godot @('--headless', '--path', $project, '--export-pack', 'Windows Desktop', $pck)
    @{ Ok = ($r.Code -eq 0 -and (Test-Path $pck)); Reason = (First-Error $r.Lines) }
}
if (-not $packed) {
    Fail "게임 데이터(pck)를 내보내지 못했습니다."
}

Write-Host "5/6 라이선스·안내문"
$licenseDir = Join-Path $dist 'licenses'
if (Test-Path $licenseDir) { Remove-Item -Recurse -Force $licenseDir }
$licenses = Invoke-Godot @('--headless', '--path', $project, '-s', 'tests/tools/write_licenses.gd', '--', $licenseDir)
if ($licenses.Code -ne 0) {
    $licenses.Lines | ForEach-Object { Write-Host "  $_" }
    Fail "라이선스 파일을 만들지 못했습니다."
}
$readme = (Get-Content (Join-Path $project 'tests\tools\dist_readme.txt') -Raw -Encoding UTF8).Replace('{VERSION}', $Version)
# 메모장에서 한글이 깨지지 않도록 BOM이 있는 UTF-8로 저장한다.
[System.IO.File]::WriteAllText((Join-Path $dist 'README.txt'), $readme, (New-Object System.Text.UTF8Encoding($true)))

Write-Host "6/6 zip 묶기"
if (Test-Path $zip) { Remove-Item -Force $zip }
# runtime.txt는 빌드용 표시 파일이라 배포본에서 뺀다.
$items = Get-ChildItem $dist | Where-Object { $_.Name -ne 'runtime.txt' } | ForEach-Object { $_.FullName }
Compress-Archive -Path $items -DestinationPath $zip

$exeMb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
$pckMb = [math]::Round((Get-Item $pck).Length / 1MB, 1)
$zipMb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "완료" -ForegroundColor Green
Write-Host "  exe: $exe ($exeMb MB)"
Write-Host "  pck: $pck ($pckMb MB)"
Write-Host "  zip: $zip ($zipMb MB)"
exit 0
