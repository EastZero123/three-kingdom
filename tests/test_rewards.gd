extends GutTest
## 5단계 보상과 로스터 테스트: 경험치, 영입, 빈 칸 강제 채움, 교체와 계승, 슬롯 이동, 방출.

const SEED: int = 12345
const FIRST_RESERVE_SLOT: int = 6

var _db: GameDatabase


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


# ---------- 보상 선택지 ----------

func test_three_rewards_after_victory() -> void:
	var run: ExpeditionRun = _strong_run()
	var expedition: Expedition = run.current_choices()[0]
	run.choose(0)
	var rewards: Array[Reward] = run.current_rewards()
	assert_eq(rewards.size(), 3, "보상 선택지는 3개")
	assert_true(rewards[0].is_exp(), "첫 선택지는 경험치")
	assert_true(rewards[1].is_card())
	assert_true(rewards[2].is_card())
	assert_ne(rewards[1].general_id, rewards[2].general_id, "장수 카드는 서로 다른 장수")
	for i: int in [1, 2]:
		assert_true(_fought(expedition, rewards[i].general_id, rewards[i].tier), "방금 맞붙은 적 장수의 카드만 나온다")


func test_exp_amount_follows_enemy_levels() -> void:
	var run: ExpeditionRun = _strong_run()
	var expedition: Expedition = run.current_choices()[2]
	var level_sum: int = 0
	for enemy: Dictionary in expedition.enemies:
		level_sum += int(enemy["level"])
	run.choose(2)
	var expected: int = roundi(float(level_sum) * 10.0 * expedition.formation.reward_exp_multiplier)
	assert_eq(run.current_rewards()[0].exp_amount, expected, "적 레벨 합 × 10 × 편성의 경험치 배율")
	assert_gt(expected, 0)


func test_rewards_are_reproducible() -> void:
	var first: ExpeditionRun = _strong_run()
	var second: ExpeditionRun = _strong_run()
	first.choose(1)
	second.choose(1)
	assert_eq(_reward_texts(first), _reward_texts(second), "같은 시드와 선택이면 같은 보상")


# ---------- 경험치 ----------

func test_exp_needed_per_level() -> void:
	assert_eq(RosterMember.exp_to_next(_db, 1), 20)
	assert_eq(RosterMember.exp_to_next(_db, 49), 980)


func test_experience_levels_up_and_keeps_damage_taken() -> void:
	var member: RosterMember = RosterMember.create(_db, "guan_yu", "C", 1)
	member.hp = 100  # 최대 150에서 50을 잃은 상태
	# 20 + 40 = 60으로 레벨 3, 남는 경험치 5.
	assert_eq(member.add_experience(_db, 65), 2)
	assert_eq(member.level, 3)
	assert_eq(member.experience, 5)
	assert_eq(member.max_hp, 159, "150 + 내림(4.6 × 2)")
	assert_eq(member.hp, 109, "최대 체력이 늘어난 만큼만 오른다 (잃은 체력 50은 그대로)")
	assert_eq(member.total_experience(_db), 65)


func test_level_is_capped_at_max() -> void:
	var member: RosterMember = RosterMember.create(_db, "guan_yu", "C", 1)
	member.add_experience(_db, 1000000)
	assert_eq(member.level, 50)
	assert_eq(member.experience, 0, "만렙에서는 경험치가 쌓이지 않는다")
	assert_eq(member.total_experience(_db), 24500, "만렙까지 필요한 경험치 합")


func test_exp_reward_goes_to_chosen_member() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_offer(run, [Reward.make_exp(65)])
	assert_true(run.reward_needs_target(0), "경험치는 받을 장수를 정해야 한다")
	assert_true(run.choose_reward(0, 3))
	assert_eq(run.roster.get_member(3).level, 3)
	assert_eq(run.roster.get_member(0).level, 1, "다른 장수는 그대로")
	assert_eq(run.phase, ExpeditionRun.PHASE_EXPEDITION)
	assert_eq(run.round_number, 2, "보상을 고르면 다음 라운드")


func test_exp_reward_can_go_to_reserve_member() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.swap_slots(5, FIRST_RESERVE_SLOT)
	_offer(run, [Reward.make_exp(20)])
	assert_true(run.choose_reward(0, FIRST_RESERVE_SLOT))
	assert_eq(run.roster.get_member(FIRST_RESERVE_SLOT).level, 2, "보유효과 슬롯 장수도 경험치를 받는다")


func test_exp_reward_without_valid_target_is_rejected() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_offer(run, [Reward.make_exp(20)])
	assert_false(run.choose_reward(0, -1))
	assert_false(run.choose_reward(0, FIRST_RESERVE_SLOT), "빈 칸에는 줄 수 없다")
	assert_push_error_count(2)
	assert_eq(run.phase, ExpeditionRun.PHASE_REWARD, "아직 보상을 고를 차례")
	assert_eq(run.round_number, 1)


