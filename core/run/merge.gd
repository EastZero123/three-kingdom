class_name Merge
extends RefCounted
## 단계식 합성 계산.
##   - 같은 장수·같은 티어 카드 cards_per_promotion장(기본 3) → 한 단계 위 티어 카드 1장.
##   - 로스터의 장수 본체도 자기 티어의 1장으로 센다 (본체 + 같은 티어 2장이면 승급).
##   - 낮은 티어부터 차례로 계산하므로 한 번에 여러 단계가 연쇄로 오를 수 있다.
##   - 합성이 끝난 뒤 가장 높은 티어의 카드 1장이 새 본체가 된다.
##     그래서 본체보다 높은 티어 카드를 얻으면 바로 그 티어로 승급하고, 옛 본체는 원래 티어의 카드로 남는다.
##   - 그 장수의 최고 티어에서는 더 오를 곳이 없으므로 카드가 쌓이기만 한다.


## 합성을 계산한다. progress(티어 → 장수 수, 본체 제외)는 계산 결과로 바뀐다.
## 돌려주는 값: {body_tier: 새 본체 티어, events: [{from: 티어, to: 티어}, …] (일어난 합성 순서대로)}
static func resolve(general: GeneralDef, body_tier: String, progress: Dictionary, cards_per_promotion: int) -> Dictionary:
	var tiers: Array[String] = general.available_tiers()
	var counts: Dictionary[String, int] = {}
	for tier: String in tiers:
		counts[tier] = int(progress.get(tier, 0))
	counts[body_tier] += 1  # 본체도 한 장으로 센다

	var events: Array[Dictionary] = []
	for i: int in range(tiers.size() - 1):
		var tier: String = tiers[i]
		var next_tier: String = tiers[i + 1]
		while counts[tier] >= cards_per_promotion:
			counts[tier] -= cards_per_promotion
			counts[next_tier] += 1
			events.append({"from": tier, "to": next_tier})

	# 가장 높은 티어의 카드 한 장이 본체가 된다.
	var new_body: String = body_tier
	for tier: String in tiers:
		if counts[tier] > 0:
			new_body = tier
	counts[new_body] -= 1

	progress.clear()
	for tier: String in tiers:
		if counts[tier] > 0:
			progress[tier] = counts[tier]
	return {"body_tier": new_body, "events": events}
