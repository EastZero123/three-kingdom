extends GutTest
## 10단계 온라인 기능 테스트.
## 서버가 필요한 테스트는 환경 변수 ONLINE_TEST_URL(예: http://localhost:8080)이 있을 때만 돈다.

const SAMPLE_PATH: String = "res://server/src/test/resources/sample_finished_run.json"

var _saved_enabled: bool
var _saved_url: String


func before_each() -> void:
	_saved_enabled = OnlineService.enabled
	_saved_url = OnlineService.api_base_url


func after_each() -> void:
	OnlineService.enabled = _saved_enabled
	OnlineService.api_base_url = _saved_url


func test_config_loads_from_data() -> void:
	# 서버 주소는 배포 환경마다 바뀌므로 값 자체가 아니라 data/online.json과 같게 읽혔는지만 본다.
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/online.json"))
	OnlineService.load_config("res://data/online.json")
	assert_eq(OnlineService.enabled, bool(config["enabled"]))
	assert_eq(OnlineService.api_base_url, String(config["api_base_url"]).trim_suffix("/"))
	assert_true(OnlineService.api_base_url.begins_with("http"), "주소는 http로 시작한다")
	assert_false(OnlineService.api_base_url.ends_with("/"), "끝의 /는 떼어 낸다")


func test_missing_config_disables_online() -> void:
	OnlineService.load_config("res://no_such_online.json")
	assert_false(OnlineService.enabled, "설정 파일이 없으면 온라인 기능은 꺼진다")


func test_submit_body_matches_server_request() -> void:
	var record: Dictionary = {"seed": 77, "years": 3, "year": 187, "round": 4, "actions": [{"type": "draft", "index": 0}]}
	var body: Dictionary = OnlineService.make_submit_body(record, "  아주아주아주아주아주아주아주긴이름입니다  ")
	assert_eq(body["playerName"].length(), 20, "이름은 앞뒤 공백을 빼고 20자까지")
	assert_eq(body["seed"], 77)
	assert_eq(body["years"], 3)
	assert_eq(body["gameVersion"], String(ProjectSettings.get_setting("application/config/version")))
	assert_eq((body["actions"] as Array).size(), 1)


func test_disabled_service_fails_without_network() -> void:
	OnlineService.enabled = false
	var result: Dictionary = await OnlineService.fetch_leaderboard()
	assert_false(result["ok"])
	assert_eq(result["code"], 0)


func test_unreachable_server_reports_error() -> void:
	OnlineService.enabled = true
	OnlineService.api_base_url = "http://127.0.0.1:9"  # 아무도 듣지 않는 포트
	var result: Dictionary = await OnlineService.fetch_leaderboard()
	assert_false(result["ok"])
	assert_eq(result["error"], "서버에 연결할 수 없습니다")


# ---------- 진짜 서버 (ONLINE_TEST_URL이 있을 때만) ----------

func test_real_server_submit_verify_leaderboard() -> void:
	var url: String = OS.get_environment("ONLINE_TEST_URL")
	if url.is_empty():
		pass_test("ONLINE_TEST_URL이 없어 건너뜀")
		return
	OnlineService.enabled = true
	OnlineService.api_base_url = url
	var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_PATH))
	var record: Dictionary = {
		"seed": sample["seed"], "actions": sample["actions"], "years": sample["years"],
		"year": sample["year"], "round": sample["round"],
	}
	var submitted: Dictionary = await OnlineService.submit_run(record, "통합 테스트")
	assert_true(submitted["ok"], "제출 성공 (%s)" % submitted)
	var run_id: int = int((submitted["body"] as Dictionary)["id"])

	# 서버가 Godot로 다시 실행해 검증할 때까지 기다린다.
	var status: String = "PENDING"
	for i: int in 30:
		await wait_seconds(0.5)
		var check: Dictionary = await OnlineService.fetch_run(run_id)
		status = String((check["body"] as Dictionary).get("status", ""))
		if status != "PENDING":
			break
	assert_eq(status, "VERIFIED", "정직한 기록은 서버 검증을 통과한다")

	var board: Dictionary = await OnlineService.fetch_leaderboard()
	assert_true(board["ok"])
	var found: bool = false
	for entry: Variant in board["body"]:
		if int((entry as Dictionary)["seed"]) == int(sample["seed"]):
			found = true
	assert_true(found, "온라인 순위에 올랐다")
