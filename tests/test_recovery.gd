extends GutTest
## 7단계 테스트: 힐러 치유, 보유효과 발동, 보유효과 슬롯 확장, 보물상자, 특별 토벌, 해 넘김 상자.

const SEED: int = 12345
const FIRST_RESERVE_SLOT: int = 6

var _db: GameDatabase


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


# ---------- 데이터 ----------

func test_chest_data_loads() -> void:
	assert_eq(_db.errors, [] as Array[String])
	assert_eq(_db.chests.size(), 4)
	assert_eq(_db.year_end_chest_id, "imperial_gift")
	assert_true(_db.get_chest("secret_manual").needs_target())
	assert_false(_db.get_chest("supply_crate").needs_target())


# ---------- 힐러 치유 ----------

func test_healer_in_battle_heals_one_wounded_after_battle() -> void:
	var run: ExpeditionRun = _healer_run()
	_fight_and_take_exp(run)
	assert_eq(_heal_lines(run).size(), 1, "출전한 힐러 1명 → 치유 1회")
	assert_string_contains(_heal_lines(run)[0], "화타 →")


func test_heal_amount_is_ratio_of_max_hp() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var target: RosterMember = run.roster.get_member(0)  # 관우 150
	target.hp = 10
	run._battle_healers = [run.roster.get_member(3)]  # 화타
	run._heal_after_battle()
	assert_eq(target.hp, 55, "최대 체력 150의 30% = 45 회복")
	assert_eq(run.roster.get_member(3).hp, run.roster.get_member(3).max_hp)


func test_heal_never_exceeds_max_and_skips_full_and_dead() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var target: RosterMember = run.roster.get_member(1)
	target.hp = target.max_hp - 3
	run._battle_healers = [run.roster.get_member(3)]
	run._heal_after_battle()
	assert_eq(target.hp, target.max_hp, "최대 체력을 넘지 않는다")
	for member: RosterMember in run.roster.members():
		assert_eq(member.hp, member.max_hp, "다친 장수가 1명뿐이면 그 장수만 치유")


func test_lower_hp_ratio_is_healed_more_often() -> void:
	var low: int = 0
	for s: int in 200:
		var run: ExpeditionRun = ExpeditionRun.start(_db, s)
		run.roster.get_member(0).hp = 15   # 10%
		run.roster.get_member(1).hp = 144  # 90%
		run._battle_healers = [run.roster.get_member(3)]
		run._heal_after_battle()
		if run.roster.get_member(0).hp > 15:
			low += 1
	# 가중치 0.9 대 0.1 → 약 90%
	assert_between(low, 160, 199, "체력 비율이 낮은 장수가 훨씬 자주 뽑힌다 (%d/200)" % low)


func test_two_healers_stack() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.get_member(0).hp = 10
	run.roster.get_member(1).hp = 10
	var second_healer: RosterMember = RosterMember.create(_db, "hua_tuo", "C", 1)
	run._battle_healers = [run.roster.get_member(3), second_healer]
	run.roster.set_member(FIRST_RESERVE_SLOT, second_healer)
	run._heal_after_battle()
	assert_eq(_heal_lines(run).size(), 2, "힐러 중첩 허용(기본값): 2명이면 2회")


func test_healer_stacking_can_be_turned_off() -> void:
	var db: GameDatabase = _db_with_balance("healer", "stacking", false)
	var run: ExpeditionRun = ExpeditionRun.start(db, SEED)
	run.roster.get_member(0).hp = 10
	run.roster.get_member(1).hp = 10
	var second_healer: RosterMember = RosterMember.create(db, "hua_tuo", "C", 1)
	run.roster.set_member(FIRST_RESERVE_SLOT, second_healer)
	run._battle_healers = [run.roster.get_member(3), second_healer]
	run._heal_after_battle()
	assert_eq(_heal_lines(run).size(), 1)


func test_healer_in_reserve_does_not_heal() -> void:
	var run: ExpeditionRun = _healer_run()
	run.swap_slots(3, FIRST_RESERVE_SLOT)  # 화타를 보유효과 슬롯으로
	_fight_and_take_exp(run)
	assert_eq(_heal_lines(run).size(), 0, "치유는 출전 슬롯에 있을 때만")


