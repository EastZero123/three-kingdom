class_name AllocationPanel
extends ColorRect
## 레벨업 포인트 배분 창: 화면을 어둡게 덮고 가운데에 능력치 5종과 +/- 버튼을 띄운다.
## 누른 만큼은 "예정"으로만 쌓이고, [확정]을 눌러야 런에 반영된다 (실수로 누른 것을 되돌릴 수 있게).
## 확정하면 능력치마다 ExpeditionRun.allocate_points를 한 번씩 불러 기록에 남긴다.

## 확정해서 런이 바뀌었다.
signal applied

const STEPS: Array[int] = [-5, -1, 1, 5]

var _db: GameDatabase
var _run: ExpeditionRun
var _slot: int = -1
## 능력치별 예정 포인트. "overflow"는 모든 능력치가 최대일 때 체력 보너스로 넣는 예정 포인트.
var _pending: Dictionary = {}
var _box: VBoxContainer


func _init() -> void:
	color = Color(0, 0, 0, 0.72)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.GOLD, 2, 8))
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)


func open(db: GameDatabase, run: ExpeditionRun, slot: int) -> void:
	_db = db
	_run = run
	_slot = slot
	_pending = {"overflow": 0}
	for key: String in Stats.KEYS:
		_pending[key] = 0
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func _member() -> RosterMember:
	return _run.roster.get_member(_slot)


func _pending_total() -> int:
	var total: int = 0
	for value: Variant in _pending.values():
		total += int(value)
	return total


## 지금 예정까지 반영한 배분량.
func _invested_with_pending() -> Dictionary:
	var member: RosterMember = _member()
	var result: Dictionary = {}
	for key: String in Stats.KEYS:
		result[key] = int(member.invested.get(key, 0)) + int(_pending[key])
	return result


func _rebuild() -> void:
	for child: Node in _box.get_children():
		child.queue_free()
	var member: RosterMember = _member()
	if member == null:
		close()
		return
	var tier_def: GeneralTierDef = member.tier_def(_db)
	var cap: int = _db.balance.get_int("ability.max")
	var remaining: int = member.unspent_points(_db) - _pending_total()
	var invested: Dictionary = _invested_with_pending()

	_box.add_child(UiStyle.label("%s  %s  Lv.%d — 능력치 배분" % [member.display_name(_db), member.tier, member.level], 24, UiStyle.tier_color(member.tier).lightened(0.35)))
	_box.add_child(UiStyle.label("남은 포인트 %d   (레벨이 1 오를 때마다 %d포인트, 능력치는 최대 %d)" % [
		remaining, _db.balance.get_int("level.points_per_level"), cap], 16, UiStyle.GOLD if remaining > 0 else UiStyle.TEXT_DIM))

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3 + STEPS.size()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_box.add_child(grid)
	for key: String in Stats.KEYS:
		var value: int = tier_def.base_stats.get_value(key) + int(invested[key])
		grid.add_child(UiStyle.label(AbilityBuild.LABELS[key], 18))
		var value_text: String = "%d" % value
		if int(_pending[key]) > 0:
			value_text += "  (+%d)" % int(_pending[key])
		var value_label: Label = UiStyle.label(value_text, 18, UiStyle.GOLD if int(_pending[key]) > 0 else Color.WHITE)
		value_label.custom_minimum_size = Vector2(90, 0)
		grid.add_child(value_label)
		grid.add_child(_value_bar(value, cap))
		var room: int = cap - value
		for step: int in STEPS:
			var button: Button = Button.new()
			button.text = "%+d" % step
			button.custom_minimum_size = Vector2(48, 30)
			if step > 0:
				button.disabled = remaining <= 0 or room <= 0
			else:
				button.disabled = int(_pending[key]) <= 0
			button.pressed.connect(_on_step.bind(key, step))
			grid.add_child(button)

	# 다섯 능력치가 모두 최대면 남은 포인트는 체력 보너스로만 넣을 수 있다.
	if AbilityBuild.all_maxed(_db.balance, tier_def.base_stats, invested):
		var bonus_hp: int = _db.balance.get_int("ability.overflow_hp_per_point")
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UiStyle.label("모든 능력치가 최대 — 체력 보너스 (포인트당 실제 체력 +%d): %d%s" % [
			bonus_hp, member.overflow_points, "  (+%d)" % int(_pending["overflow"]) if int(_pending["overflow"]) > 0 else ""], 16, UiStyle.HEAL))
		for step: int in STEPS:
			var button: Button = Button.new()
			button.text = "%+d" % step
			button.disabled = remaining <= 0 if step > 0 else int(_pending["overflow"]) <= 0
			button.pressed.connect(_on_step.bind("overflow", step))
			row.add_child(button)
		_box.add_child(row)

	# 전투 수치 미리보기: 체력은 능력치에서 변환되므로 실제 값도 함께 보여 준다.
	var preview: Stats = AbilityBuild.combat_stats(_db.balance, AbilityBuild.abilities(tier_def.base_stats, invested), member.overflow_points + int(_pending["overflow"]))
	_box.add_child(UiStyle.label("전투 수치: 최대 체력 %d · 공격 %d · 방어 %d · 속도 %d · 지략 %d" % [
		preview.hp, preview.attack, preview.defense, preview.speed, preview.intellect], 15, UiStyle.TEXT_DIM))
	_box.add_child(UiStyle.label("능력치 체력 1 = 실제 체력 %d. 승급하면 기본 능력치가 바뀌어도 배분한 포인트는 그대로 옮겨집니다." % _db.balance.get_int("ability.hp_per_point"), 13, UiStyle.TEXT_DIM))

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	var cancel: Button = Button.new()
	cancel.text = "취소"
	cancel.custom_minimum_size = Vector2(110, 38)
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	var confirm: Button = Button.new()
	confirm.text = "확정"
	confirm.custom_minimum_size = Vector2(110, 38)
	confirm.disabled = _pending_total() == 0
	confirm.pressed.connect(_on_confirm)
	buttons.add_child(confirm)
	_box.add_child(buttons)


