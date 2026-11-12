class_name AbilityBuild
extends RefCounted
## 장수의 능력치(0~100)와 레벨업 포인트 배분을 다루는 계산 모음.
##
## 두 층으로 나뉜다.
##   능력치: 장수 카드에 보이는 0~100 값 5종. 티어 기본 능력치 + 플레이어가 배분한 포인트.
##   전투 수치: 전투 계산에 실제로 쓰는 값. 능력치에서 변환한다 (balance.json의 ability 항목).
##     최대 체력 = 체력 능력치 × ability.hp_per_point + 넘친 포인트 × ability.overflow_hp_per_point
##     공격·방어·속도·지략 = 능력치 그대로
##
## 레벨이 1 오를 때마다 level.points_per_level 포인트를 받는다 (레벨 1은 0포인트).
## 능력치는 ability.max(100)를 넘을 수 없다. 다섯 능력치가 모두 100이라 더 넣을 곳이 없으면
## 그 포인트는 "넘친 포인트"가 되어 체력을 조금씩 올린다.
##
## static func: 객체를 만들지 않고 AbilityBuild.함수() 형태로 바로 부르는 함수.

## 화면에 쓰는 능력치 이름.
const LABELS: Dictionary[String, String] = {"hp": "체력", "attack": "공격", "defense": "방어", "speed": "속도", "intellect": "지략"}


## 레벨까지 받은 포인트 총량.
static func earned_points(balance: Balance, level: int) -> int:
	return maxi(0, level - 1) * balance.get_int("level.points_per_level")


## 기본 능력치 + 배분 포인트 = 현재 능력치.
static func abilities(base: Stats, invested: Dictionary) -> Stats:
	var result: Stats = Stats.new()
	for key: String in Stats.KEYS:
		result.set_value(key, base.get_value(key) + int(invested.get(key, 0)))
	return result


## 능력치를 전투 수치로 바꾼다.
static func combat_stats(balance: Balance, ability: Stats, overflow_points: int) -> Stats:
	var result: Stats = Stats.new()
	for key: String in Stats.KEYS:
		result.set_value(key, ability.get_value(key))
	result.hp = ability.hp * balance.get_int("ability.hp_per_point") + overflow_points * balance.get_int("ability.overflow_hp_per_point")
	return result


## 다섯 능력치가 모두 최대인지. 이때만 포인트가 넘친 포인트(체력)로 간다.
static func all_maxed(balance: Balance, base: Stats, invested: Dictionary) -> bool:
	var cap: int = balance.get_int("ability.max")
	for key: String in Stats.KEYS:
		if base.get_value(key) + int(invested.get(key, 0)) < cap:
			return false
	return true


## 한 능력치에 포인트를 amount만큼 넣을 수 있는지 미리 계산한다.
## 돌려주는 값: {"ok": 가능 여부, "to_stat": 능력치로 들어갈 양, "to_overflow": 넘친 포인트로 갈 양}
## 그 능력치에 빈자리가 남아 있는 만큼은 능력치로, 다섯 능력치가 다 차면 나머지는 넘친 포인트로 간다.
## 다른 능력치에 아직 자리가 있는데 이 능력치만 꽉 찼다면 넣을 수 없다 (다른 능력치를 고르라는 뜻).
static func plan_invest(balance: Balance, base: Stats, invested: Dictionary, stat: String, amount: int) -> Dictionary:
	if amount <= 0 or not Stats.is_valid_key(stat):
		return {"ok": false, "to_stat": 0, "to_overflow": 0}
	var cap: int = balance.get_int("ability.max")
	var room: int = cap - (base.get_value(stat) + int(invested.get(stat, 0)))
	var to_stat: int = clampi(room, 0, amount)
	var rest: int = amount - to_stat
	if rest == 0:
		return {"ok": true, "to_stat": to_stat, "to_overflow": 0}
	# 이 능력치를 다 채운 뒤 다섯 능력치가 모두 최대가 되는 경우에만 나머지를 넘친 포인트로 받는다.
	var after: Dictionary = invested.duplicate()
	after[stat] = int(after.get(stat, 0)) + to_stat
	if all_maxed(balance, base, after):
		return {"ok": true, "to_stat": to_stat, "to_overflow": rest}
	return {"ok": false, "to_stat": 0, "to_overflow": 0}


