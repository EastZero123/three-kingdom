class_name ExpeditionView
extends VBoxContainer
## 토벌 선택 화면: 이번 라운드의 토벌 선택지 3개를 버튼으로 보여 준다.

signal chosen(index: int)


func setup(db: GameDatabase, run: ExpeditionRun) -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiStyle.label("%d년 %d라운드 — 토벌을 고르세요" % [run.year, run.round_number], 24))
	add_child(UiStyle.label("시대: %s" % db.era_for_year(run.year).name, 15, UiStyle.TEXT_DIM))

	var choices: Array[Expedition] = run.current_choices()
	for i: int in choices.size():
		var expedition: Expedition = choices[i]
		var button: Button = Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 92)
		button.add_theme_font_size_override("font_size", 17)
		var names: Array[String] = []
		for enemy: Dictionary in expedition.enemies:
			names.append("%s(%s)" % [db.get_general(String(enemy["general_id"])).name, enemy["tier"]])
		var reward_text: String = " · 보물상자" if not expedition.type.chest_pool.is_empty() else ""
		button.text = "%d) [%s]  적 %d명 · Lv.%d · 전력 %d%% · 경험치 ×%.1f%s\n     %s" % [
			i + 1, expedition.title, expedition.enemy_count(), expedition.enemy_level,
			roundi(expedition.formation.enemy_stat_multiplier * 100.0), expedition.formation.reward_exp_multiplier,
			reward_text, ", ".join(names),
		]
		if expedition.type.is_special():
			button.add_theme_color_override("font_color", UiStyle.CHEST)
		# 람다(이름 없는 함수)는 만들어질 때의 i 값을 기억한다.
		button.pressed.connect(func() -> void: chosen.emit(i))
		add_child(button)
	add_child(UiStyle.label("전투 사이에는 아래 로스터에서 장수를 눌러 자리를 바꿀 수 있습니다.", 14, UiStyle.TEXT_DIM))
