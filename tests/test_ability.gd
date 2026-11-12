extends GutTest
## 능력치(0~100)와 레벨업 포인트 수동 배분 테스트.
## 규칙: 레벨당 5포인트, 능력치 최대 100, 승급하면 배분 총량을 100% 유지한 채 새 티어에 다시 맞춘다,
## 다섯 능력치가 모두 100이면 남는 포인트는 체력 보너스(포인트당 실제 체력 +3)로 간다.

const SEED: int = 12345

var _db: GameDatabase


func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


func _stats(hp: int, attack: int, defense: int, speed: int, intellect: int) -> Stats:
	var result: Stats = Stats.new()
	result.hp = hp
	result.attack = attack
	result.defense = defense
	result.speed = speed
	result.intellect = intellect
	return result


func _invested(hp: int, attack: int, defense: int, speed: int, intellect: int) -> Dictionary:
	return {"hp": hp, "attack": attack, "defense": defense, "speed": speed, "intellect": intellect}


# ---------- 변환과 포인트 ----------

func test_combat_conversion() -> void:
	var combat: Stats = AbilityBuild.combat_stats(_db.balance, _stats(30, 40, 20, 15, 10), 4)
	assert_eq(combat.hp, 30 * 5 + 4 * 3, "체력 = 능력치 × 5 + 넘친 포인트 × 3")
	assert_eq(combat.attack, 40, "나머지는 능력치 그대로")
	assert_eq(combat.intellect, 10)


func test_points_per_level() -> void:
	assert_eq(AbilityBuild.earned_points(_db.balance, 1), 0)
	assert_eq(AbilityBuild.earned_points(_db.balance, 2), 5)
	assert_eq(AbilityBuild.earned_points(_db.balance, 50), 245)


func test_invest_respects_points_and_cap() -> void:
	var member: RosterMember = RosterMember.create(_db, "guan_yu", "C", 3)  # 10포인트
	assert_eq(member.unspent_points(_db), 10)
	assert_false(member.invest(_db, "attack", 11), "가진 포인트보다 많이는 못 넣는다")
	assert_false(member.invest(_db, "luck", 1), "없는 능력치")
	assert_true(member.invest(_db, "attack", 7))
	assert_true(member.invest(_db, "speed", 3))
	assert_eq(member.unspent_points(_db), 0)
	assert_eq(member.abilities(_db).attack, _db.get_general("guan_yu").get_tier("C").base_stats.attack + 7)
	assert_eq(member.combat_stats(_db).attack, member.abilities(_db).attack)


func test_cannot_overfill_one_stat_while_others_have_room() -> void:
	var base: Stats = _stats(10, 98, 10, 10, 10)
	var plan: Dictionary = AbilityBuild.plan_invest(_db.balance, base, _invested(0, 0, 0, 0, 0), "attack", 5)
	assert_false(plan["ok"], "공격은 2칸만 남았고 다른 능력치에 자리가 있으니 거부")
	plan = AbilityBuild.plan_invest(_db.balance, base, _invested(0, 0, 0, 0, 0), "attack", 2)
	assert_true(plan["ok"])
	assert_eq(plan["to_stat"], 2)


func test_overflow_only_when_everything_is_maxed() -> void:
	var base: Stats = _stats(100, 100, 100, 100, 97)
	var plan: Dictionary = AbilityBuild.plan_invest(_db.balance, base, _invested(0, 0, 0, 0, 0), "intellect", 5)
	assert_true(plan["ok"], "지략 3칸을 채우면 모두 100이 되므로 나머지 2는 체력 보너스")
	assert_eq(plan["to_stat"], 3)
	assert_eq(plan["to_overflow"], 2)
	plan = AbilityBuild.plan_invest(_db.balance, base, _invested(0, 0, 0, 0, 3), "hp", 4)
	assert_true(plan["ok"])
	assert_eq(plan["to_overflow"], 4)


# ---------- 승급 재배분 ----------

func test_refit_keeps_investment_when_there_is_room() -> void:
	var fitted: Dictionary = AbilityBuild.refit(_db.balance, _stats(30, 40, 30, 20, 20), _invested(5, 10, 0, 0, 0), 0)
	assert_eq(fitted["invested"], _invested(5, 10, 0, 0, 0))
	assert_eq(fitted["overflow"], 0)


func test_refit_moves_excess_to_most_invested_stats_first() -> void:
	# 새 기본 공격 95 + 투자 20 → 5만 남고 15가 넘친다. 속도 98 + 투자 8 → 2만 남고 6이 넘친다.
	# 넘친 21은 많이 투자한 순서(공격 20 → 속도 8 → 체력 3)로 자리를 찾는다. 공격·속도는 꽉 찼으니 체력으로.
	var fitted: Dictionary = AbilityBuild.refit(_db.balance, _stats(30, 95, 30, 98, 20), _invested(3, 20, 0, 8, 0), 0)
	var invested: Dictionary = fitted["invested"]
	assert_eq(invested["attack"], 5, "공격은 100까지만")
	assert_eq(invested["speed"], 2, "속도도 100까지만 (98 + 2)")
	assert_eq(invested["hp"], 3 + 21, "넘친 21은 그다음으로 많이 투자한 체력으로")
	assert_eq(invested["defense"], 0)
	var total: int = int(fitted["overflow"])
	for key: String in Stats.KEYS:
		total += int(invested[key])
	assert_eq(total, 31, "배분 총량은 100% 그대로")


