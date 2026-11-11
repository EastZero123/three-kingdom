class_name ExpeditionRun
extends RefCounted
## 런 한 판의 진행:
##   토벌 선택 → 전투 → (승리) 보상 선택 → 다음 라운드 → 10라운드 뒤 해 넘김 → 패배하면 종료.
## 전투와 전투 사이에는 슬롯 이동과 방출을 할 수 있다.
##
## 사용 예:
##   var run: ExpeditionRun = ExpeditionRun.start(db, 12345)
##   var battle: BattleEngine = run.choose(0)        # 0번 토벌을 골라 전투까지 진행
##   if run.phase == ExpeditionRun.PHASE_REWARD:
##       run.choose_reward(0, 2)                     # 0번 보상(경험치)을 2번 슬롯 장수에게

## 지금 플레이어가 해야 할 일.
const PHASE_DRAFT: String = "draft"            # 시작 드래프트: 장수를 고를 차례
const PHASE_EXPEDITION: String = "expedition"  # 토벌을 고를 차례
const PHASE_REWARD: String = "reward"          # 보상을 고를 차례
const PHASE_OVER: String = "over"              # 런 종료

var run_seed: int = 0
var year: int = 0
## 현재 라운드 (1부터 rounds_per_year까지).
var round_number: int = 1
var phase: String = PHASE_EXPEDITION
var roster: Roster = null
## 이번 런에서 전사한 장수 기록. 각 항목: {general_id, tier, level, year, round}
var fallen: Array[Dictionary] = []
## 합성 진행도: 장수 id → {티어: 모은 카드 수 (본체 제외)}. 방출·전사해도 런 동안 보존한다.
var merge_progress: Dictionary[String, Dictionary] = {}
## 마지막 보상에서 일어난 합성과 승급 (화면 연출용). 각 항목:
##   {kind: "merge", general_id, from, to} / {kind: "promotion", general_id, from, to}
var last_merge_events: Array[Dictionary] = []
## 플레이어의 행동 기록. 시드와 함께 있으면 런을 그대로 재현할 수 있다.
##   {type: "expedition", index} / {type: "reward", index, target} / {type: "swap", a, b} / {type: "release", slot}
var history: Array[Dictionary] = []
## 진행 요약 로그.
var log_lines: Array[String] = []

## 시작 드래프트에서 지금까지 고른 횟수.
var draft_pick_count: int = 0
## 마지막 전투 직전의 로스터 (기록의 "최종 로스터"용). 각 항목: {general_id, tier, level}
var last_battle_roster: Array[Dictionary] = []

var _db: GameDatabase
var _draft_offer: Array[Dictionary] = []
var _choices: Array[Expedition] = []
var _rewards: Array[Reward] = []
## 방금 전투에 출전해 살아남은 힐러. 보상을 고른 뒤 치유한다.
var _battle_healers: Array[RosterMember] = []


## 새 런을 시작한다.
static func start(db: GameDatabase, seed_value: int) -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.new()
	run._db = db
	run.run_seed = seed_value
	run.year = db.balance.get_int("run.start_year")
	run.roster = Roster.new(db.balance.get_int("roster.active_slots"), db.balance.get_int("roster.reserve_slots_base"))
	for i: int in db.starting_roster.size():
		var entry: Dictionary = db.starting_roster[i]
		run.roster.set_member(i, RosterMember.create(db, String(entry["general_id"]), String(entry["tier"]), int(entry["level"])))
	run.log_lines.append("원정 시작: %d년 (시드 %d)" % [run.year, seed_value])
	return run


## 시작 드래프트로 새 런을 시작한다: 로스터가 빈 채로, 장수를 고르는 단계부터.
static func start_draft(db: GameDatabase, seed_value: int) -> ExpeditionRun:
	var run: ExpeditionRun = ExpeditionRun.new()
	run._db = db
	run.run_seed = seed_value
	run.year = db.balance.get_int("run.start_year")
	run.roster = Roster.new(db.balance.get_int("roster.active_slots"), db.balance.get_int("roster.reserve_slots_base"))
	run.phase = PHASE_DRAFT
	run.log_lines.append("출정 준비: 장수 %d명을 고른다 (시드 %d)" % [db.draft_picks, seed_value])
	return run


