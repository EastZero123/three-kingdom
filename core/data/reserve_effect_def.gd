class_name ReserveEffectDef
extends RefCounted
## 보유효과 정의. 보유효과 슬롯에 있는 장수가 전투에 나가지 않고 발동하는 고유 효과.

## passive = 상시 효과, conditional = 조건부 액티브 (발동 조건이 반드시 있어야 한다).
const MODES: Array[String] = ["passive", "conditional"]

## 발동 조건 종류.
## late_game = 최후반부. 기준 인원은 balance.json의 reserve_effect.late_game_allies_alive_at_most를 따른다.
const CONDITION_KINDS: Array[String] = [
	"late_game", "allies_alive_at_most", "enemies_alive_at_most", "battle_turn_at_least",
]
## 값(value)이 필요 없는 조건.
const CONDITIONS_WITHOUT_VALUE: Array[String] = ["late_game"]

## 효과 종류.
## stat_percent = 출전 장수의 스탯을 %만큼 올린다, reserve_slot_bonus = 보유효과 슬롯을 늘린다.
const EFFECT_KINDS: Array[String] = ["stat_percent", "reserve_slot_bonus"]

var name: String = ""
var description: String = ""
var mode: String = ""
var condition_kind: String = ""
var condition_value: int = 0
var effect_kind: String = ""
var effect_stat: String = ""
var effect_value: float = 0.0


func is_conditional() -> bool:
	return mode == "conditional"


## 이 효과가 늘려 주는 보유효과 슬롯 수. 해당 없으면 0.
func reserve_slot_bonus() -> int:
	if effect_kind == "reserve_slot_bonus":
		return int(effect_value)
	return 0


static func parse(data: Dictionary, context: String, errors: Array[String]) -> ReserveEffectDef:
	var effect: ReserveEffectDef = ReserveEffectDef.new()
	effect.name = DataReader.read_string(data, "name", context, errors)
	effect.description = DataReader.read_string(data, "description", context, errors)
	effect.mode = DataReader.read_string(data, "mode", context, errors)
	DataReader.check_one_of(effect.mode, MODES, "mode", context, errors)

	# 조건: 조건부 액티브는 반드시 있어야 하고, 상시 효과는 있으면 안 된다.
	var has_condition: bool = data.has("condition") and typeof(data["condition"]) == TYPE_DICTIONARY
	if effect.mode == "conditional" and not has_condition:
		errors.append("%s: 조건부 효과에 'condition'이 없다 (발동 조건은 명확해야 한다)" % context)
	elif effect.mode == "passive" and data.has("condition"):
		errors.append("%s: 상시 효과에는 'condition'을 둘 수 없다" % context)
	elif has_condition:
		var condition: Dictionary = data["condition"]
		var condition_ctx: String = "%s.condition" % context
		effect.condition_kind = DataReader.read_string(condition, "kind", condition_ctx, errors)
		DataReader.check_one_of(effect.condition_kind, CONDITION_KINDS, "kind", condition_ctx, errors)
		if not CONDITIONS_WITHOUT_VALUE.has(effect.condition_kind):
			effect.condition_value = DataReader.read_int(condition, "value", condition_ctx, errors)

	var raw_effect: Dictionary = DataReader.read_dict(data, "effect", context, errors)
	var effect_ctx: String = "%s.effect" % context
	effect.effect_kind = DataReader.read_string(raw_effect, "kind", effect_ctx, errors)
	DataReader.check_one_of(effect.effect_kind, EFFECT_KINDS, "kind", effect_ctx, errors)
	effect.effect_value = DataReader.read_float(raw_effect, "value", effect_ctx, errors)
	if effect.effect_kind == "stat_percent":
		effect.effect_stat = DataReader.read_string(raw_effect, "stat", effect_ctx, errors)
		DataReader.check_one_of(effect.effect_stat, Stats.KEYS, "stat", effect_ctx, errors)
		# 체력 증가는 전투 시작 때 한 번 정해지므로 상시 효과만 허용한다.
		if effect.effect_stat == "hp" and effect.mode == "conditional":
			errors.append("%s: 체력 증가는 조건부 효과로 둘 수 없다" % effect_ctx)
	if effect.effect_kind == "reserve_slot_bonus" and effect.mode == "conditional":
		errors.append("%s: 슬롯 확장은 조건부 효과로 둘 수 없다" % effect_ctx)
	return effect