## 승급(티어 변경)으로 기본 능력치가 바뀌었을 때, 배분한 포인트 총량을 100% 유지한 채 다시 맞춘다.
##   1. 능력치별 배분량은 그대로 둔다.
##   2. 새 기본 능력치 + 배분량이 최대를 넘는 능력치는 넘는 만큼 떼어 낸다.
##   3. 떼어 낸 포인트는 자리가 남은 능력치에 넣는다. 플레이어가 많이 투자했던 능력치부터 채운다
##      (같으면 체력·공격·방어·속도·지략 순서). 투자 성향을 최대한 그대로 살리기 위해서다.
##   4. 그래도 남으면(다섯 능력치가 모두 최대) 넘친 포인트가 되어 체력으로 간다.
## 돌려주는 값: {"invested": 새 배분, "overflow": 새 넘친 포인트}
static func refit(balance: Balance, base: Stats, invested: Dictionary, overflow_points: int) -> Dictionary:
	var cap: int = balance.get_int("ability.max")
	var result: Dictionary = {}
	var spare: int = 0
	for key: String in Stats.KEYS:
		var amount: int = int(invested.get(key, 0))
		var room: int = maxi(0, cap - base.get_value(key))
		var kept: int = mini(amount, room)
		result[key] = kept
		spare += amount - kept

	var order: Array[String] = Stats.KEYS.duplicate()
	# sort_custom: 비교 함수로 정렬한다. a가 b보다 앞이면 true. 같은 값이면 원래 순서를 지키도록 KEYS 위치를 비교한다.
	order.sort_custom(func(a: String, b: String) -> bool:
		var amount_a: int = int(invested.get(a, 0))
		var amount_b: int = int(invested.get(b, 0))
		if amount_a != amount_b:
			return amount_a > amount_b
		return Stats.KEYS.find(a) < Stats.KEYS.find(b))
	for key: String in order:
		if spare <= 0:
			break
		var room_left: int = maxi(0, cap - base.get_value(key) - int(result[key]))
		var moved: int = mini(room_left, spare)
		result[key] = int(result[key]) + moved
		spare -= moved
	return {"invested": result, "overflow": overflow_points + spare}


## 적(컴퓨터)의 포인트 배분: 티어 정의의 성향(tendency) 비율대로 자동으로 나눈다.
## 같은 입력이면 항상 같은 결과가 나온다 (난수 없음 → 서버 검증과 재현에 안전).
## 나누는 방법: 각 능력치 몫 = 총 포인트 × 성향 / 성향 합. 소수점 아래는 버리고,
## 버려서 남은 포인트는 소수 부분이 큰 능력치부터 1씩 준다 (최대 나머지 방식).
## 최대를 넘는 몫은 refit과 같은 방법으로 다른 능력치나 체력으로 옮긴다.
## points_per_level을 주면 레벨당 그만큼만 나눈다 (적은 ability.enemy_points_per_level을 쓴다, 소수 가능 → 합계를 내림).
## 0 이하면 플레이어와 같은 양.
static func auto_invest(balance: Balance, tier_def: GeneralTierDef, level: int, points_per_level: float = 0.0) -> Dictionary:
	var total: int = earned_points(balance, level) if points_per_level <= 0.0 else floori(float(maxi(0, level - 1)) * points_per_level)
	var weight_sum: float = 0.0
	for key: String in Stats.KEYS:
		weight_sum += float(tier_def.tendency.get(key, 0.0))
	var invested: Dictionary = {}
	if total == 0 or weight_sum <= 0.0:
		for key: String in Stats.KEYS:
			invested[key] = 0
		return refit(balance, tier_def.base_stats, invested, 0)

	var given: int = 0
	var fractions: Array[Dictionary] = []
	for key: String in Stats.KEYS:
		var exact: float = float(total) * float(tier_def.tendency.get(key, 0.0)) / weight_sum
		var whole: int = floori(exact)
		invested[key] = whole
		given += whole
		fractions.append({"key": key, "fraction": exact - float(whole), "index": Stats.KEYS.find(key)})
	fractions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["fraction"]), float(b["fraction"])):
			return float(a["fraction"]) > float(b["fraction"])
		return int(a["index"]) < int(b["index"]))
	var i: int = 0
	while given < total:
		var key: String = fractions[i % fractions.size()]["key"]
		invested[key] = int(invested[key]) + 1
		given += 1
		i += 1
	return refit(balance, tier_def.base_stats, invested, 0)


## 적의 레벨당 포인트: 처음에는 플레이어(5)보다 적고, 해가 지날수록 늘어난다 (초반은 넉넉하게, 후반은 몰아붙이게).
##   적 포인트 = ability.enemy_points_per_level + 지난 연수 × ability.enemy_points_per_year
static func enemy_points_per_level(balance: Balance, years_passed: int) -> float:
	return balance.get_float("ability.enemy_points_per_level") + float(maxi(0, years_passed)) * balance.get_float("ability.enemy_points_per_year")


## 적(컴퓨터 장수)의 전투 수치: 성향대로 레벨당 points_per_level 포인트를 자동 배분한다.
## points_per_level을 비우면(0) 첫해 기준값을 쓴다.
static func enemy_combat_stats(balance: Balance, tier_def: GeneralTierDef, level: int, points_per_level: float = 0.0) -> Stats:
	var points: float = points_per_level if points_per_level > 0.0 else enemy_points_per_level(balance, 0)
	var build: Dictionary = auto_invest(balance, tier_def, level, points)
	return combat_stats(balance, abilities(tier_def.base_stats, build["invested"]), int(build["overflow"]))


## "체력 14 · 공격 11 · …" 형태의 한 줄 요약.
static func describe(ability: Stats) -> String:
	var parts: Array[String] = []
	for key: String in Stats.KEYS:
		parts.append("%s %d" % [LABELS[key], ability.get_value(key)])
	return " · ".join(parts)
