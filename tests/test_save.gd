extends GutTest
## 9단계 저장 테스트: 런 저장·복원, 로컬 기록, 도감, 파일 입출력.
## 실제 기록을 건드리지 않도록 별도 폴더(user://test_save)에 저장한다.

const SEED: int = 12345
const TEST_DIR: String = "user://test_save"

var _db: GameDatabase
var _original_dir: String


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")
	_original_dir = SaveManager.base_dir


func before_each() -> void:
	SaveManager.base_dir = TEST_DIR
	SaveManager.clear_all()


func after_all() -> void:
	SaveManager.clear_all()
	SaveManager.base_dir = _original_dir
	SaveManager.load_all()


# ---------- 런 저장·복원 ----------

func test_run_roundtrip_through_json() -> void:
	var run: ExpeditionRun = _played_run()
	var text: String = JSON.stringify(RunSave.to_dict(run))
	var restored: ExpeditionRun = RunSave.restore(_db, JSON.parse_string(text))
	assert_not_null(restored, "저장 → JSON 글자 → 복원")
	assert_eq(restored.history, run.history)
	assert_eq(restored.log_lines, run.log_lines, "로그까지 똑같이 재현")
	assert_eq(restored.phase, run.phase)
	assert_eq(restored.year, run.year)
	assert_eq(restored.round_number, run.round_number)
	assert_eq(_roster_text(restored), _roster_text(run), "로스터(장수·티어·레벨·체력·자리)가 같다")
	assert_eq(restored.merge_progress, run.merge_progress)


func test_restored_run_continues_identically() -> void:
	var run: ExpeditionRun = _played_run()
	var restored: ExpeditionRun = RunSave.restore(_db, JSON.parse_string(JSON.stringify(RunSave.to_dict(run))))
	if run.phase == ExpeditionRun.PHASE_REWARD:
		run.choose_reward(1, _first_member(run))
		restored.choose_reward(1, _first_member(restored))
	run.choose(0)
	restored.choose(0)
	assert_eq(restored.log_lines, run.log_lines, "복원한 뒤에도 같은 선택이면 같은 결과")


func test_restore_during_draft_and_reward_phase() -> void:
	var draft: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	draft.choose_draft(1)
	var restored_draft: ExpeditionRun = RunSave.restore(_db, RunSave.to_dict(draft))
	assert_eq(restored_draft.phase, ExpeditionRun.PHASE_DRAFT)
	assert_eq(restored_draft.draft_pick_count, 1)
	assert_eq(restored_draft.current_draft_offer(), draft.current_draft_offer(), "드래프트 후보도 그대로")

	var reward: ExpeditionRun = _drafted_run()
	reward.choose(0)
	if reward.phase == ExpeditionRun.PHASE_REWARD:
		var restored_reward: ExpeditionRun = RunSave.restore(_db, RunSave.to_dict(reward))
		assert_eq(restored_reward.phase, ExpeditionRun.PHASE_REWARD, "보상을 고르기 전 상태로 복원")
		assert_eq(restored_reward.current_rewards().size(), reward.current_rewards().size())


func test_invalid_saves_are_rejected() -> void:
	var data: Dictionary = RunSave.to_dict(_played_run())
	var wrong_version: Dictionary = data.duplicate(true)
	wrong_version["version"] = 999
	assert_null(RunSave.restore(_db, wrong_version), "다른 버전은 불러오지 않는다")

	var broken: Dictionary = data.duplicate(true)
	var history: Array = broken["history"]
	history.append({"type": "expedition", "index": 99})
	assert_null(RunSave.restore(_db, broken), "끝까지 재현할 수 없는 기록은 거부")
	assert_push_error("고를 수 없는 토벌 번호")

	var mismatch: Dictionary = data.duplicate(true)
	mismatch["year"] = 300
	assert_null(RunSave.restore(_db, mismatch), "재현 결과가 저장 당시와 다르면 거부")


# ---------- 저장 관리자 (파일) ----------

func test_save_manager_saves_and_loads_run() -> void:
	var run: ExpeditionRun = _played_run()
	assert_false(SaveManager.has_saved_run())
	SaveManager.save_run(run)
	assert_true(SaveManager.has_saved_run())
	assert_eq(int(SaveManager.saved_run_info()["year"]), run.year)
	var loaded: ExpeditionRun = SaveManager.load_run(_db)
	assert_not_null(loaded)
	assert_eq(loaded.log_lines, run.log_lines)


func test_corrupt_save_is_discarded() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file: FileAccess = FileAccess.open(TEST_DIR.path_join("run.json"), FileAccess.WRITE)
	file.store_string("{ 깨진 파일")
	file.close()
	assert_null(SaveManager.load_run(_db))
	assert_false(SaveManager.has_saved_run(), "읽을 수 없는 저장은 지운다")


func test_finish_run_records_and_deletes_save() -> void:
	var run: ExpeditionRun = _drafted_run()
	SaveManager.save_run(run)
	for member: RosterMember in run.roster.members():
		member.hp = 1
	run.choose(2)
	assert_true(run.is_over())
	var rank: int = SaveManager.finish_run(run)
	assert_eq(rank, 1)
	assert_false(SaveManager.has_saved_run(), "끝난 런의 진행 저장은 지운다")
	assert_eq(SaveManager.records.size(), 1)
	var record: Dictionary = SaveManager.records[0]
	assert_eq(int(record["seed"]), SEED)
	assert_eq(int(record["years"]), 0)
	assert_eq((record["roster"] as Array).size(), 6, "최종 로스터 = 마지막 전투 직전의 로스터")
	assert_eq((record["actions"] as Array).size(), run.history.size(), "검증용 행동 기록도 남긴다")

	# 파일에서 다시 읽어도 남아 있다.
	SaveManager.load_all()
	assert_eq(SaveManager.records.size(), 1)
	assert_eq(SaveManager.best_years(), 0)