## 시드와 행동 기록으로 런을 처음부터 다시 진행한다 (재현·검증용).
## 기록이 드래프트로 시작하면 드래프트 런으로, 아니면 고정 로스터 런으로 시작한다.
static func replay(db: GameDatabase, seed_value: int, actions: Array[Dictionary]) -> ExpeditionRun:
	var drafted: bool = not actions.is_empty() and String(actions[0]["type"]) == "draft"
	var run: ExpeditionRun = ExpeditionRun.start_draft(db, seed_value) if drafted else ExpeditionRun.start(db, seed_value)
	for action: Dictionary in actions:
		if run.is_over():
			break
		match String(action["type"]):
			"draft":
				run.choose_draft(int(action["index"]))
			"expedition":
				run.choose(int(action["index"]))
			"reward":
				run.choose_reward(int(action["index"]), int(action["target"]))
			"swap":
				run.swap_slots(int(action["a"]), int(action["b"]))
			"release":
				run.release_member(int(action["slot"]))
	return run


func is_over() -> bool:
	return phase == PHASE_OVER


## 살아남은 연수 = 끝까지 마친 해의 수. 기록의 기준이다.
func years_survived() -> int:
	return year - _db.balance.get_int("run.start_year")


# ---------- 시작 드래프트 ----------

## 이번 드래프트 후보. 드래프트 차례가 아니면 빈 배열. 각 항목: {general_id, tier}
func current_draft_offer() -> Array[Dictionary]:
	if phase != PHASE_DRAFT:
		return []
	if _draft_offer.is_empty():
		var excluded: Array[String] = []
		for member: RosterMember in roster.members():
			excluded.append(member.general_id)
		_draft_offer = DraftGenerator.offer(_db, run_seed, draft_pick_count, excluded)
	return _draft_offer


## 드래프트 후보 하나를 골라 다음 빈 칸에 넣는다. 정해진 횟수를 다 고르면 토벌 단계로 넘어간다.
func choose_draft(index: int) -> bool:
	var offer: Array[Dictionary] = current_draft_offer()
	if index < 0 or index >= offer.size():
		push_error("고를 수 없는 드래프트 번호: %d" % index)
		return false
	var slot: int = roster.first_empty_slot()
	if slot < 0:
		push_error("드래프트 장수를 넣을 빈 칸이 없다")
		return false
	var pick: Dictionary = offer[index]
	var member: RosterMember = RosterMember.create(_db, String(pick["general_id"]), String(pick["tier"]), _db.draft_level)
	roster.set_member(slot, member)
	draft_pick_count += 1
	history.append({"type": "draft", "index": index})
	log_lines.append("  출정 준비 %d/%d: %s(%s) → %s" % [
		draft_pick_count, _db.draft_picks, member.display_name(_db), member.tier, roster.slot_label(slot)])
	_draft_offer = []
	if draft_pick_count >= _db.draft_picks:
		phase = PHASE_EXPEDITION
		log_lines.append("원정 시작: %d년" % year)
	return true


## 드래프트에서 지금까지 고른 장수 중 힐러가 있는지 (화면 안내용).
func has_healer() -> bool:
	for member: RosterMember in roster.members():
		if _db.get_general(member.general_id).is_healer():
			return true
	return false


# ---------- 토벌 ----------

## 이번 라운드의 토벌 선택지. 토벌을 고를 차례가 아니면 빈 배열.
func current_choices() -> Array[Expedition]:
	if phase != PHASE_EXPEDITION:
		return []
	if _choices.is_empty():
		_choices = ExpeditionGenerator.generate(_db, run_seed, year, round_number)
	return _choices


