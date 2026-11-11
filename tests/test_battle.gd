extends GutTest
## 3단계 텍스트 전투 테스트: 1대1 → 6대6, 시드 재현, 턴 순서, 진형, 스킬 대기, 버프·디버프.

const SEED: int = 12345

var _db: GameDatabase


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


# ---------- 1대1 ----------

func test_one_on_one_stronger_general_wins() -> void:
	var engine: BattleEngine = _battle([["lu_bu", "S", 1]], [["zhou_cang", "F", 1]], SEED)
	engine.run()
	assert_true(engine.is_finished())
	assert_true(engine.player_won(), "S 여포가 F 주창을 이긴다")
	assert_eq(engine.units[1].hp, 0, "진 쪽은 체력 0")
	assert_gt(engine.units[0].hp, 0)


func test_one_on_one_can_be_lost() -> void:
	var engine: BattleEngine = _battle([["zhou_cang", "F", 1]], [["lu_bu", "S", 1]], SEED)
	assert_eq(engine.run(), BattleEngine.SIDE_ENEMY)
	assert_false(engine.player_won())


# ---------- 시드 재현 ----------

func test_same_seed_gives_identical_battle() -> void:
	var first: BattleEngine = _six_on_six(SEED)
	var second: BattleEngine = _six_on_six(SEED)
	first.run()
	second.run()
	assert_eq(first.log_lines, second.log_lines, "같은 시드면 로그가 한 줄도 다르지 않아야 한다")
	assert_eq(first.winner, second.winner)
	assert_eq(_hp_list(first), _hp_list(second))


func test_frames_record_every_action_for_playback() -> void:
	var engine: BattleEngine = _six_on_six(SEED)
	var start_hp: Array[int] = _hp_list(engine)
	engine.run()
	assert_eq(engine.frames.size(), engine.history.size() + 1, "시작 1장 + 행동마다 1장")
	assert_eq(engine.frames[0]["hp"], start_hp)
	assert_eq(engine.frames[engine.frames.size() - 1]["hp"], _hp_list(engine), "마지막 장은 최종 체력")
	assert_eq(engine.frames[engine.frames.size() - 1]["log_end"], engine.log_lines.size())


func test_different_seed_gives_different_battle() -> void:
	var first: BattleEngine = _six_on_six(1)
	var second: BattleEngine = _six_on_six(2)
	first.run()
	second.run()
	assert_ne(first.log_lines, second.log_lines, "시드가 다르면 피해량이 달라진다")


# ---------- 6대6 ----------

func test_six_on_six_ends_with_one_side_wiped() -> void:
	var engine: BattleEngine = _six_on_six(SEED)
	engine.run()
	assert_true(engine.is_finished())
	assert_false(engine.hit_round_limit, "턴 제한에 걸리지 않고 끝나야 한다")
	var loser: int = BattleEngine.SIDE_ENEMY if engine.player_won() else BattleEngine.SIDE_PLAYER
	assert_eq(engine.living_units(loser).size(), 0, "진 쪽은 전멸")
	assert_gt(engine.living_units(engine.winner).size(), 0)


func test_five_enemies_work() -> void:
	var enemies: Array = [["zhou_cang", "F", 1], ["zhou_cang", "E", 1], ["zhang_jue", "E", 1], ["zhou_cang", "D", 1], ["zhang_jue", "D", 1]]
	var engine: BattleEngine = _battle(_ally_specs(), enemies, SEED)
	assert_eq(engine.living_units(BattleEngine.SIDE_ENEMY).size(), 5)
	engine.run()
	assert_true(engine.player_won())


func test_hp_never_increases_during_battle() -> void:
	var engine: BattleEngine = _six_on_six(SEED)
	var previous: Array[int] = _hp_list(engine)
	while not engine.is_finished():
		engine.advance()
		var current: Array[int] = _hp_list(engine)
		for i: int in current.size():
			assert_true(current[i] <= previous[i], "전투 중 회복은 없다")
		previous = current


func test_starting_hp_is_carried_in() -> void:
	var wounded: BattleUnit = BattleUnit.create(_db, "guan_yu", "C", 1, 10)
	assert_eq(wounded.hp, 10, "이전 전투의 남은 체력으로 시작한다")
	assert_eq(wounded.max_hp, 150)
	var fresh: BattleUnit = BattleUnit.create(_db, "guan_yu", "C", 1)
	assert_eq(fresh.hp, 150)


# ---------- 턴 순서 ----------

