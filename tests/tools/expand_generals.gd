extends SceneTree
## 장수 확장 도구: tests/tools/general_roster_src.json의 장수들을 data/에 반영한다.
## 실행: godot --headless --path . -s tests/tools/expand_generals.gd
##
## 하는 일
##   1. 역할별 공용 스킬을 data/skills.json에 추가한다 (이미 있으면 그대로 둔다).
##   2. 원본표의 장수를 data/generals.json에 추가한다. 이미 있는 id는 건드리지 않는다.
##      스탯 = 역할 기준(C티어 Lv.1) × 티어 배율 × grade, 성장률 = 역할 기준 × 티어 성장 배율 × grade
##   3. data/enemies.json의 시대별 적 후보에 활동 연도(span)가 겹치는 장수를 넣는다.
##      시대마다 티어 상한이 있어 초반 시대에는 낮은 티어만 나온다.
## 결과 JSON이 기준 데이터다. 이 도구는 다음에 장수를 또 늘릴 때 다시 쓰면 된다.

const ROLE_BASE: Dictionary = {
	"warrior": {"hp": 150, "attack": 24, "defense": 17, "speed": 14, "intellect": 11},
	"defender": {"hp": 160, "attack": 18, "defense": 23, "speed": 12, "intellect": 14},
	"strategist": {"hp": 130, "attack": 12, "defense": 15, "speed": 14, "intellect": 26},
	"support": {"hp": 140, "attack": 15, "defense": 17, "speed": 16, "intellect": 20},
	"healer": {"hp": 125, "attack": 10, "defense": 15, "speed": 13, "intellect": 24},
}
const ROLE_GROWTH: Dictionary = {
	"warrior": {"hp": 4.6, "attack": 0.9, "defense": 0.6, "speed": 0.3, "intellect": 0.3},
	"defender": {"hp": 5.0, "attack": 0.6, "defense": 0.85, "speed": 0.2, "intellect": 0.4},
	"strategist": {"hp": 4.0, "attack": 0.3, "defense": 0.5, "speed": 0.3, "intellect": 1.0},
	"support": {"hp": 4.2, "attack": 0.4, "defense": 0.6, "speed": 0.4, "intellect": 0.7},
	"healer": {"hp": 4.0, "attack": 0.2, "defense": 0.5, "speed": 0.3, "intellect": 0.9},
}
const TIER_STAT: Dictionary = {"F": 0.47, "E": 0.6, "D": 0.78, "C": 1.0, "B": 1.25, "A": 1.55, "S": 1.9}
const TIER_GROWTH: Dictionary = {"F": 0.65, "E": 0.75, "D": 0.87, "C": 1.0, "B": 1.18, "A": 1.38, "S": 1.6}
const RESERVE_VALUE: Dictionary = {"F": 2, "E": 3, "D": 4, "C": 5, "B": 6, "A": 8, "S": 10}

## 역할별 보유효과: 올리는 스탯과 티어대별 이름 [낮음(F~D), 중간(C~B), 높음(A~S)].
const ROLE_RESERVE: Dictionary = {
	"warrior": {"stat": "attack", "names": ["투지", "무용", "만부부당"]},
	"defender": {"stat": "defense", "names": ["버팀목", "철벽", "금성탕지"]},
	"strategist": {"stat": "intellect", "names": ["꾀", "책략", "신산귀모"]},
	"support": {"stat": "speed", "names": ["독려", "기세", "천하의 명망"]},
	"healer": {"stat": "defense", "names": ["응급 처치", "의술", "신의의 손길"]},
}
const STAT_LABEL: Dictionary = {"hp": "체력", "attack": "공격", "defense": "방어", "speed": "속도", "intellect": "지략"}

## 역할별 스킬: [기본, 두 번째(둘 중 하나), 궁극]. 티어 F~D는 기본 1개, C~B는 기본+두 번째, A~S는 궁극+두 번째.
const ROLE_SKILLS: Dictionary = {
	"warrior": {"basic": "g_charge", "second": ["g_rampage", "g_flank"], "ultimate": "g_fury"},
	"defender": {"basic": "g_bash", "second": ["g_shield_wall", "g_shield_wall"], "ultimate": "g_hold_line"},
	"strategist": {"basic": "g_rockfall", "second": ["g_fire_attack", "g_confuse"], "ultimate": "g_grand_plan"},
	"support": {"basic": "g_encourage", "second": ["g_hasten", "g_hasten"], "ultimate": "g_command"},
	"healer": {"basic": "g_herb", "second": ["g_needle", "g_needle"], "ultimate": "g_vitality"},
}

