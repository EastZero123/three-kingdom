extends GutTest
## 8단계 화면 테스트: 메인 화면을 띄워 토벌 → 전투 재생 → 보상 → 다음 라운드 흐름이 오류 없이 이어지는지 본다.
## 그림이 예쁜지는 사람이 화면 캡처로 확인하고, 여기서는 흐름과 연결만 검사한다.

const SEED: int = 12345

var _main: Control


const TEST_DIR: String = "user://test_save_ui"

var _original_dir: String


func before_all() -> void:
	_original_dir = SaveManager.base_dir


func after_all() -> void:
	SaveManager.clear_all()
	SaveManager.base_dir = _original_dir
	SaveManager.load_all()


func before_each() -> void:
	# 실제 기록을 건드리지 않도록 테스트용 폴더에 저장한다.
	SaveManager.base_dir = TEST_DIR
	SaveManager.clear_all()
	GameState.next_seed = SEED
	await _open_main()
	(_view() as TitleView).new_run.emit()
	await wait_process_frames(2)


func _open_main() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(_main)
	await wait_process_frames(2)


func test_starts_with_draft_then_expedition() -> void:
	assert_eq(GameState.run.run_seed, SEED, "시드를 고정할 수 있다")
	assert_not_null(_view() as DraftView, "새 원정은 시작 드래프트부터")
	await _finish_draft()
	var view: ExpeditionView = _view() as ExpeditionView
	assert_not_null(view, "처음 화면은 토벌 선택")
	var buttons: int = 0
	for child: Node in view.get_children():
		if child is Button:
			buttons += 1
	assert_eq(buttons, 3, "토벌 선택지 버튼 3개")
	assert_eq(_main._roster_view._cards.size(), 8, "로스터 카드: 출전 6 + 보유효과 2")


func test_draft_reroll_starts_new_run() -> void:
	var first_seed: int = GameState.run.run_seed
	(_view() as DraftView).chosen.emit(0)
	await wait_process_frames(2)
	assert_eq(GameState.run.roster.member_count(), 1)
	(_view() as DraftView).reroll.emit()
	await wait_process_frames(2)
	assert_ne(GameState.run.run_seed, first_seed, "다시 뽑기는 새 시드로 다시 시작")
	assert_eq(GameState.run.roster.member_count(), 0)
	assert_not_null(_view() as DraftView)


func test_full_round_flow() -> void:
	await _finish_draft()
	var expedition_view: ExpeditionView = _view() as ExpeditionView
	expedition_view.chosen.emit(0)
	await wait_process_frames(2)
	var battle_view: BattleView = _view() as BattleView
	assert_not_null(battle_view, "토벌을 고르면 전투 화면")
	assert_eq(_main._roster_view._mode, "locked", "전투 중에는 로스터를 못 건드린다")

	battle_view.press_button()  # 건너뛰기
	await wait_process_frames(3)
	battle_view.press_button()  # 계속
	await wait_process_frames(2)

	if GameState.run.is_over():
		assert_not_null(_view() as GameOverView)
		return
	var reward_view: RewardView = _view() as RewardView
	assert_not_null(reward_view, "이기면 보상 화면")
	assert_eq(GameState.run.current_rewards()[0].is_exp(), true)

	# 경험치는 받을 장수를 골라야 한다 → 로스터가 고르기 모드가 된다.
	reward_view.chosen.emit(0)
	await wait_process_frames(2)
	assert_eq(_main._roster_view._mode, "pick")
	var target: int = 0
	while GameState.run.roster.get_member(target) == null:
		target += 1  # 전투에서 전사한 칸은 건너뛴다
	_main._roster_view.slot_picked.emit(target)
	await wait_process_frames(2)
	_main._overlay.skip()
	await wait_process_frames(3)

	assert_eq(GameState.run.round_number, 2, "보상을 고르면 다음 라운드")
	assert_not_null(_view() as ExpeditionView, "다시 토벌 선택 화면")
	assert_eq(_main._roster_view._mode, "manage")


