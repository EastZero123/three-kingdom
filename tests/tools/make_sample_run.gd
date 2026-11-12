extends SceneTree
## 서버 테스트용 표본 기록을 만든다: 드래프트부터 패배까지 자동으로 플레이한 기록을 POST /runs 요청 형식으로 저장한다.
## 실행: godot --headless --path . -s tests/tools/make_sample_run.gd -- <저장할 JSON 경로>
## 게임 로직이나 데이터가 바뀌면 다시 만들어야 서버의 실제 검증 테스트가 통과한다.

const SEED: int = 12345


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "res://server/src/test/resources/sample_finished_run.json"
	var db: GameDatabase = GameDatabase.load_from_dir("res://data")
	var run: ExpeditionRun = ExpeditionRun.start_draft(db, SEED)
	for i: int in db.draft_picks:
		run.choose_draft(i % db.draft_choices)
	var guard: int = 0
	while not run.is_over() and guard < 2000:
		guard += 1
		if run.phase == ExpeditionRun.PHASE_EXPEDITION:
			# 전투가 많은 기록이 검증에 의미 있으므로, 경험치 배율이 가장 낮은(가장 쉬운) 토벌을 고른다.
			var choices: Array[Expedition] = run.current_choices()
			var easiest: int = 0
			for i: int in choices.size():
				if choices[i].type.reward_exp_multiplier < choices[easiest].type.reward_exp_multiplier:
					easiest = i
			run.choose(easiest)
		elif run.phase == ExpeditionRun.PHASE_REWARD:
			var target: int = -1
			for slot: int in run.roster.size():
				if run.roster.get_member(slot) != null:
					target = slot
					break
			run.choose_reward(0, target)
			_allocate(db, run)
	var request: Dictionary = {
		"playerName": "표본 기록",
		"seed": run.run_seed,
		"actions": run.history,
		"years": run.years_survived(),
		"year": run.year,
		"round": run.round_number,
		"gameVersion": String(ProjectSettings.get_setting("application/config/version")),
	}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(request, "\t"))
	file.close()
	print("표본 기록 저장: %s (생존 %d년, 행동 %d개)" % [path, run.years_survived(), run.history.size()])
	quit(0)


## 검증에 배분 행동도 들어가도록, 포인트가 생기면 능력치를 돌아가며 하나씩 고른다 (칸 번호 + 횟수로 정해 재현 가능).
func _allocate(db: GameDatabase, run: ExpeditionRun) -> void:
	for slot: int in run.roster.size():
		var member: RosterMember = run.roster.get_member(slot)
		if member == null:
			continue
		var turn: int = 0
		while member.unspent_points(db) > 0 and turn < Stats.KEYS.size() * 2:
			var key: String = Stats.KEYS[(slot + run.history.size() + turn) % Stats.KEYS.size()]
			run.allocate_points(slot, key, mini(5, member.unspent_points(db)))
			turn += 1
