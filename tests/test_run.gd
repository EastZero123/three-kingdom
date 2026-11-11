extends GutTest
## 4단계 원정 루프 테스트: 토벌 선택지 3개, 10라운드, 해 넘김, 체력 유지, 패배 처리, 시드 재현.

const SEED: int = 12345

var _db: GameDatabase


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


# ---------- 데이터 ----------

func test_enemy_and_run_data_load() -> void:
	assert_eq(_db.errors, [] as Array[String])
	assert_eq(_db.starting_roster.size(), 6)
	assert_eq(_db.expedition_types.size(), 5, "일반 3종 + 특별 2종")
	assert_eq(_db.era_for_year(184).id, "yellow_turban_rising")
	assert_eq(_db.era_for_year(190).id, "warlords")
	assert_eq(_db.era_for_year(300).id, "three_kingdoms", "마지막 시대는 계속 이어진다")


func test_bad_enemy_data_is_reported() -> void:
	var enemies_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var eras: Array = enemies_data["eras"]
	var first_era: Dictionary = eras[0]
	var second_era: Dictionary = eras[1]
	var pool: Array = first_era["pool"]
	pool.append({"general_id": "nobody", "tier": "F", "weight": 1})
	pool.append({"general_id": "lu_bu", "tier": "F", "weight": 1})
	second_era["year_from"] = 188  # 186~187년이 비게 된다
	var db: GameDatabase = _load_with(enemies_data)
	assert_true(_has_error(db, "없는 장수 'nobody'"))
	assert_true(_has_error(db, "장수 'lu_bu'에게 F 티어가 없다"))
	assert_true(_has_error(db, "사이 연도가 이어지지 않는다"))


func test_era_with_too_few_generals_is_reported() -> void:
	var enemies_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var eras: Array = enemies_data["eras"]
	var first_era: Dictionary = eras[0]
	first_era["pool"] = [{"general_id": "zhou_cang", "tier": "F", "weight": 1}]
	var db: GameDatabase = _load_with(enemies_data)
	assert_true(_has_error(db, "적 7명을 채울 수 없다"))


# ---------- 편성 ----------

func test_formations_vary_count_within_difficulty() -> void:
	var counts_by_type: Dictionary[String, Dictionary] = {}
	var names_by_type: Dictionary[String, Dictionary] = {}
	for s: int in 60:
		for expedition: Expedition in ExpeditionGenerator.generate(_db, s, 186, 1 + s % 10):
			var type_id: String = expedition.type.id
			if not counts_by_type.has(type_id):
				counts_by_type[type_id] = {}
				names_by_type[type_id] = {}
			counts_by_type[type_id][expedition.enemy_count()] = true
			names_by_type[type_id][expedition.formation.name] = true
	for type_id: String in ["easy", "normal", "hard"]:
		assert_gt(counts_by_type[type_id].size(), 2, "%s: 같은 난이도 안에서 인원이 여러 가지 (%s)" % [type_id, counts_by_type[type_id].keys()])
		assert_gt(names_by_type[type_id].size(), 1, "%s: 편성이 여러 가지" % type_id)
	assert_true(counts_by_type["easy"].has(7) and counts_by_type["easy"].has(3), "쉬움에도 7명 대군과 3명 소수가 있다")


func test_formation_values_override_type() -> void:
	var hard: ExpeditionTypeDef = null
	for type_def: ExpeditionTypeDef in _db.expedition_types:
		if type_def.id == "hard":
			hard = type_def
	var elite: FormationDef = null
	var main_force: FormationDef = null
	for formation: FormationDef in hard.formations:
		if formation.name == "정예 소수":
			elite = formation
		elif formation.name == "주력군":
			main_force = formation
	assert_eq(elite.enemy_count_max, 4)
	assert_eq(elite.level_offset, 3, "편성 값이 토벌 종류 값을 덮어쓴다")
	assert_almost_eq(elite.tier_weight_per_step, 2.0, 0.001)
	assert_eq(main_force.enemy_count_min, 6, "적지 않은 값은 토벌 종류에서 물려받는다")
	assert_almost_eq(main_force.enemy_stat_multiplier, 0.8, 0.001)