const GENERIC_SKILLS: Array[Dictionary] = [
	{"id": "g_charge", "name": "돌격", "description": "적 하나에게 달려들어 벤다.", "target": "enemy_single", "scaling_stat": "attack", "power": 1.4, "cooldown": 2, "effects": []},
	{"id": "g_rampage", "name": "난전", "description": "적 전열에 뛰어들어 휘젓는다.", "target": "enemy_front_row", "scaling_stat": "attack", "power": 1.15, "cooldown": 3, "effects": []},
	{"id": "g_flank", "name": "측면 기습", "description": "돌아 들어가 적 후열을 친다.", "target": "enemy_back_row", "scaling_stat": "attack", "power": 1.15, "cooldown": 3, "effects": []},
	{"id": "g_fury", "name": "필살의 일격", "description": "적 하나에게 온 힘을 실은 일격.", "target": "enemy_single", "scaling_stat": "attack", "power": 2.0, "cooldown": 3, "effects": []},
	{"id": "g_bash", "name": "방패 치기", "description": "방패로 적 하나를 밀쳐 친다.", "target": "enemy_single", "scaling_stat": "attack", "power": 1.1, "cooldown": 2, "effects": []},
	{"id": "g_shield_wall", "name": "방진", "description": "방패를 세워 자신의 방어를 크게 올린다.", "target": "self", "scaling_stat": "attack", "power": 0, "cooldown": 3, "effects": [{"kind": "stat_mod", "stat": "defense", "percent": 30, "duration": 2}]},
	{"id": "g_hold_line", "name": "견수", "description": "진을 굳혀 아군 전체의 방어를 올린다.", "target": "ally_all", "scaling_stat": "intellect", "power": 0, "cooldown": 4, "effects": [{"kind": "stat_mod", "stat": "defense", "percent": 20, "duration": 3}]},
	{"id": "g_rockfall", "name": "낙석계", "description": "돌을 굴려 적 전열을 덮친다.", "target": "enemy_front_row", "scaling_stat": "intellect", "power": 1.2, "cooldown": 3, "effects": []},
	{"id": "g_fire_attack", "name": "화계", "description": "불을 놓아 적 전체를 태운다.", "target": "enemy_all", "scaling_stat": "intellect", "power": 0.9, "cooldown": 4, "effects": []},
	{"id": "g_confuse", "name": "혼란계", "description": "적진을 어지럽혀 적 전체의 속도를 떨어뜨린다.", "target": "enemy_all", "scaling_stat": "intellect", "power": 0, "cooldown": 4, "effects": [{"kind": "stat_mod", "stat": "speed", "percent": -20, "duration": 2}]},
	{"id": "g_grand_plan", "name": "대계", "description": "치밀한 계책으로 적 전체에 큰 피해를 준다.", "target": "enemy_all", "scaling_stat": "intellect", "power": 1.3, "cooldown": 4, "effects": []},
	{"id": "g_encourage", "name": "격려", "description": "아군 전체의 공격을 올린다.", "target": "ally_all", "scaling_stat": "intellect", "power": 0, "cooldown": 4, "effects": [{"kind": "stat_mod", "stat": "attack", "percent": 10, "duration": 2}]},
	{"id": "g_hasten", "name": "독려", "description": "아군 전체의 속도를 올린다.", "target": "ally_all", "scaling_stat": "intellect", "power": 0, "cooldown": 4, "effects": [{"kind": "stat_mod", "stat": "speed", "percent": 15, "duration": 2}]},
	{"id": "g_command", "name": "대호령", "description": "아군 전체의 공격과 방어를 올린다.", "target": "ally_all", "scaling_stat": "intellect", "power": 0, "cooldown": 4, "effects": [{"kind": "stat_mod", "stat": "attack", "percent": 15, "duration": 3}, {"kind": "stat_mod", "stat": "defense", "percent": 10, "duration": 3}]},
	{"id": "g_herb", "name": "약초 처방", "description": "아군 하나의 방어를 올린다. 체력은 회복하지 않는다.", "target": "ally_single", "scaling_stat": "intellect", "power": 0, "cooldown": 2, "effects": [{"kind": "stat_mod", "stat": "defense", "percent": 20, "duration": 3}]},
	{"id": "g_needle", "name": "침술", "description": "적 하나의 혈을 짚어 속도를 떨어뜨린다.", "target": "enemy_single", "scaling_stat": "intellect", "power": 0, "cooldown": 3, "effects": [{"kind": "stat_mod", "stat": "speed", "percent": -25, "duration": 2}]},
	{"id": "g_vitality", "name": "기혈 조화", "description": "아군 전체의 기혈을 다스려 방어를 올린다.", "target": "ally_all", "scaling_stat": "intellect", "power": 0, "cooldown": 4, "effects": [{"kind": "stat_mod", "stat": "defense", "percent": 12, "duration": 3}]},
]

