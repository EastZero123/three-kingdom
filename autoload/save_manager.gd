extends Node
## 오토로드 SaveManager: 저장 파일 읽고 쓰기를 맡는다. 무엇을 저장할지는 core/save/의 클래스가 정한다.
## user:// 는 Godot가 정해 주는 사용자 데이터 폴더다. Windows에서는
##   %APPDATA%\Godot\app_userdata\삼국지 원정 로그라이트\
## 파일: save/run.json(진행 중인 런), save/records.json(기록), save/codex.json(도감)

const RUN_FILE: String = "run.json"
const RECORDS_FILE: String = "records.json"
const CODEX_FILE: String = "codex.json"
## 기록은 상위 몇 개까지 남길지.
const RECORD_LIMIT: int = 50

## 저장 폴더. 테스트에서는 다른 폴더로 바꿔 실제 기록을 건드리지 않는다.
var base_dir: String = "user://save"
var records: Array[Dictionary] = []
var codex: Dictionary = {}


func _ready() -> void:
	load_all()


## 기록과 도감을 파일에서 다시 읽는다.
func load_all() -> void:
	records = []
	var raw_records: Dictionary = _read(RECORDS_FILE)
	for item: Variant in raw_records.get("records", []):
		if typeof(item) == TYPE_DICTIONARY:
			records.append(item as Dictionary)
	codex = _read(CODEX_FILE).get("codex", {})


# ---------- 진행 중인 런 ----------

func has_saved_run() -> bool:
	return FileAccess.file_exists(_path(RUN_FILE))


## 저장된 런의 요약 (시작 화면 표시용). 없으면 빈 Dictionary.
func saved_run_info() -> Dictionary:
	return _read(RUN_FILE)


func save_run(run: ExpeditionRun) -> void:
	if run.is_over():
		return
	_write(RUN_FILE, RunSave.to_dict(run))


## 저장된 런을 복원한다. 실패하면(형식이 다르거나 데이터가 바뀜) 저장을 지우고 null.
func load_run(db: GameDatabase) -> ExpeditionRun:
	if not has_saved_run():
		return null
	var data: Dictionary = _read(RUN_FILE)
	var run: ExpeditionRun = null if data.is_empty() else RunSave.restore(db, data)
	if run == null:
		push_warning("저장된 원정을 복원하지 못해 지웁니다 (게임 데이터가 바뀌었을 수 있음).")
		delete_run()
	return run


func delete_run() -> void:
	if has_saved_run():
		DirAccess.remove_absolute(_path(RUN_FILE))


# ---------- 기록 ----------

## 끝난 런을 기록에 넣고 진행 중 저장을 지운다. 기록의 순위(1부터, 남지 못했으면 0)를 돌려준다.
func finish_run(run: ExpeditionRun) -> int:
	var record: Dictionary = RunRecords.make(run, Time.get_datetime_string_from_system(false, true))
	var rank: int = RunRecords.insert(records, record, RECORD_LIMIT)
	_write(RECORDS_FILE, {"records": records})
	delete_run()
	return rank


func best_years() -> int:
	return int(records[0]["years"]) if not records.is_empty() else -1


# ---------- 도감 ----------

## 런의 지금 상태에서 보이는 장수를 도감에 더한다. 새로 추가된 수를 돌려준다.
func update_codex(run: ExpeditionRun) -> int:
	var added: int = Codex.merge(codex, Codex.collect(run))
	if added > 0:
		_write(CODEX_FILE, {"codex": codex})
	return added


## 테스트용: 저장 폴더의 파일을 모두 지우고 메모리의 내용도 비운다.
func clear_all() -> void:
	for file_name: String in [RUN_FILE, RECORDS_FILE, CODEX_FILE]:
		if FileAccess.file_exists(_path(file_name)):
			DirAccess.remove_absolute(_path(file_name))
	records = []
	codex = {}


# ---------- 파일 ----------

func _path(file_name: String) -> String:
	return base_dir.path_join(file_name)


func _read(file_name: String) -> Dictionary:
	var path: String = _path(file_name)
	if not FileAccess.file_exists(path):
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("저장 파일을 읽지 못했습니다: %s" % path)
		return {}
	var data: Dictionary = json.data
	return data


## 임시 파일에 다 쓴 뒤 이름을 바꿔, 쓰는 도중 게임이 꺼져도 기존 파일이 깨지지 않게 한다.
func _write(file_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(base_dir)
	var path: String = _path(file_name)
	var temp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("저장 파일을 쓸 수 없습니다: %s" % temp_path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(temp_path, path)