func test_expedition_uses_formation_values() -> void:
	for s: int in 40:
		for expedition: Expedition in ExpeditionGenerator.generate(_db, s, 190, 1):
			var expected_level: int = clampi(_db.enemy_base_level(190, 1) + expedition.formation.level_offset, 1, 50)
			assert_eq(expedition.enemy_level, expected_level)
			if not expedition.formation.name.is_empty():
				assert_string_contains(expedition.title, expedition.formation.name, "이름에 편성이 붙는다")


func test_formation_count_outside_battle_range_is_reported() -> void:
	var enemies_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var types: Array = enemies_data["expedition_types"]
	var easy: Dictionary = types[0]
	var formations: Array = easy["formations"]
	var first: Dictionary = formations[0]
	first["enemy_count_max"] = 9
	var db: GameDatabase = _load_with(enemies_data)
	assert_true(_has_error(db, "적 인원이 3~7명 범위를 벗어난다"))


func test_battle_with_seven_or_three_enemies_works() -> void:
	for s: int in 30:
		var run: ExpeditionRun = _strong_run()
		run.run_seed = s
		for i: int in 3:
			var expedition: Expedition = run.current_choices()[i]
			if expedition.enemy_count() == 7 or expedition.enemy_count() == 3:
				var battle: BattleEngine = run.choose(i)
				assert_true(battle.is_finished())
				assert_eq(battle.living_units(BattleEngine.SIDE_ENEMY).size() + _dead_enemies(battle), expedition.enemy_count())
				return
	fail_test("3명이나 7명 편성을 찾지 못했다")


# ---------- 런 시작 ----------

func test_run_starts_at_first_year_with_full_roster() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_eq(run.year, 184)
	assert_eq(run.round_number, 1)
	assert_false(run.is_over())
	assert_eq(run.years_survived(), 0)
	assert_eq(run.phase, ExpeditionRun.PHASE_EXPEDITION)
	assert_eq(run.roster.active_count, 6, "출전 슬롯 6칸")
	assert_eq(run.roster.reserve_count(), 2, "보유효과 슬롯 기본 2칸")
	assert_eq(run.roster.member_count(), 6)
	for member: RosterMember in run.roster.members():
		assert_eq(member.hp, member.max_hp, "시작할 때는 체력이 가득")
	assert_eq(run.roster.get_member(0).general_id, "guan_yu")
	assert_eq(run.roster.get_member(0).max_hp, 150)


# ---------- 토벌 선택지 ----------

func test_three_choices_with_valid_enemies() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var choices: Array[Expedition] = run.current_choices()
	assert_eq(choices.size(), 3, "토벌 선택지는 3개")
	var type_ids: Dictionary[String, bool] = {}
	for expedition: Expedition in choices:
		type_ids[expedition.type.id] = true
		assert_between(expedition.enemy_count(), 3, 7, "적은 3~7명")
		assert_between(expedition.enemy_count(), expedition.formation.enemy_count_min, expedition.formation.enemy_count_max, "편성의 인원 범위 안")
		var seen: Dictionary[String, bool] = {}
		for enemy: Dictionary in expedition.enemies:
			var general_id: String = enemy["general_id"]
			assert_false(seen.has(general_id), "한 원정대에 같은 장수는 없다")
			seen[general_id] = true
			assert_true(_db.get_general(general_id).has_tier(String(enemy["tier"])))
			assert_true(_in_pool(expedition.era, general_id, String(enemy["tier"])), "그 시대의 후보에서만 나온다")
		assert_string_contains(expedition.summary(_db), expedition.type.name)
	assert_eq(type_ids.size(), 3, "난이도가 서로 다른 선택지 3개")


func test_choices_are_stable_until_chosen() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_eq(_summaries(run.current_choices()), _summaries(run.current_choices()), "다시 봐도 같은 선택지")


