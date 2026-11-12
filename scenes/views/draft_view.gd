class_name DraftView
extends VBoxContainer
## 시작 드래프트 화면: 후보 장수 3명 중 1명을 고르는 일을 6번 한다. 고른 장수는 아래 로스터의 다음 빈 칸에 들어간다.
## 마음에 들지 않으면(예: 힐러가 안 나옴) "처음부터 다시 뽑기"로 새 시드로 다시 시작한다.

signal chosen(index: int)
signal reroll


func setup(db: GameDatabase, run: ExpeditionRun) -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiStyle.label("출정 준비 — 장수 %d/%d번째를 고르세요" % [run.draft_pick_count + 1, db.draft_picks], 24))
	var healer_text: String = "힐러 있음 ✓" if run.has_healer() else "아직 힐러가 없습니다 (힐러는 전투 후 치유를 합니다)"
	add_child(UiStyle.label(healer_text, 15, UiStyle.HEAL if run.has_healer() else UiStyle.TEXT_DIM))

	var offer: Array[Dictionary] = run.current_draft_offer()
	for i: int in offer.size():
		var general: GeneralDef = db.get_general(String(offer[i]["general_id"]))
		var tier: String = offer[i]["tier"]
		# 드래프트 장수의 레벨업 포인트는 영입 뒤 직접 배분하므로, 여기서는 기본 능력치를 보여 준다.
		var info: Array[String] = GeneralInfo.summary_lines(db, general.id, tier)

		var button: Button = Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 88)
		button.add_theme_font_size_override("font_size", 16)
		button.text = "%d) %s  [%s]  %s\n     %s\n     %s   %s" % [i + 1, general.name, tier, info[0], info[1], info[2], info[3]]
		button.tooltip_text = GeneralInfo.tooltip(db, general.id, tier)
		button.add_theme_color_override("font_color", UiStyle.HEAL if general.is_healer() else UiStyle.tier_color(tier).lightened(0.35))
		button.pressed.connect(func() -> void: chosen.emit(i))
		add_child(button)

	var restart: Button = Button.new()
	restart.text = "처음부터 다시 뽑기"
	restart.custom_minimum_size = Vector2(200, 36)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_END
	restart.pressed.connect(func() -> void: reroll.emit())
	add_child(restart)