# ---------- 장수 카드 ----------

func test_card_of_owned_general_goes_to_merge_progress() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_offer(run, [Reward.make_card("guan_yu", "C")])
	assert_false(run.reward_needs_target(0))
	assert_true(run.choose_reward(0))
	assert_eq(run.merge_card_count("guan_yu", "C"), 1, "이미 있는 장수의 카드는 합성 진행도에 쌓인다")
	assert_eq(run.roster.member_count(), 6, "로스터는 그대로")
	assert_eq(run.roster.get_member(0).tier, "C", "본체 + 1장으로는 아직 승급하지 않는다")


func test_new_general_must_fill_empty_slot() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_offer(run, [Reward.make_card("lu_bu", "B")])
	assert_false(run.reward_needs_target(0), "빈 칸이 있으면 교체 선택지가 없다")
	# 교체하려는 슬롯을 넘겨도 무시되고 빈 칸이 채워진다.
	assert_true(run.choose_reward(0, 0))
	assert_eq(run.roster.get_member(0).general_id, "guan_yu", "기존 장수는 교체되지 않는다")
	var newcomer: RosterMember = run.roster.get_member(FIRST_RESERVE_SLOT)
	assert_eq(newcomer.general_id, "lu_bu", "출전이 가득 찼으니 보유효과 슬롯의 빈 칸으로")
	assert_eq(newcomer.tier, "B")
	assert_eq(newcomer.level, 1, "빈 칸 영입에는 계승이 없다")
	assert_eq(newcomer.hp, newcomer.max_hp)
	assert_eq(run.roster.member_count(), 7)


func test_empty_active_slot_is_filled_first() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(2, null)  # 전사로 생긴 빈 칸
	_offer(run, [Reward.make_card("lu_bu", "B")])
	run.choose_reward(0)
	assert_eq(run.roster.get_member(2).general_id, "lu_bu", "출전 슬롯의 빈 칸을 먼저 채운다")
	assert_null(run.roster.get_member(FIRST_RESERVE_SLOT))


func test_full_roster_replaces_and_inherits() -> void:
	var run: ExpeditionRun = _full_run()
	var outgoing: RosterMember = run.roster.get_member(1)
	outgoing.add_experience(_db, 900)  # 레벨 10 (20+40+…+180 = 900)
	assert_eq(outgoing.level, 10)
	outgoing.hp = 5
	run.add_merge_card("zhang_fei", "C")

	_offer(run, [Reward.make_card("lu_bu", "B")])
	assert_true(run.reward_needs_target(0), "가득 찼으면 교체할 장수를 골라야 한다")
	assert_false(run.choose_reward(0, -1), "대상 없이는 고를 수 없다")
	assert_push_error("보상 대상 슬롯이 잘못됐다")
	assert_true(run.choose_reward(0, 1))

	var newcomer: RosterMember = run.roster.get_member(1)
	assert_eq(newcomer.general_id, "lu_bu")
	# 계승: 900 × 75% = 675 → 레벨 8 (560 필요), 남는 경험치 115.
	assert_eq(newcomer.level, 8)
	assert_eq(newcomer.experience, 115)
	assert_eq(newcomer.total_experience(_db), 675)
	assert_eq(newcomer.hp, newcomer.max_hp, "교체로 들어온 장수는 체력이 가득")
	assert_eq(newcomer.max_hp, _db.get_general("lu_bu").get_tier("B").stats_at_level(8).hp, "스탯은 새 장수 고유의 성장을 따른다")
	assert_false(run.roster.has_general("zhang_fei"), "교체된 장수는 나간다")
	assert_eq(run.roster.member_count(), 8)
	assert_eq(run.merge_card_count("zhang_fei", "C"), 1, "나간 장수의 합성 진행도는 남는다")


func test_reserve_member_can_be_replaced_too() -> void:
	var run: ExpeditionRun = _full_run()
	_offer(run, [Reward.make_card("lu_bu", "B")])
	assert_true(run.choose_reward(0, FIRST_RESERVE_SLOT + 1))
	assert_eq(run.roster.get_member(FIRST_RESERVE_SLOT + 1).general_id, "lu_bu")


# ---------- 카드 레벨과 난이도별 티어 ----------

func test_card_carries_enemy_level() -> void:
	var run: ExpeditionRun = _strong_run()
	var expedition: Expedition = run.current_choices()[2]
	run.choose(2)
	var card: Reward = run.current_rewards()[1]
	assert_true(card.is_card())
	assert_eq(card.enemy_level, expedition.enemy_level, "카드는 맞붙은 적의 레벨을 기억한다")