func test_recorded_actions_reproduce_the_run() -> void:
	var run: ExpeditionRun = _drafted_run()
	for member: RosterMember in run.roster.members():
		member.hp = 1
	run.choose(2)
	SaveManager.finish_run(run)
	var actions: Array[Dictionary] = []
	for item: Variant in SaveManager.records[0]["actions"]:
		actions.append(item as Dictionary)
	var copy: ExpeditionRun = ExpeditionRun.replay(_db, SEED, actions)
	# 체력을 직접 1로 바꾼 런이라 결과는 다를 수 있지만, 기록한 행동은 모두 다시 실행된다.
	assert_eq(copy.history.size(), actions.size())


# ---------- 기록 순위 ----------

func test_records_sorted_by_years_then_progress() -> void:
	var records: Array[Dictionary] = []
	assert_eq(RunRecords.insert(records, _record(2, 186, 5), 50), 1)
	assert_eq(RunRecords.insert(records, _record(5, 189, 1), 50), 1, "더 오래 버틴 기록이 1위")
	assert_eq(RunRecords.insert(records, _record(2, 186, 8), 50), 2, "같은 연수면 더 멀리 간 쪽이 위")
	assert_eq(RunRecords.insert(records, _record(2, 186, 5), 50), 4, "완전히 같으면 먼저 세운 기록이 위")
	var years: Array[int] = []
	for record: Dictionary in records:
		years.append(int(record["years"]))
	assert_eq(years, [5, 2, 2, 2] as Array[int])


func test_records_keep_only_limit() -> void:
	var records: Array[Dictionary] = []
	for i: int in 5:
		RunRecords.insert(records, _record(i + 1, 185 + i, 1), 3)
	assert_eq(records.size(), 3)
	assert_eq(int(records[2]["years"]), 3)
	assert_eq(RunRecords.insert(records, _record(0, 184, 1), 3), 0, "순위에 못 들면 0")


# ---------- 도감 ----------

func test_codex_collects_draft_enemies_and_roster() -> void:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	var found: Dictionary = Codex.collect(run)
	for pick: Dictionary in run.current_draft_offer():
		assert_true((found[pick["general_id"]] as Array).has(pick["tier"]), "드래프트 후보는 만난 것으로 친다")

	var started: ExpeditionRun = _drafted_run()
	var seen: Dictionary = Codex.collect(started)
	for expedition: Expedition in started.current_choices():
		for enemy: Dictionary in expedition.enemies:
			assert_true(Codex.has_met(seen, String(enemy["general_id"]), String(enemy["tier"])), "토벌 선택지의 적도 만난 것")
	for member: RosterMember in started.roster.members():
		assert_true(Codex.has_met(seen, member.general_id, member.tier))


func test_codex_merge_counts_only_new() -> void:
	var codex: Dictionary = {}
	assert_eq(Codex.merge(codex, {"guan_yu": ["C"], "lu_bu": ["B", "A"]}), 3)
	assert_eq(Codex.merge(codex, {"guan_yu": ["C", "B"]}), 1, "이미 만난 티어는 세지 않는다")
	assert_eq(codex, {"guan_yu": ["C", "B"], "lu_bu": ["B", "A"]})
	var progress: Dictionary = Codex.progress(_db, codex)
	assert_eq(progress["generals"], 2)
	assert_eq(progress["tiers"], 4)
	assert_eq(progress["generals_total"], 66)


func test_codex_persists_across_runs() -> void:
	SaveManager.update_codex(ExpeditionRun.start_draft(_db, 1))
	var first: int = Codex.progress(_db, SaveManager.codex)["tiers"]
	SaveManager.load_all()
	assert_eq(Codex.progress(_db, SaveManager.codex)["tiers"], first, "도감은 파일에 남는다")
	SaveManager.update_codex(ExpeditionRun.start_draft(_db, 2))
	assert_true(Codex.progress(_db, SaveManager.codex)["tiers"] >= first, "도감은 줄어들지 않는다")


# ---------- 테스트용 도우미 ----------

func _drafted_run() -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	for i: int in 6:
		run.choose_draft(i % 3)
	return run


## 드래프트 → 토벌 몇 번 → 자리 이동까지 한 런.
func _played_run() -> ExpeditionRun:
	var run: ExpeditionRun = _drafted_run()
	run.swap_slots(0, 6)
	for i: int in 3:
		if run.phase != ExpeditionRun.PHASE_EXPEDITION:
			break
		run.choose(0)
		if run.phase == ExpeditionRun.PHASE_REWARD and i < 2:
			run.choose_reward(0, _first_member(run))
	return run


func _first_member(run: ExpeditionRun) -> int:
	for slot: int in run.roster.size():
		if run.roster.get_member(slot) != null:
			return slot
	return -1


func _roster_text(run: ExpeditionRun) -> Array[String]:
	var result: Array[String] = []
	for slot: int in run.roster.size():
		var member: RosterMember = run.roster.get_member(slot)
		result.append("-" if member == null else "%s %s %d %d/%d %d" % [member.general_id, member.tier, member.level, member.hp, member.max_hp, member.experience])
	return result


func _record(years: int, year: int, round_number: int) -> Dictionary:
	return {"seed": 1, "years": years, "year": year, "round": round_number, "ended_at": "", "roster": [], "fallen": 0, "actions": []}
