extends Control
## 메인 화면: 위쪽 상태 줄, 가운데 현재 화면(토벌 선택·전투·보상·종료), 오른쪽 원정 기록, 아래 로스터.
## 흐름: 시작 화면 → 드래프트 → 토벌 선택 → 전투 재생 → 보상 선택(대상이 필요하면 로스터에서 고름)
##       → 합성·치유 연출 → 다음 라운드. 행동마다 자동 저장하고, 패배하면 기록에 남긴다.
## 게임 규칙은 모두 core/의 ExpeditionRun이 처리하고, 이 화면은 결과를 보여 주고 입력만 넘긴다.

## 보상 뒤 연출로 크게 보여 줄 로그 줄의 앞부분.
const SHOWCASE_MARKERS: Array[String] = ["보물상자", "합성:", "승급:", "치유:", "보유효과 슬롯", "슬롯 축소로 방출", "해가 넘어갔다"]

var _status: Label
var _content: PanelContainer
var _log: RichTextLabel
var _roster_view: RosterView
var _overlay: MergeOverlay
var _allocation: AllocationPanel
var _log_box: VBoxContainer
var _log_shown: int = 0
var _pending_reward: int = -1
## 방금 끝난 런의 기록 순위 (종료 화면 표시용).
var _last_rank: int = 0


func _ready() -> void:
	_build_layout()
	_show_title()


# ---------- 화면 틀 ----------

func _build_layout() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = UiStyle.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_status = UiStyle.label("", 18)
	column.add_child(_status)

	var middle: HBoxContainer = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	column.add_child(middle)

	_content = PanelContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.BORDER, 1, 8))
	middle.add_child(_content)

	_log_box = VBoxContainer.new()
	_log_box.custom_minimum_size = Vector2(340, 0)
	_log_box.add_child(UiStyle.label("원정 기록", 15, UiStyle.TEXT_DIM))
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.PANEL_DARK))
	_log_box.add_child(_log)
	middle.add_child(_log_box)

	_roster_view = RosterView.new()
	_roster_view.custom_minimum_size = Vector2(0, 236)
	_roster_view.slot_picked.connect(_on_slot_picked)
	_roster_view.changed.connect(_on_roster_changed)
	_roster_view.allocate_requested.connect(func(slot: int) -> void: _allocation.open(GameState.db, GameState.run, slot))
	column.add_child(_roster_view)

	_overlay = MergeOverlay.new()
	add_child(_overlay)
	# 능력치 배분 창: 확정하면 로스터가 바뀐 것과 같게 처리한다 (화면 갱신 + 자동 저장).
	_allocation = AllocationPanel.new()
	_allocation.applied.connect(func() -> void:
		_roster_view.refresh(GameState.db, GameState.run)
		_on_roster_changed())
	add_child(_allocation)


func _set_content(view: Control) -> void:
	for child: Node in _content.get_children():
		child.queue_free()
	_content.add_child(view)


## 게임 진행 중에만 상태 줄·원정 기록·로스터를 보인다 (시작·기록·도감 화면에서는 숨김).
func _set_game_chrome(visible_in_game: bool) -> void:
	_status.visible = visible_in_game
	_log_box.visible = visible_in_game
	_roster_view.visible = visible_in_game


## 진행 중인 런을 저장하고, 지금 보이는 장수를 도감에 남긴다. 행동이 하나 끝날 때마다 부른다.
func _autosave() -> void:
	SaveManager.update_codex(GameState.run)
	SaveManager.save_run(GameState.run)


func _on_roster_changed() -> void:
	_refresh_side()
	_autosave()


# ---------- 시작·기록·도감 ----------

func _show_title() -> void:
	var view: TitleView = TitleView.new()
	view.setup(GameState.db)
	view.continue_run.connect(_continue_run)
	view.new_run.connect(_start_new_run)
	view.show_records.connect(_show_records)
	view.show_codex.connect(_show_codex)
	view.show_online.connect(_show_online)
	_set_content(view)
	_set_game_chrome(false)


func _show_online() -> void:
	var view: OnlineLeaderboardView = OnlineLeaderboardView.new()
	view.setup()
	view.back.connect(_show_title)
	_set_content(view)
	_set_game_chrome(false)
	var result: Dictionary = await OnlineService.fetch_leaderboard(30)
	if not is_instance_valid(view) or not view.is_inside_tree():
		return  # 기다리는 동안 다른 화면으로 갔다
	if result["ok"]:
		view.show_entries(result["body"], SaveManager.player_name)
	else:
		view.show_error(String(result["error"]))


