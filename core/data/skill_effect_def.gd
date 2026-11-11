class_name SkillEffectDef
extends RefCounted
## 스킬에 딸린 부가 효과 하나 (버프·디버프).
## 전투 중 회복은 기획상 금지라서 회복 종류는 아예 허용 목록에 없다.

## 허용되는 효과 종류. stat_mod = 스탯을 일정 턴 동안 퍼센트로 올리거나 내린다.
const KINDS: Array[String] = ["stat_mod"]
## 전투 중 바꿀 수 있는 스탯. 체력(hp)은 회복·최대치 변동을 막기 위해 제외한다.
const MOD_STATS: Array[String] = ["attack", "defense", "speed", "intellect"]

var kind: String = ""
var stat: String = ""
## 변화량(%). 양수면 버프, 음수면 디버프.
var percent: float = 0.0
## 지속 턴 수.
var duration: int = 0


static func parse(data: Dictionary, context: String, errors: Array[String]) -> SkillEffectDef:
	var effect: SkillEffectDef = SkillEffectDef.new()
	effect.kind = DataReader.read_string(data, "kind", context, errors)
	DataReader.check_one_of(effect.kind, KINDS, "kind", context, errors)
	effect.stat = DataReader.read_string(data, "stat", context, errors)
	DataReader.check_one_of(effect.stat, MOD_STATS, "stat", context, errors)
	effect.percent = DataReader.read_float(data, "percent", context, errors)
	effect.duration = DataReader.read_int(data, "duration", context, errors)
	if effect.duration < 1:
		errors.append("%s: 'duration'은 1 이상이어야 한다" % context)
	return effect
