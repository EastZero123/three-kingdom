class_name RecordsView
extends VBoxContainer
## 기록 화면: 생존 연수 순위.

signal back

const SHOWN: int = 20


func setup(db: GameDatabase, highlight_rank: int = 0) -> void:
	add_theme_constant_override("separation", 8)
	add_child(UiStyle.label("기록 — 생존 연수 순위", 26, UiStyle.GOLD))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	add_child(scroll)

	if SaveManager.records.is_empty():
		rows.add_child(UiStyle.label("아직 기록이 없습니다. 원정을 떠나 보세요.", 18, UiStyle.TEXT_DIM))
	for i: int in mini(SHOWN, SaveManager.records.size()):
		var record: Dictionary = SaveManager.records[i]
		var names: Array[String] = []
		for member: Variant in record.get("roster", []):
			var entry: Dictionary = member
			names.append("%s(%s) Lv.%d" % [db.get_general(String(entry["general_id"])).name if db.generals.has(String(entry["general_id"])) else String(entry["general_id"]), entry["tier"], int(entry["level"])])
		var row: Label = UiStyle.label("%d위   생존 %d년   %d년 %d라운드에서 패배   %s   시드 %d\n      최종 로스터: %s" % [
			i + 1, int(record["years"]), int(record["year"]), int(record["round"]), record.get("ended_at", ""),
			int(record["seed"]), ", ".join(names)], 16, UiStyle.GOLD if i + 1 == highlight_rank else Color.WHITE)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(row)

	var button: Button = Button.new()
	button.text = "돌아가기"
	button.custom_minimum_size = Vector2(160, 40)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.pressed.connect(func() -> void: back.emit())
	add_child(button)
