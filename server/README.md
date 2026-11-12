# 온라인 랭킹 서버

Java 17 + Spring Boot 3.5 + MySQL. 게임이 보낸 기록(시드 + 행동 기록)을 Godot 헤드리스로 다시 실행해 검증한 뒤 순위에 올린다.

## API

| 요청 | 내용 |
| --- | --- |
| `POST /runs` | 끝난 원정 기록 제출. 접수되면 `202`, 같은 기록을 다시 보내면 `409`, 잘못된 요청은 `400` |
| `GET /runs/{id}` | 제출한 기록의 상태: `PENDING`(검증 중) / `VERIFIED`(통과) / `REJECTED`(거부, `rejectReason`에 이유) |
| `GET /leaderboard?limit=20` | 검증을 통과한 기록의 순위 (limit 1~100) |

거부 이유: `result_mismatch`(주장한 결과와 다름), `replay_diverged`(실행할 수 없는 행동), `run_not_finished`(패배로 끝나지 않음), `game_version`(서버와 게임 버전이 다름) 등.
검증기 설정이 없거나 Godot 실행에 실패하면 기록은 `PENDING`으로 남고, 서버를 다시 켤 때 다시 검증한다.

## 환경별 설정 (프로필)

| 파일 | 프로필 | 쓰는 곳 |
| --- | --- | --- |
| `application.yml` | (항상) | 공통 설정, DB 접속 정보 |
| `application-windows.yml` | `windows` | 개발 PC. 포트 9090, 이 PC의 Godot·게임 경로가 기본값 |
| `application-linux.yml` | `linux` | Linux 서버. 포트 9090, DB는 `localhost`, Godot·게임은 `/opt/samgukji/...` |

프로필 파일의 값은 기본값이고, 같은 이름의 환경 변수가 있으면 환경 변수가 우선한다.

## IntelliJ에서 열기 (Windows)

가장 간단한 방법: `RankingServerApplication` 실행 구성의 **Active profiles**에 `windows`를 넣는다. 환경 변수는 필요 없다.
아래는 프로필 없이 환경 변수로 지정하는 방법이다.

1. IntelliJ에서 `server/pom.xml`을 프로젝트로 연다. Project SDK는 Java 17.
2. MySQL에 DB와 계정을 만든다 (한 번만):

   ```sql
   CREATE DATABASE samgukji_ranking CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER 'samgukji'@'localhost' IDENTIFIED BY '비밀번호';
   GRANT ALL PRIVILEGES ON samgukji_ranking.* TO 'samgukji'@'localhost';
   ```

   표는 서버가 처음 켜질 때 Flyway가 `db/migration`의 SQL로 만든다.
3. 실행 구성: `RankingServerApplication`의 Environment variables에 넣는다.

   | 변수 | 예 |
   | --- | --- |
   | `DB_URL` | `jdbc:mysql://localhost:3306/samgukji_ranking?serverTimezone=UTC&characterEncoding=UTF-8` (생략하면 이 값) |
   | `DB_USERNAME` | `samgukji` (생략하면 이 값) |
   | `DB_PASSWORD` | 위에서 정한 비밀번호 |
   | `GODOT_PATH` | `C:\Users\…\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_…\Godot_v4.7.2-stable_win64_console.exe` |
   | `GAME_PROJECT_PATH` | `D:\study\vibecoding\game` |
   | `PORT` | `8080` (생략하면 이 값) |

   비밀번호는 코드나 설정 파일에 쓰지 않는다.

### MySQL 없이 빨리 띄우기

테스트 소스의 `LocalDevServer`를 실행하면 메모리 DB(H2)로 뜬다. 서버를 끄면 데이터는 사라진다. 검증까지 하려면 `GODOT_PATH`, `GAME_PROJECT_PATH`만 넣으면 된다.

## Linux 서버에 올리기 (Ubuntu 24.04)

1. Windows에서 배포 묶음을 만든다 (게임 프로젝트 폴더에서):

   ```bash
   powershell -ExecutionPolicy Bypass -File server\deploy\package_linux.ps1
   ```

   결과: `build\linux\samgukji-ranking-linux.tar.gz` (서버 jar + 검증용 게임 파일 + 설치 스크립트 + 표본 기록)
2. 서버에 올려 설치한다:

   ```bash
   mkdir samgukji-deploy && tar -xzf samgukji-ranking-linux.tar.gz -C samgukji-deploy && cd samgukji-deploy && sudo bash install.sh
   ```

   설치 스크립트(`deploy/linux/install.sh`)가 Java 17, Linux용 Godot 4.7.2(체크섬 확인), 서비스 사용자, systemd 서비스를 준비하고,
   마지막에 **Windows에서 만든 표본 기록을 서버의 Godot로 검증**해 운영체제가 달라도 결과가 같은지 알려 준다.
3. 처음 설치했다면 `/etc/samgukji-ranking.env`에 DB 비밀번호를 넣고 서비스를 켠다:

   ```bash
   sudo nano /etc/samgukji-ranking.env
   sudo systemctl restart samgukji-ranking
   ```

4. 방화벽에서 9090 포트를 연다 (스크립트는 방화벽을 건드리지 않는다). 예: `sudo ufw allow 9090/tcp`

| 서버의 위치 | 내용 |
| --- | --- |
| `/opt/samgukji/ranking-server.jar` | API 서버 |
| `/opt/samgukji/game/` | 검증용 게임 파일 (플레이어의 게임과 같은 버전이어야 한다) |
| `/opt/samgukji/godot/godot` | Linux용 Godot |
| `/etc/samgukji-ranking.env` | 환경 변수 (DB 비밀번호 등, root만 읽기) |
| `samgukji-ranking` | systemd 서비스. 로그: `sudo journalctl -u samgukji-ranking -f` |

게임이나 서버를 고친 뒤에는 1~2를 다시 하면 된다. 환경 변수 파일은 덮어쓰지 않는다.

## 테스트

```bash
mvn test
```

- `RunApiTest`: 제출 → 검증 → 순위 흐름 (가짜 검증기, H2)
- `GodotRunVerifierTest`: Godot 출력 해석
- `GodotRunVerifierIntegrationTest`: 진짜 Godot로 표본 기록 검증. `GODOT_PATH`, `GAME_PROJECT_PATH`가 있을 때만 돈다.

표본 기록 `src/test/resources/sample_finished_run.json`은 게임 데이터나 로직이 바뀌면 다시 만든다:

```bash
godot --headless --path D:\study\vibecoding\game -s tests/tools/make_sample_run.gd -- D:\study\vibecoding\game\server\src\test\resources\sample_finished_run.json
```

## 게임 쪽

- 서버 주소: 게임의 `data/online.json`의 `api_base_url` (기본 `http://localhost:8080`). 서버를 옮기면 이 값을 바꾸고 다시 빌드한다.
- 검증 스크립트: 게임의 `verify/verify_run.gd` (배포 exe에는 들어가지 않는다).
- 서버의 게임 폴더(`GAME_PROJECT_PATH`)는 플레이어가 쓰는 게임과 같은 버전이어야 한다. `project.godot`의 `application/config/version`이 다르면 `game_version`으로 거부된다.