func test_recruit_level_follows_enemy_level() -> void:
	assert_eq(Reward.make_card("lu_bu", "B", 10).recruit_level(_db), 8, "적 Lv.10 × 0.8 = 8")
	assert_eq(Reward.make_card("lu_bu", "B", 1).recruit_level(_db), 1, "최소 1")
	assert_eq(Reward.make_card("lu_bu", "B", 99).recruit_level(_db), 50, "만렙을 넘지 않는다")


func test_recruit_into_empty_slot_uses_card_level() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_offer(run, [Reward.make_card("lu_bu", "B", 10)])
	run.choose_reward(0)
	var newcomer: RosterMember = run.roster.get_member(FIRST_RESERVE_SLOT)
	assert_eq(newcomer.level, 8)
	assert_eq(newcomer.hp, newcomer.max_hp)
	assert_eq(newcomer.max_hp, _db.get_general("lu_bu").get_tier("B").stats_at_level(8).hp)


func test_replacement_uses_higher_of_card_level_and_inheritance() -> void:
	# 계승이 더 높은 경우: 나가는 장수 Lv.10 (900) → 675 → Lv.8, 카드는 Lv.4.
	var run: ExpeditionRun = _full_run()
	run.roster.get_member(1).add_experience(_db, 900)
	_offer(run, [Reward.make_card("lu_bu", "B", 5)])
	run.choose_reward(0, 1)
	assert_eq(run.roster.get_member(1).level, 8, "계승 쪽이 높으면 계승")
	assert_string_contains(run.log_lines[run.log_lines.size() - 1], "계승으로 Lv.8")

	# 카드가 더 높은 경우: 나가는 장수 Lv.1 → 계승 0, 카드 Lv.16.
	var run2: ExpeditionRun = _full_run()
	_offer(run2, [Reward.make_card("lu_bu", "B", 20)])
	run2.choose_reward(0, 1)
	assert_eq(run2.roster.get_member(1).level, 16, "카드 레벨 쪽이 높으면 카드 레벨")
	assert_eq(run2.roster.get_member(1).experience, 0, "둘을 더하지 않는다")


func test_harder_expeditions_bring_higher_tier_enemies() -> void:
	# 같은 시대(190년대)에서 적 6명 뽑기를 400번씩 반복해 평균 티어를 비교한다.
	var era: EraDef = _db.era_for_year(195)
	var average: Dictionary[String, float] = {}
	for type_def: ExpeditionTypeDef in _db.expedition_types:
		if type_def.is_special():
			continue
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = SEED
		var total: int = 0
		var count: int = 0
		for i: int in 400:
			for enemy: Dictionary in ExpeditionGenerator._pick_enemies(_db, rng, era, 6, 10, type_def.tier_weight_per_step):
				total += Tier.index_of(String(enemy["tier"]))
				count += 1
		average[type_def.id] = float(total) / float(count)
	assert_lt(average["easy"], average["normal"], "쉬움보다 보통이 높은 티어 (%.2f < %.2f)" % [average["easy"], average["normal"]])
	assert_lt(average["normal"], average["hard"], "보통보다 어려움이 높은 티어 (%.2f < %.2f)" % [average["normal"], average["hard"]])


# ---------- 슬롯 이동 ----------

func test_swap_between_active_and_reserve() -> void:
	var run: ExpeditionRun = _full_run()
	var active_id: String = run.roster.get_member(0).general_id
	var reserve_id: String = run.roster.get_member(FIRST_RESERVE_SLOT).general_id
	assert_true(run.swap_slots(0, FIRST_RESERVE_SLOT))
	assert_eq(run.roster.get_member(0).general_id, reserve_id)
	assert_eq(run.roster.get_member(FIRST_RESERVE_SLOT).general_id, active_id)
	assert_eq(run.history[run.history.size() - 1], {"type": "swap", "a": 0, "b": FIRST_RESERVE_SLOT})


func test_reserve_members_do_not_fight() -> void:
	var run: ExpeditionRun = _strong_run()
	run.swap_slots(5, FIRST_RESERVE_SLOT)  # 한 명을 보유효과 슬롯으로
	var resting: RosterMember = run.roster.get_member(FIRST_RESERVE_SLOT)
	var battle: BattleEngine = run.choose(0)
	assert_eq(battle.living_units(BattleEngine.SIDE_PLAYER).size(), 5, "출전 슬롯의 5명만 싸운다")
	assert_eq(resting.hp, resting.max_hp)


