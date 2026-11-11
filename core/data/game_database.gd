class_name GameDatabase
extends RefCounted
## 게임 데이터 전체(밸런스, 스킬, 장수)를 읽고 검증해서 들고 있는 저장소.
## 사용 예:
##   var db: GameDatabase = GameDatabase.load_from_dir("res://data")
##   if db.is_valid(): var guan_yu: GeneralDef = db.get_general("guan_yu")

const BALANCE_FILE: String = "balance.json"
const SKILLS_FILE: String = "skills.json"
const GENERALS_FILE: String = "generals.json"
const ENEMIES_FILE: String = "enemies.json"
const RUN_FILE: String = "run.json"
const CHESTS_FILE: String = "chests.json"

var balance: Balance = Balance.new()
var skills: Dictionary[String, SkillDef] = {}
var generals: Dictionary[String, GeneralDef] = {}
## 시대 목록 (연도 순).
var eras: Array[EraDef] = []
var expedition_types: Array[ExpeditionTypeDef] = []
## 적 레벨 공식의 계수: 기준 레벨 = base + (지난 연수 × per_year) + ((라운드 - 1) × per_round)
var enemy_level_base: float = 1.0
var enemy_level_per_year: float = 0.0
var enemy_level_per_round: float = 0.0
## 런 시작 때의 로스터 (드래프트 없이 시작할 때: 테스트·자동 진행 도구용). 각 항목: {general_id, tier, level}
var starting_roster: Array[Dictionary] = []
## 시작 드래프트: 후보 choices명 중 1명을 고르는 일을 picks번. 영입 레벨과 후보 티어 가중치.
var draft_picks: int = 0
var draft_choices: int = 0
var draft_level: int = 1
var draft_tier_weights: Dictionary[String, float] = {}
var chests: Dictionary[String, ChestDef] = {}
## 상자 카드의 티어 가중치. 순번 = 그 장수의 가장 낮은 티어에서 몇 단계 위인지.
var chest_tier_offset_weights: Array[float] = []
## 해 넘김 때 자동으로 주는 상자.
var year_end_chest_id: String = ""
## 읽으면서 발견한 문제 목록. 비어 있어야 정상이다.
var errors: Array[String] = []


func is_valid() -> bool:
	return errors.is_empty()


func get_skill(id: String) -> SkillDef:
	if not skills.has(id):
		push_error("없는 스킬: %s" % id)
		return null
	return skills[id]


func get_general(id: String) -> GeneralDef:
	if not generals.has(id):
		push_error("없는 장수: %s" % id)
		return null
	return generals[id]


## 폴더 안의 JSON 파일들을 읽어 데이터베이스를 만든다.
static func load_from_dir(dir_path: String = "res://data") -> GameDatabase:
	var file_errors: Array[String] = []
	var balance_data: Dictionary = _read_json_file(dir_path.path_join(BALANCE_FILE), file_errors)
	var skills_data: Dictionary = _read_json_file(dir_path.path_join(SKILLS_FILE), file_errors)
	var generals_data: Dictionary = _read_json_file(dir_path.path_join(GENERALS_FILE), file_errors)
	var enemies_data: Dictionary = _read_json_file(dir_path.path_join(ENEMIES_FILE), file_errors)
	var run_data: Dictionary = _read_json_file(dir_path.path_join(RUN_FILE), file_errors)
	var chests_data: Dictionary = _read_json_file(dir_path.path_join(CHESTS_FILE), file_errors)
	var db: GameDatabase = from_dicts(balance_data, skills_data, generals_data, enemies_data, run_data, chests_data)
	# 파일을 못 읽은 오류를 맨 앞에 둔다.
	file_errors.append_array(db.errors)
	db.errors = file_errors
	return db


