class_name TitleView
extends VBoxContainer
## 시작 화면: 이어하기 / 새 원정 / 기록 / 도감.

signal continue_run
signal new_run
signal show_records
signal show_codex
signal show_online


func setup(db: GameDatabase) -> void:
	add_theme_constant_override("separation", 14)
	alignment = BoxContainer.ALIGNMENT_CENTER
	var title: Label = UiStyle.label("삼국지 원정 로그라이트", 44, UiStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var best: int = SaveManager.best_years()
	var progress: Dictionary = Codex.progress(db, SaveManager.codex)
	var summary: Label = UiStyle.label("최고 기록: %s  ·  도감 %d/%d명" % [
		"생존 %d년" % best if best >= 0 else "없음", progress["generals"], progress["generals_total"]], 18, UiStyle.TEXT_DIM)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(summary)

	if SaveManager.has_saved_run():
		var info: Dictionary = SaveManager.saved_run_info()
		var where: String = "출정 준비 중" if info.get("phase", "") == ExpeditionRun.PHASE_DRAFT else "%d년 %d라운드" % [int(info.get("year", 0)), int(info.get("round", 0))]
		_add_button("이어하기 — %s" % where, func() -> void: continue_run.emit())
		_add_button("새 원정 (진행 중인 원정은 사라집니다)", func() -> void: new_run.emit())
	else:
		_add_button("새 원정", func() -> void: new_run.emit())
	_add_button("기록", func() -> void: show_records.emit())
	if OnlineService.enabled:
		_add_button("온라인 순위", func() -> void: show_online.emit())
	_add_button("도감", func() -> void: show_codex.emit())


func _add_button(text: String, on_pressed: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(on_pressed)
	add_child(button)
