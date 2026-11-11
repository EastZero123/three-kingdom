class_name FormationDef
extends RefCounted
## 편성: 같은 난이도 안에서 적 원정대의 모양을 바꾼다. 예) 쉬움 안의 "오합지졸 대군"(7명, 약함), "숙련된 소수"(3명, 강함)
## data/enemies.json의 토벌 종류마다 formations로 정의하고, 적지 않은 값은 토벌 종류의 값을 그대로 쓴다.

## 편성 이름. 토벌 종류에 편성이 없으면 빈 문자열.
var name: String = ""
var enemy_count_min: int = 0
var enemy_count_max: int = 0
var level_offset: int = 0
var enemy_stat_multiplier: float = 1.0
var tier_weight_per_step: float = 1.0
var reward_exp_multiplier: float = 1.0
## 이 편성이 뽑힐 가중치.
var weight: float = 1.0


## 토벌 종류의 값만으로 기본 편성을 만든다 (편성이 정의되지 않은 경우).
static func from_type(type_def: ExpeditionTypeDef) -> FormationDef:
	var formation: FormationDef = FormationDef.new()
	formation.enemy_count_min = type_def.enemy_count_min
	formation.enemy_count_max = type_def.enemy_count_max
	formation.level_offset = type_def.level_offset
	formation.enemy_stat_multiplier = type_def.enemy_stat_multiplier
	formation.tier_weight_per_step = type_def.tier_weight_per_step
	formation.reward_exp_multiplier = type_def.reward_exp_multiplier
	return formation


## JSON 항목을 읽는다. 없는 값은 토벌 종류의 값을 물려받는다.
static func parse(data: Dictionary, type_def: ExpeditionTypeDef, context: String, errors: Array[String]) -> FormationDef:
	var formation: FormationDef = from_type(type_def)
	formation.name = DataReader.read_string(data, "name", context, errors)
	var ctx: String = "%s(%s)" % [context, formation.name]
	if data.has("enemy_count_min"):
		formation.enemy_count_min = DataReader.read_int(data, "enemy_count_min", ctx, errors)
	if data.has("enemy_count_max"):
		formation.enemy_count_max = DataReader.read_int(data, "enemy_count_max", ctx, errors)
	if data.has("level_offset"):
		formation.level_offset = DataReader.read_int(data, "level_offset", ctx, errors)
	if data.has("enemy_stat_multiplier"):
		formation.enemy_stat_multiplier = DataReader.read_float(data, "enemy_stat_multiplier", ctx, errors)
	if data.has("tier_weight_per_step"):
		formation.tier_weight_per_step = DataReader.read_float(data, "tier_weight_per_step", ctx, errors)
	if data.has("reward_exp_multiplier"):
		formation.reward_exp_multiplier = DataReader.read_float(data, "reward_exp_multiplier", ctx, errors)
	if data.has("weight"):
		formation.weight = DataReader.read_float(data, "weight", ctx, errors)
	if formation.enemy_count_min < 1 or formation.enemy_count_max < formation.enemy_count_min:
		errors.append("%s: 적 인원 범위가 잘못됐다" % ctx)
	if formation.enemy_stat_multiplier <= 0.0 or formation.tier_weight_per_step <= 0.0 or formation.weight <= 0.0:
		errors.append("%s: 배율과 가중치는 0보다 커야 한다" % ctx)
	return formation
