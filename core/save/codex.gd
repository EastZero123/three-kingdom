class_name Codex
extends RefCounted
## 도감: 지금까지 만나 본 장수와 티어의 영구 기록 (런이 끝나도 남는다). 수집 재미용.
## 형식: {장수 id: [만난 티어, …]}  예) {"guan_yu": ["C", "B"]}
## "만났다" = 드래프트 후보로 나왔거나, 토벌 선택지의 적으로 나왔거나, 로스터에 들어왔거나.


## 런의 지금 상태에서 보이는 장수와 티어를 모은다.
static func collect(run: ExpeditionRun) -> Dictionary:
	var found: Dictionary = {}
	for pick: Dictionary in run.current_draft_offer():
		_add(found, String(pick["general_id"]), String(pick["tier"]))
	for expedition: Expedition in run.current_choices():
		for enemy: Dictionary in expedition.enemies:
			_add(found, String(enemy["general_id"]), String(enemy["tier"]))
	for member: RosterMember in run.roster.members():
		_add(found, member.general_id, member.tier)
	return found


## 새로 만난 것을 도감에 더한다. 새로 추가된 (장수, 티어) 수를 돌려준다.
static func merge(codex: Dictionary, found: Dictionary) -> int:
	var added: int = 0
	for general_id: Variant in found:
		if not codex.has(general_id):
			codex[general_id] = []
		var known: Array = codex[general_id]
		for tier: Variant in found[general_id]:
			if not known.has(tier):
				known.append(tier)
				added += 1
	return added


static func has_met(codex: Dictionary, general_id: String, tier: String = "") -> bool:
	if not codex.has(general_id):
		return false
	if tier.is_empty():
		return true
	var known: Array = codex[general_id]
	return known.has(tier)


## 도감 진행: {generals: 만난 장수 수, generals_total, tiers: 만난 티어 수, tiers_total}
static func progress(db: GameDatabase, codex: Dictionary) -> Dictionary:
	var tiers_total: int = 0
	var tiers_met: int = 0
	var generals_met: int = 0
	for general_id: String in db.generals:
		var available: Array[String] = db.generals[general_id].available_tiers()
		tiers_total += available.size()
		if codex.has(general_id):
			generals_met += 1
			for tier: String in available:
				if has_met(codex, general_id, tier):
					tiers_met += 1
	return {"generals": generals_met, "generals_total": db.generals.size(), "tiers": tiers_met, "tiers_total": tiers_total}


static func _add(found: Dictionary, general_id: String, tier: String) -> void:
	if not found.has(general_id):
		found[general_id] = []
	var tiers: Array = found[general_id]
	if not tiers.has(tier):
		tiers.append(tier)