func test_non_healer_does_not_heal() -> void:
	var run: ExpeditionRun = _healer_run()
	run.roster.set_member(3, RosterMember.create(_db, "zhang_jue", "C", 50))
	_fight_and_take_exp(run)
	assert_eq(_heal_lines(run).size(), 0)


# ---------- 보유효과 ----------

func test_passive_reserve_effect_buffs_active_units() -> void:
	# 관우 B(천리행의 의리): 출전 장수 공격 +6%
	var run: ExpeditionRun = _strong_run()
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "guan_yu", "B", 1))
	var battle: BattleEngine = run.choose(0)
	assert_true(_has_line(battle.log_lines, "보유효과 발동: 관우의 천리행의 의리 — 아군 공격 +6%"))


func test_passive_effect_value_in_battle() -> void:
	var allies: Array[BattleUnit] = [BattleUnit.create(_db, "lu_bu", "B", 1)]
	var enemies: Array[BattleUnit] = [BattleUnit.create(_db, "dong_zhuo", "S", 50)]
	var battle: BattleEngine = BattleEngine.new(_db.balance, allies, enemies, SEED)
	battle.add_player_aura("guan_yu", "시험", "attack", 10.0)
	battle.peek_actor()
	assert_eq(allies[0].effective_stat("attack"), 39, "35 × 1.1 = 38.5 → 39")
	assert_eq(enemies[0].effective_stat("attack"), enemies[0].base_stats.attack, "적에게는 걸리지 않는다")


func test_conditional_effect_turns_on_when_condition_met() -> void:
	var allies: Array[BattleUnit] = []
	for i: int in 4:
		allies.append(BattleUnit.create(_db, "lu_bu", "S", 50))
	var enemies: Array[BattleUnit] = [BattleUnit.create(_db, "zhou_cang", "F", 1)]
	var battle: BattleEngine = BattleEngine.new(_db.balance, allies, enemies, SEED)
	battle.add_player_aura("hua_tuo", "화타의 응급 처치", "defense", 10.0, "allies_alive_at_most", 2)
	battle.peek_actor()
	battle._refresh_auras()
	assert_eq(allies[0].effective_stat("defense"), allies[0].base_stats.defense, "아군 4명 생존: 아직 아니다")
	allies[2].take_damage(99999)
	allies[3].take_damage(99999)
	battle._refresh_auras()
	assert_gt(allies[0].effective_stat("defense"), allies[0].base_stats.defense, "2명 이하 → 발동")
	assert_true(_has_line(battle.log_lines, "보유효과 발동: 화타의 응급 처치"))


func test_turn_condition() -> void:
	var allies: Array[BattleUnit] = [BattleUnit.create(_db, "dong_zhuo", "S", 50)]
	var enemies: Array[BattleUnit] = [BattleUnit.create(_db, "dong_zhuo", "S", 50)]
	var battle: BattleEngine = BattleEngine.new(_db.balance, allies, enemies, SEED)
	# 동탁의 스킬은 공격 디버프를 걸 수 있으니, 아무도 건드리지 않는 지략으로 확인한다.
	battle.add_player_aura("zhang_jue", "시험", "intellect", 8.0, "battle_turn_at_least", 3)
	var base_intellect: int = allies[0].base_stats.intellect
	while battle.round_number < 3:
		assert_eq(allies[0].effective_stat("intellect"), base_intellect)
		battle.advance()
		battle.peek_actor()
	assert_gt(allies[0].effective_stat("intellect"), base_intellect, "3턴째부터 발동")


func test_late_game_uses_balance_value() -> void:
	var run: ExpeditionRun = _strong_run()
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "hua_tuo", "B", 1))
	var battle: BattleEngine = BattleEngine.new(_db.balance, [] as Array[BattleUnit], [] as Array[BattleUnit], SEED)
	run._apply_reserve_auras(battle, 0.0)
	assert_eq(battle._auras.size(), 1)
	assert_eq(battle._auras[0]["condition_kind"], "allies_alive_at_most")
	assert_eq(battle._auras[0]["condition_value"], 2, "최후반부 = 아군 2명 이하 (balance 기본값)")