func test_sides_alternate_within_a_round() -> void:
	var engine: BattleEngine = _six_on_six(SEED)
	var sides: Array[int] = []
	for i: int in 12:
		var actor: BattleUnit = engine.peek_actor()
		if engine.round_number != 1:
			break
		sides.append(actor.side)
		engine.advance()
	# 아무도 쓰러지지 않은 구간에서는 양 진영이 한 명씩 번갈아 행동한다.
	for i: int in range(1, mini(sides.size(), 6)):
		assert_ne(sides[i], sides[i - 1], "%d번째 행동은 앞 행동과 다른 진영" % (i + 1))


func test_faster_side_acts_first_and_speed_orders_the_line() -> void:
	# 아군: 주창 F(속도 9), 초선 D(속도 15) / 적: 주창 F(속도 9) 하나.
	var engine: BattleEngine = _battle([["zhou_cang", "F", 1], ["diao_chan", "D", 1]], [["zhou_cang", "F", 1]], SEED)
	var first: BattleUnit = engine.peek_actor()
	assert_eq(first.side, BattleEngine.SIDE_PLAYER, "속도 합이 큰 진영이 선공")
	assert_eq(first.general_id, "diao_chan", "진영 안에서는 빠른 장수가 먼저")


func test_everyone_acts_once_per_round() -> void:
	var engine: BattleEngine = _battle([["dong_zhuo", "S", 1], ["dong_zhuo", "A", 1]], [["dong_zhuo", "S", 1]], SEED)
	var actors: Array[BattleUnit] = []
	engine.peek_actor()
	while engine.round_number == 1 and not engine.is_finished():
		actors.append(engine.peek_actor())
		engine.advance()
		engine.peek_actor()
	assert_eq(actors.size(), 3, "1턴에 3명이 한 번씩 행동")
	assert_eq(actors[0].side, BattleEngine.SIDE_PLAYER)
	assert_eq(actors[1].side, BattleEngine.SIDE_ENEMY)
	assert_eq(actors[2].side, BattleEngine.SIDE_PLAYER, "인원이 많은 쪽의 남은 장수가 이어서 행동")


# ---------- 진형 ----------

func test_front_row_protects_back_row() -> void:
	var engine: BattleEngine = _six_on_six(SEED)
	var attacker: BattleUnit = engine.units[0]
	var targets: Array[BattleUnit] = engine.legal_single_targets(attacker, "enemy_single")
	assert_eq(targets.size(), 3)
	for unit: BattleUnit in targets:
		assert_true(unit.is_front, "전열이 살아 있으면 전열만 고를 수 있다")
		assert_eq(unit.side, BattleEngine.SIDE_ENEMY)

	# 적 전열을 모두 쓰러뜨리면 후열을 고를 수 있다.
	for unit: BattleUnit in targets:
		unit.take_damage(unit.max_hp)
	var after: Array[BattleUnit] = engine.legal_single_targets(attacker, "enemy_single")
	assert_eq(after.size(), 3)
	for unit: BattleUnit in after:
		assert_false(unit.is_front)


func test_ai_targets_weakest_legal_enemy() -> void:
	var engine: BattleEngine = _six_on_six(SEED)
	var weakened: BattleUnit = engine.units[7]  # 적 전열 두 번째
	weakened.take_damage(weakened.max_hp - 1)
	var actor: BattleUnit = engine.peek_actor()
	if actor.side != BattleEngine.SIDE_PLAYER:
		engine.advance()
		actor = engine.peek_actor()
	var action: BattleAction = BattleAI.choose(engine, actor)
	if action.target_kind() == "enemy_single":
		assert_eq(action.target, weakened, "가장 약한 대상을 우선 공격")
	else:
		pass_test("첫 행동이 단일 대상이 아니다")


# ---------- 스킬 대기와 버프·디버프 ----------

func test_skill_cooldown_cycle() -> void:
	# 동탁 B의 스킬은 폭군의 일격(대기 2턴) 하나. 스킬 → 기본 → 기본 → 스킬 순서로 쓴다.
	var engine: BattleEngine = _battle([["dong_zhuo", "B", 30]], [["dong_zhuo", "S", 50]], SEED)
	var used: Array[bool] = []
	while used.size() < 4 and not engine.is_finished():
		var actor: BattleUnit = engine.peek_actor()
		engine.advance()
		if actor.side == BattleEngine.SIDE_PLAYER:
			used.append(not engine.history[engine.history.size() - 1].is_basic_attack())
	assert_eq(used, [true, false, false, true] as Array[bool])


