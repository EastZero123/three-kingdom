class_name GameOverView
extends VBoxContainer
## 원정 종료 화면: 생존 연수(기록)와 전사한 장수, 새 원정 버튼.

signal restart
signal to_title


func setup(db: GameDatabase, run: ExpeditionRun, rank: int = 0) -> void:
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