func _show_records() -> void:
	var view: RecordsView = RecordsView.new()
	view.setup(GameState.db)
	view.back.connect(_show_title)
	_set_content(view)
	_set_game_chrome(false)


func _show_codex() -> void:
	var view: CodexView = CodexView.new()
	view.setup(GameState.db)
	view.back.connect(_show_title)
	_set_content(view)
	_set_game_chrome(false)


func _continue_run() -> void:
	if not GameState.continue_run():
		_show_title()
		return
	_log.clear()
	_log_shown = 0
	_set_game_chrome(true)
	_show_current_phase()


## 런의 지금 단계에 맞는 화면을 보인다 (이어하기용).
func _show_current_phase() -> void:
	match GameState.run.phase:
		ExpeditionRun.PHASE_DRAFT:
			_show_draft()
		ExpeditionRun.PHASE_REWARD:
			_show_reward()
		_:
			_show_expedition()


func _refresh_side() -> void:
	var run: ExpeditionRun = GameState.run
	_status.text = "%d년 %d라운드  ·  %s  ·  생존 %d년  ·  장수 %d명  ·  시드 %d" % [
		run.year, run.round_number, GameState.db.era_for_year(run.year).name,
		run.years_survived(), run.roster.member_count(), run.run_seed,
	]
	while _log_shown < run.log_lines.size():
		var line: String = run.log_lines[_log_shown]
		_log.push_color(_log_color(line))
		_log.add_text(line + "\n")
		_log.pop()
		_log_shown += 1
	_roster_view.refresh(GameState.db, run)


func _log_color(line: String) -> Color:
	if line.contains("전사") or line.contains("패배") or line.contains("방출"):
		return UiStyle.DANGER
	if line.contains("승급"):
		return UiStyle.GOLD
	if line.contains("합성"):
		return UiStyle.MERGE
	if line.contains("치유"):
		return UiStyle.HEAL
	if line.contains("보물상자"):
		return UiStyle.CHEST
	if line.begins_with("  "):
		return UiStyle.TEXT_DIM
	return Color.WHITE


# ---------- 흐름 ----------

func _start_new_run() -> void:
	GameState.new_run()
	_log.clear()
	_log_shown = 0
	_set_game_chrome(true)
	_show_draft()


func _show_draft() -> void:
	var view: DraftView = DraftView.new()
	view.setup(GameState.db, GameState.run)
	view.chosen.connect(_on_draft_chosen)
	view.reroll.connect(_start_new_run)
	_set_content(view)
	_roster_view.set_mode("manage", "고른 장수는 다음 빈 칸에 들어갑니다. 장수를 눌러 자리를 바꿀 수 있습니다.")
	_refresh_side()
	_autosave()


func _on_draft_chosen(index: int) -> void:
	GameState.run.choose_draft(index)
	if GameState.run.phase == ExpeditionRun.PHASE_DRAFT:
		_show_draft()
	else:
		_show_expedition()


func _show_expedition() -> void:
	var view: ExpeditionView = ExpeditionView.new()
	view.setup(GameState.db, GameState.run)
	view.chosen.connect(_on_expedition_chosen)
	_set_content(view)
	_roster_view.set_mode("manage")
	_refresh_side()
	_autosave()


func _on_expedition_chosen(index: int) -> void:
	var title: String = GameState.run.current_choices()[index].title
	# 로스터를 전투 전 상태로 잠가 두고 나서 전투를 계산한다 (순서가 바뀌면 결과가 미리 보인다).
	_roster_view.set_mode("locked")
	# 전투 결과는 여기서 한 번에 계산된다. 화면은 그 기록을 재생한다.
	# 재생이 끝날 때까지는 결과가 드러나지 않도록 로스터와 기록을 갱신하지 않는다.
	var battle: BattleEngine = GameState.run.choose(index)
	# 결과는 바로 저장한다: 전투 재생 중에 게임을 꺼도 결과가 바뀌지 않는다.
	if GameState.run.is_over():
		_last_rank = SaveManager.finish_run(GameState.run)
	else:
		SaveManager.save_run(GameState.run)
	var view: BattleView = BattleView.new()
	view.finished.connect(_after_battle)
	_set_content(view)
	view.play(GameState.db, battle, title)