## 이미 읽어 둔 Dictionary로 데이터베이스를 만든다. 테스트에서 파일 없이 쓰기 좋다.
## enemies_data, run_data, chests_data는 비워 두면 건너뛴다 (장수·스킬만 검사하는 테스트용).
static func from_dicts(balance_data: Dictionary, skills_data: Dictionary, generals_data: Dictionary, enemies_data: Dictionary = {}, run_data: Dictionary = {}, chests_data: Dictionary = {}) -> GameDatabase:
	var db: GameDatabase = GameDatabase.new()
	db.balance = Balance.new(balance_data)
	db.errors.append_array(db.balance.validate())
	db._parse_skills(skills_data)
	db._parse_generals(generals_data)
	db._check_references()
	if not chests_data.is_empty():
		db._parse_chests(chests_data)
	if not enemies_data.is_empty():
		db._parse_enemies(enemies_data)
	if not run_data.is_empty():
		db._parse_run(run_data)
	return db


## 주어진 연도의 시대. 마지막 시대 이후의 연도는 마지막 시대로 본다.
func era_for_year(year: int) -> EraDef:
	for era: EraDef in eras:
		if era.contains_year(year):
			return era
	if eras.is_empty():
		push_error("시대 데이터가 없다")
		return null
	return eras[eras.size() - 1] if year > eras[eras.size() - 1].year_to else eras[0]


## 연도와 라운드에 따른 기준 적 레벨 (토벌 종류의 보정은 더하기 전).
func enemy_base_level(year: int, round_number: int) -> int:
	var years_passed: int = year - balance.get_int("run.start_year")
	var level: float = enemy_level_base + float(years_passed) * enemy_level_per_year + float(round_number - 1) * enemy_level_per_round
	return floori(level)


## 장수 id와 티어가 실제 데이터에 있는지 검사한다.
func _check_general_tier(general_id: String, tier: String, context: String) -> void:
	if general_id.is_empty() or tier.is_empty():
		return
	if not generals.has(general_id):
		errors.append("%s: 없는 장수 '%s'" % [context, general_id])
	elif not generals[general_id].has_tier(tier):
		errors.append("%s: 장수 '%s'에게 %s 티어가 없다" % [context, general_id, tier])


func _parse_enemies(data: Dictionary) -> void:
	var level: Dictionary = DataReader.read_dict(data, "level", "enemies.json", errors)
	enemy_level_base = DataReader.read_float(level, "base", "enemies.level", errors)
	enemy_level_per_year = DataReader.read_float(level, "per_year", "enemies.level", errors)
	enemy_level_per_round = DataReader.read_float(level, "per_round", "enemies.level", errors)

	var raw_types: Array = DataReader.read_array(data, "expedition_types", "enemies.json", errors)
	var max_enemy_count: int = 0
	for i: int in raw_types.size():
		if typeof(raw_types[i]) != TYPE_DICTIONARY:
			errors.append("expedition_types[%d]: 객체가 아니다" % i)
			continue
		var type_data: Dictionary = raw_types[i]
		var type_def: ExpeditionTypeDef = ExpeditionTypeDef.parse(type_data, "expedition_types[%d]" % i, errors)
		expedition_types.append(type_def)
		for entry: Dictionary in type_def.chest_pool:
			if not chests.has(String(entry["chest_id"])):
				errors.append("토벌 종류 %s: 없는 상자 '%s'" % [type_def.id, entry["chest_id"]])
		# 적 인원은 전투 규칙의 범위(battle.enemy_count_min~max) 안이어야 한다.
		var count_min: int = balance.get_int("battle.enemy_count_min")
		var count_max: int = balance.get_int("battle.enemy_count_max")
		for formation: FormationDef in type_def.formations:
			if formation.enemy_count_min < count_min or formation.enemy_count_max > count_max:
				errors.append("토벌 종류 %s 편성 '%s': 적 인원이 %d~%d명 범위를 벗어난다" % [type_def.id, formation.name, count_min, count_max])
			max_enemy_count = maxi(max_enemy_count, formation.enemy_count_max)
	var normal_count: int = 0
	for type_def: ExpeditionTypeDef in expedition_types:
		if not type_def.is_special():
			normal_count += 1
	if normal_count == 0:
		errors.append("enemies.json: 일반 토벌 종류가 하나도 없다")

	var raw_eras: Array = DataReader.read_array(data, "eras", "enemies.json", errors)
	for i: int in raw_eras.size():
		if typeof(raw_eras[i]) != TYPE_DICTIONARY:
			errors.append("eras[%d]: 객체가 아니다" % i)
			continue
		var era_data: Dictionary = raw_eras[i]
		var era: EraDef = EraDef.parse(era_data, "eras[%d]" % i, errors)
		eras.append(era)
		for entry: Dictionary in era.pool:
			_check_general_tier(String(entry["general_id"]), String(entry["tier"]), "시대 %s" % era.id)
		# 적 원정대는 서로 다른 장수로 채우므로 후보가 최대 인원보다 적으면 안 된다.
		if era.distinct_general_count() < max_enemy_count:
			errors.append("시대 %s: 후보 장수가 %d명뿐이라 적 %d명을 채울 수 없다" % [era.id, era.distinct_general_count(), max_enemy_count])

	if eras.is_empty():
		errors.append("enemies.json: 시대가 하나도 없다")
		return
	# 시대는 시작 연도부터 빈 해 없이 이어져야 한다.
	if eras[0].year_from > balance.get_int("run.start_year"):
		errors.append("시대 %s: 시작 연도(%d)보다 늦게 시작한다" % [eras[0].id, balance.get_int("run.start_year")])
	for i: int in range(1, eras.size()):
		if eras[i].year_from != eras[i - 1].year_to + 1:
			errors.append("시대 %s와 %s 사이 연도가 이어지지 않는다" % [eras[i - 1].id, eras[i].id])


