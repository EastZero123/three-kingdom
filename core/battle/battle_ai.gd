class_name BattleAI
extends RefCounted
## 규칙 기반 전투 AI. 난수를 쓰지 않으므로 같은 상황이면 항상 같은 선택을 한다.
## 규칙:
##   1. 쓸 수 있는 스킬이 있으면 목록에서 가장 앞의 것을 쓴다. 없으면 기본 공격.
##   2. 적 하나를 고를 때는 남은 체력이 가장 적은 대상(가장 약한 대상 우선).
##   3. 아군 하나를 고를 때는 체력 비율이 가장 낮은 아군.
##   4. 같으면 자리 번호가 앞선 쪽.


static func choose(engine: BattleEngine, actor: BattleUnit) -> BattleAction:
	var skill: SkillDef = null
	for candidate: SkillDef in actor.skills:
		if actor.is_skill_ready(candidate):
			skill = candidate
			break

	var action: BattleAction = BattleAction.create(actor, skill, null)
	var kind: String = action.target_kind()
	var candidates: Array[BattleUnit] = engine.legal_single_targets(actor, kind)
	if kind == "enemy_single":
		action.target = _lowest_hp(candidates)
	elif kind == "ally_single":
		action.target = _lowest_hp_ratio(candidates)
	return action


static func _lowest_hp(candidates: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for unit: BattleUnit in candidates:
		if best == null or unit.hp < best.hp:
			best = unit
	return best


static func _lowest_hp_ratio(candidates: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for unit: BattleUnit in candidates:
		if best == null or unit.hp_ratio() < best.hp_ratio():
			best = unit
	return best
