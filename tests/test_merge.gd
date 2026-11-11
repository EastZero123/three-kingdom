extends GutTest
## 6단계 합성 테스트: 단계식 합성, 연쇄, 상위 티어 즉시 승급, 승급 시 전체 회복, 합성 진행도 보존.

const SEED: int = 12345
const FIRST_RESERVE_SLOT: int = 6

var _db: GameDatabase


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


# ---------- 합성 계산 (Merge.resolve) ----------

func test_body_plus_two_cards_promotes() -> void:
	var progress: Dictionary = {"C": 2}
	var result: Dictionary = Merge.resolve(_db.get_general("guan_yu"), "C", progress, 3)
	assert_eq(result["body_tier"], "B", "본체 + 같은 티어 2장 = 3장 → 승급")
	assert_eq(result["events"], [{"from": "C", "to": "B"}])
	assert_eq(progress, {}, "쓴 카드는 진행도에서 빠진다")


func test_body_plus_one_card_does_not_promote() -> void:
	var progress: Dictionary = {"C": 1}
	var result: Dictionary = Merge.resolve(_db.get_general("guan_yu"), "C", progress, 3)
	assert_eq(result["body_tier"], "C")
	assert_eq(result["events"], [])
	assert_eq(progress, {"C": 1})


func test_low_tier_cards_merge_step_by_step() -> void:
	# 본체 D, F 카드 3장 → E 1장. 본체보다 낮으니 본체는 그대로.
	var progress: Dictionary = {"F": 3}
	var result: Dictionary = Merge.resolve(_db.get_general("zhou_cang"), "D", progress, 3)
	assert_eq(result["body_tier"], "D")
	assert_eq(result["events"], [{"from": "F", "to": "E"}])
	assert_eq(progress, {"E": 1}, "F 3장이 E 1장이 되어 E 진행도에 쌓인다")


func test_chain_merge_in_one_go() -> void:
	# 본체 F + F 2장 → E 1장, E 2장과 합쳐 3장 → D 1장. 본체는 D가 된다.
	var progress: Dictionary = {"F": 2, "E": 2}
	var result: Dictionary = Merge.resolve(_db.get_general("zhou_cang"), "F", progress, 3)
	assert_eq(result["events"], [{"from": "F", "to": "E"}, {"from": "E", "to": "D"}], "한 번에 연쇄 합성")
	assert_eq(result["body_tier"], "D")
	assert_eq(progress, {})


func test_higher_tier_card_promotes_immediately() -> void:
	# 본체 C에 A 카드 1장 → 즉시 A. 옛 본체는 C 카드 1장으로 남는다.
	var progress: Dictionary = {"A": 1}
	var result: Dictionary = Merge.resolve(_db.get_general("guan_yu"), "C", progress, 3)
	assert_eq(result["body_tier"], "A")
	assert_eq(result["events"], [])
	assert_eq(progress, {"C": 1})


func test_top_tier_cards_just_pile_up() -> void:
	var progress: Dictionary = {"S": 5}
	var result: Dictionary = Merge.resolve(_db.get_general("cao_cao"), "S", progress, 3)
	assert_eq(result["body_tier"], "S", "최고 티어 위로는 오를 수 없다")
	assert_eq(result["events"], [])
	assert_eq(progress, {"S": 5})


func test_merge_size_comes_from_balance() -> void:
	var progress: Dictionary = {"C": 1}
	var result: Dictionary = Merge.resolve(_db.get_general("guan_yu"), "C", progress, 2)
	assert_eq(result["body_tier"], "B", "합성 장수가 2장이면 본체 + 1장으로 승급")


# ---------- 런에서의 합성 ----------

func test_promotion_heals_fully_and_keeps_level() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var guan_yu: RosterMember = run.roster.get_member(0)
	guan_yu.add_experience(_db, 900)  # 레벨 10
	guan_yu.hp = 10
	_give_card(run, "guan_yu", "C")
	assert_eq(guan_yu.tier, "C")
	assert_eq(guan_yu.hp, 10, "승급 전에는 회복이 없다")
	_give_card(run, "guan_yu", "C")
	assert_eq(guan_yu.tier, "B", "본체 + 2장 → 승급")
	assert_eq(guan_yu.level, 10, "레벨은 그대로")
	assert_eq(guan_yu.max_hp, _db.get_general("guan_yu").get_tier("B").stats_at_level(10).hp, "새 티어의 스탯으로 다시 계산")
	assert_eq(guan_yu.hp, guan_yu.max_hp, "승급하면 체력이 전부 회복된다")
	assert_eq(run.merge_card_count("guan_yu", "C"), 0)
	assert_eq(run.last_merge_events, [
		{"kind": "merge", "general_id": "guan_yu", "from": "C", "to": "B"},
		{"kind": "promotion", "general_id": "guan_yu", "from": "C", "to": "B"},
	], "연출용 기록")
	assert_string_contains(run.log_lines[run.log_lines.size() - 2], "합성: 관우 C 3장 → B 1장")
	assert_string_contains(run.log_lines[run.log_lines.size() - 1], "승급: 관우 C → B")