func get_chest(id: String) -> ChestDef:
	if not chests.has(id):
		push_error("없는 상자: %s" % id)
		return null
	return chests[id]


func _parse_chests(data: Dictionary) -> void:
	for raw_weight: Variant in DataReader.read_array(data, "tier_offset_weights", "chests.json", errors):
		if not DataReader.is_number(raw_weight) or float(raw_weight) < 0.0:
			errors.append("chests.json: 'tier_offset_weights'에 0 이상의 숫자만 넣을 수 있다")
			continue
		chest_tier_offset_weights.append(float(raw_weight))
	if chest_tier_offset_weights.is_empty():
		errors.append("chests.json: 'tier_offset_weights'가 비어 있다")

	var raw_chests: Array = DataReader.read_array(data, "chests", "chests.json", errors)
	for i: int in raw_chests.size():
		if typeof(raw_chests[i]) != TYPE_DICTIONARY:
			errors.append("chests[%d]: 객체가 아니다" % i)
			continue
		var chest_data: Dictionary = raw_chests[i]
		var chest: ChestDef = ChestDef.parse(chest_data, "chests[%d]" % i, errors)
		if chests.has(chest.id):
			errors.append("chests[%d]: 상자 id '%s'가 중복이다" % [i, chest.id])
			continue
		chests[chest.id] = chest

	year_end_chest_id = DataReader.read_string(data, "year_end_chest", "chests.json", errors)
	if chests.has(year_end_chest_id) and chests[year_end_chest_id].needs_target():
		errors.append("chests.json: 해 넘김 상자는 대상을 고르는 상자(single)일 수 없다")
	elif not year_end_chest_id.is_empty() and not chests.has(year_end_chest_id):
		errors.append("chests.json: 해 넘김 상자 '%s'가 없다" % year_end_chest_id)


