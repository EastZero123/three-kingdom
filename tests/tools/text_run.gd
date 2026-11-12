extends SceneTree
## 텍스트 원정 실행 도구: 런 하나를 자동으로 진행하며 라운드별 요약을 출력한다.
## 실행: godot --headless --path . -s tests/tools/text_run.gd -- <시드> <고르는 방식>
##   고르는 방식: easy(가장 쉬운 토벌, 기본값) / hard(가장 어려운 토벌) / 0, 1, 2(항상 그 번호)
##   세 번째 인자로 detail을 주면 첫 전투의 전체 로그도 출력한다.
##   세 번째 인자로 quiet를 주면 마지막 결과만 출력한다.
##
## 자동으로 하는 판단 (사람이 할 법한 간단한 규칙):
##   - 전투 전 배치: 힐러를 우선 출전시키고, 나머지는 남은 체력이 많은 순으로 출전. 출전 장수 중 체력이 많은 3명이 전열.
##   - 보상: 보물상자 > 승급이 되는 카드 > 빈 칸을 채울 새 장수 > 진행도 적립 카드 > 레벨이 가장 낮은 출전 장수에게 경험치.
##     집중 상자는 체력 비율이 가장 낮은 출전 장수에게 쓴다.
##   - 레벨업 포인트: 장수 성향(tendency) 비율대로 배분한다 (적과 같은 방식).

const DEFAULT_SEED: int = 12345


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else DEFAULT_SEED
	var policy: String = args[1] if args.size() > 1 else "easy"
	var detail: bool = args.size() > 2 and args[2] == "detail"
	var quiet: bool = args.size() > 2 and args[2] == "quiet"

	var db: GameDatabase = GameDatabase.load_from_dir("res://data")
	if not db.is_valid():
		for message: String in db.errors:
			printerr(message)
		quit(1)
		return

	var run: ExpeditionRun = ExpeditionRun.start(db, seed_value)
	if not quiet:
		print("시작 로스터:")
		_print_roster(db, run)

	var first_battle: bool = true
	while not run.is_over():
		_arrange(db, run)
		var choices: Array[Expedition] = run.current_choices()
		var index: int = _pick(choices, policy)
		if not quiet:
			print("")
			print("%d년 %d라운드 선택지:" % [run.year, run.round_number])
			for i: int in choices.size():
				print("  %d) %s" % [i + 1, choices[i].summary(db)])
			print("  → %d번 선택" % (index + 1))
		var logged: int = run.log_lines.size()
		var battle: BattleEngine = run.choose(index)
		if detail and first_battle:
			for line: String in battle.log_lines:
				print("    " + line)
			first_battle = false
		if run.phase == ExpeditionRun.PHASE_REWARD:
			if not quiet:
				var texts: Array[String] = []
				for reward: Reward in run.current_rewards():
					texts.append(reward.summary(db, run.roster.is_full()))
				print("  보상 선택지: " + " / ".join(texts))
			_take_reward(db, run)
			_allocate(db, run)
		if not quiet:
			for i: int in range(logged, run.log_lines.size()):
				print(run.log_lines[i])
			_print_roster(db, run)

	if quiet:
		print(run.log_lines[run.log_lines.size() - 1])
	quit(0)


## 배분하지 않은 포인트를 성향대로 나눈다. 목표 = 같은 레벨의 적이 받는 자동 배분.
func _allocate(db: GameDatabase, run: ExpeditionRun) -> void:
	for slot: int in run.roster.size():
		var member: RosterMember = run.roster.get_member(slot)
		if member == null or member.unspent_points(db) <= 0:
			continue
		var goal: Dictionary = AbilityBuild.auto_invest(db.balance, member.tier_def(db), member.level)["invested"]
		for key: String in Stats.KEYS:
			var need: int = mini(int(goal[key]) - int(member.invested[key]), member.unspent_points(db))
			if need > 0:
				run.allocate_points(slot, key, need)
		# 목표와 어긋나 남은 포인트(승급 재배분 등)는 넣을 수 있는 곳에 하나씩 넣는다.
		var guard: int = 0
		while member.unspent_points(db) > 0 and guard < 500:
			guard += 1
			var placed: bool = false
			for key: String in Stats.KEYS:
				if run.allocate_points(slot, key, 1):
					placed = true
					break
			if not placed:
				break


