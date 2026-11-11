class_name GeneralDef
extends RefCounted
## 장수 한 명의 정의 (data/generals.json의 한 항목). 티어별 정의를 여러 개 가진다.

## 전투 역할. healer만 전투 후 치유를 한다.
const ROLES: Array[String] = ["warrior", "defender", "strategist", "healer", "support"]

var id: String = ""
var name: String = ""
## 소속 세력. 현상금 토벌처럼 세력별 내용에 쓴다.
var faction: String = ""
var role: String = ""
## 티어 이름("B" 등) → 그 티어의 정의.
var tiers: Dictionary[String, GeneralTierDef] = {}


func is_healer() -> bool:
	return role == "healer"


func has_tier(tier: String) -> bool:
	return tiers.has(tier)


func get_tier(tier: String) -> GeneralTierDef:
	if not tiers.has(tier):
		push_error("장수 %s에게 %s 티어 정의가 없다" % [id, tier])
		return null
	return tiers[tier]


## 이 장수가 가진 티어를 낮은 순서로 돌려준다.
func available_tiers() -> Array[String]:
	var result: Array[String] = []
	for tier: String in Tier.ORDER:
		if tiers.has(tier):
			result.append(tier)
	return result


func lowest_tier() -> String:
	var available: Array[String] = available_tiers()
	return "" if available.is_empty() else available[0]


func highest_tier() -> String:
	var available: Array[String] = available_tiers()
	return "" if available.is_empty() else available[available.size() - 1]


static func parse(data: Dictionary, context: String, errors: Array[String]) -> GeneralDef:
	var general: GeneralDef = GeneralDef.new()
	general.id = DataReader.read_string(data, "id", context, errors)
	var ctx: String = "%s(%s)" % [context, general.id]
	general.name = DataReader.read_string(data, "name", ctx, errors)
	general.faction = DataReader.read_string(data, "faction", ctx, errors)
	general.role = DataReader.read_string(data, "role", ctx, errors)
	DataReader.check_one_of(general.role, ROLES, "role", ctx, errors)

	var raw_tiers: Dictionary = DataReader.read_dict(data, "tiers", ctx, errors)
	if raw_tiers.is_empty():
		errors.append("%s: 티어 정의가 하나도 없다" % ctx)
	for raw_key: Variant in raw_tiers:
		var tier_name: String = String(raw_key)
		var tier_ctx: String = "%s.tiers.%s" % [ctx, tier_name]
		if not Tier.is_valid(tier_name):
			errors.append("%s: 없는 티어다 (가능: %s)" % [tier_ctx, ", ".join(Tier.ORDER)])
			continue
		if typeof(raw_tiers[raw_key]) != TYPE_DICTIONARY:
			errors.append("%s: 객체가 아니다" % tier_ctx)
			continue
		var tier_data: Dictionary = raw_tiers[raw_key]
		general.tiers[tier_name] = GeneralTierDef.parse(tier_name, tier_data, tier_ctx, errors)

	# 합성으로 한 단계씩 오르므로, 가진 티어 사이에 빈 단계가 있으면 안 된다.
	var available: Array[String] = general.available_tiers()
	for i: int in range(1, available.size()):
		if Tier.index_of(available[i]) != Tier.index_of(available[i - 1]) + 1:
			errors.append("%s: %s와 %s 사이 티어가 비어 있다 (티어는 연속이어야 한다)" % [ctx, available[i - 1], available[i]])
	return general
