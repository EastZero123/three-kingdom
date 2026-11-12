#!/usr/bin/env bash
# 삼국지 원정 로그라이트 — 온라인 랭킹 서버 설치·업데이트 (Ubuntu 24.04 기준)
# 사용: 배포 묶음을 푼 폴더에서   sudo bash install.sh
# 여러 번 실행해도 된다. 두 번째부터는 서버 jar와 게임 파일만 바꾸고 서비스를 다시 켠다.
#
# 하는 일
#   1. Java 17, curl, unzip 설치 (없을 때만)
#   2. 서비스 전용 사용자 samgukji 만들기
#   3. Linux용 Godot 내려받기 (공식 GitHub 릴리스, SHA-512 확인)
#   4. 게임 파일(검증용)을 /opt/samgukji/game 에 배치하고 Godot 가져오기 실행
#   5. 서버 jar 배치, 환경 변수 파일(/etc/samgukji-ranking.env) 준비, systemd 서비스 등록
#      운영 명령어 모음(COMMANDS.txt)을 /opt/samgukji 에 둔다
#   6. Windows에서 만든 표본 기록을 이 서버의 Godot로 검증 (운영체제가 달라도 결과가 같은지 확인)
# 방화벽(포트 열기)과 DB 비밀번호는 건드리지 않고 안내만 한다.