func _value_bar(value: int, cap: int) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = cap
	bar.value = value
	bar.custom_minimum_size = Vector2(150, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill: StyleBoxFlat = UiStyle.box(UiStyle.MERGE, UiStyle.MERGE, 0, 3)
	fill.set_content_margin_all(0)
	var background: StyleBoxFlat = UiStyle.box(Color("15171b"), Color("15171b"), 0, 3)
	background.set_content_margin_all(0)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	return bar


## +/- 버튼. 넣을 때는 남은 포인트와 그 능력치의 빈자리만큼만 들어간다.
func _on_step(key: String, step: int) -> void:
	var member: RosterMember = _member()
	if step < 0:
		_pending[key] = maxi(0, int(_pending[key]) + step)
	else:
		var remaining: int = member.unspent_points(_db) - _pending_total()
		var room: int = remaining
		if key != "overflow":
			var value: int = member.tier_def(_db).base_stats.get_value(key) + int(_invested_with_pending()[key])
			room = mini(remaining, _db.balance.get_int("ability.max") - value)
		_pending[key] = int(_pending[key]) + clampi(step, 0, maxi(0, room))
	_rebuild()


func _on_confirm() -> void:
	# 능력치를 먼저 넣고, 체력 보너스는 마지막에 넣는다 (모든 능력치가 최대일 때만 체력 보너스로 들어가므로).
	for key: String in Stats.KEYS:
		if int(_pending[key]) > 0:
			_run.allocate_points(_slot, key, int(_pending[key]))
	if int(_pending["overflow"]) > 0:
		_run.allocate_points(_slot, "hp", int(_pending["overflow"]))
	close()
	applied.emit()


func _gui_input(event: InputEvent) -> void:
	# 바깥(어두운 부분)을 눌러도 아무 일도 없게 이벤트를 여기서 막는다.
	accept_event()