func _after_battle() -> void:
	if GameState.run.is_over():
		var view: GameOverView = GameOverView.new()
		view.setup(GameState.db, GameState.run, _last_rank, OnlineService.enabled, SaveManager.player_name)
		view.restart.connect(_start_new_run)
		view.to_title.connect(_show_title)
		view.submit_online.connect(_on_submit_online.bind(view))
		_set_content(view)
		_roster_view.set_mode("locked", "원정이 끝났습니다.")
		_refresh_side()
		return
	_show_reward()


## 방금 끝난 기록을 온라인 랭킹에 보낸다. 접수되면 잠시 뒤 검증 결과를 한 번 물어본다.
func _on_submit_online(player_name: String, view: GameOverView) -> void:
	SaveManager.set_player_name(player_name)
	var record: Dictionary = SaveManager.last_record
	var result: Dictionary = await OnlineService.submit_run(record, player_name)
	if not is_instance_valid(view):
		return
	if not result["ok"]:
		view.show_online_status("등록 실패: %s" % result["error"], UiStyle.DANGER)
		return
	var body: Dictionary = result["body"] if typeof(result["body"]) == TYPE_DICTIONARY else {}
	var run_id: int = int(body.get("id", 0))
	if result["code"] == 409:
		view.show_online_status("이미 등록한 기록입니다 (기록 #%d, %s)." % [run_id, _status_label(String(body.get("status", "")))], UiStyle.TEXT_DIM, true)
		return
	SaveManager.mark_record_online(record, run_id, "PENDING")
	view.show_online_status("접수됨 — 서버가 기록을 다시 실행해 검증하는 중입니다 (기록 #%d)" % run_id, UiStyle.MERGE, true)

	# 검증은 보통 몇 초 안에 끝난다. 3초 뒤 한 번 물어본다.
	await get_tree().create_timer(3.0).timeout
	var check: Dictionary = await OnlineService.fetch_run(run_id)
	if not is_instance_valid(view) or not check["ok"]:
		return
	var status: String = String((check["body"] as Dictionary).get("status", ""))
	SaveManager.mark_record_online(record, run_id, status)
	match status:
		"VERIFIED":
			view.show_online_status("검증 통과! 온라인 순위에 올랐습니다 (기록 #%d)" % run_id, UiStyle.GOLD, true)
		"REJECTED":
			view.show_online_status("검증에서 거부됐습니다: %s" % (check["body"] as Dictionary).get("rejectReason", ""), UiStyle.DANGER, true)
		_:
			view.show_online_status("검증이 아직 끝나지 않았습니다. 잠시 뒤 온라인 순위에서 확인하세요 (기록 #%d)" % run_id, UiStyle.MERGE, true)


func _status_label(status: String) -> String:
	match status:
		"VERIFIED":
			return "검증 통과"
		"REJECTED":
			return "거부됨"
	return "검증 중"


func _show_reward() -> void:
	var view: RewardView = RewardView.new()
	view.setup(GameState.db, GameState.run)
	view.chosen.connect(_on_reward_chosen)
	view.cancelled.connect(func() -> void: _roster_view.set_mode("manage"))
	_set_content(view)
	_roster_view.set_mode("manage")
	_refresh_side()


func _on_reward_chosen(index: int) -> void:
	if not GameState.run.reward_needs_target(index):
		_apply_reward(index, -1)
		return
	_pending_reward = index
	var reward: Reward = GameState.run.current_rewards()[index]
	var prompt: String = "교체할 장수를 고르세요" if reward.is_card() else "보상을 받을 장수를 고르세요"
	var view: RewardView = _content.get_child(0) as RewardView
	if view != null:
		view.show_prompt(prompt)
	_roster_view.set_mode("pick", prompt)


func _on_slot_picked(slot: int) -> void:
	if _pending_reward >= 0:
		_apply_reward(_pending_reward, slot)


func _apply_reward(index: int, target_slot: int) -> void:
	var run: ExpeditionRun = GameState.run
	var before: int = run.log_lines.size()
	if not run.choose_reward(index, target_slot):
		return
	_pending_reward = -1
	_refresh_side()
	_autosave()

	var showcase: Array[String] = []
	for i: int in range(before, run.log_lines.size()):
		for marker: String in SHOWCASE_MARKERS:
			if run.log_lines[i].contains(marker):
				showcase.append(run.log_lines[i])
				break
	if not showcase.is_empty():
		_roster_view.set_mode("locked", "연출 중… 화면을 누르면 건너뜁니다.")
		await _overlay.play(showcase)
	_show_expedition()
