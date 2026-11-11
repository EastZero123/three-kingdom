class_name UnitCard
extends PanelContainer
## 장수 한 명을 보여 주는 작은 카드: 이름·티어, 레벨, 체력 막대.
## 시그널(signal): "무슨 일이 일어났다"를 바깥에 알리는 방법. 카드를 누르면 pressed를 내보내고,
## 이 카드를 만든 쪽이 card.pressed.connect(함수)로 연결해 두면 그 함수가 불린다.

signal pressed(card: UnitCard)

const CARD_SIZE: Vector2 = Vector2(128, 88)

## 이 카드가 가리키는 슬롯 번호 (로스터 화면용).
var slot: int = -1

var _title: Label
var _sub: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _fill: StyleBoxFlat
var _border_color: Color = UiStyle.BORDER
var _selected: bool = false


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_title = _make_label(column, 16)
	_sub = _make_label(column, 13)
	_sub.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 9)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = UiStyle.box(UiStyle.hp_color(1.0), UiStyle.hp_color(1.0), 0, 3)
	_fill.set_content_margin_all(0)
	var bar_background: StyleBoxFlat = UiStyle.box(Color("15171b"), Color("15171b"), 0, 3)
	bar_background.set_content_margin_all(0)
	_hp_bar.add_theme_stylebox_override("fill", _fill)
	_hp_bar.add_theme_stylebox_override("background", bar_background)
	column.add_child(_hp_bar)
	_hp_text = _make_label(column, 13)
	_apply_style()


## 좁은 카드로 바꾼다 (한 줄에 카드가 많을 때).
func set_compact() -> void:
	custom_minimum_size = Vector2(104, CARD_SIZE.y)
	_title.add_theme_font_size_override("font_size", 14)


## 장수를 보여 준다.
func show_general(general_name: String, tier: String, level: int, hp: int, max_hp: int) -> void:
	_title.text = "%s  %s" % [general_name, tier]
	_title.add_theme_color_override("font_color", Color.WHITE)
	_sub.text = "Lv.%d" % level
	_border_color = UiStyle.tier_color(tier)
	_hp_bar.visible = true
	set_hp(hp, max_hp)
	_apply_style()


## 빈 칸을 보여 준다.
func show_empty(text: String = "빈 칸") -> void:
	_title.text = text
	_title.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_sub.text = ""
	_hp_text.text = ""
	_hp_bar.visible = false
	_border_color = UiStyle.BORDER
	modulate = Color.WHITE
	_apply_style()


func set_hp(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	var ratio: float = float(hp) / float(maxi(1, max_hp))
	_fill.bg_color = UiStyle.hp_color(ratio)
	_hp_text.text = "체력 %d/%d" % [hp, max_hp] if hp > 0 else "쓰러짐"
	# 쓰러진 장수는 흐리게.
	modulate = Color(1, 1, 1, 0.35) if hp <= 0 else Color.WHITE


func set_selected(value: bool) -> void:
	_selected = value
	_apply_style()


func _apply_style() -> void:
	var background: Color = Color("33404f") if _selected else UiStyle.PANEL
	var border: Color = UiStyle.GOLD if _selected else _border_color
	add_theme_stylebox_override("panel", UiStyle.box(background, border, 3 if _selected else 2, 6))


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)


func _make_label(parent: Control, font_size: int) -> Label:
	var result: Label = Label.new()
	result.add_theme_font_size_override("font_size", font_size)
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result