func test_refit_overflows_to_hp_bonus_when_all_maxed() -> void:
	var fitted: Dictionary = AbilityBuild.refit(_db.balance, _stats(99, 100, 100, 100, 100), _invested(10, 5, 0, 0, 0), 2)
	assert_eq(fitted["invested"], _invested(1, 0, 0, 0, 0))
	assert_eq(fitted["overflow"], 2 + 14, "자리가 없는 14포인트는 체력 보너스로")


func test_promotion_keeps_all_points() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var guan_yu: RosterMember = run.roster.get_member(0)
	guan_yu.add_experience(_db, 900)  # 레벨 10 → 45포인트
	assert_true(run.allocate_points(0, "attack", 30))
	assert_true(run.allocate_points(0, "hp", 15))
	run.add_merge_card("guan_yu", "C")
	run.add_merge_card("guan_yu", "C")
	assert_true(run.apply_merge(0))
	assert_eq(guan_yu.tier, "B")
	assert_eq(guan_yu.spent_points(), 45, "승급해도 배분 총량은 그대로")
	assert_eq(guan_yu.unspent_points(_db), 0)
	var base: Stats = _db.get_general("guan_yu").get_tier("B").base_stats
	assert_eq(guan_yu.abilities(_db).attack, mini(100, base.attack + 30))
	assert_eq(guan_yu.hp, guan_yu.max_hp, "승급하면 체력이 가득")


# ---------- 런 행동과 재현 ----------

func test_allocate_is_recorded_and_replayed() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	run.roster.get_member(1).add_experience(_db, 60)  # 레벨 3 → 10포인트 (시험용으로 직접 경험치를 준다)
	assert_true(run.allocate_points(1, "defense", 4))
	assert_eq(run.history.back(), {"type": "allocate", "slot": 1, "stat": "defense", "amount": 4})
	assert_false(run.allocate_points(1, "defense", 7), "남은 6포인트보다 많다")
	assert_false(run.allocate_points(15, "defense", 1), "없는 칸")
	assert_eq(run.history.size(), 1, "실패한 배분은 기록되지 않는다")


func test_allocation_changes_battle_stats() -> void:
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	var member: RosterMember = run.roster.get_member(0)
	member.add_experience(_db, 60)
	var before: int = member.combat_stats(_db).attack
	run.allocate_points(0, "attack", 10)
	assert_eq(member.combat_stats(_db).attack, before + 10)
	var unit: BattleUnit = BattleUnit.create_from_stats(_db, member.general_id, member.tier, member.level, member.combat_stats(_db), member.hp)
	assert_eq(unit.base_stats.attack, before + 10, "전투 유닛에 배분한 능력치가 그대로 들어간다")


func test_no_allocation_during_draft() -> void:
	var run: ExpeditionRun = ExpeditionRun.start_draft(_db, SEED)
	run.choose_draft(0)
	assert_false(run.allocate_points(0, "attack", 1), "드래프트 중에는 배분할 수 없다")


func test_full_replay_with_allocations_matches() -> void:
	# 실제 진행처럼: 싸우고, 보상을 받고, 포인트가 생기면 공격에 넣는다. 그 기록을 다시 실행하면 같은 결과.
	var run: ExpeditionRun = ExpeditionRun.start(_db, SEED)
	for step: int in 40:
		if run.is_over():
			break
		if run.phase == ExpeditionRun.PHASE_EXPEDITION:
			run.choose(0)
		elif run.phase == ExpeditionRun.PHASE_REWARD:
			var target: int = -1
			if run.reward_needs_target(0):
				# 살아 있는 첫 장수를 대상으로 고른다.
				for slot: int in run.roster.size():
					if run.roster.get_member(slot) != null:
						target = slot
						break
			run.choose_reward(0, target)
		for slot: int in run.roster.size():
			var member: RosterMember = run.roster.get_member(slot)
			if member != null and member.unspent_points(_db) > 0:
				for key: String in ["attack", "hp", "defense", "speed", "intellect"]:
					if run.allocate_points(slot, key, member.unspent_points(_db)):
						break
	var replayed: ExpeditionRun = ExpeditionRun.replay(_db, SEED, run.history)
	assert_eq(replayed.history.size(), run.history.size(), "모든 행동이 다시 실행된다")
	assert_eq(replayed.year, run.year)
	assert_eq(replayed.round_number, run.round_number)
	for slot: int in run.roster.size():
		var original: RosterMember = run.roster.get_member(slot)
		var copy: RosterMember = replayed.roster.get_member(slot)
		if original == null:
			assert_null(copy)
		else:
			assert_eq(copy.to_dict(), original.to_dict(), "칸 %d" % slot)
