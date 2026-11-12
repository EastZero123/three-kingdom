extends SceneTree
## 서버 검증용: 제출된 기록(시드 + 행동 기록)을 처음부터 다시 실행해, 주장한 결과와 같은지 확인한다.
## 실행: godot --headless --path <게임 프로젝트> -s verify/verify_run.gd -- <입력 JSON 파일>
## 입력: {"seed": 정수, "actions": [...], "years": 정수, "year": 정수, "round": 정수, "game_version": "문자열"}
## 출력: 마지막에 아래 한 줄을 찍는다. 서버는 이 접두어로 결과 줄을 찾는다.
##   VERIFY_RESULT {"ok": true/false, "years": 재현한 생존 연수, "year": …, "round": …, "reason": "실패 이유(영문 코드)"}
## 이 스크립트는 core/ 로직만 쓴다. 오토로드·화면 클래스는 참조하지 않는다 (-s 스크립트는 오토로드보다 먼저 컴파일되므로).

const PREFIX: String = "VERIFY_RESULT "


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_finish({"ok": false, "reason": "no_input"})
		return
	# 파일을 열 수 없는 경우(권한, 없는 경로)와 내용이 JSON이 아닌 경우를 구분해 알린다.
	var file: FileAccess = FileAccess.open(args[0], FileAccess.READ)
	if file == null:
		_finish({"ok": false, "reason": "cannot_read_input", "error": error_string(FileAccess.get_open_error()), "path": args[0]})
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_finish({"ok": false, "reason": "bad_json"})
		return
	_finish(verify(parsed))


## 기록 하나를 검증한다. 테스트에서도 부를 수 있도록 결과를 Dictionary로 돌려준다.
static func verify(input: Dictionary) -> Dictionary:
	var game_version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	if String(input.get("game_version", "")) != game_version:
		return {"ok": false, "reason": "game_version", "server_version": game_version}
	if typeof(input.get("actions")) != TYPE_ARRAY or not DataReader.is_number(input.get("seed")):
		return {"ok": false, "reason": "bad_input"}

	var db: GameDatabase = GameDatabase.load_from_dir("res://data")
	if not db.is_valid():
		return {"ok": false, "reason": "server_data_invalid"}

	var actions: Array[Dictionary] = []
	for item: Variant in input["actions"]:
		if typeof(item) != TYPE_DICTIONARY or not (item as Dictionary).has("type"):
			return {"ok": false, "reason": "bad_action"}
		actions.append(item as Dictionary)

	var run: ExpeditionRun = ExpeditionRun.replay(db, int(input["seed"]), actions)
	var result: Dictionary = {"years": run.years_survived(), "year": run.year, "round": run.round_number}
	if run.history.size() != actions.size():
		result["ok"] = false
		result["reason"] = "replay_diverged"  # 기록 중간의 행동을 다시 실행할 수 없었다
	elif not run.is_over():
		result["ok"] = false
		result["reason"] = "run_not_finished"  # 패배로 끝나지 않은 기록
	elif run.years_survived() != int(input.get("years", -1)) or run.year != int(input.get("year", -1)) or run.round_number != int(input.get("round", -1)):
		result["ok"] = false
		result["reason"] = "result_mismatch"  # 주장한 결과와 재현한 결과가 다르다
	else:
		result["ok"] = true
		result["reason"] = ""
	return result


func _finish(result: Dictionary) -> void:
	print(PREFIX + JSON.stringify(result))
	quit(0)
