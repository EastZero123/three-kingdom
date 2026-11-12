class_name GameOverView
extends VBoxContainer
## 원정 종료 화면: 생존 연수(기록)와 전사한 장수, 온라인 랭킹 등록, 새 원정 버튼.

signal restart
signal to_title
## 온라인 랭킹에 등록하기를 눌렀다 (입력한 이름).
signal submit_online(player_name: String)

var _online_status: Label
var _name_edit: LineEdit
var _submit_button: Button


## online_enabled: 온라인 기능이 켜져 있으면 이름 입력칸과 등록 버튼을 보인다.
func setup(db: GameDatabase, run: ExpeditionRun, rank: int = 0, online_enabled: bool = false, player_name: String = "") -> void:
	add_theme_constant_override("separation", 12)
	add_child(UiStyle.label("원정 종료", 34, UiStyle.DANGER))
	add_child(UiStyle.label("생존 %d년" % run.years_survived(), 48, UiStyle.GOLD))
	if rank > 0:
		add_child(UiStyle.label("기록 %d위%s" % [rank, " — 최고 기록!" if rank == 1 else ""], 22, UiStyle.GOLD if rank == 1 else Color.WHITE))
	add_child(UiStyle.label("%d년 %d라운드에서 패배 · 시드 %d" % [run.year, run.round_number, run.run_seed], 18, UiStyle.TEXT_DIM))

	var names: Array[String] = []
	for entry: Dictionary in run.fallen:
		names.append("%s(%s)" % [db.get_general(String(entry["general_id"])).name, entry["tier"]])
	var fallen_label: Label = UiStyle.label("전사한 장수 %d명: %s" % [names.size(), ", ".join(names)], 16)
	fallen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(fallen_label)

	if online_enabled:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_name_edit = LineEdit.new()
		_name_edit.placeholder_text = "온라인 랭킹 이름 (최대 20자)"
		_name_edit.max_length = 20
		_name_edit.text = player_name
		_name_edit.custom_minimum_size = Vector2(280, 40)
		row.add_child(_name_edit)
		_submit_button = Button.new()
		_submit_button.text = "온라인 랭킹에 등록"
		_submit_button.custom_minimum_size = Vector2(200, 40)
		_submit_button.pressed.connect(_on_submit_pressed)
		row.add_child(_submit_button)
		add_child(row)
		_online_status = UiStyle.label("", 16, UiStyle.TEXT_DIM)
		add_child(_online_status)

	var button: Button = Button.new()
	button.text = "새 원정 시작"
	button.custom_minimum_size = Vector2(220, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(func() -> void: restart.emit())
	add_child(button)

	var title_button: Button = Button.new()
	title_button.text = "처음 화면으로"
	title_button.custom_minimum_size = Vector2(220, 40)
	title_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title_button.pressed.connect(func() -> void: to_title.emit())
	add_child(title_button)


## 온라인 등록 진행 상황을 보인다. done이 참이면 다시 누를 수 없게 한다.
func show_online_status(text: String, color: Color, done: bool = false) -> void:
	if _online_status == null:
		return
	_online_status.text = text
	_online_status.add_theme_color_override("font_color", color)
	_submit_button.disabled = done
	_name_edit.editable = not done


func _on_submit_pressed() -> void:
	var name: String = _name_edit.text.strip_edges()
	if name.is_empty():
		show_online_status("이름을 입력하세요.", UiStyle.DANGER)
		return
	_submit_button.disabled = true
	show_online_status("서버에 보내는 중…", UiStyle.TEXT_DIM)
	submit_online.emit(name)
