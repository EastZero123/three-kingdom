extends SceneTree
## 화면 흐름 캡처 도구: 메인 화면을 띄워 한 라운드를 진행하며 단계마다 PNG를 저장한다.
## 실행: godot --path . -s tests/tools/capture_flow.gd -- <저장 폴더>
## 01_expedition / 02_battle / 03_reward / 04_overlay / 05_next_round

const SEED: int = 12345

var _dir: String = ""
var _main: Control


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://captures"
	DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	await process_frame
	var game_state: Node = root.get_node("GameState")
	game_state.set("next_seed", SEED)
	# 실제 기록을 건드리지 않도록 캡처용 폴더에 저장한다.
	var save_manager: Node = root.get_node("SaveManager")
	save_manager.set("base_dir", "user://capture_save")
	save_manager.call("clear_all")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(5)
	await _shot("00_title")
	# -s 도구 스크립트는 오토로드가 등록되기 전에 컴파일되므로, 오토로드를 쓰는 화면 클래스는 이름으로 참조하지 않는다.
	_current().emit_signal("new_run")
	await _frames(3)
	await _shot("00_draft")
	# 시작 드래프트: 힐러가 후보에 있으면 힐러를, 없으면 첫 후보를 고른다.
	for i: int in 6:
		var draft: DraftView = _current() as DraftView
		var run: ExpeditionRun = game_state.get("run")
		var db: GameDatabase = game_state.get("db")
		var pick: int = 0
		var offer: Array[Dictionary] = run.current_draft_offer()
		for j: int in offer.size():
			if db.get_general(String(offer[j]["general_id"])).is_healer():
				pick = j
		draft.chosen.emit(pick)
		await _frames(3)
		if i == 2:
			await _shot("00_draft_mid")
	await _shot("01_expedition")

	var expedition_view: ExpeditionView = _current() as ExpeditionView
	expedition_view.chosen.emit(1)
	await create_timer(2.2).timeout
	await _shot("02_battle")
	var battle_view: BattleView = _current() as BattleView
	battle_view.press_button()
	await _frames(3)
	battle_view.press_button()
	await _frames(5)
	await _shot("03_reward")

	var reward_view: RewardView = _current() as RewardView
	if reward_view != null:
		# 장수 카드를 고른다 (빈 칸 영입 또는 합성 진행도). 대상이 필요하면 첫 장수.
		reward_view.chosen.emit(1)
		await _frames(2)
		var roster_view: RosterView = _main.get("_roster_view")
		if roster_view._mode == "pick":
			roster_view.slot_picked.emit(0)
		await create_timer(0.3).timeout
		await _shot("04_overlay")
		await create_timer(4.0).timeout
	await _frames(3)
	await _shot("05_next_round")

	# 껐다 켠 것처럼 처음 화면을 다시 띄워 이어하기 버튼과 도감을 본다.
	_main.call("_show_title")
	await _frames(3)
	await _shot("06_title_continue")
	_current().emit_signal("show_codex")
	await _frames(3)
	await _shot("07_codex")
	save_manager.call("clear_all")
	quit(0)


func _current() -> Control:
	var content: PanelContainer = _main.get("_content")
	for child: Node in content.get_children():
		if not child.is_queued_for_deletion():
			return child as Control
	return null


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	var image: Image = root.get_texture().get_image()
	var path: String = _dir.path_join(name + ".png")
	image.save_png(path)
	print("화면 저장: ", path)
