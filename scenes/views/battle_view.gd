class_name BattleView
extends VBoxContainer
## 전투 화면: 이미 계산이 끝난 전투(BattleEngine)를 행동 하나씩 재생한다.
## 전투 계산은 로직 쪽에서 한 번에 끝나고, 이 화면은 frames 기록을 따라 체력과 로그만 갱신한다.

signal finished

## 행동 하나를 보여 주는 시간(초).
const STEP_SECONDS: float = 0.35

var _engine: BattleEngine = null
var _cards: Array[UnitCard] = []
var _log: RichTextLabel
var _button: Button
var _shown_lines: int = 0
var _skip: bool = false
var _done: bool = false


func play(db: GameDatabase, engine: BattleEngine, title: String) -> void:
	_engine = engine
	add_theme_constant_override("separation", 6)
	add_child(UiStyle.label("전투 — %s" % title, 20))

	var enemy_row: HBoxContainer = _make_row("적")
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.PANEL_DARK))
	add_child(_log)
	var ally_row: HBoxContainer = _make_row("아군")

	# 한쪽이 6명을 넘으면 카드를 좁혀 한 줄에 들어가게 한다.
	var compact: bool = engine.living_units(BattleEngine.SIDE_ENEMY).size() > 6 or engine.living_units(BattleEngine.SIDE_PLAYER).size() > 6
	for unit: BattleUnit in engine.units:
		var card: UnitCard = UnitCard.new()
		if compact:
			card.set_compact()
		card.show_general(unit.name, unit.tier, unit.level, unit.hp, unit.max_hp)
		card.tooltip_text = "%s %s 자리" % [unit.side_label(), "전열" if unit.is_front else "후열"]
		(ally_row if unit.side == BattleEngine.SIDE_PLAYER else enemy_row).add_child(card)
		_cards.append(card)

	_button = Button.new()
	_button.text = "건너뛰기"
	_button.custom_minimum_size = Vector2(160, 36)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.pressed.connect(press_button)
	add_child(_button)

	_apply_frame(0)
	for index: int in range(1, engine.frames.size()):
		await _wait(STEP_SECONDS)
		if not is_inside_tree():
			return
		if _skip:
			break
		_apply_frame(index)
	_apply_frame(engine.frames.size() - 1)
	_done = true
	_button.text = "계속"
	var result: String = "승리!" if engine.player_won() else "패배…"
	_log.push_color(UiStyle.GOLD if engine.player_won() else UiStyle.DANGER)
	_log.add_text("\n%s\n" % result)
	_log.pop()


## 재생 중이면 끝까지 건너뛰고, 다 끝났으면 다음 화면으로 넘어간다.
func press_button() -> void:
	if _done:
		finished.emit()
	else:
		_skip = true


func _make_row(caption: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var caption_label: Label = UiStyle.label(caption, 15, UiStyle.TEXT_DIM)
	caption_label.custom_minimum_size = Vector2(40, 0)
	row.add_child(caption_label)
	add_child(row)
	return row


func _apply_frame(index: int) -> void:
	var frame: Dictionary = _engine.frames[index]
	var hp_list: Array = frame["hp"]
	for i: int in _cards.size():
		_cards[i].set_hp(int(hp_list[i]), _engine.units[i].max_hp)
	var log_end: int = frame["log_end"]
	while _shown_lines < log_end:
		_append_line(_engine.log_lines[_shown_lines])
		_shown_lines += 1


func _append_line(line: String) -> void:
	var color: Color = Color.WHITE
	if line.begins_with("──"):
		color = UiStyle.TEXT_DIM
	elif line.contains("쓰러짐"):
		color = UiStyle.DANGER
	elif line.begins_with("보유효과"):
		color = UiStyle.MERGE
	elif line.begins_with("아군"):
		color = Color("cfe3ff")
	elif line.begins_with("적"):
		color = Color("ffd6d0")
	_log.push_color(color)
	_log.add_text(line + "\n")
	_log.pop()


## 건너뛰기를 누르면 바로 끝나는 기다림.
func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds and not _skip and is_inside_tree():
		await get_tree().process_frame
		elapsed += get_process_delta_time()
