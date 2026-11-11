class_name MergeOverlay
extends ColorRect
## 연쇄 합성·승급·치유·보물상자 연출: 화면 가운데에 한 줄씩 크게 띄운다. 누르면 건너뛴다.
## 트윈(Tween): 값(크기, 투명도 등)을 시간에 걸쳐 부드럽게 바꿔 주는 도구. create_tween()으로 만든다.

signal finished

const LINE_SECONDS: float = 0.8

var _label: Label
var _skip: bool = false


func _init() -> void:
	color = Color(0, 0, 0, 0.72)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 30)
	add_child(_label)


func play(lines: Array[String]) -> void:
	_skip = false
	visible = true
	for line: String in lines:
		if _skip:
			break
		_label.text = line.strip_edges()
		_label.add_theme_color_override("font_color", _color_for(line))
		_label.pivot_offset = size / 2.0
		_label.scale = Vector2(0.6, 0.6)
		_label.modulate = Color(1, 1, 1, 0)
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_label, "modulate:a", 1.0, 0.2)
		await _wait(LINE_SECONDS)
	visible = false
	finished.emit()


func skip() -> void:
	_skip = true


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed:
		skip()


func _color_for(line: String) -> Color:
	if line.contains("승급"):
		return UiStyle.GOLD
	if line.contains("합성"):
		return UiStyle.MERGE
	if line.contains("치유"):
		return UiStyle.HEAL
	if line.contains("보물상자"):
		return UiStyle.CHEST
	if line.contains("방출") or line.contains("전사"):
		return UiStyle.DANGER
	return Color.WHITE


func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds and not _skip and is_inside_tree():
		await get_tree().process_frame
		elapsed += get_process_delta_time()
