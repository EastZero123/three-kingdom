class_name BattleUnit
extends RefCounted
## 전투에 나온 장수 한 명의 전투 중 상태 (체력, 버프·디버프, 스킬 대기 턴).
## GeneralDef가 바뀌지 않는 원본이라면, BattleUnit은 전투 동안 계속 바뀌는 사본이다.

var general_id: String = ""
var name: String = ""
var tier: String = ""
var level: int = 1
var role: String = ""

## 진영(BattleEngine.SIDE_PLAYER / SIDE_ENEMY)과 자리 번호. 전투 시작 때 BattleEngine이 정한다.
## slot을 미리 0 이상으로 정해 두면 그 자리를 그대로 쓴다 (쓰러진 장수가 빠져도 남은 장수의 자리 유지).
var side: int = 0
var slot: int = -1
var is_front: bool = true

var max_hp: int = 1
var hp: int = 1
## 버프·디버프가 적용되기 전의 스탯.
var base_stats: Stats = Stats.new()
var skills: Array[SkillDef] = []
## 스킬 id → 남은 재사용 대기 턴. 0이면 쓸 수 있다.
var cooldowns: Dictionary[String, int] = {}
## 적용 중인 버프·디버프 목록. 각 항목: {source, stat, percent, remaining}
var mods: Array[Dictionary] = []


## 데이터에서 전투 유닛을 만든다. current_hp가 0 미만이면 가득 찬 체력으로 시작한다.
## (체력은 라운드가 지나도 유지되므로, 원정 중에는 이전 전투의 남은 체력을 넘긴다.)
## stat_multiplier는 모든 스탯에 곱하는 배율로, 토벌 난이도에 따라 적을 약하게 하거나 강하게 할 때 쓴다.
static func create(db: GameDatabase, p_general_id: String, p_tier: String, p_level: int, current_hp: int = -1, stat_multiplier: float = 1.0) -> BattleUnit:
	var general: GeneralDef = db.get_general(p_general_id)
	if general == null:
		return null
	var tier_def: GeneralTierDef = general.get_tier(p_tier)
	if tier_def == null:
		return null

	var unit: BattleUnit = BattleUnit.new()
	unit.general_id = p_general_id
	unit.name = general.name
	unit.tier = p_tier
	unit.level = p_level
	unit.role = general.role
	unit.base_stats = tier_def.stats_at_level(p_level)
	if stat_multiplier != 1.0:
		for key: String in Stats.KEYS:
			unit.base_stats.set_value(key, maxi(1, roundi(float(unit.base_stats.get_value(key)) * stat_multiplier)))
	unit.max_hp = unit.base_stats.hp
	unit.hp = unit.max_hp if current_hp < 0 else mini(current_hp, unit.max_hp)
	for skill_id: String in tier_def.skill_ids:
		var skill: SkillDef = db.get_skill(skill_id)
		if skill != null:
			unit.skills.append(skill)
			unit.cooldowns[skill_id] = 0
	return unit


func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return float(hp) / float(max_hp)


## 버프·디버프가 반영된 현재 스탯. 최소 1.
func effective_stat(key: String) -> int:
	var total_percent: float = 0.0
	for mod: Dictionary in mods:
		if mod["stat"] == key:
			total_percent += float(mod["percent"])
	var value: float = float(base_stats.get_value(key)) * (1.0 + total_percent / 100.0)
	return maxi(1, roundi(value))


## 버프·디버프를 건다. 같은 스킬의 같은 효과가 이미 걸려 있으면 겹치지 않고 지속 턴만 새로 고친다.
func add_mod(source: String, stat: String, percent: float, duration: int) -> void:
	for mod: Dictionary in mods:
		if mod["source"] == source and mod["stat"] == stat:
			mod["percent"] = percent
			mod["remaining"] = duration
			return
	mods.append({"source": source, "stat": stat, "percent": percent, "remaining": duration})


## 특정 출처의 효과를 없앤다.
func remove_mod(source: String, stat: String) -> void:
	var kept: Array[Dictionary] = []
	for mod: Dictionary in mods:
		if not (mod["source"] == source and mod["stat"] == stat):
			kept.append(mod)
	mods = kept


## 한 턴이 끝날 때 호출한다. 지속 턴을 1 줄이고 끝난 효과를 없앤다.
func tick_mods() -> void:
	var kept: Array[Dictionary] = []
	for mod: Dictionary in mods:
		mod["remaining"] = int(mod["remaining"]) - 1
		if int(mod["remaining"]) > 0:
			kept.append(mod)
	mods = kept


## 피해를 받는다. 체력은 0 아래로 내려가지 않는다.
func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


## 지금 쓸 수 있는 스킬.
func is_skill_ready(skill: SkillDef) -> bool:
	return cooldowns.get(skill.id, 0) == 0


## 행동을 마친 뒤 대기 턴을 갱신한다: 쓴 스킬은 대기에 들어가고, 나머지는 1씩 줄어든다.
func update_cooldowns(used_skill: SkillDef) -> void:
	for skill: SkillDef in skills:
		if skill == used_skill:
			cooldowns[skill.id] = skill.cooldown
		elif cooldowns[skill.id] > 0:
			cooldowns[skill.id] -= 1


func side_label() -> String:
	return "아군" if side == 0 else "적"


## 로그에 쓰는 이름. 예: "아군 관우"
func label() -> String:
	return "%s %s" % [side_label(), name]