## 선택지 하나를 골라 전투를 치르고 결과를 런에 반영한다. 전투 내용(로그 등)을 돌려준다.
## 토벌을 고를 차례가 아니거나 번호가 잘못됐으면 null.
func choose(choice_index: int) -> BattleEngine:
	var choices: Array[Expedition] = current_choices()
	if choice_index < 0 or choice_index >= choices.size():
		push_error("고를 수 없는 토벌 번호: %d" % choice_index)
		return null
	var expedition: Expedition = choices[choice_index]
	last_battle_roster = []
	for member: RosterMember in roster.members():
		last_battle_roster.append({"general_id": member.general_id, "tier": member.tier, "level": member.level})

	# 보유효과 중 체력 증가(상시)는 전투 동안 최대 체력과 현재 체력을 함께 늘린다.
	var hp_bonus_percent: float = 0.0
	for entry: Dictionary in reserve_effects():
		var effect: ReserveEffectDef = entry["effect"]
		if effect.effect_kind == "stat_percent" and effect.effect_stat == "hp":
			hp_bonus_percent += effect.effect_value

	# 출전 슬롯의 장수만 싸운다. 빈 칸은 건너뛰고, 장수는 자기 자리 그대로 출전한다.
	var allies: Array[BattleUnit] = []
	var fighters: Array[RosterMember] = []
	var hp_bonuses: Array[int] = []
	for slot: int in roster.active_count:
		var member: RosterMember = roster.get_member(slot)
		if member == null:
			continue
		var unit: BattleUnit = BattleUnit.create(_db, member.general_id, member.tier, member.level, member.hp)
		unit.slot = slot
		var bonus: int = roundi(float(unit.max_hp) * hp_bonus_percent / 100.0)
		unit.max_hp += bonus
		unit.hp += bonus
		allies.append(unit)
		fighters.append(member)
		hp_bonuses.append(bonus)

	var enemies: Array[BattleUnit] = []
	for enemy: Dictionary in expedition.enemies:
		enemies.append(BattleUnit.create(_db, String(enemy["general_id"]), String(enemy["tier"]), int(enemy["level"]), -1, expedition.formation.enemy_stat_multiplier))

	var battle: BattleEngine = BattleEngine.new(_db.balance, allies, enemies, expedition.battle_seed)
	_apply_reserve_auras(battle, hp_bonus_percent)
	battle.run()

	# 체력 유지: 전투가 끝난 체력을 그대로 로스터에 적는다. 회복은 없다.
	# 보유효과로 늘었던 체력은 전투가 끝나면 빠진다. 전투에서 버틴 장수는 최소 1이 남는다.
	_battle_healers = []
	for i: int in fighters.size():
		if allies[i].is_alive():
			fighters[i].hp = maxi(1, allies[i].hp - hp_bonuses[i])
			if _db.get_general(fighters[i].general_id).is_healer():
				_battle_healers.append(fighters[i])
		else:
			fighters[i].hp = 0
	var dead_names: Array[String] = _bury_dead()

	history.append({"type": "expedition", "index": choice_index})
	log_lines.append("%d년 %d라운드 [%s] 적 %d명 → %s (%d턴), 남은 장수 %d명" % [
		year, round_number, expedition.title, expedition.enemy_count(),
		"승리" if battle.player_won() else "패배", battle.round_number, roster.member_count(),
	])
	if not dead_names.is_empty():
		log_lines.append("  전사: %s" % ", ".join(dead_names))

	_choices = []
	if battle.player_won():
		_rewards = RewardGenerator.generate(_db, expedition, SeedUtil.derive(run_seed, year, round_number, 100 + choice_index))
		phase = PHASE_REWARD
	else:
		_handle_defeat()
	return battle


# ---------- 보상 ----------

## 지금 고를 수 있는 보상 선택지. 보상을 고를 차례가 아니면 빈 배열.
func current_rewards() -> Array[Reward]:
	return _rewards if phase == PHASE_REWARD else ([] as Array[Reward])


## 이 보상을 고를 때 대상 슬롯을 함께 정해야 하는지.
##   - 경험치: 받을 장수를 정해야 한다.
##   - 장수 카드: 로스터에 없는 장수인데 모든 칸이 찼을 때만 교체할 장수를 정한다.
func reward_needs_target(reward_index: int) -> bool:
	var rewards: Array[Reward] = current_rewards()
	if reward_index < 0 or reward_index >= rewards.size():
		return false
	var reward: Reward = rewards[reward_index]
	if reward.is_exp():
		return true
	if reward.is_chest():
		return _db.get_chest(reward.chest_id).needs_target()
	return not roster.has_general(reward.general_id) and roster.is_full()


