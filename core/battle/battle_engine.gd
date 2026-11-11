class_name BattleEngine
extends RefCounted
## 전투 한 판을 진행하는 순수 로직. 화면과 무관하게 텍스트 로그만 남긴다.
##
## 턴 구조 (기획 확정: 진영별로 번갈아 행동):
##   - 한 턴마다 각 진영이 살아 있는 장수를 속도 순으로 줄 세운다.
##   - 속도 합이 큰 진영이 먼저 시작해, 양 진영이 한 명씩 번갈아 행동한다.
##   - 한쪽이 인원이 많으면 남은 장수가 이어서 행동한다.
##
## 사용 예:
##   var engine: BattleEngine = BattleEngine.new(db.balance, allies, enemies, 12345)
##   engine.run()                      # 끝까지 자동 진행
##   print("\n".join(engine.log_lines))

const SIDE_PLAYER: int = 0
const SIDE_ENEMY: int = 1
const WINNER_NONE: int = -1

## 전투에 참여한 모든 유닛 (아군 먼저, 그다음 적).
var units: Array[BattleUnit] = []
## 현재 턴 번호. 전투 시작 전에는 0.
var round_number: int = 0
## 텍스트 로그.
var log_lines: Array[String] = []
## 지금까지 일어난 행동 기록.
var history: Array[BattleAction] = []
## 승리한 진영. 아직 안 끝났으면 WINNER_NONE.
var winner: int = WINNER_NONE
## 턴 제한에 걸려 끝났는지.
var hit_round_limit: bool = false
## 화면 재생용 기록. 전투 시작 시점과 행동 하나가 끝날 때마다 한 장씩 남긴다.
## 각 항목: {log_end: 그 시점까지의 로그 줄 수, hp: 유닛 순서대로의 체력}
var frames: Array[Dictionary] = []

## 보유효과처럼 아군 전체에 걸리는 지속 효과. 조건이 맞는 동안만 적용된다.
## 각 항목: {source, label, stat, percent, condition_kind, condition_value, announced}
var _auras: Array[Dictionary] = []
## 보유효과는 전투 내내 유지되므로 지속 턴을 충분히 길게 잡고, 매 행동마다 다시 건다.
const AURA_DURATION: int = 1000000

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 이번 턴에 아직 행동하지 않은 유닛 줄.
var _queue: Array[BattleUnit] = []

# 밸런스 수치 (balance.json에서 읽는다).
var _front_row_size: int
var _basic_attack_power: float
var _defense_constant: float
var _damage_variance: float
var _min_damage: int
var _round_limit: int


## 배열의 순서가 곧 자리 번호다. 앞의 front_row_size명이 전열, 나머지가 후열.
func _init(balance: Balance, player_units: Array[BattleUnit], enemy_units: Array[BattleUnit], seed_value: int) -> void:
	_front_row_size = balance.get_int("battle.front_row_size")
	_basic_attack_power = balance.get_float("battle.basic_attack_power")
	_defense_constant = balance.get_float("battle.defense_constant")
	_damage_variance = balance.get_float("battle.damage_variance")
	_min_damage = balance.get_int("battle.min_damage")
	_round_limit = balance.get_int("battle.round_limit")
	# 시드를 정하면 난수 순서가 고정된다. 같은 시드 = 같은 전투 결과.
	_rng.seed = seed_value

	_place(player_units, SIDE_PLAYER)
	_place(enemy_units, SIDE_ENEMY)
	log_lines.append("전투 시작: 아군 %d명 대 적 %d명 (시드 %d)" % [player_units.size(), enemy_units.size(), seed_value])
	_check_winner()
	_record_frame()


## 아군 전체에 지속 효과를 건다. 전투를 시작하기(run/advance) 전에 불러야 한다.
## condition_kind: "" (상시), "allies_alive_at_most", "enemies_alive_at_most", "battle_turn_at_least"
func add_player_aura(source: String, label: String, stat: String, percent: float, condition_kind: String = "", condition_value: int = 0) -> void:
	_auras.append({
		"source": "aura:" + source, "label": label, "stat": stat, "percent": percent,
		"condition_kind": condition_kind, "condition_value": condition_value, "announced": false,
	})


func is_finished() -> bool:
	return winner != WINNER_NONE


func player_won() -> bool:
	return winner == SIDE_PLAYER


## 전투가 끝날 때까지 양 진영 모두 AI로 자동 진행한다. 승리 진영을 돌려준다.
func run() -> int:
	while not is_finished():
		advance()
	return winner


## 다음에 행동할 유닛. 전투가 끝났으면 null.
func peek_actor() -> BattleUnit:
	if is_finished():
		return null
	_drop_dead_from_queue()
	if _queue.is_empty():
		_start_round()
		if is_finished():
			return null
	return _queue[0]


