# 게임 데이터 (JSON)

수치와 내용은 모두 여기서 고친다. 형식이 틀리면 `GameDatabase`가 한국어 오류 메시지로 알려 준다.
고친 뒤에는 테스트를 돌려 확인한다: `godot --headless --path . -s addons/gut/gut_cmdln.gd`

## balance.json — 밸런스 수치

기획서의 확정값과 미확정 항목의 기본값. 필수 키 목록은 `core/data/balance.gd`의 `REQUIRED`.

## skills.json — 스킬

| 키 | 내용 |
| --- | --- |
| `id` / `name` / `description` | 고유 id(영문), 표시 이름, 설명 |
| `target` | `enemy_single`, `enemy_front_row`, `enemy_back_row`, `enemy_all`, `ally_single`, `ally_all`, `self` |
| `scaling_stat` | 피해 계산에 쓰는 스탯: `attack` 또는 `intellect` |
| `power` | 피해 배율. 0이면 부가 효과만 |
| `cooldown` | 재사용 대기 턴 (1 이상) |
| `effects` | 부가 효과 목록. `{"kind": "stat_mod", "stat": 스탯, "percent": 변화량%, "duration": 턴}` |

전투 중 회복은 금지라서 회복 효과는 넣을 수 없다.

## 장수를 많이 늘릴 때

1. `tests/tools/general_roster_src.json`에 장수를 적는다: id, 이름, 세력, 역할, 활동 연도(`span`), 스탯 배율(`grade`), 티어별 [칭호, 시기 설명].
2. `godot --headless --path . -s tests/tools/expand_generals.gd` 를 실행한다.
   - 스탯·성장률은 역할 기준 × 티어 배율 × grade로 계산되고, 스킬·보유효과는 역할과 티어로 정해진다.
   - 시대별 적 후보에는 활동 연도가 겹치는 장수가 들어간다. 초반 시대는 티어 상한이 있다 (황건적의 난 D, 잔당 C, 군웅할거 B, 관도~한중 A).
   - 이미 있는 장수는 건드리지 않으므로, 개성을 살리고 싶은 장수는 실행 뒤 `generals.json`에서 직접 고친다.

## generals.json — 장수

| 키 | 내용 |
| --- | --- |
| `id` / `name` / `faction` | 고유 id(영문), 표시 이름, 세력 |
| `role` | `warrior`, `defender`, `strategist`, `healer`, `support`. `healer`만 전투 후 치유 |
| `tiers` | 티어 이름(`F`~`S`) → 티어 정의. 가진 티어는 연속이어야 한다 |

티어 정의:

| 키 | 내용 |
| --- | --- |
| `title` / `era` | 그 시기의 칭호와 설명 |
| `base_stats` | 레벨 1 스탯: `hp`, `attack`, `defense`, `speed`, `intellect` |
| `growth` | 레벨당 증가량 (소수 가능). 스탯 = 기본 + 내림(성장 × (레벨 - 1)) |
| `skill_ids` | 쓰는 스킬 id 목록 (1개 이상) |
| `reserve_effect` | 보유효과. 아래 참조 |

보유효과:

| 키 | 내용 |
| --- | --- |
| `mode` | `passive`(상시) 또는 `conditional`(조건부, `condition` 필수) |
| `condition` | `{"kind": "late_game"}` 또는 `{"kind": "allies_alive_at_most" / "enemies_alive_at_most" / "battle_turn_at_least", "value": 숫자}` |
| `effect` | `{"kind": "stat_percent", "stat": 스탯, "value": %}` 또는 `{"kind": "reserve_slot_bonus", "value": 칸 수}` |

## enemies.json — 적 편성

| 키 | 내용 |
| --- | --- |
| `level` | 기준 적 레벨 = `base` + 지난 연수 × `per_year` + (라운드 - 1) × `per_round` (내림) |
| `expedition_types` | 토벌 종류(난이도). 적 인원 범위, 레벨 보정 `level_offset`, 적 스탯 배율 `enemy_stat_multiplier`, 티어 가중치 `tier_weight_per_step`(선택, 기본 1), 경험치 배율, 뽑힐 가중치 `weight` |
| `eras` | 시대. `year_from`~`year_to` 동안 `pool`의 장수·티어가 `weight` 가중치로 등장한다 |

시대는 시작 연도부터 빈 해 없이 이어져야 하고, 시대마다 후보 장수가 적 최대 인원 이상 있어야 한다.

특별 토벌(`kind`가 `imperial_requisition` 또는 `bounty`)은 선택 항목을 더 가진다.

| 키 | 내용 |
| --- | --- |
| `from_year` | 이 연도부터 등장 |
| `chest_pool` | 승리 보상 첫 선택지로 나올 상자 후보 `[{"chest_id", "weight"}]` (특별 토벌은 필수) |
| `issuers` | 이름 앞에 붙는 세력 후보. 예: `["위", "촉", "오"]` → "위 현상금 토벌" |

매 라운드 `balance.json`의 `run.special_expedition_chance` 확률로 특별 토벌 하나가 선택지 하나를 대신한다.

## chests.json — 보물상자

| 키 | 내용 |
| --- | --- |
| `tier_offset_weights` | 카드 티어 가중치. 순번 0 = 그 장수의 가장 낮은 티어, 1 = 한 단계 위, … |
| `year_end_chest` | 해 넘김 때 자동으로 여는 상자 id (`single`은 불가) |
| `chests` | 상자 목록. `scope`: `roster`(전체 로스터) / `active`(출전 장수) / `single`(고른 장수 1명), `card_count`: 장수 |

## run.json — 런 시작 설정

`starting_roster`: 시작 로스터 6명(`general_id`, `tier`, `level`). 순서가 자리이며 앞의 3명이 전열이다.

## 보유효과의 late_game

`late_game`의 기준 인원은 `balance.json`의 `reserve_effect.late_game_allies_alive_at_most`를 따른다.