## 보상 하나를 고른다. target_slot은 reward_needs_target()이 참일 때만 쓰인다.
## 성공하면 true를 돌려주고 다음 라운드로 넘어간다.
func choose_reward(reward_index: int, target_slot: int = -1) -> bool:
	var rewards: Array[Reward] = current_rewards()
	if reward_index < 0 or reward_index >= rewards.size():
		push_error("고를 수 없는 보상 번호: %d" % reward_index)
		return false
	var reward: Reward = rewards[reward_index]
	if reward_needs_target(reward_index) and roster.get_member(target_slot) == null:
		push_error("보상 대상 슬롯이 잘못됐다: %d" % target_slot)
		return false

	last_merge_events = []
	if reward.is_exp():
		_grant_experience(reward, roster.get_member(target_slot))
	elif reward.is_chest():
		open_chest(_db.get_chest(reward.chest_id), target_slot, SeedUtil.derive(run_seed, year, round_number, 300))
	else:
		_take_general_card(reward, target_slot)

	# 전투 후 처리: 보상(합성·승급) 다음에 힐러 치유, 그다음 보유효과 슬롯 휴식 회복.
	_heal_after_battle()
	_rest_reserve()
	_update_reserve_capacity()

	history.append({"type": "reward", "index": reward_index, "target": target_slot})
	_rewards = []
	phase = PHASE_EXPEDITION
	_advance_round()
	return true


# ---------- 보유효과 ----------

## 보유효과 슬롯에 있는 장수들의 보유효과. 각 항목: {member: RosterMember, effect: ReserveEffectDef}
func reserve_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: int in range(roster.active_count, roster.size()):
		var member: RosterMember = roster.get_member(slot)
		if member == null:
			continue
		var effect: ReserveEffectDef = _db.get_general(member.general_id).get_tier(member.tier).reserve_effect
		result.append({"member": member, "effect": effect})
	return result


## 보유효과 중 스탯 효과(체력 제외)를 전투에 지속 효과로 건다.
func _apply_reserve_auras(battle: BattleEngine, hp_bonus_percent: float) -> void:
	if hp_bonus_percent > 0.0:
		battle.log_lines.append("보유효과 발동: 아군 체력 +%d%%" % roundi(hp_bonus_percent))
	for entry: Dictionary in reserve_effects():
		var member: RosterMember = entry["member"]
		var effect: ReserveEffectDef = entry["effect"]
		if effect.effect_kind != "stat_percent" or effect.effect_stat == "hp":
			continue
		var condition_kind: String = effect.condition_kind
		var condition_value: int = effect.condition_value
		# 최후반부 = 아군이 balance의 기준 인원 이하로 남았을 때.
		if condition_kind == "late_game":
			condition_kind = "allies_alive_at_most"
			condition_value = _db.balance.get_int("reserve_effect.late_game_allies_alive_at_most")
		var label: String = "%s의 %s" % [member.display_name(_db), effect.name]
		battle.add_player_aura(member.general_id, label, effect.effect_stat, effect.effect_value, condition_kind, condition_value)


## 보유효과 슬롯 수를 다시 계산한다: 기본 칸 + 보유효과 슬롯에 있는 장수들의 슬롯 확장 (최대치까지).
## 줄어들면 마지막 보유효과 슬롯의 장수가 방출된다 (기본값). 방출로 다시 줄어들 수 있어 안정될 때까지 반복한다.
func _update_reserve_capacity() -> void:
	var base: int = _db.balance.get_int("roster.reserve_slots_base")
	var maximum: int = _db.balance.get_int("roster.reserve_slots_max")
	while true:
		var bonus: int = 0
		for entry: Dictionary in reserve_effects():
			var effect: ReserveEffectDef = entry["effect"]
			bonus += effect.reserve_slot_bonus()
		var wanted: int = clampi(base + bonus, base, maximum)
		if wanted == roster.reserve_count():
			return
		var growing: bool = wanted > roster.reserve_count()
		var released: Array[RosterMember] = roster.set_reserve_count(wanted)
		log_lines.append("  보유효과 슬롯 %s: %d칸" % ["확장" if growing else "축소", wanted])
		for member: RosterMember in released:
			log_lines.append("  슬롯 축소로 방출: %s(%s)" % [member.display_name(_db), member.tier])


# ---------- 회복 ----------