func test_higher_tier_card_in_run() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var zhang_fei: RosterMember = run.roster.get_member(1)
	zhang_fei.hp = 1
	_give_card(run, "zhang_fei", "A")
	assert_eq(zhang_fei.tier, "A", "본체보다 높은 티어 카드는 즉시 승급")
	assert_eq(zhang_fei.hp, zhang_fei.max_hp)
	assert_eq(run.merge_card_count("zhang_fei", "C"), 1, "옛 본체는 C 카드로 남는다")


func test_lower_tier_card_does_not_change_body() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	# 관우 C 본체에 같은 C 카드 1장은 진행도만 쌓인다 (보유효과 슬롯에 있어도 같다).
	run.swap_slots(0, FIRST_RESERVE_SLOT)
	var guan_yu: RosterMember = run.roster.get_member(FIRST_RESERVE_SLOT)
	guan_yu.hp = 1
	_give_card(run, "guan_yu", "C")
	assert_eq(guan_yu.tier, "C")
	assert_eq(guan_yu.hp, 1, "승급이 없으면 회복도 없다")
	assert_eq(run.merge_card_count("guan_yu", "C"), 1)


func test_chain_merge_in_run() -> void:
	# 주창 F 본체, 진행도 F 1장·E 2장. F 카드 1장을 더 얻으면 F→E→D 연쇄.
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var zhou_cang: RosterMember = RosterMember.create(_db, "zhou_cang", "F", 1)
	zhou_cang.hp = 3
	run.roster.set_member(FIRST_RESERVE_SLOT, zhou_cang)
	run.merge_progress["zhou_cang"] = {"F": 1, "E": 2}
	_give_card(run, "zhou_cang", "F")
	assert_eq(zhou_cang.tier, "D")
	assert_eq(zhou_cang.hp, zhou_cang.max_hp)
	assert_eq(run.last_merge_events.size(), 3, "합성 2번 + 승급 1번")
	assert_eq(run.last_merge_events[0]["to"], "E")
	assert_eq(run.last_merge_events[1]["to"], "D")
	assert_eq(run.last_merge_events[2]["kind"], "promotion")


func test_progress_survives_release_and_continues_on_recruit() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_give_card(run, "zhang_fei", "C")
	run.release_member(1)
	assert_false(run.roster.has_general("zhang_fei"))
	assert_eq(run.merge_card_count("zhang_fei", "C"), 1, "방출해도 진행도는 남는다")

	# 다시 C 카드로 영입하면 본체 C + 진행도 C 1장 = 2장, 아직 승급 아님.
	_give_card(run, "zhang_fei", "C")
	assert_eq(run.roster.get_member(1).general_id, "zhang_fei", "빈 칸으로 다시 영입")
	assert_eq(run.roster.get_member(1).tier, "C")
	assert_eq(run.merge_card_count("zhang_fei", "C"), 1)
	# 한 장 더 얻으면 이어서 쌓여 승급한다.
	_give_card(run, "zhang_fei", "C")
	assert_eq(run.roster.get_member(1).tier, "B", "예전 진행도에 이어서 쌓인다")


func test_recruit_with_enough_old_progress_promotes_at_once() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.merge_progress["lu_bu"] = {"B": 2}
	_give_card(run, "lu_bu", "B")
	var lu_bu: RosterMember = run.roster.get_member(FIRST_RESERVE_SLOT)
	assert_eq(lu_bu.general_id, "lu_bu")
	assert_eq(lu_bu.tier, "A", "영입 카드 + 예전 진행도 2장 → 바로 승급")


func test_progress_survives_death() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_give_card(run, "guan_yu", "C")
	run.roster.get_member(0).hp = 0
	run._bury_dead()
	assert_false(run.roster.has_general("guan_yu"))
	assert_eq(run.merge_card_count("guan_yu", "C"), 1, "전사해도 진행도는 남는다")


func test_merge_progress_resets_on_new_run() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	_give_card(run, "guan_yu", "C")
	var next_run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	assert_eq(next_run.merge_card_count("guan_yu", "C"), 0, "합성 진행도는 런마다 새로 시작")


func test_merge_is_reproducible_through_replay() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	for i: int in 3:
		run.choose(0)
		if run.is_over():
			break
		var rewards: Array[Reward] = run.current_rewards()
		var index: int = 1 if rewards[1].is_card() else 0
		run.choose_reward(index, 0 if run.reward_needs_target(index) else -1)
	var copy: ExpeditionRun = ExpeditionRun.replay(_db, SEED, run.history)
	assert_eq(copy.merge_progress, run.merge_progress)
	assert_eq(copy.log_lines, run.log_lines)


# ---------- 테스트용 도우미 ----------

## 장수 카드 한 장을 보상으로 받는다 (전투 없이 규칙만 시험).
func _give_card(run: ExpeditionRun, general_id: String, tier: String) -> void:
	run._rewards = [Reward.make_card(general_id, tier)]
	run.phase = ExpeditionRun.PHASE_REWARD
	assert_true(run.choose_reward(0))