func _parse_run(data: Dictionary) -> void:
	var draft: Dictionary = DataReader.read_dict(data, "draft", "run.json", errors)
	draft_picks = DataReader.read_int(draft, "picks", "run.draft", errors)
	draft_choices = DataReader.read_int(draft, "choices", "run.draft", errors)
	draft_level = DataReader.read_int(draft, "level", "run.draft", errors)
	var raw_weights: Dictionary = DataReader.read_dict(draft, "tier_weights", "run.draft", errors)
	for raw_tier: Variant in raw_weights:
		var tier: String = String(raw_tier)
		if not Tier.is_valid(tier) or not DataReader.is_number(raw_weights[raw_tier]) or float(raw_weights[raw_tier]) < 0.0:
			errors.append("run.draft.tier_weights: '%s' 항목이 잘못됐다" % tier)
			continue
		draft_tier_weights[tier] = float(raw_weights[raw_tier])
	var roster_size: int = balance.get_int("roster.active_slots") + balance.get_int("roster.reserve_slots_base")
	if draft_picks < 1 or draft_picks > roster_size:
		errors.append("run.draft: 'picks'는 1~%d 사이여야 한다" % roster_size)
	if draft_choices < 1:
		errors.append("run.draft: 'choices'는 1 이상이어야 한다")
	# 같은 장수는 한 번만 뽑히므로 장수 수가 충분해야 한다.
	if generals.size() < draft_picks + draft_choices - 1:
		errors.append("run.draft: 장수가 %d명뿐이라 드래프트를 채울 수 없다" % generals.size())

	var raw_roster: Array = DataReader.read_array(data, "starting_roster", "run.json", errors)
	var seen: Dictionary[String, bool] = {}
	for i: int in raw_roster.size():
		var context: String = "starting_roster[%d]" % i
		if typeof(raw_roster[i]) != TYPE_DICTIONARY:
			errors.append("%s: 객체가 아니다" % context)
			continue
		var raw_entry: Dictionary = raw_roster[i]
		var general_id: String = DataReader.read_string(raw_entry, "general_id", context, errors)
		var tier: String = DataReader.read_string(raw_entry, "tier", context, errors)
		var level: int = DataReader.read_int(raw_entry, "level", context, errors)
		_check_general_tier(general_id, tier, context)
		if level < 1 or level > balance.get_int("level.max_level"):
			errors.append("%s: 레벨이 범위를 벗어났다" % context)
		if seen.has(general_id):
			errors.append("%s: 같은 장수 '%s'가 두 번 있다 (동일 장수 공존 불가)" % [context, general_id])
		seen[general_id] = true
		starting_roster.append({"general_id": general_id, "tier": tier, "level": level})
	var active_slots: int = balance.get_int("roster.active_slots")
	if starting_roster.size() != active_slots:
		errors.append("run.json: 시작 로스터는 출전 슬롯 수(%d명)와 같아야 한다" % active_slots)


func _parse_skills(data: Dictionary) -> void:
	var raw_skills: Array = DataReader.read_array(data, "skills", "skills.json", errors)
	for i: int in raw_skills.size():
		var context: String = "skills[%d]" % i
		if typeof(raw_skills[i]) != TYPE_DICTIONARY:
			errors.append("%s: 객체가 아니다" % context)
			continue
		var skill_data: Dictionary = raw_skills[i]
		var skill: SkillDef = SkillDef.parse(skill_data, context, errors)
		if skill.id.is_empty():
			continue
		if skills.has(skill.id):
			errors.append("%s: 스킬 id '%s'가 중복이다" % [context, skill.id])
			continue
		skills[skill.id] = skill


func _parse_generals(data: Dictionary) -> void:
	var raw_generals: Array = DataReader.read_array(data, "generals", "generals.json", errors)
	for i: int in raw_generals.size():
		var context: String = "generals[%d]" % i
		if typeof(raw_generals[i]) != TYPE_DICTIONARY:
			errors.append("%s: 객체가 아니다" % context)
			continue
		var general_data: Dictionary = raw_generals[i]
		var general: GeneralDef = GeneralDef.parse(general_data, context, errors)
		if general.id.is_empty():
			continue
		if generals.has(general.id):
			errors.append("%s: 장수 id '%s'가 중복이다" % [context, general.id])
			continue
		generals[general.id] = general


## 파일 사이의 연결을 검사한다: 장수가 쓰는 스킬이 실제로 있는지 등.
func _check_references() -> void:
	for general_id: String in generals:
		var general: GeneralDef = generals[general_id]
		for tier_name: String in general.tiers:
			var tier_def: GeneralTierDef = general.tiers[tier_name]
			for skill_id: String in tier_def.skill_ids:
				if not skills.has(skill_id):
					errors.append("장수 %s %s티어: 없는 스킬 '%s'를 쓴다" % [general_id, tier_name, skill_id])


## JSON 파일 하나를 읽어 Dictionary로 돌려준다. 실패하면 빈 Dictionary와 오류 메시지.
static func _read_json_file(path: String, file_errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		file_errors.append("파일이 없다: %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	var result: Error = json.parse(text)
	if result != OK:
		file_errors.append("%s: JSON 문법 오류 (%d번째 줄) %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		file_errors.append("%s: 최상위가 객체({})가 아니다" % path)
		return {}
	var data: Dictionary = json.data
	return data