## 선택지 중 하나를 고른다.
func _pick(choices: Array[Expedition], policy: String) -> int:
	if policy.is_valid_int():
		return clampi(int(policy), 0, choices.size() - 1)
	var best: int = 0
	for i: int in choices.size():
		var harder: bool = choices[i].type.reward_exp_multiplier > choices[best].type.reward_exp_multiplier
		var easier: bool = choices[i].type.reward_exp_multiplier < choices[best].type.reward_exp_multiplier
		if (policy == "hard" and harder) or (policy != "hard" and easier):
			best = i
	return best


## 장수를 다시 배치한다: 0~2번(전열), 3~5번(후열), 그 뒤 보유효과 슬롯.
func _arrange(db: GameDatabase, run: ExpeditionRun) -> void:
	var by_priority: Array[RosterMember] = run.roster.members()
	by_priority.sort_custom(func(a: RosterMember, b: RosterMember) -> bool:
		var healer_a: bool = db.get_general(a.general_id).is_healer()
		var healer_b: bool = db.get_general(b.general_id).is_healer()
		if healer_a != healer_b:
			return healer_a
		return a.hp > b.hp
	)
	var active_count: int = mini(run.roster.active_count, by_priority.size())
	var active: Array[RosterMember] = by_priority.slice(0, active_count)
	active.sort_custom(func(a: RosterMember, b: RosterMember) -> bool: return a.hp > b.hp)
	var order: Array[RosterMember] = active
	order.append_array(by_priority.slice(active_count))
	for i: int in order.size():
		var current: int = run.roster.slots.find(order[i])
		if current != i:
			run.swap_slots(i, current)


func _take_reward(db: GameDatabase, run: ExpeditionRun) -> void:
	var rewards: Array[Reward] = run.current_rewards()
	var cards_needed: int = db.balance.get_int("merge.cards_per_promotion")
	for i: int in rewards.size():
		if rewards[i].is_chest():
			var target_slot: int = -1
			if run.reward_needs_target(i):
				for slot: int in run.roster.active_count:
					var member: RosterMember = run.roster.get_member(slot)
					if member != null and (target_slot < 0 or float(member.hp) / member.max_hp < float(run.roster.get_member(target_slot).hp) / run.roster.get_member(target_slot).max_hp):
						target_slot = slot
			run.choose_reward(i, target_slot)
			return
	var promote: int = -1
	var recruit: int = -1
	var progress: int = -1
	for i: int in rewards.size():
		var reward: Reward = rewards[i]
		if not reward.is_card():
			continue
		var slot: int = run.roster.find_general(reward.general_id)
		if slot >= 0:
			var body: RosterMember = run.roster.get_member(slot)
			var same_tier: bool = reward.tier == body.tier and run.merge_card_count(reward.general_id, body.tier) + 2 >= cards_needed
			if Tier.is_higher(reward.tier, body.tier) or same_tier:
				promote = i
			elif progress < 0:
				progress = i
		elif not run.roster.is_full() and recruit < 0:
			recruit = i
	for choice: int in [promote, recruit, progress]:
		if choice >= 0:
			run.choose_reward(choice)
			return

	var target: int = -1
	for slot: int in run.roster.active_count:
		var member: RosterMember = run.roster.get_member(slot)
		if member != null and (target < 0 or member.level < run.roster.get_member(target).level):
			target = slot
	run.choose_reward(0, target)


func _print_roster(db: GameDatabase, run: ExpeditionRun) -> void:
	var parts: Array[String] = []
	for slot: int in run.roster.size():
		if slot == run.roster.active_count:
			parts.append("| 보유효과:")
		var member: RosterMember = run.roster.get_member(slot)
		if member == null:
			parts.append("(빈 칸)")
			continue
		parts.append("%s(%s) Lv.%d %d/%d" % [member.display_name(db), member.tier, member.level, member.hp, member.max_hp])
	print("  로스터: " + " ".join(parts))