func test_hp_reserve_effect_adds_battle_buffer_only() -> void:
	# 동탁 S(천자를 낀 권세): 출전 장수 체력 +12%
	var run: ExpeditionRun = _strong_run()
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "dong_zhuo", "S", 1))
	var member: RosterMember = run.roster.get_member(0)
	var roster_max: int = member.max_hp
	var battle: BattleEngine = run.choose(0)
	var unit: BattleUnit = battle.units[0]
	assert_eq(unit.max_hp, roster_max + roundi(float(roster_max) * 0.12), "전투 중에는 최대 체력이 늘어난다")
	assert_eq(member.max_hp, roster_max, "로스터의 최대 체력은 그대로")
	assert_true(member.hp <= member.max_hp)
	assert_eq(member.hp, maxi(1, unit.hp - (unit.max_hp - roster_max)), "늘었던 만큼 빼고 기록")


func test_reserve_members_effects_only_from_reserve() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_eq(run.reserve_effects().size(), 0, "보유효과 슬롯이 비면 효과 없음")
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "lu_bu", "B", 1))
	assert_eq(run.reserve_effects().size(), 1)


# ---------- 보유효과 슬롯 확장 ----------

func test_slot_bonus_general_in_reserve_adds_slot() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "cao_cao", "S", 1))
	run._update_reserve_capacity()
	assert_eq(run.roster.reserve_count(), 3, "조조 S(구현령): 보유효과 슬롯 +1")
	assert_eq(run.roster.first_empty_slot(), FIRST_RESERVE_SLOT + 1)


func test_slot_bonus_needs_to_be_in_reserve() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(0, RosterMember.create(_db, "cao_cao", "S", 1))
	run._update_reserve_capacity()
	assert_eq(run.roster.reserve_count(), 2, "출전 슬롯에 있으면 보유효과가 발동하지 않는다")


func test_slot_shrink_releases_last_reserve_member() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "cao_cao", "S", 1))
	run._update_reserve_capacity()
	run.roster.set_member(FIRST_RESERVE_SLOT + 1, RosterMember.create(_db, "sun_quan", "C", 1))
	run.roster.set_member(FIRST_RESERVE_SLOT + 2, RosterMember.create(_db, "lu_bu", "B", 1))
	assert_true(run.roster.is_full())
	# 조조를 출전 슬롯으로 옮기면 칸이 줄고, 마지막 칸의 여포가 방출된다.
	assert_true(run.swap_slots(0, FIRST_RESERVE_SLOT))
	assert_eq(run.roster.reserve_count(), 2)
	assert_false(run.roster.has_general("lu_bu"), "마지막 보유효과 슬롯의 장수 방출 (기본값)")
	assert_true(run.roster.has_general("guan_yu"), "옮겨 간 관우는 남는다")
	assert_true(_has_line(run.log_lines, "슬롯 축소로 방출: 여포(B)"))


func test_slot_capacity_respects_maximum() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var balance_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var roster_data: Dictionary = balance_data["roster"]
	roster_data["reserve_slots_max"] = 2
	run._db = GameDatabase.from_dicts(balance_data,
		JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/generals.json")))
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "cao_cao", "S", 1))
	run._update_reserve_capacity()
	assert_eq(run.roster.reserve_count(), 2, "최대치를 넘지 않는다")


func test_promotion_into_slot_bonus_tier_expands() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "cao_cao", "A", 1))
	run._rewards = [Reward.make_card("cao_cao", "S")]
	run.phase = ExpeditionRun.PHASE_REWARD
	run.choose_reward(0)
	assert_eq(run.roster.get_member(FIRST_RESERVE_SLOT).tier, "S")
	assert_eq(run.roster.reserve_count(), 3, "승급으로 슬롯 확장 효과를 얻으면 바로 늘어난다")


# ---------- 보물상자 ----------

func test_roster_chest_gives_cards_to_roster() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.open_chest(_db.get_chest("supply_crate"), -1, 7)
	var total: int = _total_cards_given(run)
	assert_eq(total, 10, "10장 (합성으로 줄어든 장수까지 셈)")
	assert_true(_has_line(run.log_lines, "보물상자 군량 상자 10장"))


