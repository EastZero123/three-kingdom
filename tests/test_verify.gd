extends GutTest
## 10단계 검증 스크립트 테스트: 정상 기록은 통과하고, 조작·미완료·버전 불일치 기록은 거부한다.

const SEED: int = 12345

var _db: GameDatabase
var _verifier: GDScript


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")
	_verifier = load("res://verify/verify_run.gd")


func test_honest_record_passes() -> void:
	var result: Dictionary = _verify(_finished_input())
	assert_true(result["ok"], "정상 기록은 통과 (%s)" % result)
	assert_eq(result["reason"], "")


func test_record_survives_json_roundtrip() -> void:
	# 서버를 거치면 숫자가 모두 실수가 되므로, JSON을 한 번 거친 기록도 통과해야 한다.
	var input: Dictionary = JSON.parse_string(JSON.stringify(_finished_input()))
	assert_true(_verify(input)["ok"])


func test_inflated_years_are_rejected() -> void:
	var input: Dictionary = _finished_input()
	input["years"] = int(input["years"]) + 5
	var result: Dictionary = _verify(input)
	assert_false(result["ok"])
	assert_eq(result["reason"], "result_mismatch", "생존 연수를 부풀리면 거부")


func test_tampered_actions_are_rejected() -> void:
	var input: Dictionary = _finished_input()
	var actions: Array = input["actions"]
	actions.insert(3, {"type": "expedition", "index": 99})
	var result: Dictionary = _verify(input)
	assert_false(result["ok"])
	assert_eq(result["reason"], "replay_diverged", "실행할 수 없는 행동이 끼면 거부")
	assert_push_error("고를 수 없는")


func test_unfinished_run_is_rejected() -> void:
	var run: ExpeditionRun = _drafted_run()
	var input: Dictionary = _input_for(run)
	var result: Dictionary = _verify(input)
	assert_false(result["ok"])
	assert_eq(result["reason"], "run_not_finished", "패배로 끝나지 않은 기록은 거부")


func test_wrong_game_version_is_rejected() -> void:
	var input: Dictionary = _finished_input()
	input["game_version"] = "0.0.1"
	var result: Dictionary = _verify(input)
	assert_false(result["ok"])
	assert_eq(result["reason"], "game_version")


func test_bad_input_is_rejected() -> void:
	assert_eq(_verify({"game_version": _version(), "seed": "abc", "actions": []})["reason"], "bad_input")
	assert_eq(_verify({"game_version": _version(), "seed": 1, "actions": [5]})["reason"], "bad_action")


# ---------- 도우미 ----------

func _verify(input: Dictionary) -> Dictionary:
	return _verifier.call("verify", input)


func _version() -> String:
	return String(ProjectSettings.get_setting("application/config/version"))


func _drafted_run() -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	for i: int in 6:
		run.choose_draft(i % 3)
	return run


## 실제로 끝까지 플레이한 기록 (자동으로 가장 쉬운 토벌을 고르다 패배할 때까지).
func _finished_input() -> Dictionary:
	var run: ExpeditionRun = _drafted_run()
	var guard: int = 0
	while not run.is_over() and guard < 400:
		guard += 1
		if run.phase == ExpeditionRun.PHASE_EXPEDITION:
			run.choose(0)
		elif run.phase == ExpeditionRun.PHASE_REWARD:
			var target: int = -1
			for slot: int in run.roster.size():
				if run.roster.get_member(slot) != null:
					target = slot
					break
			run.choose_reward(0, target)
	assert_true(run.is_over(), "테스트용 런이 패배로 끝났다")
	return _input_for(run)


func _input_for(run: ExpeditionRun) -> Dictionary:
	return {
		"seed": run.run_seed, "actions": run.history.duplicate(true),
		"years": run.years_survived(), "year": run.year, "round": run.round_number,
		"game_version": _version(),
	}
