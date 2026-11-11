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
		var tier_def: GeneralTierDef = general.get_tier(tier)
		var stats: Stats = tier_def.stats_at_level(db.draft_level)
		var skill_names: Array[String] = []
		for skill_id: String in tier_def.skill_ids:
			skill_names.append(db.get_skill(skill_id).name)

		var button: Button = Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 88)
		button.add_theme_font_size_override("font_size", 16)
		button.text = "%d) %s  [%s]  %s · %s\n     체력 %d · 공격 %d · 방어 %d · 속도 %d · 지략 %d   스킬: %s\n     보유효과: %s — %s" % [
			i + 1, general.name, tier, tier_def.title, _role_label(general.role),
			stats.hp, stats.attack, stats.defense, stats.speed, stats.intellect, ", ".join(skill_names),
			tier_def.reserve_effect.name, tier_def.reserve_effect.description,
		]
		button.tooltip_text = tier_def.era
		button.add_theme_color_override("font_color", UiStyle.HEAL if general.is_healer() else UiStyle.tier_color(tier).lightened(0.35))
		button.pressed.connect(func() -> void: chosen.emit(i))
		add_child(button)

	var restart: Button = Button.new()
	restart.text = "처음부터 다시 뽑기"
	restart.custom_minimum_size = Vector2(200, 36)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_END
	restart.pressed.connect(func() -> void: reroll.emit())
	add_child(restart)


func _role_label(role: String) -> String:
	match role:
		"warrior":
			return "무장"
		"defender":
			return "수비"
		"strategist":
			return "책사"
		"healer":
			return "힐러"
		"support":
			return "보조"
	return role
