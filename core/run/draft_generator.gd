class_name DraftGenerator
extends RefCounted
## 시작 드래프트의 후보를 만든다: 장수를 먼저 고르고(모두 같은 확률), 그 장수가 가진 티어 중에서 가중치로 티어를 정한다.
## 장수를 먼저 고르므로 세력이 장수 수에 비례해 고르게 나오고, 티어는 주로 그 장수의 낮은 쪽 티어가 나온다.
## 이미 로스터에 있는 장수와 같은 후보 안의 장수는 다시 나오지 않는다.
## 런 시드와 몇 번째 뽑기인지만으로 정해지므로, 같은 시드·같은 선택이면 같은 후보가 나온다.


## 돌려주는 값: 후보 목록. 각 항목: {general_id: String, tier: String}
static func offer(db: GameDatabase, run_seed: int, pick_index: int, excluded_ids: Array[String]) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SeedUtil.derive(run_seed, 0, pick_index, 500)

	var taken: Array[String] = excluded_ids.duplicate()
	var result: Array[Dictionary] = []
	for i: int in db.draft_choices:
		var candidates: Array[String] = []
		for general_id: String in db.generals:
			if not taken.has(general_id) and not _tier_options(db, general_id).is_empty():
				candidates.append(general_id)
		if candidates.is_empty():
			break
		var general_id: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		var tiers: Array[String] = _tier_options(db, general_id)
		var weights: Array[float] = []
		for tier: String in tiers:
			weights.append(db.draft_tier_weights[tier])
		taken.append(general_id)
		result.append({"general_id": general_id, "tier": tiers[SeedUtil.pick_weighted(rng, weights)]})
	return result


## 이 장수가 가진 티어 중 드래프트 가중치가 0보다 큰 것.
static func _tier_options(db: GameDatabase, general_id: String) -> Array[String]:
	var result: Array[String] = []
	for tier: String in db.generals[general_id].available_tiers():
		if db.draft_tier_weights.get(tier, 0.0) > 0.0:
			result.append(tier)
	return result