func test_stat_mod_applies_and_expires() -> void:
	var unit: BattleUnit = BattleUnit.create(_db, "lu_bu", "B", 1)
	assert_eq(unit.effective_stat("attack"), 35)
	unit.add_mod("charm", "attack", -25.0, 2)
	assert_eq(unit.effective_stat("attack"), 26, "35 × 0.75 = 26.25 → 26")
	unit.add_mod("charm", "attack", -25.0, 2)
	assert_eq(unit.effective_stat("attack"), 26, "같은 스킬은 겹치지 않는다")
	unit.add_mod("changban_roar", "attack", -20.0, 2)
	assert_eq(unit.effective_stat("attack"), 19, "다른 스킬은 더해진다: 35 × 0.55 = 19.25 → 19")
	unit.tick_mods()
	assert_eq(unit.effective_stat("attack"), 19, "1턴 지나도 유지")
	unit.tick_mods()
	assert_eq(unit.effective_stat("attack"), 35, "2턴 뒤 원래대로")


func test_debuff_skill_lowers_enemy_stat_in_battle() -> void:
	# 초선의 매혹: 적 하나의 공격 -25%.
	var engine: BattleEngine = _battle([["diao_chan", "D", 1]], [["dong_zhuo", "B", 1]], SEED)
	var enemy: BattleUnit = engine.units[1]
	assert_eq(engine.peek_actor().general_id, "diao_chan", "초선이 더 빨라 먼저 행동")
	engine.advance()
	assert_eq(enemy.hp, enemy.max_hp, "매혹은 피해가 없다")
	assert_lt(enemy.effective_stat("attack"), enemy.base_stats.attack)


func test_damage_is_at_least_minimum() -> void:
	# 최소 피해를 500으로 올린 설정에서, 약한 주창 F의 공격이 정확히 500을 깎는지 본다.
	var balance_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var battle_data: Dictionary = balance_data["battle"]
	battle_data["min_damage"] = 500
	var allies: Array[BattleUnit] = _make_units([["zhou_cang", "F", 1], ["zhou_cang", "F", 1], ["zhou_cang", "F", 1], ["zhou_cang", "F", 1]])
	var enemies: Array[BattleUnit] = _make_units([["dong_zhuo", "S", 50]])
	var engine: BattleEngine = BattleEngine.new(Balance.new(balance_data), allies, enemies, SEED)
	var enemy: BattleUnit = enemies[0]
	assert_eq(engine.peek_actor().side, BattleEngine.SIDE_PLAYER, "속도 합이 커서 아군 선공")
	engine.advance()
	assert_eq(enemy.hp, enemy.max_hp - 500, "계산된 피해가 작아도 최소 피해는 들어간다")


func test_round_limit_ends_battle_as_defeat() -> void:
	var balance_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var battle_data: Dictionary = balance_data["battle"]
	battle_data["round_limit"] = 2
	var allies: Array[BattleUnit] = [BattleUnit.create(_db, "dong_zhuo", "S", 50)]
	var enemies: Array[BattleUnit] = [BattleUnit.create(_db, "dong_zhuo", "S", 50)]
	var engine: BattleEngine = BattleEngine.new(Balance.new(balance_data), allies, enemies, SEED)
	engine.run()
	assert_true(engine.hit_round_limit)
	assert_eq(engine.round_number, 2)
	assert_false(engine.player_won())


# ---------- 테스트용 도우미 ----------

func _ally_specs() -> Array:
	return [
		["guan_yu", "C", 5], ["zhang_fei", "C", 5], ["sun_quan", "C", 5],
		["liu_bei", "C", 5], ["hua_tuo", "C", 5], ["diao_chan", "C", 5],
	]


func _enemy_specs() -> Array:
	return [
		["dong_zhuo", "B", 3], ["lu_bu", "B", 3], ["zhou_cang", "D", 8],
		["zhang_jue", "C", 5], ["cao_cao", "B", 3], ["zhuge_liang", "B", 3],
	]


func _six_on_six(seed_value: int) -> BattleEngine:
	return _battle(_ally_specs(), _enemy_specs(), seed_value)


func _battle(ally_specs: Array, enemy_specs: Array, seed_value: int) -> BattleEngine:
	return BattleEngine.new(_db.balance, _make_units(ally_specs), _make_units(enemy_specs), seed_value)


func _make_units(specs: Array) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for spec: Array in specs:
		result.append(BattleUnit.create(_db, String(spec[0]), String(spec[1]), int(spec[2])))
	return result


func _hp_list(engine: BattleEngine) -> Array[int]:
	var result: Array[int] = []
	for unit: BattleUnit in engine.units:
		result.append(unit.hp)
	return result