## 힐러 치유: 이번 전투에 출전해 살아남은 힐러마다 다친 장수 1명을 치유한다.
## 대상은 체력 비율이 낮을수록 잘 뽑히는 가중치 랜덤. 힐러 중첩(healer.stacking)이 꺼져 있으면 한 번만.
func _heal_after_battle() -> void:
	var healers: Array[RosterMember] = []
	for healer: RosterMember in _battle_healers:
		if roster.slots.has(healer) and not healer.is_dead():
			healers.append(healer)
	if not _db.balance.get_bool("healer.stacking"):
		healers = healers.slice(0, 1)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SeedUtil.derive(run_seed, year, round_number, 200)
	var ratio: float = _db.balance.get_float("healer.heal_ratio")
	for healer: RosterMember in healers:
		var wounded: Array[RosterMember] = []
		var weights: Array[float] = []
		for member: RosterMember in roster.members():
			if member.hp > 0 and member.hp < member.max_hp:
				wounded.append(member)
				weights.append(1.0 - float(member.hp) / float(member.max_hp))
		if wounded.is_empty():
			return
		var target: RosterMember = wounded[SeedUtil.pick_weighted(rng, weights)]
		var before: int = target.hp
		target.hp = mini(target.max_hp, target.hp + maxi(1, roundi(float(target.max_hp) * ratio)))
		log_lines.append("  치유: %s → %s +%d (%d/%d)" % [
			healer.display_name(_db), target.display_name(_db), target.hp - before, target.hp, target.max_hp])
	_battle_healers = []


## 보유효과 슬롯 휴식 회복: 보유효과 슬롯의 장수가 매 라운드 최대 체력의 일정 비율을 회복한다. 기본값은 0(회복 없음).
func _rest_reserve() -> void:
	var ratio: float = _db.balance.get_float("roster.reserve_rest_heal_ratio")
	if ratio <= 0.0:
		return
	for slot: int in range(roster.active_count, roster.size()):
		var member: RosterMember = roster.get_member(slot)
		if member != null:
			member.hp = mini(member.max_hp, member.hp + maxi(1, roundi(float(member.max_hp) * ratio)))


# ---------- 보물상자 ----------

## 보물상자를 연다: 범위 안의 로스터 장수들에게 카드를 무작위로 나눠 주고, 모두 합성 진행도에 넣은 뒤 합성한다.
## 카드 티어는 그 장수가 가진 티어 중 낮은 쪽이 주로 나온다 (chests.json의 tier_offset_weights).
## target_slot은 장수 1명 집중 상자에서만 쓴다.
func open_chest(chest: ChestDef, target_slot: int, seed_value: int) -> void:
	var receivers: Array[RosterMember] = []
	match chest.scope:
		"roster":
			receivers = roster.members()
		"active":
			for slot: int in roster.active_count:
				if roster.get_member(slot) != null:
					receivers.append(roster.get_member(slot))
		"single":
			if roster.get_member(target_slot) != null:
				receivers.append(roster.get_member(target_slot))
	if receivers.is_empty():
		log_lines.append("  보물상자 %s: 받을 장수가 없다" % chest.name)
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var tally: Dictionary[String, int] = {}
	var tally_order: Array[String] = []
	for i: int in chest.card_count:
		var member: RosterMember = receivers[rng.randi_range(0, receivers.size() - 1)]
		var tiers: Array[String] = _db.get_general(member.general_id).available_tiers()
		var offset: int = SeedUtil.pick_weighted(rng, _db.chest_tier_offset_weights)
		var tier: String = tiers[mini(offset, tiers.size() - 1)]
		add_merge_card(member.general_id, tier)
		var key: String = "%s %s" % [member.display_name(_db), tier]
		if not tally.has(key):
			tally[key] = 0
			tally_order.append(key)
		tally[key] += 1

	var parts: Array[String] = []
	for key: String in tally_order:
		parts.append("%s×%d" % [key, tally[key]])
	log_lines.append("  보물상자 %s %d장: %s" % [chest.name, chest.card_count, ", ".join(parts)])
	for member: RosterMember in receivers:
		apply_merge(roster.slots.find(member))


