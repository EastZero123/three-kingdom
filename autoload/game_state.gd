extends Node
## 오토로드(Autoload): 게임을 켜면 자동으로 만들어져 씬이 바뀌어도 계속 살아 있는 노드.
## project.godot에 "GameState"라는 이름으로 등록해 두었으므로, 어느 스크립트에서든 GameState.run처럼 바로 쓴다.
## 게임 데이터와 지금 진행 중인 런을 들고 있다.

var db: GameDatabase = null
var run: ExpeditionRun = null
## 다음 런에 쓸 시드. 0이면 무작위로 정한다 (테스트와 화면 캡처에서 고정할 때 쓴다).
var next_seed: int = 0


func _ready() -> void:
	db = GameDatabase.load_from_dir("res://data")
	for message: String in db.errors:
		push_error(message)
	# 배포판에서도 데이터가 제대로 들어갔는지 로그(user://logs/godot.log)로 확인할 수 있게 남긴다.
	print("게임 데이터: 장수 %d명, 스킬 %d개, 상자 %d종, 오류 %d건" % [db.generals.size(), db.skills.size(), db.chests.size(), db.errors.size()])


func new_run() -> void:
	var seed_value: int = next_seed
	if seed_value == 0:
		seed_value = randi_range(1, 999999999)
	next_seed = 0
	# 화면에서 하는 게임은 시작 드래프트부터 한다.
	run = ExpeditionRun.start_draft(db, seed_value)


## 저장된 원정을 불러온다. 성공하면 true.
func continue_run() -> bool:
	var loaded: ExpeditionRun = SaveManager.load_run(db)
	if loaded == null:
		return false
	run = loaded
	return true