## 시대별 티어 상한: 초반 시대에 너무 강한 적이 나오지 않게 한다.
const ERA_TIER_CAP: Dictionary = {
	"yellow_turban_rising": "D", "yellow_turban_remnants": "C", "warlords": "B",
	"three_way_struggle": "A", "three_kingdoms": "S",
}


func _initialize() -> void:
	var source: Dictionary = _read("res://tests/tools/general_roster_src.json")
	var skills_data: Dictionary = _read("res://data/skills.json")
	var generals_data: Dictionary = _read("res://data/generals.json")
	var enemies_data: Dictionary = _read("res://data/enemies.json")

	# 1. 공용 스킬
	var skills: Array = skills_data["skills"]
	var skill_ids: Dictionary = {}
	for skill: Dictionary in skills:
		skill_ids[skill["id"]] = true
	var added_skills: int = 0
	for skill: Dictionary in GENERIC_SKILLS:
		if not skill_ids.has(skill["id"]):
			skills.append(skill)
			added_skills += 1

	# 2. 장수
	var generals: Array = generals_data["generals"]
	var existing: Dictionary = {}
	for general: Dictionary in generals:
		existing[general["id"]] = true
	var added: Array[Dictionary] = []
	for entry: Dictionary in source["generals"]:
		if existing.has(entry["id"]):
			continue
		var general: Dictionary = _build_general(entry)
		generals.append(general)
		added.append(entry)

	# 3. 시대별 적 후보
	var added_pool: int = 0
	for era: Dictionary in enemies_data["eras"]:
		var pool: Array = era["pool"]
		var in_pool: Dictionary = {}
		for item: Dictionary in pool:
			in_pool["%s/%s" % [item["general_id"], item["tier"]]] = true
		for entry: Dictionary in added:
			for item: Dictionary in _pool_entries(entry, era):
				var key: String = "%s/%s" % [item["general_id"], item["tier"]]
				if not in_pool.has(key):
					pool.append(item)
					in_pool[key] = true
					added_pool += 1

	_write("res://data/skills.json", skills_data)
	_write("res://data/generals.json", generals_data)
	_write("res://data/enemies.json", enemies_data)
	print("공용 스킬 %d개, 장수 %d명, 시대 후보 %d개 추가 (장수 총 %d명)" % [added_skills, added.size(), added_pool, generals.size()])
	quit(0)


func _build_general(entry: Dictionary) -> Dictionary:
	var role: String = entry["role"]
	var grade: float = float(entry.get("grade", 1.0))
	var tiers: Dictionary = {}
	var raw_tiers: Dictionary = entry["tiers"]
	for tier: String in Tier.ORDER:
		if not raw_tiers.has(tier):
			continue
		var texts: Array = raw_tiers[tier]
		var base_stats: Dictionary = {}
		var growth: Dictionary = {}
		for key: String in Stats.KEYS:
			base_stats[key] = maxi(1, roundi(float(ROLE_BASE[role][key]) * float(TIER_STAT[tier]) * grade))
			growth[key] = snappedf(float(ROLE_GROWTH[role][key]) * float(TIER_GROWTH[tier]) * grade, 0.1)
		tiers[tier] = {
			"title": texts[0],
			"era": texts[1],
			"base_stats": base_stats,
			"growth": growth,
			"skill_ids": _skills_for(entry, tier),
			"reserve_effect": _reserve_for(entry, tier),
		}
	return {"id": entry["id"], "name": entry["name"], "faction": entry["faction"], "role": role, "tiers": tiers}


