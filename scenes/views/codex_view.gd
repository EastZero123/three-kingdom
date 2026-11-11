class_name CodexView
extends VBoxContainer
## 도감 화면: 만나 본 장수와 티어. 만나지 못한 장수는 이름을 가린다.

signal back

const FACTION_ORDER: Array[String] = ["shu", "wei", "wu", "han", "dong_zhuo", "lu_bu", "yuan", "gongsun", "liu_biao", "yellow_turban", "nanman", "none"]
const FACTION_LABEL: Dictionary = {
	"shu": "촉", "wei": "위", "wu": "오", "han": "한", "dong_zhuo": "동탁군", "lu_bu": "여포군", "yuan": "원씨",
	"gongsun": "공손씨", "liu_biao": "형주", "yellow_turban": "황건", "nanman": "남만", "none": "재야",
}


func setup(db: GameDatabase) -> void:
	add_theme_constant_override("separation", 8)
	var progress: Dictionary = Codex.progress(db, SaveManager.codex)
	add_child(UiStyle.label("도감 — 장수 %d/%d명 · 티어 %d/%d" % [
		progress["generals"], progress["generals_total"], progress["tiers"], progress["tiers_total"]], 24, UiStyle.GOLD))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid: GridContainer = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	add_child(scroll)

	var ids: Array[String] = []
	for general_id: String in db.generals:
		ids.append(general_id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var fa: int = FACTION_ORDER.find(db.generals[a].faction)
		var fb: int = FACTION_ORDER.find(db.generals[b].faction)
		if fa != fb:
			return fa < fb
		return db.generals[a].name < db.generals[b].name
	)
	for general_id: String in ids:
		grid.add_child(_entry(db.generals[general_id]))

	var button: Button = Button.new()
	button.text = "돌아가기"
	button.custom_minimum_size = Vector2(160, 40)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.pressed.connect(func() -> void: back.emit())
	add_child(button)


func _entry(general: GeneralDef) -> PanelContainer:
	var met: bool = Codex.has_met(SaveManager.codex, general.id)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(164, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_DARK if met else Color("1e2025")))
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	var faction: String = FACTION_LABEL.get(general.faction, general.faction)
	column.add_child(UiStyle.label("%s  %s" % [general.name if met else "???", faction], 16, Color.WHITE if met else UiStyle.TEXT_DIM))

	# 티어 칸: 만난 티어는 티어 색, 못 만난 티어는 회색 점.
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	var tooltip: Array[String] = []
	for tier: String in general.available_tiers():
		var tier_met: bool = Codex.has_met(SaveManager.codex, general.id, tier)
		chips.add_child(UiStyle.label(tier if tier_met else "·", 15, UiStyle.tier_color(tier) if tier_met else UiStyle.BORDER))
		if tier_met:
			tooltip.append("%s %s — %s" % [tier, general.get_tier(tier).title, general.get_tier(tier).era])
	column.add_child(chips)
	panel.tooltip_text = "\n".join(tooltip) if met else "아직 만나지 못한 장수"
	return panel