func test_chest_card_tiers_follow_general_tiers() -> void:
	# 조조(B·A·S) 한 명만 있는 로스터에 20장 상자를 여러 번 열어 티어별 장수를 센다.
	var counts: Dictionary[String, int] = {"B": 0, "A": 0, "S": 0}
	var regex: RegEx = RegEx.create_from_string("조조 ([A-Z])×(\\d+)")
	for s: int in 20:
		var probe: ExpeditionRun = ExpeditionRun.start(_db, SEED)
		probe.roster = Roster.new(6, 2)
		probe.roster.set_member(0, RosterMember.create(_db, "cao_cao", "S", 1))
		probe.open_chest(_db.get_chest("imperial_gift"), -1, s)
		for line: String in probe.log_lines:
			for found: RegExMatch in regex.search_all(line):
				assert_true(counts.has(found.get_string(1)), "그 장수에게 없는 티어(%s)는 나오지 않는다" % found.get_string(1))
				counts[found.get_string(1)] += int(found.get_string(2))
	assert_eq(counts["B"] + counts["A"] + counts["S"], 400)
	# 가중치 80 : 18 : 2 → B가 대부분.
	assert_between(counts["B"], 280, 360, "가장 낮은 티어가 주로 나온다 (B %d장)" % counts["B"])
	assert_lt(counts["S"], 30)


func test_active_chest_skips_reserve() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "lu_bu", "B", 1))
	run.open_chest(_db.get_chest("war_merit"), -1, 3)
	assert_eq(run.merge_card_count("lu_bu", "B") + run.merge_card_count("lu_bu", "A"), 0, "출전 장수 한정 상자")
	assert_eq(run.roster.get_member(FIRST_RESERVE_SLOT).tier, "B")


func test_single_chest_goes_to_chosen_general_and_chains() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var guan_yu: RosterMember = run.roster.get_member(0)
	guan_yu.hp = 1
	run._rewards = [Reward.make_chest("secret_manual")]
	run.phase = ExpeditionRun.PHASE_REWARD
	assert_true(run.reward_needs_target(0), "집중 상자는 받을 장수를 골라야 한다")
	assert_true(run.choose_reward(0, 0))
	# 8장 대부분이 C(관우의 가장 낮은 티어) → 본체 포함 연쇄 합성으로 여러 단계 승급.
	assert_true(Tier.is_higher(guan_yu.tier, "C"), "대량 유입으로 승급 (%s)" % guan_yu.tier)
	assert_eq(guan_yu.hp, guan_yu.max_hp, "승급으로 전체 회복")
	var others_untouched: bool = true
	for slot: int in range(1, 6):
		if run.merge_progress.has(run.roster.get_member(slot).general_id):
			others_untouched = false
	assert_true(others_untouched, "다른 장수는 카드를 받지 않는다")
	var promotions: int = 0
	for event: Dictionary in run.last_merge_events:
		if event["kind"] == "promotion":
			promotions += 1
	assert_eq(promotions, 1, "승급 기록은 장수당 한 번 (최종 티어로)")


func test_chest_is_reproducible() -> void:
	var a: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var b: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	a.open_chest(_db.get_chest("imperial_gift"), -1, 99)
	b.open_chest(_db.get_chest("imperial_gift"), -1, 99)
	assert_eq(a.merge_progress, b.merge_progress)
	assert_eq(a.log_lines, b.log_lines)


# ---------- 특별 토벌과 해 넘김 상자 ----------

func test_special_expeditions_appear_from_their_year() -> void:
	assert_eq(_count_kind(184, "imperial_requisition"), 0, "184년에는 특별 토벌이 없다")
	assert_gt(_count_kind(185, "imperial_requisition"), 0, "185년부터 왕실 조달 명령")
	assert_eq(_count_kind(189, "bounty"), 0)
	assert_gt(_count_kind(195, "bounty"), 0, "190년부터 현상금 토벌")


