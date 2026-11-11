class_name RewardGenerator
extends RefCounted
## 승리 보상 선택지를 만든다.
##   - 경험치: 쓰러뜨린 적 레벨의 합 × reward.exp_per_enemy_level × 토벌의 경험치 배율
##   - 장수 카드: 방금 맞붙은 적 장수 중에서 무작위 (서로 다른 장수)
##   - 보물상자: 특별 토벌에서만. 토벌 종류의 상자 후보에서 가중치로 하나
## 순서는 보물상자 → 경험치 → 장수 카드. 전체 개수는 reward.choices로 같다.


static func generate(db: GameDatabase, expedition: Expedition, seed_value: int) -> Array[Reward]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	var total: int = db.balance.get_int("reward.choices")
	var result: Array[Reward] = []
	if not expedition.type.chest_pool.is_empty():
		var weights: Array[float] = []
		for entry: Dictionary in expedition.type.chest_pool:
			weights.append(float(entry["weight"]))
		var picked: Dictionary = expedition.type.chest_pool[SeedUtil.pick_weighted(rng, weights)]
		result.append(Reward.make_chest(String(picked["chest_id"])))

	var exp_count: int = mini(db.balance.get_int("reward.exp_choices"), total - result.size())
	for i: int in exp_count:
		result.append(Reward.make_exp(exp_amount(db, expedition)))

	# 적 목록에서 겹치지 않게 뽑는다.
	var candidates: Array[Dictionary] = expedition.enemies.duplicate()
	while result.size() < total and not candidates.is_empty():
		var index: int = rng.randi_range(0, candidates.size() - 1)
		var enemy: Dictionary = candidates[index]
		candidates.remove_at(index)
		result.append(Reward.make_card(String(enemy["general_id"]), String(enemy["tier"]), int(enemy["level"])))
	return result


static func exp_amount(db: GameDatabase, expedition: Expedition) -> int:
	var level_sum: int = 0
	for enemy: Dictionary in expedition.enemies:
		level_sum += int(enemy["level"])
	var per_level: float = db.balance.get_float("reward.exp_per_enemy_level")
	return roundi(float(level_sum) * per_level * expedition.formation.reward_exp_multiplier)
