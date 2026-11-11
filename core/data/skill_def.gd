class_name SkillDef
extends RefCounted
## 스킬 하나의 정의 (data/skills.json의 한 항목).
## "Def"는 정의(definition)의 줄임으로, 전투 중 바뀌지 않는 원본 데이터를 뜻한다.

## 대상 지정 방식.
const TARGETS: Array[String] = [
	"enemy_single", "enemy_front_row", "enemy_back_row", "enemy_all",
	"ally_single", "ally_all", "self",
]
## 피해량 계산에 쓰는 스탯.
const SCALING_STATS: Array[String] = ["attack", "intellect"]

var id: String = ""
var name: String = ""
var description: String = ""
var target: String = ""
var scaling_stat: String = ""
## 피해 배율. 0이면 피해 없이 부가 효과만 주는 스킬.
var power: float = 0.0
## 재사용 대기 턴 수. 발동 조건을 명확히 하기 위해 모든 스킬이 가진다.
var cooldown: int = 0
var effects: Array[SkillEffectDef] = []


func deals_damage() -> bool:
	return power > 0.0


static func parse(data: Dictionary, context: String, errors: Array[String]) -> SkillDef:
	var skill: SkillDef = SkillDef.new()
	skill.id = DataReader.read_string(data, "id", context, errors)
	var ctx: String = "%s(%s)" % [context, skill.id]
	skill.name = DataReader.read_string(data, "name", ctx, errors)
	skill.description = DataReader.read_string(data, "description", ctx, errors)
	skill.target = DataReader.read_string(data, "target", ctx, errors)
	DataReader.check_one_of(skill.target, TARGETS, "target", ctx, errors)
	skill.scaling_stat = DataReader.read_string(data, "scaling_stat", ctx, errors)
	DataReader.check_one_of(skill.scaling_stat, SCALING_STATS, "scaling_stat", ctx, errors)
	skill.power = DataReader.read_float(data, "power", ctx, errors)
	if skill.power < 0.0:
		errors.append("%s: 'power'는 0 이상이어야 한다" % ctx)
	skill.cooldown = DataReader.read_int(data, "cooldown", ctx, errors)
	if skill.cooldown < 1:
		errors.append("%s: 'cooldown'은 1 이상이어야 한다" % ctx)

	var raw_effects: Array = DataReader.read_array(data, "effects", ctx, errors)
	for i: int in raw_effects.size():
		var effect_ctx: String = "%s.effects[%d]" % [ctx, i]
		if typeof(raw_effects[i]) != TYPE_DICTIONARY:
			errors.append("%s: 객체가 아니다" % effect_ctx)
			continue
		var effect_data: Dictionary = raw_effects[i]
		skill.effects.append(SkillEffectDef.parse(effect_data, effect_ctx, errors))

	if not skill.deals_damage() and skill.effects.is_empty():
		errors.append("%s: 피해도 부가 효과도 없는 스킬이다" % ctx)
	if skill.deals_damage() and skill.target.begins_with("ally") or skill.deals_damage() and skill.target == "self":
		errors.append("%s: 아군 대상 스킬에 피해 배율이 있다" % ctx)
	return skill
