# Linux 서버 배포 묶음을 만든다 (Windows에서 실행).
# 실행: 게임 프로젝트 폴더에서  powershell -ExecutionPolicy Bypass -File server\deploy\package_linux.ps1
# 결과: build\linux\samgukji-ranking-linux.tar.gz
#   ranking-server.jar               API 서버
#   game\                            검증용 게임 파일 (project.godot, core, data, verify, autoload, ui, scenes)
#   sample_verify_input.json         운영체제 간 재현 확인용 표본 기록 (이 PC에서 만든 것)
#   install.sh, samgukji-ranking.service, samgukji-ranking.env.example
# 서버에서:  tar -xzf samgukji-ranking-linux.tar.gz -C samgukji-deploy && cd samgukji-deploy && sudo bash install.sh
#
# Windows PowerShell 5.1과 7 모두에서 동작한다. 이 파일은 BOM이 있는 UTF-8로 저장한다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

function Fail([string]$message) {
    Write-Host "실패: $message" -ForegroundColor Red
    exit 1
}

$server = Split-Path $PSScriptRoot -Parent
$project = Split-Path $server -Parent
$out = Join-Path $project 'build\linux'
$stage = Join-Path $out 'stage'
$archive = Join-Path $out 'samgukji-ranking-linux.tar.gz'

# JDK 17 찾기 (JAVA_HOME이 17이 아니면 흔한 설치 위치에서 찾는다).
$jdk = $env:JAVA_HOME
if (-not $jdk -or -not (Test-Path (Join-Path $jdk 'bin\javac.exe')) -or -not ((& (Join-Path $jdk 'bin\java.exe') -version 2>&1 | Out-String) -match 'version "17')) {
    $jdk = @(Get-ChildItem 'C:\Program Files\Java\jdk-17*', "$env:USERPROFILE\.jdks\*17*", 'C:\Program Files\Eclipse Adoptium\jdk-17*', 'C:\Program Files\Amazon Corretto\jdk17*' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object FullName)[0]
}
if (-not $jdk) { Fail "JDK 17을 찾지 못했습니다. JAVA_HOME을 JDK 17로 지정하세요." }
$env:JAVA_HOME = $jdk

Write-Host "1/4 서버 jar 만들기 (JDK: $jdk)"
Push-Location $server
$mvnLog = & mvn -q -B package 2>&1 | ForEach-Object { "$_" }
$mvnCode = $LASTEXITCODE
Pop-Location
if ($mvnCode -ne 0) {
    $mvnLog | Select-Object -Last 30 | ForEach-Object { Write-Host "  $_" }
    Fail "서버 빌드(테스트 포함)에 실패했습니다."
}
$jar = Get-ChildItem (Join-Path $server 'target') -Filter 'ranking-server-*.jar' | Where-Object { $_.Name -notmatch 'plain' } | Select-Object -First 1
if ($null -eq $jar) { Fail "서버 jar를 찾지 못했습니다." }

Write-Host "2/4 묶음 폴더 준비"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force (Join-Path $stage 'game') | Out-Null
Copy-Item $jar.FullName (Join-Path $stage 'ranking-server.jar')
foreach ($name in @('install.sh', 'samgukji-ranking.service', 'samgukji-ranking.env.example', 'COMMANDS.txt')) {
    # Linux에서 쓰는 파일이므로 줄바꿈을 LF로 맞춘다.
    $text = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "linux\$name"), [System.Text.Encoding]::UTF8) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText((Join-Path $stage $name), $text, (New-Object System.Text.UTF8Encoding($false)))
}

# 검증에 필요한 게임 파일만 넣는다 (테스트·빌드 결과·서버 코드·편집기 캐시는 뺀다).
Copy-Item (Join-Path $project 'project.godot') (Join-Path $stage 'game')
foreach ($dir in @('core', 'data', 'verify', 'autoload', 'ui', 'scenes')) {
    Copy-Item (Join-Path $project $dir) (Join-Path $stage "game\$dir") -Recurse
}
$version = (Select-String -Path (Join-Path $project 'project.godot') -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value

Write-Host "3/4 운영체제 간 재현 확인용 표본 기록"
# 서버 테스트용 표본(POST /runs 형식)을 검증 스크립트 입력 형식으로 바꾼다.
$sample = Get-Content (Join-Path $server 'src\test\resources\sample_finished_run.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($sample.gameVersion -ne $version) {
    Fail "표본 기록의 게임 버전($($sample.gameVersion))이 현재 버전($version)과 다릅니다. tests/tools/make_sample_run.gd로 다시 만드세요."
}
$verifyInput = [ordered]@{ seed = $sample.seed; actions = $sample.actions; years = $sample.years; year = $sample.year; round = $sample.round; game_version = $sample.gameVersion }
[System.IO.File]::WriteAllText((Join-Path $stage 'sample_verify_input.json'), ($verifyInput | ConvertTo-Json -Depth 10 -Compress), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "4/4 tar.gz 묶기"
if (Test-Path $archive) { Remove-Item -Force $archive }
& tar.exe -czf $archive -C $stage .
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $archive)) { Fail "압축에 실패했습니다." }

$mb = [math]::Round((Get-Item $archive).Length / 1MB, 1)
Write-Host "완료 (게임 버전 $version)" -ForegroundColor Green
Write-Host "  $archive ($mb MB)"
Write-Host "  서버에 올린 뒤:  mkdir samgukji-deploy && tar -xzf samgukji-ranking-linux.tar.gz -C samgukji-deploy && cd samgukji-deploy && sudo bash install.sh"
exit 0