func test_roster_swap_by_clicking_two_cards() -> void:
	await _finish_draft()
	var roster_view: RosterView = _main._roster_view
	var first_id: String = GameState.run.roster.get_member(0).general_id
	roster_view._on_card_pressed(roster_view._cards[0])
	await wait_process_frames(1)
	roster_view._on_card_pressed(roster_view._cards[6])  # 보유효과 1번 (빈 칸)
	await wait_process_frames(1)
	assert_eq(GameState.run.roster.get_member(6).general_id, first_id, "두 칸을 누르면 자리가 바뀐다")
	assert_null(GameState.run.roster.get_member(0))


func test_game_over_screen_and_restart() -> void:
	await _finish_draft()
	for member: RosterMember in GameState.run.roster.members():
		member.hp = 1
	(_view() as ExpeditionView).chosen.emit(2)
	await wait_process_frames(2)
	var battle_view: BattleView = _view() as BattleView
	battle_view.press_button()
	await wait_process_frames(3)
	battle_view.press_button()
	await wait_process_frames(2)
	var over: GameOverView = _view() as GameOverView
	assert_not_null(over, "패배하면 종료 화면")
	over.restart.emit()
	await wait_process_frames(2)
	assert_false(GameState.run.is_over(), "새 원정이 시작된다")
	assert_not_null(_view() as DraftView, "새 원정은 드래프트부터")


func test_autosave_and_continue_from_title() -> void:
	await _finish_draft()
	(_view() as ExpeditionView).chosen.emit(0)
	await wait_process_frames(2)
	assert_true(SaveManager.has_saved_run(), "행동마다 자동 저장")
	var expected_log: Array[String] = GameState.run.log_lines.duplicate()
	var expected_phase: String = GameState.run.phase

	# 게임을 껐다 켠 것처럼 메인 화면을 새로 띄운다.
	_main.queue_free()
	GameState.run = null
	await wait_process_frames(2)
	await _open_main()
	var title: TitleView = _view() as TitleView
	assert_not_null(title, "다시 켜면 시작 화면")
	title.continue_run.emit()
	await wait_process_frames(2)
	assert_eq(GameState.run.log_lines, expected_log, "이어하기로 그대로 복원")
	assert_eq(GameState.run.phase, expected_phase)
	if expected_phase == ExpeditionRun.PHASE_REWARD:
		assert_not_null(_view() as RewardView, "보상을 고르던 화면으로 돌아온다")


func test_defeat_records_and_title_shows_records_and_codex() -> void:
	await _finish_draft()
	for member: RosterMember in GameState.run.roster.members():
		member.hp = 1
	(_view() as ExpeditionView).chosen.emit(2)
	await wait_process_frames(2)
	assert_eq(SaveManager.records.size(), 1, "패배하면 바로 기록된다")
	assert_false(SaveManager.has_saved_run())
	var battle_view: BattleView = _view() as BattleView
	battle_view.press_button()
	await wait_process_frames(3)
	battle_view.press_button()
	await wait_process_frames(2)
	(_view() as GameOverView).to_title.emit()
	await wait_process_frames(2)
	(_view() as TitleView).show_records.emit()
	await wait_process_frames(2)
	assert_not_null(_view() as RecordsView)
	(_view() as RecordsView).back.emit()
	await wait_process_frames(2)
	(_view() as TitleView).show_codex.emit()
	await wait_process_frames(2)
	assert_not_null(_view() as CodexView)
	assert_gt(Codex.progress(GameState.db, SaveManager.codex)["generals"], 6, "드래프트 후보·적·로스터가 도감에 남았다")


## 드래프트 6번을 첫 후보로 끝낸다.
func _finish_draft() -> void:
	for i: int in 6:
		var draft: DraftView = _view() as DraftView
		assert_not_null(draft, "%d번째 드래프트 화면" % (i + 1))
		draft.chosen.emit(0)
		await wait_process_frames(2)


func _view() -> Control:
	var content: PanelContainer = _main._content
	for child: Node in content.get_children():
		if not child.is_queued_for_deletion():
			return child as Control
	return null
