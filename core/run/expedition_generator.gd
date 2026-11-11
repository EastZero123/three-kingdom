class_name ExpeditionGenerator
extends RefCounted
## 한 라운드의 토벌 선택지를 만든다.
## 런 시드·연도·라운드만으로 결과가 정해지므로, 같은 시드면 같은 라운드에 항상 같은 선택지가 나온다.

## 전열에 서는 역할.
const FRONT_ROLES: Array[String] = ["warrior", "defender"]


static func generate(db: GameDatabase, run_seed: int, year: int, round_number: int) -> Array[Expedition]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SeedUtil.derive(run_seed, year, round_number, 0)

	var era: EraDef = db.era_for_year(year)
	var choice_count: int = db.balance.get_int("run.expedition_choices")
	var max_level: int = db.balance.get_int("level.max_level")
	var base_level: int = db.enemy_base_level(year, round_number)

	var result: Array[Expedition] = []
	var types: Array[ExpeditionTypeDef] = _pick_types(db, rng, choice_count)
	_maybe_add_special(db, rng, types, year)
	for i: int in types.size():
		var expedition: Expedition = Expedition.new()
		expedition.type = types[i]
		expedition.title = types[i].name
		if not types[i].issuers.is_empty():
			expedition.title = "%s %s" % [types[i].issuers[rng.randi_range(0, types[i].issuers.size() - 1)], types[i].name]
		# 같은 난이도 안에서도 편성을 뽑아 인원·레벨·전력·티어를 바꾼다.
		var formation_weights: Array[float] = []
		for candidate: FormationDef in types[i].formations:
			formation_weights.append(candidate.weight)
		var formation: FormationDef = types[i].formations[SeedUtil.pick_weighted(rng, formation_weights)]
		expedition.formation = formation
		if not formation.name.is_empty():
			expedition.title = "%s · %s" % [expedition.title, formation.name]
		expedition.era = era
		expedition.enemy_level = clampi(base_level + formation.level_offset, 1, max_level)
		var count: int = rng.randi_range(formation.enemy_count_min, formation.enemy_count_max)
		expedition.enemies = _pick_enemies(db, rng, era, count, expedition.enemy_level, formation.tier_weight_per_step)
		expedition.battle_seed = SeedUtil.derive(run_seed, year, round_number, i + 1)
		result.append(expedition)
	return result


## 일반 토벌 종류를 가중치로 뽑는다. 종류가 충분하면 서로 겹치지 않게 뽑는다.
static func _pick_types(db: GameDatabase, rng: RandomNumberGenerator, count: int) -> Array[ExpeditionTypeDef]:
	var normal_types: Array[ExpeditionTypeDef] = []
	for type_def: ExpeditionTypeDef in db.expedition_types:
		if not type_def.is_special():
			normal_types.append(type_def)
	var remaining: Array[ExpeditionTypeDef] = normal_types.duplicate()
	var picked: Array[ExpeditionTypeDef] = []
	while picked.size() < count:
		if remaining.is_empty():
			remaining = normal_types.duplicate()
		var weights: Array[float] = []
		for type_def: ExpeditionTypeDef in remaining:
			weights.append(type_def.weight)
		var index: int = SeedUtil.pick_weighted(rng, weights)
		picked.append(remaining[index])
		remaining.remove_at(index)
	return picked


## run.special_expedition_chance 확률로, 이 연도에 나올 수 있는 특별 토벌 하나가 선택지 하나를 대신한다.
static func _maybe_add_special(db: GameDatabase, rng: RandomNumberGenerator, types: Array[ExpeditionTypeDef], year: int) -> void:
	var specials: Array[ExpeditionTypeDef] = []
	var weights: Array[float] = []
	for type_def: ExpeditionTypeDef in db.expedition_types:
		if type_def.is_special() and year >= type_def.from_year:
			specials.append(type_def)
			weights.append(type_def.weight)
	# 난수를 쓰는 순서가 연도와 무관하게 같도록, 특별 토벌이 없어도 주사위는 굴린다.
	var roll: float = rng.randf()
	if specials.is_empty() or types.is_empty() or roll >= db.balance.get_float("run.special_expedition_chance"):
		return
	var special: ExpeditionTypeDef = specials[SeedUtil.pick_weighted(rng, weights)]
	types[rng.randi_range(0, types.size() - 1)] = special


## 시대의 후보에서 서로 다른 장수를 가중치로 뽑아 적 원정대를 만든다.
## 후보 가중치 × tier_step^(티어 순번): 어려운 토벌일수록 높은 티어 후보가 더 잘 뽑힌다.
static func _pick_enemies(db: GameDatabase, rng: RandomNumberGenerator, era: EraDef, count: int, level: int, tier_step: float) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = era.pool.duplicate()
	var picked: Array[Dictionary] = []
	while picked.size() < count and not remaining.is_empty():
		var weights: Array[float] = []
		for entry: Dictionary in remaining:
			weights.append(float(entry["weight"]) * pow(tier_step, Tier.index_of(String(entry["tier"]))))
		var chosen: Dictionary = remaining[SeedUtil.pick_weighted(rng, weights)]
		picked.append({"general_id": chosen["general_id"], "tier": chosen["tier"], "level": level})
		# 같은 장수의 다른 티어 후보는 모두 뺀다.
		var filtered: Array[Dictionary] = []
		for entry: Dictionary in remaining:
			if entry["general_id"] != chosen["general_id"]:
				filtered.append(entry)
		remaining = filtered
	return _arrange(db, picked)


## 무장·수비 역할을 앞쪽 자리에 세운다. 같은 역할끼리는 뽑힌 순서를 유지한다.
static func _arrange(db: GameDatabase, enemies: Array[Dictionary]) -> Array[Dictionary]:
	var front: Array[Dictionary] = []
	var back: Array[Dictionary] = []
	for enemy: Dictionary in enemies:
		if FRONT_ROLES.has(db.get_general(String(enemy["general_id"])).role):
			front.append(enemy)
		else:
			back.append(enemy)
	front.append_array(back)
	return front
