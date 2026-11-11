class_name RosterView
extends PanelContainer
## 로스터 관리 화면 (항상 아래에 보인다): 출전 6칸(전열 3 · 후열 3)과 보유효과 슬롯.
## 모드:
##   manage = 장수를 눌러 고르고, 다른 칸을 누르면 자리를 맞바꾼다. 고른 장수를 방출할 수 있다.
##   pick   = 보상을 받을 장수를 고른다 (slot_picked를 내보낸다).
##   locked = 전투·연출 중이라 아무것도 할 수 없다.

signal slot_picked(slot: int)
## 자리 이동이나 방출로 로스터가 바뀌었다.
signal changed

var _db: GameDatabase
var _run: ExpeditionRun
var _mode: String = "manage"
var _hint_text: String = ""
var _selected: int = -1
var _cards: Array[UnitCard] = []


func _init() -> void:
	add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_DARK, UiStyle.BORDER, 1, 0))


func refresh(db: GameDatabase, run: ExpeditionRun) -> void:
	_db = db
	_run = run
	if not _run.roster.is_valid_slot(_selected) or _run.roster.get_member(_selected) == null:
		_selected = -1
	for child: Node in get_children():
		child.queue_free()
	_cards.clear()

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	# 출전 슬롯: 위 줄이 전열, 아래 줄이 후열.
	var active_box: VBoxContainer = VBoxContainer.new()
	active_box.add_child(UiStyle.label("출전 (위: 전열 · 아래: 후열)", 14, UiStyle.TEXT_DIM))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	active_box.add_child(grid)
	row.add_child(active_box)
	for slot: int in run.roster.active_count:
		grid.add_child(_make_card(slot))

	row.add_child(VSeparator.new())

	var reserve_box: VBoxContainer = VBoxContainer.new()
	reserve_box.add_child(UiStyle.label("보유효과 (%d칸) — 전투에 나가지 않고 효과만 발동" % run.roster.reserve_count(), 14, UiStyle.TEXT_DIM))
	var reserve_row: HBoxContainer = HBoxContainer.new()
	reserve_row.add_theme_constant_override("separation", 6)
	reserve_box.add_child(reserve_row)
	row.add_child(reserve_box)
	for slot: int in range(run.roster.active_count, run.roster.size()):
		reserve_row.add_child(_make_card(slot))

	# 안내와 방출 버튼.
	var side: VBoxContainer = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint: Label = UiStyle.label(_current_hint(), 15, UiStyle.GOLD if _mode == "pick" else UiStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(160, 0)
	side.add_child(hint)
	if _mode == "manage" and _selected >= 0:
		var release: Button = Button.new()
		release.text = "방출 (계승 없음)"
		release.pressed.connect(_on_release)
		side.add_child(release)
	row.add_child(side)


func set_mode(mode: String, hint: String = "") -> void:
	_mode = mode
	_hint_text = hint
	_selected = -1
	if _run != null:
		refresh(_db, _run)


func _make_card(slot: int) -> UnitCard:
	var card: UnitCard = UnitCard.new()
	card.slot = slot
	var member: RosterMember = _run.roster.get_member(slot)
	if member == null:
		card.show_empty()
	else:
		card.show_general(member.display_name(_db), member.tier, member.level, member.hp, member.max_hp)
		card.tooltip_text = _tooltip(member)
	card.set_selected(slot == _selected)
	card.pressed.connect(_on_card_pressed)
	_cards.append(card)
	return card


func _tooltip(member: RosterMember) -> String:
	var tier_def: GeneralTierDef = _db.get_general(member.general_id).get_tier(member.tier)
	var effect: ReserveEffectDef = tier_def.reserve_effect
	var progress: Array[String] = []
	for tier: String in Tier.ORDER:
		var count: int = _run.merge_card_count(member.general_id, tier)
		if count > 0:
			progress.append("%s %d장" % [tier, count])
	return "%s — %s\n%s\n경험치 %d / %d\n보유효과: %s (%s)\n합성 진행도: %s" % [
		tier_def.title, member.display_name(_db), tier_def.era,
		member.experience, RosterMember.exp_to_next(_db, member.level),
		effect.name, effect.description, ", ".join(progress) if not progress.is_empty() else "없음",
	]


func _current_hint() -> String:
	if not _hint_text.is_empty():
		return _hint_text
	match _mode:
		"locked":
			return "전투 중에는 자리를 바꿀 수 없습니다."
		"manage":
			if _selected >= 0:
				return "%s 선택됨 — 옮길 칸을 누르세요." % _run.roster.slot_label(_selected)
			return "장수를 누른 뒤 다른 칸을 누르면 자리를 바꿉니다. 마우스를 올리면 정보가 보입니다."
	return ""


func _on_card_pressed(card: UnitCard) -> void:
	var member: RosterMember = _run.roster.get_member(card.slot)
	match _mode:
		"pick":
			if member != null:
				slot_picked.emit(card.slot)
		"manage":
			if _selected < 0:
				if member != null:
					_selected = card.slot
			elif _selected == card.slot:
				_selected = -1
			else:
				_run.swap_slots(_selected, card.slot)
				_selected = -1
				changed.emit()
			refresh(_db, _run)


func _on_release() -> void:
	if _selected >= 0 and _run.release_member(_selected):
		_selected = -1
		changed.emit()
	refresh(_db, _run)