func test_choices_depend_on_seed_year_and_round() -> void:
	var base: Array[String] = _summaries(ExpeditionGenerator.generate(_db, SEED, 184, 1))
	assert_eq(base, _summaries(ExpeditionGenerator.generate(_db, SEED, 184, 1)), "같은 시드·연도·라운드면 같다")
	assert_ne(base, _summaries(ExpeditionGenerator.generate(_db, SEED + 1, 184, 1)))
	assert_ne(base, _summaries(ExpeditionGenerator.generate(_db, SEED, 184, 2)))
	assert_ne(base, _summaries(ExpeditionGenerator.generate(_db, SEED, 185, 1)))


func test_enemies_get_stronger_over_years() -> void:
	assert_gt(_db.enemy_base_level(190, 1), _db.enemy_base_level(184, 1))
	assert_gt(_db.enemy_base_level(184, 10), _db.enemy_base_level(184, 1))
	# 190년대에는 B티어 장수가 나온다 (184년에는 없다).
	assert_false(_has_tier_in_choices(184, "B"))
	assert_true(_has_tier_in_choices(195, "B"))
	assert_true(_has_tier_in_choices(230, "S"))


func test_front_roles_stand_in_front() -> void:
	for round_number: int in range(1, 11):
		for expedition: Expedition in ExpeditionGenerator.generate(_db, SEED, 186, round_number):
			var seen_back_role: bool = false
			for enemy: Dictionary in expedition.enemies:
				var is_front_role: bool = ExpeditionGenerator.FRONT_ROLES.has(_db.get_general(String(enemy["general_id"])).role)
				if not is_front_role:
					seen_back_role = true
				elif seen_back_role:
					fail_test("무장·수비가 책사·보조보다 뒤에 섰다")
	pass_test("무장·수비가 항상 앞자리")


# ---------- 체력 유지 ----------

func test_hp_is_kept_between_rounds() -> void:
	var run: ExpeditionRun = _strong_run()
	var battle: BattleEngine = run.choose(0)
	assert_true(battle.player_won())
	var after_first: Array[int] = _hp_list(run)
	for i: int in run.roster.active_count:
		assert_eq(run.roster.get_member(i).hp, battle.units[i].hp, "전투가 끝난 체력이 그대로 로스터에 남는다")
	run.choose_reward(0, 0)
	assert_eq(_hp_list(run), after_first, "보상을 받고 다음 라운드가 돼도 체력은 그대로")
	run.choose(0)
	var after_second: Array[int] = _hp_list(run)
	for i: int in after_first.size():
		assert_true(after_second[i] <= after_first[i], "라운드가 지나도 회복되지 않는다")


func test_dead_members_leave_the_roster() -> void:
	# 시작 로스터에 든든한 전열(동탁 S)을 세우고, 전열 두 번째 자리에 체력 1짜리 장수를 둔다.
	# 적은 가장 약한 대상을 먼저 노리므로 이 장수가 쓰러진다.
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(0, RosterMember.create(_db, "dong_zhuo", "S", 1))
	var weak: RosterMember = RosterMember.create(_db, "zhou_cang", "F", 1)
	weak.hp = 1
	run.roster.set_member(1, weak)
	var battle: BattleEngine = run.choose(0)
	assert_true(battle.player_won())
	assert_null(run.roster.get_member(1), "쓰러진 장수는 전사해 자리가 빈다")
	assert_eq(run.roster.active_count, 6, "슬롯 수는 그대로")
	assert_eq(run.roster.member_count(), 5)
	assert_eq(run.fallen.size(), 1)
	assert_eq(run.fallen[0], {"general_id": "zhou_cang", "tier": "F", "level": 1, "year": 184, "round": 1})
	assert_false(run.is_over(), "이겼으면 런은 계속된다")
	assert_string_contains(run.log_lines[run.log_lines.size() - 1], "전사: 주창")


