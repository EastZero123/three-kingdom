class_name GeneralTierDef
extends RefCounted
## 한 장수의 한 티어 정의. 티어마다 다른 시기의 인물이라 스탯·스킬·보유효과가 따로 있다.

var tier: String = ""
## 그 시기를 나타내는 칭호. 예: "상국"
var title: String = ""
## 어떤 시기의 모습인지 설명.
var era: String = ""
## 레벨 1일 때의 스탯.
var base_stats: Stats = Stats.new()
## 레벨이 1 오를 때마다 늘어나는 스탯 (소수 가능).
var growth: Dictionary[String, float] = {}
var skill_ids: Array[String] = []
var reserve_effect: ReserveEffectDef = null


## 주어진 레벨에서의 스탯. 레벨 1이면 기본 스탯 그대로다.
## 계산식: 기본 스탯 + 내림(성장률 × (레벨 - 1))
func stats_at_level(level: int) -> Stats:
	var result: Stats = Stats.new()
	for key: String in Stats.KEYS:
		var gained: int = floori(growth.get(key, 0.0) * float(level - 1))
		result.set_value(key, base_stats.get_value(key) + gained)
	return result


static func parse(tier_name: String, data: Dictionary, context: String, errors: Array[String]) -> GeneralTierDef:
	var def: GeneralTierDef = GeneralTierDef.new()
	def.tier = tier_name
	def.title = DataReader.read_string(data, "title", context, errors)
	def.era = DataReader.read_string(data, "era", context, errors)

	var raw_stats: Dictionary = DataReader.read_dict(data, "base_stats", context, errors)
	var raw_growth: Dictionary = DataReader.read_dict(data, "growth", context, errors)
	for key: String in Stats.KEYS:
		var base_value: int = DataReader.read_int(raw_stats, key, "%s.base_stats" % context, errors)
		if base_value < 1:
			errors.append("%s.base_stats: '%s'는 1 이상이어야 한다" % [context, key])
		def.base_stats.set_value(key, base_value)
		var growth_value: float = DataReader.read_float(raw_growth, key, "%s.growth" % context, errors)
		if growth_value < 0.0:
			errors.append("%s.growth: '%s'는 0 이상이어야 한다" % [context, key])
		def.growth[key] = growth_value

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
