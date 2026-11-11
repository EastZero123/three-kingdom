class_name EraDef
extends RefCounted
## 시대 정의 (data/enemies.json의 eras 항목). 연도 범위마다 등장하는 적 장수와 티어가 다르다.

var id: String = ""
var name: String = ""
var year_from: int = 0
var year_to: int = 0
## 등장 후보 목록. 각 항목: {general_id: String, tier: String, weight: float}
var pool: Array[Dictionary] = []


func contains_year(year: int) -> bool:
	return year >= year_from and year <= year_to


## 후보에 들어 있는 서로 다른 장수의 수.
func distinct_general_count() -> int:
	var seen: Dictionary[String, bool] = {}
	for entry: Dictionary in pool:
		seen[String(entry["general_id"])] = true
	return seen.size()


static func parse(data: Dictionary, context: String, errors: Array[String]) -> EraDef:
	var era: EraDef = EraDef.new()
	era.id = DataReader.read_string(data, "id", context, errors)
	var ctx: String = "%s(%s)" % [context, era.id]
	era.name = DataReader.read_string(data, "name", ctx, errors)
	era.year_from = DataReader.read_int(data, "year_from", ctx, errors)
	era.year_to = DataReader.read_int(data, "year_to", ctx, errors)
	if era.year_to < era.year_from:
		errors.append("%s: 'year_to'가 'year_from'보다 앞선다" % ctx)

	var raw_pool: Array = DataReader.read_array(data, "pool", ctx, errors)
	for i: int in raw_pool.size():
		var entry_ctx: String = "%s.pool[%d]" % [ctx, i]
		if typeof(raw_pool[i]) != TYPE_DICTIONARY:
			errors.append("%s: 객체가 아니다" % entry_ctx)
			continue
		var raw_entry: Dictionary = raw_pool[i]
		var weight: float = DataReader.read_float(raw_entry, "weight", entry_ctx, errors)
		if weight <= 0.0:
			errors.append("%s: 'weight'는 0보다 커야 한다" % entry_ctx)
		era.pool.append({
			"general_id": DataReader.read_string(raw_entry, "general_id", entry_ctx, errors),
			"tier": DataReader.read_string(raw_entry, "tier", entry_ctx, errors),
			"weight": weight,
		})
	return era
