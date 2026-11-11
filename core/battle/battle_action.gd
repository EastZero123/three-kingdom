class_name BattleAction
extends RefCounted
## 한 장수의 행동 하나: 누가, 어떤 스킬로, 누구를.

var actor: BattleUnit = null
## 쓰는 스킬. null이면 기본 공격.
var skill: SkillDef = null
## 단일 대상 스킬의 대상. 전체·열 대상 스킬이면 null.
var target: BattleUnit = null
## 이 행동이 일어난 턴 번호 (BattleEngine이 기록한다).
var round_number: int = 0


static func create(p_actor: BattleUnit, p_skill: SkillDef, p_target: BattleUnit) -> BattleAction:
	var action: BattleAction = BattleAction.new()
	action.actor = p_actor
	action.skill = p_skill
	action.target = p_target
	return action


func is_basic_attack() -> bool:
	return skill == null


## 대상 지정 방식. 기본 공격은 적 하나.
func target_kind() -> String:
	return "enemy_single" if skill == null else skill.target