set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_RELEASE="${GODOT_VERSION}-stable"
PREFIX="/opt/samgukji"
APP_USER="samgukji"
SERVICE="samgukji-ranking"
ENV_FILE="/etc/${SERVICE}.env"
HERE="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\n== %s\n' "$1"; }
fail() { printf '실패: %s\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "sudo bash install.sh 로 실행하세요."
[ -f "${HERE}/ranking-server.jar" ] || fail "ranking-server.jar가 없습니다. 배포 묶음을 푼 폴더에서 실행하세요."

say "1/6 필요한 프로그램"
need_install=()
if ! command -v java >/dev/null 2>&1 || ! java -version 2>&1 | grep -Eq 'version "(1[7-9]|[2-9][0-9])'; then
    need_install+=(openjdk-17-jre-headless)
fi
command -v curl >/dev/null 2>&1 || need_install+=(curl)
command -v unzip >/dev/null 2>&1 || need_install+=(unzip)
if [ "${#need_install[@]}" -gt 0 ]; then
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${need_install[@]}"
fi
java -version 2>&1 | head -n 1

say "2/6 서비스 사용자"
if ! id "${APP_USER}" >/dev/null 2>&1; then
    useradd --system --home-dir "${PREFIX}" --shell /usr/sbin/nologin "${APP_USER}"
fi
mkdir -p "${PREFIX}"

say "3/6 Godot ${GODOT_RELEASE} (Linux)"
GODOT_DIR="${PREFIX}/godot"
GODOT_BIN="${GODOT_DIR}/Godot_v${GODOT_RELEASE}_linux.x86_64"
if [ ! -x "${GODOT_BIN}" ]; then
    mkdir -p "${GODOT_DIR}"
    tmp="$(mktemp -d)"
    zip_name="Godot_v${GODOT_RELEASE}_linux.x86_64.zip"
    base="https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}"
    curl -fsSL -o "${tmp}/${zip_name}" "${base}/${zip_name}"
    curl -fsSL -o "${tmp}/SHA512-SUMS.txt" "${base}/SHA512-SUMS.txt"
    (cd "${tmp}" && grep " ${zip_name}\$" SHA512-SUMS.txt | sha512sum -c -) || fail "Godot 파일의 체크섬이 공식 값과 다릅니다."
    unzip -q -o "${tmp}/${zip_name}" -d "${GODOT_DIR}"
    chmod +x "${GODOT_BIN}"
    rm -rf "${tmp}"
fi
ln -sf "${GODOT_BIN}" "${GODOT_DIR}/godot"
"${GODOT_DIR}/godot" --headless --version

say "4/6 게임 파일 (검증용)"
rm -rf "${PREFIX}/game.new"
cp -r "${HERE}/game" "${PREFIX}/game.new"
rm -rf "${PREFIX}/game"
mv "${PREFIX}/game.new" "${PREFIX}/game"
chown -R "${APP_USER}:${APP_USER}" "${PREFIX}"
# Godot가 스크립트 목록(.godot 폴더)을 만들게 한다.
sudo -u "${APP_USER}" HOME="${PREFIX}" "${GODOT_DIR}/godot" --headless --path "${PREFIX}/game" --import >/dev/null 2>&1 || true
grep -E '^config/version=' "${PREFIX}/game/project.godot"

say "5/6 서버 jar · 환경 변수 · 서비스"
install -o "${APP_USER}" -g "${APP_USER}" -m 0644 "${HERE}/ranking-server.jar" "${PREFIX}/ranking-server.jar"
first_env=0
if [ ! -f "${ENV_FILE}" ]; then
    install -o root -g root -m 0600 "${HERE}/${SERVICE}.env.example" "${ENV_FILE}"
    first_env=1
fi
install -o root -g root -m 0644 "${HERE}/${SERVICE}.service" "/etc/systemd/system/${SERVICE}.service"
# 운영 명령어 모음을 서비스 폴더에 둔다 (보기: less /opt/samgukji/COMMANDS.txt).
if [ -f "${HERE}/COMMANDS.txt" ]; then
    install -o root -g root -m 0644 "${HERE}/COMMANDS.txt" "${PREFIX}/COMMANDS.txt"
fi
systemctl daemon-reload
systemctl enable "${SERVICE}" >/dev/null

say "6/6 운영체제 간 재현 확인 (Windows에서 만든 표본 기록을 이 서버에서 검증)"
# 묶음을 푼 폴더(보통 홈 폴더)는 서비스 사용자가 읽지 못하므로, 표본을 서비스 폴더로 복사해서 검증한다.
sample="${PREFIX}/sample_verify_input.json"
install -o "${APP_USER}" -g "${APP_USER}" -m 0644 "${HERE}/sample_verify_input.json" "${sample}"
result_line="$(sudo -u "${APP_USER}" HOME="${PREFIX}" "${GODOT_DIR}/godot" --headless --path "${PREFIX}/game" \
    -s verify/verify_run.gd -- "${sample}" 2>/dev/null | grep '^VERIFY_RESULT ' | tail -n 1 || true)"
echo "${result_line:-결과 줄 없음}"
if echo "${result_line}" | grep -Eq '"ok": ?true'; then
    echo "→ 통과: Windows에서 만든 기록이 이 서버에서도 똑같이 재현됩니다."
elif echo "${result_line}" | grep -Eq 'result_mismatch|replay_diverged|run_not_finished'; then
    echo "→ 주의: 재현 결과가 Windows와 다릅니다. 온라인 기록이 모두 거부될 수 있으니 이 출력을 개발자에게 알려 주세요." >&2
else
    echo "→ 주의: 검증을 실행하지 못했습니다 (재현 여부와는 별개의 문제). 이 출력을 개발자에게 알려 주세요." >&2
fi

if [ "${first_env}" -eq 1 ] || grep -q 'CHANGE_ME' "${ENV_FILE}"; then
    say "남은 일"
    echo "1) ${ENV_FILE} 을 열어 DB_PASSWORD 등을 채우세요:  sudo nano ${ENV_FILE}"
    echo "2) 서비스 시작:  sudo systemctl restart ${SERVICE}"
else
    systemctl restart "${SERVICE}"
    sleep 3
    systemctl --no-pager --lines=5 status "${SERVICE}" || true
fi
port="$(grep -E '^PORT=' "${ENV_FILE}" | cut -d= -f2)"
echo
echo "게임이 접속하려면 방화벽에서 포트 ${port:-9090}/tcp 를 열어야 합니다 (예: sudo ufw allow ${port:-9090}/tcp)."
echo "확인:  curl http://localhost:${port:-9090}/leaderboard"
echo "명령어 모음:  less ${PREFIX}/COMMANDS.txt"