## 행동 하나를 진행한다. action이 null이면 AI가 고른다.
## 나중에 플레이어가 직접 고르는 방식을 붙일 때는 peek_actor()로 차례를 확인하고 action을 넘기면 된다.
func advance(action: BattleAction = null) -> void:
	var actor: BattleUnit = peek_actor()
	if actor == null:
		return
	_refresh_auras()
	if action == null:
		action = BattleAI.choose(self, actor)
	elif action.actor != actor:
		push_error("지금은 %s의 차례다" % actor.label())
		return

	_queue.pop_front()
	action.round_number = round_number
	history.append(action)
	_execute(action)
	actor.update_cooldowns(action.skill)
	_check_winner()
	_record_frame()


func _record_frame() -> void:
	var hp_list: Array[int] = []
	for unit: BattleUnit in units:
		hp_list.append(unit.hp)
	frames.append({"log_end": log_lines.size(), "hp": hp_list})


func living_units(side: int) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit: BattleUnit in units:
		if unit.side == side and unit.is_alive():
			result.append(unit)
	return result


## 단일 대상 스킬로 고를 수 있는 대상 목록. 전체·열 대상 스킬이면 빈 배열.
## 적 하나를 고를 때는 전열이 살아 있는 동안 후열을 고를 수 없다 (전열이 후열을 지킨다).
func legal_single_targets(actor: BattleUnit, kind: String) -> Array[BattleUnit]:
	match kind:
		"enemy_single":
			return _row_or_fallback(_opponent(actor.side), true)
		"ally_single":
			return living_units(actor.side)
	return []


# ---------- 내부 구현 ----------

func _place(side_units: Array[BattleUnit], side: int) -> void:
	for i: int in side_units.size():
		var unit: BattleUnit = side_units[i]
		unit.side = side
		if unit.slot < 0:
			unit.slot = i
		unit.is_front = unit.slot < _front_row_size
		units.append(unit)


func _opponent(side: int) -> int:
	return SIDE_ENEMY if side == SIDE_PLAYER else SIDE_PLAYER


## 한 진영의 전열(또는 후열) 생존자. 그 열이 비었으면 다른 열을 대신 돌려준다.
func _row_or_fallback(side: int, front: bool) -> Array[BattleUnit]:
	var wanted: Array[BattleUnit] = []
	var other: Array[BattleUnit] = []
	for unit: BattleUnit in living_units(side):
		if unit.is_front == front:
			wanted.append(unit)
		else:
			other.append(unit)
	return wanted if not wanted.is_empty() else other


func _start_round() -> void:
	if round_number >= _round_limit:
		hit_round_limit = true
		winner = SIDE_ENEMY
		log_lines.append("전투 종료: %d턴 제한에 걸려 아군 패배" % _round_limit)
		return
	# 이전 턴이 끝났으므로 버프·디버프 지속 턴을 줄인다.
	if round_number > 0:
		for unit: BattleUnit in units:
			unit.tick_mods()
	round_number += 1
	log_lines.append("── %d턴 ──" % round_number)
	# 턴 수 조건이 바뀌었을 수 있고, 속도 효과가 행동 순서에 반영되도록 줄을 세우기 전에 갱신한다.
	_refresh_auras()
	_queue = _build_queue()


## 지속 효과의 조건을 다시 확인해, 맞으면 아군에게 걸고 아니면 거둔다.
func _refresh_auras() -> void:
	for aura: Dictionary in _auras:
		var active: bool = _aura_condition_met(aura)
		for unit: BattleUnit in units:
			if unit.side != SIDE_PLAYER:
				continue
			if active and unit.is_alive():
				unit.add_mod(String(aura["source"]), String(aura["stat"]), float(aura["percent"]), AURA_DURATION)
			else:
				unit.remove_mod(String(aura["source"]), String(aura["stat"]))
		if active and not bool(aura["announced"]):
			aura["announced"] = true
			log_lines.append("보유효과 발동: %s — 아군 %s %+d%%" % [aura["label"], _stat_label(String(aura["stat"])), roundi(float(aura["percent"]))])


func _aura_condition_met(aura: Dictionary) -> bool:
	var value: int = int(aura["condition_value"])
	match String(aura["condition_kind"]):
		"":
			return true
		"allies_alive_at_most":
			return living_units(SIDE_PLAYER).size() <= value
		"enemies_alive_at_most":
			return living_units(SIDE_ENEMY).size() <= value
		"battle_turn_at_least":
			return round_number >= value
	push_error("알 수 없는 보유효과 조건: %s" % aura["condition_kind"])
	return false


## 이번 턴의 행동 순서를 만든다: 진영별 속도 순 줄을 한 명씩 번갈아 섞는다.
func _build_queue() -> Array[BattleUnit]:
	var player_line: Array[BattleUnit] = _speed_line(SIDE_PLAYER)
	var enemy_line: Array[BattleUnit] = _speed_line(SIDE_ENEMY)
	var first: Array[BattleUnit] = player_line
	var second: Array[BattleUnit] = enemy_line
	# 속도 합이 큰 진영이 선공. 같으면 아군이 선공.
	if _total_speed(enemy_line) > _total_speed(player_line):
		first = enemy_line
		second = player_line

	var queue: Array[BattleUnit] = []
	for i: int in maxi(first.size(), second.size()):
		if i < first.size():
			queue.append(first[i])
		if i < second.size():
			queue.append(second[i])
	return queue