func _grant_experience(reward: Reward, member: RosterMember) -> void:
	var before: int = member.level
	member.add_experience(_db, reward.exp_amount)
	var level_text: String = "" if member.level == before else " (Lv.%d → Lv.%d)" % [before, member.level]
	log_lines.append("  보상: %s에게 경험치 %d%s" % [member.display_name(_db), reward.exp_amount, level_text])


## 장수 카드 처리 순서 (기획서 그대로):
##   1. 로스터에 이미 있는 장수 → 합성 진행도에 적립
##   2. 없는 장수이고 빈 칸이 있음 → 반드시 빈 칸을 채운다
##   3. 없는 장수이고 모든 칸이 참 → 고른 장수와 교체하고 성장을 계승한다
## 영입한 경우에도 예전에 모아 둔 합성 진행도가 있으면 이어서 합성한다.
func _take_general_card(reward: Reward, target_slot: int) -> void:
	var general_name: String = _db.get_general(reward.general_id).name
	var owned_slot: int = roster.find_general(reward.general_id)
	if owned_slot >= 0:
		add_merge_card(reward.general_id, reward.tier)
		log_lines.append("  보상: %s(%s) 카드 → 합성 진행도 적립" % [general_name, reward.tier])
		apply_merge(owned_slot)
		return

	# 영입 장수는 카드가 나온 적의 레벨에 비례한 레벨로 들어온다.
	var newcomer: RosterMember = RosterMember.create(_db, reward.general_id, reward.tier, reward.recruit_level(_db))
	var empty_slot: int = roster.first_empty_slot()
	if empty_slot >= 0:
		roster.set_member(empty_slot, newcomer)
		log_lines.append("  보상: %s(%s) Lv.%d 영입 → %s 빈 칸" % [general_name, reward.tier, newcomer.level, roster.slot_label(empty_slot)])
		apply_merge(empty_slot)
		return

	# 교체 영입: 나가는 장수가 쌓은 경험치의 일정 비율을 새 장수가 이어받는다.
	# 카드 레벨과 계승 중 더 높은 쪽을 쓴다 (둘을 더하지 않는다).
	# 스탯은 새 장수 고유의 성장률을 따르고, 새 장수는 체력이 가득 찬 상태로 합류한다.
	var outgoing: RosterMember = roster.get_member(target_slot)
	var inherited: int = floori(float(outgoing.total_experience(_db)) * _db.balance.get_float("inheritance.ratio"))
	var source: String = "카드 레벨로"
	if inherited > newcomer.total_experience(_db):
		newcomer = RosterMember.create(_db, reward.general_id, reward.tier, 1)
		newcomer.add_experience(_db, inherited)
		source = "계승으로"
	newcomer.hp = newcomer.max_hp
	roster.set_member(target_slot, newcomer)
	log_lines.append("  보상: %s(%s) 영입 ← %s 교체, %s Lv.%d (나간 장수 Lv.%d)" % [
		general_name, reward.tier, outgoing.display_name(_db), source, newcomer.level, outgoing.level,
	])
	apply_merge(target_slot)


## 슬롯의 장수에 대해 합성을 계산하고, 티어가 오르면 승급시킨다. 승급하면 체력이 전부 회복된다.
## 레벨과 경험치는 그대로 유지되고, 스탯은 새 티어의 기본 스탯·성장률로 다시 계산된다.
## 승급했으면 true.
func apply_merge(slot: int) -> bool:
	var member: RosterMember = roster.get_member(slot)
	if member == null:
		return false
	if not merge_progress.has(member.general_id):
		merge_progress[member.general_id] = {}
	var progress: Dictionary = merge_progress[member.general_id]
	var result: Dictionary = Merge.resolve(
		_db.get_general(member.general_id), member.tier, progress, _db.balance.get_int("merge.cards_per_promotion"))

	var general_name: String = member.display_name(_db)
	var events: Array = result["events"]
	for event: Dictionary in events:
		last_merge_events.append({"kind": "merge", "general_id": member.general_id, "from": event["from"], "to": event["to"]})
		log_lines.append("  합성: %s %s %d장 → %s 1장" % [
			general_name, event["from"], _db.balance.get_int("merge.cards_per_promotion"), event["to"]])

	var new_tier: String = result["body_tier"]
	if new_tier == member.tier:
		return false
	var old_tier: String = member.tier
	member.tier = new_tier
	member.refresh_max_hp(_db)
	member.hp = member.max_hp
	last_merge_events.append({"kind": "promotion", "general_id": member.general_id, "from": old_tier, "to": new_tier})
	log_lines.append("  승급: %s %s → %s, 체력 전부 회복 (%d/%d)" % [general_name, old_tier, new_tier, member.hp, member.max_hp])
	return true