func test_swap_is_allowed_while_choosing_reward() -> void:
	var run: ExpeditionRun = _strong_run()
	run.choose(0)
	assert_eq(run.phase, ExpeditionRun.PHASE_REWARD)
	assert_true(run.swap_slots(0, 1), "전투와 전투 사이에는 자유롭게 옮길 수 있다")


func test_invalid_swaps_are_rejected() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_false(run.swap_slots(0, 0))
	assert_false(run.swap_slots(0, 99))
	assert_false(run.swap_slots(-1, 2))
	# 출전 장수를 한 명만 남기고, 그 한 명을 보유효과 슬롯으로 보내려 하면 거부된다.
	for slot: int in range(1, 6):
		run.roster.set_member(slot, null)
	assert_false(run.swap_slots(0, FIRST_RESERVE_SLOT), "출전 장수가 0명이 되는 이동은 불가")
	assert_eq(run.roster.get_member(0).general_id, "guan_yu")


func test_no_moves_after_run_is_over() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	for member: RosterMember in run.roster.members():
		member.hp = 1
	run.swap_slots(5, FIRST_RESERVE_SLOT)
	run.choose(2)
	assert_true(run.is_over())
	assert_false(run.swap_slots(FIRST_RESERVE_SLOT, 0))
	assert_false(run.release_member(FIRST_RESERVE_SLOT))


# ---------- 방출 ----------

func test_release_has_no_inheritance() -> void:
	var run: ExpeditionRun = _full_run()
	run.roster.get_member(1).add_experience(_db, 900)
	run.add_merge_card("zhang_fei", "C")
	assert_true(run.release_member(1))
	assert_null(run.roster.get_member(1))
	assert_eq(run.merge_card_count("zhang_fei", "C"), 1, "방출해도 합성 진행도는 런 동안 남는다")

	# 방출로 생긴 빈 칸에 들어오는 새 장수는 레벨 1이다.
	_offer(run, [Reward.make_card("lu_bu", "B")])
	run.choose_reward(0)
	assert_eq(run.roster.get_member(1).general_id, "lu_bu")
	assert_eq(run.roster.get_member(1).level, 1, "자발적 방출에는 계승이 없다")


func test_cannot_release_last_active_member_or_empty_slot() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_false(run.release_member(FIRST_RESERVE_SLOT), "빈 칸은 방출할 수 없다")
	for slot: int in range(1, 6):
		assert_true(run.release_member(slot))
	assert_false(run.release_member(0), "마지막 출전 장수는 방출할 수 없다")
	assert_eq(run.roster.active_member_count(), 1)


# ---------- 로스터 ----------

func test_roster_lookup() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_eq(run.roster.find_general("hua_tuo"), 3)
	assert_eq(run.roster.find_general("lu_bu"), -1)
	assert_true(run.roster.is_active_slot(5))
	assert_false(run.roster.is_active_slot(FIRST_RESERVE_SLOT))
	assert_eq(run.roster.first_empty_slot(), FIRST_RESERVE_SLOT)
	assert_false(run.roster.is_full())
	assert_true(_full_run().roster.is_full())
	assert_eq(run.roster.slot_label(0), "출전 1번")
	assert_eq(run.roster.slot_label(7), "보유효과 2번")


# ---------- 테스트용 도우미 ----------

## 원하는 보상 선택지를 직접 내놓은 상태로 만든다 (전투 결과와 무관하게 규칙만 시험하려고).
func _offer(run: ExpeditionRun, rewards: Array[Reward]) -> void:
	run._rewards = rewards
	run.phase = ExpeditionRun.PHASE_REWARD


## 보유효과 슬롯까지 8칸이 모두 찬 런.
func _full_run() -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.set_member(FIRST_RESERVE_SLOT, RosterMember.create(_db, "sun_quan", "C", 1))
	run.roster.set_member(FIRST_RESERVE_SLOT + 1, RosterMember.create(_db, "cao_cao", "B", 1))
	return run


func _strong_run() -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var specs: Array = [["lu_bu", "S"], ["dong_zhuo", "S"], ["guan_yu", "A"], ["zhuge_liang", "S"], ["cao_cao", "S"], ["liu_bei", "A"]]
	for i: int in specs.size():
		var spec: Array = specs[i]
		run.roster.set_member(i, RosterMember.create(_db, String(spec[0]), String(spec[1]), 50))
	return run


func _fought(expedition: Expedition, general_id: String, tier: String) -> bool:
	for enemy: Dictionary in expedition.enemies:
		if enemy["general_id"] == general_id and enemy["tier"] == tier:
			return true
	return false


func _reward_texts(run: ExpeditionRun) -> Array[String]:
	var result: Array[String] = []
	for reward: Reward in run.current_rewards():
		result.append(reward.summary(_db, run.roster.is_full()))
	return result