func _speed_line(side: int) -> Array[BattleUnit]:
	var line: Array[BattleUnit] = living_units(side)
	# sort_custom: 비교 함수를 넘겨 정렬한다. 속도가 빠른 순, 같으면 자리 번호가 앞선 순.
	line.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		var speed_a: int = a.effective_stat("speed")
		var speed_b: int = b.effective_stat("speed")
		if speed_a != speed_b:
			return speed_a > speed_b
		return a.slot < b.slot
	)
	return line


func _total_speed(line: Array[BattleUnit]) -> int:
	var total: int = 0
	for unit: BattleUnit in line:
		total += unit.effective_stat("speed")
	return total


func _drop_dead_from_queue() -> void:
	while not _queue.is_empty() and not _queue[0].is_alive():
		_queue.pop_front()


## 행동의 실제 대상 목록을 정한다.
func _resolve_targets(action: BattleAction) -> Array[BattleUnit]:
	var actor: BattleUnit = action.actor
	var enemy_side: int = _opponent(actor.side)
	match action.target_kind():
		"enemy_single", "ally_single":
			var legal: Array[BattleUnit] = legal_single_targets(actor, action.target_kind())
			if legal.has(action.target):
				return [action.target]
			push_error("%s: 고를 수 없는 대상이다" % actor.label())
			return []
		"enemy_front_row":
			return _row_or_fallback(enemy_side, true)
		"enemy_back_row":
			return _row_or_fallback(enemy_side, false)
		"enemy_all":
			return living_units(enemy_side)
		"ally_all":
			return living_units(actor.side)
		"self":
			return [actor]
	return []


func _execute(action: BattleAction) -> void:
	var actor: BattleUnit = action.actor
	var targets: Array[BattleUnit] = _resolve_targets(action)
	var skill: SkillDef = action.skill
	var skill_name: String = "기본 공격" if skill == null else skill.name
	var power: float = _basic_attack_power if skill == null else skill.power
	var scaling_stat: String = "attack" if skill == null else skill.scaling_stat

	if power > 0.0:
		for target: BattleUnit in targets:
			var damage: int = _roll_damage(actor, target, power, scaling_stat)
			target.take_damage(damage)
			log_lines.append("%s → %s: %s, 피해 %d (남은 체력 %d/%d)" % [
				actor.label(), target.label(), skill_name, damage, target.hp, target.max_hp,
			])
			if not target.is_alive():
				log_lines.append("  %s 쓰러짐" % target.label())

	if skill != null and not skill.effects.is_empty():
		var effect_texts: Array[String] = []
		for effect: SkillEffectDef in skill.effects:
			effect_texts.append("%s %+d%% (%d턴)" % [_stat_label(effect.stat), roundi(effect.percent), effect.duration])
			for target: BattleUnit in targets:
				if target.is_alive():
					target.add_mod(skill.id, effect.stat, effect.percent, effect.duration)
		log_lines.append("%s: %s — %s에게 %s" % [actor.label(), skill_name, _targets_label(action, targets), ", ".join(effect_texts)])


## 피해량 계산.
##   기본 피해 = 공격 측 스탯 × 배율 × K / (K + 방어 측 스탯)      (K = battle.defense_constant)
##   공격(attack) 스킬은 상대 방어(defense)로, 지략(intellect) 스킬은 상대 지략으로 막는다.
##   여기에 ±damage_variance 범위의 난수를 곱하고, 최소 min_damage를 보장한다.
func _roll_damage(actor: BattleUnit, target: BattleUnit, power: float, scaling_stat: String) -> int:
	var offense: float = float(actor.effective_stat(scaling_stat))
	var guard_stat: String = "defense" if scaling_stat == "attack" else "intellect"
	var guard: float = float(target.effective_stat(guard_stat))
	var base_damage: float = offense * power * _defense_constant / (_defense_constant + guard)
	var variance: float = _rng.randf_range(1.0 - _damage_variance, 1.0 + _damage_variance)
	return maxi(_min_damage, roundi(base_damage * variance))


func _check_winner() -> void:
	if is_finished():
		return
	var player_alive: bool = not living_units(SIDE_PLAYER).is_empty()
	var enemy_alive: bool = not living_units(SIDE_ENEMY).is_empty()
	if player_alive and enemy_alive:
		return
	winner = SIDE_PLAYER if player_alive else SIDE_ENEMY
	log_lines.append("전투 종료: %s (%d턴)" % ["아군 승리" if player_won() else "아군 패배", round_number])


func _stat_label(stat: String) -> String:
	match stat:
		"hp":
			return "체력"
		"attack":
			return "공격"
		"defense":
			return "방어"
		"speed":
			return "속도"
		"intellect":
			return "지략"
	return stat


func _targets_label(action: BattleAction, targets: Array[BattleUnit]) -> String:
	match action.target_kind():
		"enemy_all":
			return "상대 전체"
		"ally_all":
			return "자기 진영 전체"
		"enemy_front_row":
			return "상대 전열"
		"enemy_back_row":
			return "상대 후열"
		"self":
			return "자신"
	var names: Array[String] = []
	for unit: BattleUnit in targets:
		names.append(unit.label())
	return ", ".join(names)
