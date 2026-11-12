class_name RewardView
extends VBoxContainer
## 보상 선택 화면: 승리 보상 3개를 보여 준다. 대상이 필요한 보상은 로스터에서 장수를 고르게 한다.

signal chosen(index: int)
signal cancelled

var _db: GameDatabase
var _run: ExpeditionRun


func setup(db: GameDatabase, run: ExpeditionRun) -> void:
	_db = db
	_run = run
	_build_choices()


## 대상을 고르는 동안 보여 줄 안내.
func show_prompt(text: String) -> void:
	_clear()
	add_child(UiStyle.label(text, 22, UiStyle.GOLD))
	add_child(UiStyle.label("아래 로스터에서 장수를 누르세요.", 16, UiStyle.TEXT_DIM))
	var back: Button = Button.new()
	back.text = "다른 보상 고르기"
	back.custom_minimum_size = Vector2(200, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func() -> void:
		_build_choices()
		cancelled.emit())
	add_child(back)


func _build_choices() -> void:
	_clear()
	add_theme_constant_override("separation", 10)
	add_child(UiStyle.label("승리! 보상을 하나 고르세요", 24, UiStyle.GOLD))
	var rewards: Array[Reward] = _run.current_rewards()
	for i: int in rewards.size():
		var reward: Reward = rewards[i]
		var button: Button = Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 80)
		button.add_theme_font_size_override("font_size", 18)
		button.text = "%d) %s\n     %s" % [i + 1, reward.summary(_db, _run.roster.is_full()), _describe(i, reward)]
		if reward.is_chest():
			button.add_theme_color_override("font_color", UiStyle.CHEST)
		elif reward.is_card():
			# 장수 카드는 고르기 전에 어떤 장수인지(능력치·스킬·보유효과) 미리 보여 준다. 자세한 설명은 마우스를 올리면 보인다.
			var info: Array[String] = GeneralInfo.summary_lines(_db, reward.general_id, reward.tier)
			button.add_theme_font_size_override("font_size", 16)
			button.text += "\n     %s   %s\n     %s   %s" % [info[0], info[1], info[2], info[3]]
			button.tooltip_text = GeneralInfo.tooltip(_db, reward.general_id, reward.tier)
			button.add_theme_color_override("font_color", UiStyle.tier_color(reward.tier).lightened(0.45))
		button.pressed.connect(func() -> void: chosen.emit(i))
		add_child(button)


## 이 보상을 고르면 무슨 일이 일어나는지 한 줄로 설명한다.
func _describe(index: int, reward: Reward) -> String:
	if reward.is_exp():
		return "로스터 장수 1명에게 경험치를 줍니다 (받을 장수 선택)"
	if reward.is_chest():
		var chest: ChestDef = _db.get_chest(reward.chest_id)
		if chest.needs_target():
			return "고른 장수 1명에게 카드 %d장 (받을 장수 선택)" % chest.card_count
		return "%s에게 카드 %d장을 나눠 줍니다 → 연쇄 합성" % [chest.scope_label(), chest.card_count]
	if _run.roster.has_general(reward.general_id):
		return GeneralInfo.merge_preview(_db, _run, reward.general_id, reward.tier)
	if _run.reward_needs_target(index):
		return "로스터가 가득 참 → 교체할 장수 선택 (Lv.%d와 경험치 75%% 계승 중 높은 쪽, 레벨 포인트는 새로 배분)" % reward.recruit_level(_db)
	return "빈 칸에 Lv.%d로 영입합니다 (배분할 포인트 %d)" % [
		reward.recruit_level(_db), AbilityBuild.earned_points(_db.balance, reward.recruit_level(_db))]


func _clear() -> void:
	for child: Node in get_children():
		child.queue_free()
