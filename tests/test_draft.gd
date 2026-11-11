extends GutTest
## 시작 드래프트 테스트: 후보 3명 중 1명 × 6번, 중복 없음, 빈 칸 순서대로 배치, 시드 재현.

const SEED: int = 12345

var _db: GameDatabase


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


func test_draft_data_loads() -> void:
	assert_eq(_db.errors, [] as Array[String])
	assert_eq(_db.draft_picks, 6)
	assert_eq(_db.draft_choices, 3)
	assert_eq(_db.draft_level, 1)


func test_draft_run_starts_empty() -> void:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	assert_eq(run.phase, ExpeditionRun.PHASE_DRAFT)
	assert_eq(run.roster.member_count(), 0, "드래프트 전에는 로스터가 비어 있다")
	assert_eq(run.current_choices().size(), 0, "드래프트 중에는 토벌을 고를 수 없다")
	assert_eq(run.current_draft_offer().size(), 3, "후보 3명")


func test_offer_has_distinct_valid_generals() -> void:
	for s: int in 50:
		var run: ExpeditionRun = ExpeditionRun.start_draft(_db, s)
		var seen: Dictionary[String, bool] = {}
		for pick: Dictionary in run.current_draft_offer():
			var general_id: String = pick["general_id"]
			assert_false(seen.has(general_id), "한 번의 후보 안에 같은 장수는 없다")
			seen[general_id] = true
			assert_true(_db.get_general(general_id).has_tier(String(pick["tier"])), "그 장수에게 있는 티어")
			assert_gt(_db.draft_tier_weights.get(String(pick["tier"]), 0.0), 0.0, "가중치가 0인 티어(S)는 나오지 않는다")


func test_six_picks_fill_active_slots_then_start() -> void:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	var picked_ids: Array[String] = []
	for i: int in 6:
		var offer: Array[Dictionary] = run.current_draft_offer()
		for pick: Dictionary in offer:
			assert_false(picked_ids.has(String(pick["general_id"])), "이미 고른 장수는 후보에 다시 나오지 않는다")
		picked_ids.append(String(offer[i % 3]["general_id"]))
		assert_true(run.choose_draft(i % 3))
		assert_eq(run.roster.get_member(i).general_id, picked_ids[i], "%d번째 장수는 출전 %d번 칸" % [i + 1, i + 1])
		assert_eq(run.roster.get_member(i).level, 1)
	assert_eq(run.phase, ExpeditionRun.PHASE_EXPEDITION, "6번 고르면 원정 시작")
	assert_eq(run.current_draft_offer().size(), 0)
	assert_eq(run.current_choices().size(), 3)
	assert_eq(run.round_number, 1)


func test_offer_is_stable_until_chosen() -> void:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	assert_eq(run.current_draft_offer(), run.current_draft_offer())


func test_swap_during_draft_and_next_pick_fills_first_empty() -> void:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	run.choose_draft(0)
	assert_true(run.swap_slots(0, 2), "드래프트 중에도 자리를 옮길 수 있다")
	run.choose_draft(0)
	assert_not_null(run.roster.get_member(0), "다음 장수는 가장 앞의 빈 칸으로")
	assert_not_null(run.roster.get_member(2))


func test_same_seed_same_draft_and_replay() -> void:
	var a: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	var b: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	assert_eq(a.current_draft_offer(), b.current_draft_offer(), "같은 시드면 같은 후보")
	for i: int in 6:
		a.choose_draft((i * 2) % 3)
	a.choose(0)
	var copy: ExpeditionRun = ExpeditionRun.replay(_db, SEED, a.history)
	assert_eq(copy.history, a.history, "드래프트부터 기록하면 그대로 재현된다")
	assert_eq(copy.log_lines, a.log_lines)
	var ids_a: Array[String] = []
	var ids_copy: Array[String] = []
	for member: RosterMember in a.roster.members():
		ids_a.append(member.general_id)
	for member: RosterMember in copy.roster.members():
		ids_copy.append(member.general_id)
	assert_eq(ids_copy, ids_a)


func test_different_seeds_give_different_offers() -> void:
	var offers: Dictionary[String, bool] = {}
	for s: int in 10:
		offers[str(ExpeditionRun.start_draft(_db, s).current_draft_offer())] = true
	assert_gt(offers.size(), 5, "시드마다 후보가 다르다 (다시 뽑기의 의미)")


func test_healer_shows_up_reasonably_often() -> void:
	var with_healer: int = 0
	for s: int in 100:
		var run: ExpeditionRun = ExpeditionRun.start_draft(_db, s)
		var seen: bool = false
		for i: int in 6:
			for pick: Dictionary in run.current_draft_offer():
				if _db.get_general(String(pick["general_id"])).is_healer():
					seen = true
			run.choose_draft(0)
		if seen:
			with_healer += 1
	assert_between(with_healer, 30, 100, "드래프트 중 힐러 후보를 만나는 런: %d/100" % with_healer)
	gut.p("힐러 후보를 만난 런: %d/100" % with_healer)


func test_invalid_draft_pick_is_rejected() -> void:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	assert_false(run.choose_draft(5))
	assert_push_error("고를 수 없는 드래프트 번호")
	assert_eq(run.draft_pick_count, 0)
