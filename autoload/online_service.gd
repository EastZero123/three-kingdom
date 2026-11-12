extends Node
## 오토로드 OnlineService: 온라인 랭킹 서버와 통신한다 (HTTPRequest 노드 사용).
## 서버 주소는 data/online.json의 api_base_url. 실행 파일에는 서버 주소만 들어가고, DB 주소·비밀번호는 들어가지 않는다.
## 사용 예 (await: 응답이 올 때까지 그 함수만 기다린다):
##   var result: Dictionary = await OnlineService.submit_run(record, "조운")
##   if result["ok"]: print(result["body"]["status"])

const CONFIG_PATH: String = "res://data/online.json"

var enabled: bool = false
var api_base_url: String = ""
var timeout_seconds: float = 10.0


func _ready() -> void:
	load_config(CONFIG_PATH)


func load_config(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		enabled = false
		return
	var config: Dictionary = parsed
	enabled = bool(config.get("enabled", false))
	api_base_url = String(config.get("api_base_url", "")).trim_suffix("/")
	timeout_seconds = float(config.get("timeout_seconds", 10))
	if api_base_url.is_empty():
		enabled = false


## 로컬 기록 한 줄로 서버에 보낼 요청 본문을 만든다 (서버의 SubmitRunRequest와 같은 모양).
static func make_submit_body(record: Dictionary, player_name: String) -> Dictionary:
	return {
		"playerName": player_name.strip_edges().left(20),
		"seed": int(record["seed"]),
		"actions": record["actions"],
		"years": int(record["years"]),
		"year": int(record["year"]),
		"round": int(record["round"]),
		"gameVersion": String(ProjectSettings.get_setting("application/config/version", "")),
	}


## 기록을 제출한다. 돌려주는 값: {ok, code, body, error}
##   202 = 접수됨(검증 중), 409 = 이미 올린 기록. 둘 다 ok로 본다.
func submit_run(record: Dictionary, player_name: String) -> Dictionary:
	var result: Dictionary = await _request("/runs", HTTPClient.METHOD_POST, JSON.stringify(make_submit_body(record, player_name)))
	result["ok"] = result["code"] == 202 or result["code"] == 409
	return result


## 제출한 기록의 검증 상태를 묻는다.
func fetch_run(run_id: int) -> Dictionary:
	var result: Dictionary = await _request("/runs/%d" % run_id, HTTPClient.METHOD_GET, "")
	result["ok"] = result["code"] == 200
	return result


## 온라인 순위를 받는다. 성공하면 body가 순위 목록(Array)이다.
func fetch_leaderboard(limit: int = 20) -> Dictionary:
	var result: Dictionary = await _request("/leaderboard?limit=%d" % limit, HTTPClient.METHOD_GET, "")
	result["ok"] = result["code"] == 200 and typeof(result["body"]) == TYPE_ARRAY
	return result


## HTTP 요청 하나. 응답이 오거나 시간이 다 될 때까지 기다린다.
## 돌려주는 값: {code: HTTP 상태 코드(연결 실패면 0), body: 해석한 JSON, error: 실패 설명}
func _request(path: String, method: int, body: String) -> Dictionary:
	if not enabled:
		return {"code": 0, "body": null, "error": "온라인 기능이 꺼져 있습니다"}
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var started: Error = http.request(api_base_url + path, headers, method, body)
	if started != OK:
		http.queue_free()
		return {"code": 0, "body": null, "error": "요청을 보낼 수 없습니다"}
	# 시그널을 await하면 그 시그널의 인자들이 배열로 돌아온다: [result, response_code, headers, body]
	var response: Array = await http.request_completed
	http.queue_free()
	var transport: int = response[0]
	var code: int = response[1]
	var raw: PackedByteArray = response[3]
	if transport != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "body": null, "error": "서버에 연결할 수 없습니다"}
	var text: String = raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return {"code": code, "body": parsed, "error": "" if code >= 200 and code < 300 else "서버 응답 %d" % code}
