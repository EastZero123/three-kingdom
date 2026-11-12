class_name GeneralTierDef
extends RefCounted
## 한 장수의 한 티어 정의. 티어마다 다른 시기의 인물이라 스탯·스킬·보유효과가 따로 있다.

var tier: String = ""
## 그 시기를 나타내는 칭호. 예: "상국"
var title: String = ""
## 어떤 시기의 모습인지 설명.
var era: String = ""
## 기본 능력치 (0~100, 레벨 1·배분 전). 체력도 능력치 단위다 (실제 체력은 AbilityBuild가 변환).
var base_stats: Stats = Stats.new()
## 성향: 컴퓨터가 레벨업 포인트를 나누는 비율 (적 장수용, 소수 가능). 플레이어 장수는 직접 배분한다.
## 화면에서 "이 장수는 무엇이 잘 크는가"를 보여 줄 때도 쓸 수 있다.
var tendency: Dictionary[String, float] = {}
var skill_ids: Array[String] = []
var reserve_effect: ReserveEffectDef = null


static func parse(tier_name: String, data: Dictionary, context: String, errors: Array[String]) -> GeneralTierDef:
	var def: GeneralTierDef = GeneralTierDef.new()
	def.tier = tier_name
	def.title = DataReader.read_string(data, "title", context, errors)
	def.era = DataReader.read_string(data, "era", context, errors)

	var raw_stats: Dictionary = DataReader.read_dict(data, "base_stats", context, errors)
	var raw_tendency: Dictionary = DataReader.read_dict(data, "tendency", context, errors)
	for key: String in Stats.KEYS:
		var base_value: int = DataReader.read_int(raw_stats, key, "%s.base_stats" % context, errors)
		if base_value < 1:
			errors.append("%s.base_stats: '%s'는 1 이상이어야 한다" % [context, key])
		def.base_stats.set_value(key, base_value)
		var tendency_value: float = DataReader.read_float(raw_tendency, key, "%s.tendency" % context, errors)
		if tendency_value < 0.0:
			errors.append("%s.tendency: '%s'는 0 이상이어야 한다" % [context, key])
		def.tendency[key] = tendency_value

	var raw_skills: Array = DataReader.read_array(data, "skill_ids", context, errors)
	if raw_skills.is_empty():
		errors.append("%s: 'skill_ids'에 스킬이 하나 이상 있어야 한다" % context)
	for raw_id: Variant in raw_skills:
		if typeof(raw_id) != TYPE_STRING:
			errors.append("%s: 'skill_ids'에 문자열이 아닌 값이 있다" % context)
			continue
		def.skill_ids.append(String(raw_id))

	var raw_reserve: Dictionary = DataReader.read_dict(data, "reserve_effect", context, errors)
	def.reserve_effect = ReserveEffectDef.parse(raw_reserve, "%s.reserve_effect" % context, errors)
	return def