## 합성 진행도에 카드 한 장을 더한다.
func add_merge_card(general_id: String, tier: String) -> void:
	if not merge_progress.has(general_id):
		merge_progress[general_id] = {}
	var by_tier: Dictionary = merge_progress[general_id]
	by_tier[tier] = int(by_tier.get(tier, 0)) + 1


func merge_card_count(general_id: String, tier: String) -> int:
	if not merge_progress.has(general_id):
		return 0
	var by_tier: Dictionary = merge_progress[general_id]
	return int(by_tier.get(tier, 0))


# ---------- 슬롯 정비 ----------

## 두 슬롯을 맞바꾼다 (출전 ↔ 보유효과 포함). 전투는 choose() 안에서 한 번에 끝나므로 전투 중 이동은 일어날 수 없다.
## 출전 장수가 한 명도 남지 않게 되는 이동은 거부한다.
func swap_slots(slot_a: int, slot_b: int) -> bool:
	if is_over() or not roster.is_valid_slot(slot_a) or not roster.is_valid_slot(slot_b) or slot_a == slot_b:
		return false
	roster.swap(slot_a, slot_b)
	if roster.active_member_count() == 0:
		roster.swap(slot_a, slot_b)
		return false
	history.append({"type": "swap", "a": slot_a, "b": slot_b})
	# 슬롯 확장 장수가 출전 슬롯으로 나가면 보유효과 슬롯이 줄어들 수 있다.
	_update_reserve_capacity()
	return true


## 장수를 자발적으로 방출한다. 계승은 없고, 합성 진행도는 런 동안 남는다.
## 마지막 출전 장수는 방출할 수 없다.
func release_member(slot: int) -> bool:
	var member: RosterMember = roster.get_member(slot)
	if is_over() or member == null:
		return false
	if roster.is_active_slot(slot) and roster.active_member_count() <= 1:
		return false
	roster.set_member(slot, null)
	history.append({"type": "release", "slot": slot})
	log_lines.append("  방출: %s(%s)" % [member.display_name(_db), member.tier])
	_update_reserve_capacity()
	return true


# ---------- 내부 구현 ----------

## 체력이 0이 된 출전 장수를 전사 처리한다: 기록에 남기고 자리를 비운다. 전사한 장수의 이름을 돌려준다.
func _bury_dead() -> Array[String]:
	var names: Array[String] = []
	for slot: int in roster.active_count:
		var member: RosterMember = roster.get_member(slot)
		if member == null or not member.is_dead():
			continue
		fallen.append({"general_id": member.general_id, "tier": member.tier, "level": member.level, "year": year, "round": round_number})
		names.append(member.display_name(_db))
		roster.set_member(slot, null)
	return names


func _advance_round() -> void:
	round_number += 1
	if round_number > _db.balance.get_int("run.rounds_per_year"):
		round_number = 1
		year += 1
		log_lines.append("── 해가 넘어갔다: %d년 (%s) ──" % [year, _db.era_for_year(year).name])
		# 해 넘김 보상: 정해진 상자를 자동으로 연다.
		if not _db.year_end_chest_id.is_empty():
			last_merge_events = []
			open_chest(_db.get_chest(_db.year_end_chest_id), -1, SeedUtil.derive(run_seed, year, 0, 400))
			_update_reserve_capacity()


func _handle_defeat() -> void:
	# 기본값(run.defeat_ends_run = true): 전투에서 지면 런이 끝난다.
	# 대안(일부 전사 후 계속)은 규칙이 정해지면 여기에 추가한다. 지금은 설정과 무관하게 종료한다.
	phase = PHASE_OVER
	log_lines.append("원정 종료: %d년 %d라운드에서 패배. 생존 %d년" % [year, round_number, years_survived()])