func test_bounty_has_issuer_in_title() -> void:
	for round_number: int in range(1, 11):
		for s: int in 20:
			for expedition: Expedition in ExpeditionGenerator.generate(_db, s, 195, round_number):
				if expedition.type.kind == "bounty":
					var issuer_title: String = expedition.title.split(" · ")[0]
					assert_true(issuer_title in ["위 현상금 토벌", "촉 현상금 토벌", "오 현상금 토벌"], expedition.title)
					return
	fail_test("현상금 토벌이 한 번도 나오지 않았다")


func test_special_expedition_reward_includes_chest() -> void:
	var expedition: Expedition = _find_special(185)
	var rewards: Array[Reward] = RewardGenerator.generate(_db, expedition, SEED)
	assert_eq(rewards.size(), 3)
	assert_true(rewards[0].is_chest(), "특별 토벌 보상의 첫 선택지는 보물상자")
	assert_true(rewards[1].is_exp())
	assert_true(rewards[2].is_card())


func test_year_end_opens_chest_automatically() -> void:
	var run: ExpeditionRun = _strong_run()
	for i: int in 10:
		run.choose(0)
		run.choose_reward(0, 0)
	assert_eq(run.year, 185)
	assert_true(_has_line(run.log_lines, "보물상자 조정 하사품 20장"), "해 넘김 보상")


# ---------- 테스트용 도우미 ----------

## 화타가 출전하고, 다친 장수가 있는 강한 로스터.
func _healer_run() -> ExpeditionRun:
	var run: ExpeditionRun = _strong_run()
	run.roster.set_member(3, RosterMember.create(_db, "hua_tuo", "B", 50))
	return run


func _strong_run() -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var specs: Array = [["lu_bu", "S"], ["dong_zhuo", "S"], ["guan_yu", "A"], ["zhuge_liang", "S"], ["cao_cao", "A"], ["liu_bei", "A"]]
	for i: int in specs.size():
		var spec: Array = specs[i]
		run.roster.set_member(i, RosterMember.create(_db, String(spec[0]), String(spec[1]), 50))
	return run


func _fight_and_take_exp(run: ExpeditionRun) -> void:
	var battle: BattleEngine = run.choose(0)
	assert_true(battle.player_won())
	# 강한 로스터는 거의 다치지 않으므로, 치유 대상이 생기도록 한 명을 다치게 둔다.
	var wounded: RosterMember = run.roster.get_member(0)
	wounded.hp = maxi(1, wounded.hp - 100)
	var exp_index: int = 0
	for i: int in run.current_rewards().size():
		if run.current_rewards()[i].is_exp():
			exp_index = i
	run.choose_reward(exp_index, 0)


func _heal_lines(run: ExpeditionRun) -> Array[String]:
	var result: Array[String] = []
	for line: String in run.log_lines:
		if line.contains("치유:"):
			result.append(line)
	return result


func _has_line(lines: Array[String], fragment: String) -> bool:
	for line: String in lines:
		if line.contains(fragment):
			return true
	return false


func _total_cards_given(run: ExpeditionRun) -> int:
	var line: String = ""
	for candidate: String in run.log_lines:
		if candidate.contains("보물상자"):
			line = candidate
	var total: int = 0
	for part: String in line.split(": ", true, 1)[1].split(", "):
		total += int(part.split("×")[1])
	return total


func _count_kind(year: int, kind: String) -> int:
	var count: int = 0
	for round_number: int in range(1, 11):
		for s: int in 5:
			for expedition: Expedition in ExpeditionGenerator.generate(_db, s, year, round_number):
				if expedition.type.kind == kind:
					count += 1
	return count


func _find_special(year: int) -> Expedition:
	for round_number: int in range(1, 11):
		for s: int in 10:
			for expedition: Expedition in ExpeditionGenerator.generate(_db, s, year, round_number):
				if expedition.type.is_special():
					return expedition
	return null


func _db_with_balance(section: String, key: String, value: Variant) -> GameDatabase:
	var balance_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var section_data: Dictionary = balance_data[section]
	section_data[key] = value
	return GameDatabase.from_dicts(balance_data,
		JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/generals.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/run.json")),
		JSON.parse_string(FileAccess.get_file_as_string("res://data/chests.json")))