func test_empty_slots_are_skipped_and_positions_kept() -> void:
	var run: ExpeditionRun = _strong_run()
	run.roster.set_member(1, null)
	var battle: BattleEngine = run.choose(0)
	var allies: Array[BattleUnit] = []
	for unit: BattleUnit in battle.units:
		if unit.side == BattleEngine.SIDE_PLAYER:
			allies.append(unit)
	assert_eq(allies.size(), 5, "빈 칸은 출전하지 않는다")
	assert_eq(allies[1].slot, 2, "남은 장수는 원래 자리를 지킨다")
	assert_false(allies[3].is_front, "후열 장수가 전열로 밀려 올라오지 않는다")


func test_everyone_dies_on_defeat() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	for member: RosterMember in run.roster.members():
		member.hp = 1
	run.choose(2)
	assert_true(run.is_over())
	assert_eq(run.roster.member_count(), 0)
	assert_eq(run.fallen.size(), 6, "전멸하면 모두 전사 기록에 남는다")


# ---------- 라운드와 해 넘김 ----------

func test_winning_advances_round() -> void:
	var run: ExpeditionRun = _strong_run()
	run.choose(1)
	assert_eq(run.phase, ExpeditionRun.PHASE_REWARD, "이기면 보상을 고를 차례")
	assert_eq(run.round_number, 1, "보상을 고르기 전에는 라운드가 넘어가지 않는다")
	assert_null(run.choose(0), "보상을 고르기 전에는 다음 토벌을 고를 수 없다")
	assert_push_error("고를 수 없는 토벌 번호")
	assert_true(run.choose_reward(0, 0))
	assert_eq(run.phase, ExpeditionRun.PHASE_EXPEDITION)
	assert_eq(run.round_number, 2)
	assert_eq(run.year, 184)
	assert_eq(run.history.size(), 2)
	assert_eq(run.history[0], {"type": "expedition", "index": 1})
	assert_eq(run.history[1], {"type": "reward", "index": 0, "target": 0})


func test_ten_rounds_make_a_year() -> void:
	var run: ExpeditionRun = _strong_run()
	for i: int in 9:
		_win(run)
	assert_eq(run.year, 184)
	assert_eq(run.round_number, 10, "9번 이기면 10라운드")
	_win(run)
	assert_eq(run.year, 185, "10라운드를 마치면 해가 넘어간다")
	assert_eq(run.round_number, 1)
	assert_eq(run.years_survived(), 1)
	assert_false(run.is_over())


func test_enemy_pool_changes_with_year() -> void:
	var run: ExpeditionRun = _strong_run()
	assert_eq(run.current_choices()[0].era.id, "yellow_turban_rising")
	for i: int in 20:
		_win(run)
	assert_eq(run.year, 186)
	assert_eq(run.current_choices()[0].era.id, "yellow_turban_remnants", "해가 지나면 등장 세력이 바뀐다")


# ---------- 패배 ----------

func test_defeat_ends_run() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	for member: RosterMember in run.roster.members():
		member.hp = 1
	var battle: BattleEngine = run.choose(2)
	assert_false(battle.player_won())
	assert_true(run.is_over(), "기본 설정: 전투에서 지면 런 종료")
	assert_eq(run.phase, ExpeditionRun.PHASE_OVER)
	assert_eq(run.years_survived(), 0)
	assert_eq(run.current_choices().size(), 0, "끝난 런에는 선택지가 없다")
	assert_eq(run.current_rewards().size(), 0, "지면 보상이 없다")
	assert_eq(run.year, 184)
	assert_eq(run.round_number, 1, "진 라운드에서 멈춘다")


# ---------- 시드 재현 ----------

