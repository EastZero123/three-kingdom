class_name ChestDef
extends RefCounted
## 보물상자 정의 (data/chests.json의 chests 항목). 로스터 장수들의 카드를 한꺼번에 지급한다.

## 카드를 받을 장수의 범위.
##   roster = 로스터 전체(출전 + 보유효과), active = 출전 장수만, single = 플레이어가 고른 장수 1명
const SCOPES: Array[String] = ["roster", "active", "single"]

var id: String = ""
var name: String = ""
var scope: String = ""
var card_count: int = 0


func needs_target() -> bool:
	return scope == "single"


func scope_label() -> String:
	match scope:
		"roster":
			return "전체 로스터"
		"active":
			return "출전 장수"
		"single":
			return "장수 1명 집중"
	return scope


static func parse(data: Dictionary, context: String, errors: Array[String]) -> ChestDef:
	var chest: ChestDef = ChestDef.new()
	chest.id = DataReader.read_string(data, "id", context, errors)
	var ctx: String = "%s(%s)" % [context, chest.id]
	chest.name = DataReader.read_string(data, "name", ctx, errors)
	chest.scope = DataReader.read_string(data, "scope", ctx, errors)
	DataReader.check_one_of(chest.scope, SCOPES, "scope", ctx, errors)
	chest.card_count = DataReader.read_int(data, "card_count", ctx, errors)
	if chest.card_count < 1:
		errors.append("%s: 'card_count'는 1 이상이어야 한다" % ctx)
	return chest