func _skills_for(entry: Dictionary, tier: String) -> Array:
	var role_skills: Dictionary = ROLE_SKILLS[entry["role"]]
	# id 길이로 두 번째 스킬을 갈라, 같은 역할이라도 스킬 구성이 조금씩 다르게 한다.
	var second: String = role_skills["second"][String(entry["id"]).length() % 2]
	var index: int = Tier.index_of(tier)
	if index <= Tier.index_of("D"):
		return [role_skills["basic"]]
	if index <= Tier.index_of("B"):
		return [role_skills["basic"], second]
	return [role_skills["ultimate"], second]


func _reserve_for(entry: Dictionary, tier: String) -> Dictionary:
	if entry.get("slot_bonus_tier", "") == tier:
		return {"name": "인재 등용", "description": "보유효과 슬롯 +1", "mode": "passive", "effect": {"kind": "reserve_slot_bonus", "value": 1}}
	var role: String = entry["role"]
	var info: Dictionary = ROLE_RESERVE[role]
	var stat: String = info["stat"]
	var index: int = Tier.index_of(tier)
	var band: int = 0 if index <= Tier.index_of("D") else (1 if index <= Tier.index_of("B") else 2)
	var name: String = info["names"][band]
	var value: int = int(RESERVE_VALUE[tier])
	if role == "healer":
		# 힐러의 보유효과는 최후반부 조건 위주 (기획서).
		value = roundi(float(value) * 2.5)
		return {"name": name, "description": "최후반부에 출전 장수의 %s +%d%%" % [STAT_LABEL[stat], value],
			"mode": "conditional", "condition": {"kind": "late_game"}, "effect": {"kind": "stat_percent", "stat": stat, "value": value}}
	return {"name": name, "description": "출전 장수의 %s +%d%%" % [STAT_LABEL[stat], value],
		"mode": "passive", "effect": {"kind": "stat_percent", "stat": stat, "value": value}}


## 한 장수가 한 시대에 들어갈 적 후보: 활동 연도에서 그 시대가 차지하는 위치로 티어를 정하고, 상한을 적용한다.
## 그 티어를 가중치 2로, 한 단계 아래 티어가 있으면 가중치 1로 넣는다.
func _pool_entries(entry: Dictionary, era: Dictionary) -> Array[Dictionary]:
	var span: Array = entry["span"]
	var from_year: int = int(span[0])
	var to_year: int = int(span[1])
	var era_from: int = int(era["year_from"])
	var era_to: int = mini(int(era["year_to"]), era_from + 20)
	if to_year < era_from or from_year > era_to:
		return []
	var tiers: Array[String] = []
	for tier: String in Tier.ORDER:
		if entry["tiers"].has(tier):
			tiers.append(tier)
	var cap: int = Tier.index_of(String(ERA_TIER_CAP.get(era["id"], "S")))
	var middle: float = clampf((float(era_from + era_to) / 2.0 - from_year) / maxf(1.0, float(to_year - from_year)), 0.0, 1.0)
	var position: int = clampi(floori(middle * tiers.size()), 0, tiers.size() - 1)
	while position >= 0 and Tier.index_of(tiers[position]) > cap:
		position -= 1
	if position < 0:
		return []
	var result: Array[Dictionary] = [{"general_id": entry["id"], "tier": tiers[position], "weight": 2}]
	if position > 0:
		result.append({"general_id": entry["id"], "tier": tiers[position - 1], "weight": 1})
	return result


func _read(path: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data


func _write(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_normalize(data), "\t", false) + "\n")


## JSON을 읽으면 모든 숫자가 실수가 되므로, 소수점이 없는 수는 정수로 되돌려 150.0이 아니라 150으로 저장되게 한다.
func _normalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var number: float = value
			return int(number) if number == floorf(number) else number
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var result: Dictionary = {}
			for key: Variant in dict:
				result[key] = _normalize(dict[key])
			return result
		TYPE_ARRAY:
			var list: Array = value
			var result_list: Array = []
			for item: Variant in list:
				result_list.append(_normalize(item))
			return result_list
	return value