func test_same_seed_and_choices_reproduce_the_run() -> void:
	# 토벌과 보상을 번갈아 바꿔 가며 고르고, 중간에 슬롯도 한 번 옮긴다.
	var original: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	original.swap_slots(0, 6)
	var step: int = 0
	while not original.is_over() and step < 30:
		original.choose(step % 3)
		if original.phase == ExpeditionRun.PHASE_REWARD:
			var reward_index: int = step % 3
			var target: int = _first_member_slot(original) if original.reward_needs_target(reward_index) else -1
			original.choose_reward(reward_index, target)
		step += 1
	assert_gt(original.history.size(), 3)

	var copy: ExpeditionRun = ExpeditionRun.replay(_db, SEED, original.history)
	assert_eq(copy.history, original.history)
	assert_eq(copy.merge_progress, original.merge_progress)
	assert_eq(copy.phase, original.phase)
	assert_eq(copy.log_lines, original.log_lines)
	assert_eq(_hp_list(copy), _hp_list(original))
	assert_eq(copy.year, original.year)
	assert_eq(copy.round_number, original.round_number)


func test_different_choices_change_the_battle() -> void:
	var first: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var second: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_ne(first.choose(0).log_lines, second.choose(2).log_lines)


func test_derived_seeds_are_stable_and_distinct() -> void:
	assert_eq(SeedUtil.derive(SEED, 184, 1, 1), SeedUtil.derive(SEED, 184, 1, 1))
	var seen: Dictionary[int, bool] = {}
	for year: int in range(184, 194):
		for round_number: int in range(1, 11):
			for choice: int in range(0, 4):
				var derived: int = SeedUtil.derive(SEED, year, round_number, choice)
				assert_true(derived >= 0)
				seen[derived] = true
	assert_eq(seen.size(), 400, "연도·라운드·선택지마다 다른 시드")


# ---------- 테스트용 도우미 ----------

## 계속 이길 수 있도록 로스터를 만렙 최고 티어 장수로 바꾼 런.
func _strong_run() -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var specs: Array = [["lu_bu", "S"], ["dong_zhuo", "S"], ["guan_yu", "A"], ["zhuge_liang", "S"], ["cao_cao", "S"], ["liu_bei", "A"]]
	for i: int in specs.size():
		var spec: Array = specs[i]
		run.roster.set_member(i, RosterMember.create(_db, String(spec[0]), String(spec[1]), 50))
	return run


## 0번 토벌을 골라 이기고, 경험치 보상을 첫 장수에게 준다.
func _win(run: ExpeditionRun) -> void:
	var battle: BattleEngine = run.choose(0)
	assert_true(battle.player_won(), "강한 로스터는 이겨야 한다")
	run.choose_reward(0, _first_member_slot(run))


func _dead_enemies(battle: BattleEngine) -> int:
	var count: int = 0
	for unit: BattleUnit in battle.units:
		if unit.side == BattleEngine.SIDE_ENEMY and not unit.is_alive():
			count += 1
	return count


func _first_member_slot(run: ExpeditionRun) -> int:
	for slot: int in run.roster.size():
		if run.roster.get_member(slot) != null:
			return slot
	return -1


func _load_with(enemies_data: Dictionary) -> GameDatabase:
	return GameDatabase.from_dicts(
		JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/generals.json")),
		enemies_data,
		JSON.parse_string(FileAccess.get_file_as_string("res://data/run.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/chests.json")),
	)


func _has_error(db: GameDatabase, fragment: String) -> bool:
	for message: String in db.errors:
		if message.contains(fragment):
			return true
	return false


func _in_pool(era: EraDef, general_id: String, tier: String) -> bool:
	for entry: Dictionary in era.pool:
		if entry["general_id"] == general_id and entry["tier"] == tier:
			return true
	return false


func _summaries(choices: Array[Expedition]) -> Array[String]:
	var result: Array[String] = []
	for expedition: Expedition in choices:
		result.append(expedition.summary(_db))
	return result


func _has_tier_in_choices(year: int, tier: String) -> bool:
	for round_number: int in range(1, 11):
		for expedition: Expedition in ExpeditionGenerator.generate(_db, SEED, year, round_number):
			for enemy: Dictionary in expedition.enemies:
				if enemy["tier"] == tier:
					return true
	return false


func _hp_list(run: ExpeditionRun) -> Array[int]:
	var result: Array[int] = []
	for member: RosterMember in run.roster.slots:
		result.append(-1 if member == null else member.hp)
	return result
