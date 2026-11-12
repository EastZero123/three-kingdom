class_name OnlineLeaderboardView
extends VBoxContainer
## 온라인 순위 화면: 서버에서 검증을 통과한 기록의 순위를 받아 보여 준다.

signal back

var _rows: VBoxContainer


func setup() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UiStyle.label("온라인 순위 — 검증을 통과한 기록", 26, UiStyle.GOLD))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	add_child(scroll)
	_rows.add_child(UiStyle.label("불러오는 중…", 18, UiStyle.TEXT_DIM))

	var button: Button = Button.new()
	button.text = "돌아가기"
	button.custom_minimum_size = Vector2(160, 40)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.pressed.connect(func() -> void: back.emit())
	add_child(button)


## 받은 순위를 보인다. my_name과 같은 이름은 금색으로.
func show_entries(entries: Array, my_name: String) -> void:
	_clear_rows()
	if entries.is_empty():
		_rows.add_child(UiStyle.label("아직 등록된 기록이 없습니다.", 18, UiStyle.TEXT_DIM))
		return
	for item: Variant in entries:
		var entry: Dictionary = item
		var mine: bool = not my_name.is_empty() and String(entry.get("playerName", "")) == my_name
		var row: Label = UiStyle.label("%d위   %s   생존 %d년   %d년 %d라운드에서 패배   버전 %s   시드 %d" % [
			int(entry.get("rank", 0)), entry.get("playerName", "?"), int(entry.get("years", 0)),
			int(entry.get("finalYear", 0)), int(entry.get("finalRound", 0)), entry.get("gameVersion", ""),
			int(entry.get("seed", 0))], 17, UiStyle.GOLD if mine else Color.WHITE)
		_rows.add_child(row)


func show_error(message: String) -> void:
	_clear_rows()
	_rows.add_child(UiStyle.label("순위를 불러오지 못했습니다: %s" % message, 18, UiStyle.DANGER))


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
