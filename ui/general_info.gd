class_name GeneralInfo
extends RefCounted
## 장수 한 명(장수 + 티어)을 화면에 설명하는 글을 만든다. 드래프트·보상 화면이 함께 쓴다.
## 화면마다 따로 쓰면 표시가 어긋나기 쉬워서 한곳에 모았다.


static func role_label(role: String) -> String:
	match role:
		"warrior":
			return "무장"
		"defender":
			return "수비"
		"strategist":
			return "책사"
		"healer":
			return "힐러"
		"support":
			return "보조"
	return role


## 카드에 바로 보이는 요약 (여러 줄).
##   칭호 · 역할
##   능력치 체력 26(실제 130) · 공격 13 · …
##   스킬: 이름(대기 N턴), …
##   보유효과: 이름 — 설명
static func summary_lines(db: GameDatabase, general_id: String, tier: String) -> Array[String]:
	var general: GeneralDef = db.get_general(general_id)
	var tier_def: GeneralTierDef = general.get_tier(tier)
	var base: Stats = tier_def.base_stats
	var lines: Array[String] = []
	lines.append("%s · %s" % [tier_def.title, role_label(general.role)])
	lines.append("능력치 체력 %d(실제 %d) · 공격 %d · 방어 %d · 속도 %d · 지략 %d   잘 크는 능력치: %s" % [
		base.hp, base.hp * db.balance.get_int("ability.hp_per_point"), base.attack, base.defense, base.speed, base.intellect,
		top_tendency(tier_def)])
	var skills: Array[String] = []
	for skill_id: String in tier_def.skill_ids:
		var skill: SkillDef = db.get_skill(skill_id)
		skills.append("%s(대기 %d턴)" % [skill.name, skill.cooldown])
	lines.append("스킬: %s" % ", ".join(skills))
	lines.append("보유효과: %s — %s" % [tier_def.reserve_effect.name, tier_def.reserve_effect.description])
	return lines


## 마우스를 올렸을 때 보이는 자세한 설명: 시기 설명과 스킬 설명.
static func tooltip(db: GameDatabase, general_id: String, tier: String) -> String:
	var tier_def: GeneralTierDef = db.get_general(general_id).get_tier(tier)
	var lines: Array[String] = [tier_def.era, ""]
	for skill_id: String in tier_def.skill_ids:
		var skill: SkillDef = db.get_skill(skill_id)
		lines.append("[%s] %s" % [skill.name, skill.description])
	lines.append("")
	lines.append("잘 크는 능력치는 적 장수가 포인트를 나누는 비율입니다. 내 장수는 직접 배분합니다.")
	return "\n".join(lines)


## 성향(tendency)이 높은 능력치 2개. 예: "공격·체력"
static func top_tendency(tier_def: GeneralTierDef) -> String:
	var keys: Array[String] = Stats.KEYS.duplicate()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var weight_a: float = float(tier_def.tendency.get(a, 0.0))
		var weight_b: float = float(tier_def.tendency.get(b, 0.0))
		if not is_equal_approx(weight_a, weight_b):
			return weight_a > weight_b
		return Stats.KEYS.find(a) < Stats.KEYS.find(b))
	return "%s·%s" % [AbilityBuild.LABELS[keys[0]], AbilityBuild.LABELS[keys[1]]]


## 이미 로스터에 있는 장수의 카드를 받으면 합성이 어떻게 되는지 미리 계산한다 (실제 합성 계산을 사본으로 돌려 본다).
## 예: "합성: 본체 C, C 카드 1장 → 이번 카드로 C 3장 → B 승급!"
static func merge_preview(db: GameDatabase, run: ExpeditionRun, general_id: String, card_tier: String) -> String:
	var slot: int = run.roster.find_general(general_id)
	if slot < 0:
		return ""
	var body: RosterMember = run.roster.get_member(slot)
	var progress: Dictionary = {}
	for tier: String in Tier.ORDER:
		var count: int = run.merge_card_count(general_id, tier)
		if count > 0:
			progress[tier] = count
	var before: String = _progress_text(progress)
	progress[card_tier] = int(progress.get(card_tier, 0)) + 1
	var result: Dictionary = Merge.resolve(db.get_general(general_id), body.tier, progress, db.balance.get_int("merge.cards_per_promotion"))
	var new_tier: String = result["body_tier"]
	var text: String = "이미 있는 장수 — 본체 %s Lv.%d, 모아 둔 카드: %s" % [body.tier, body.level, before]
	if new_tier != body.tier:
		return text + "  → 이번 카드로 %s 승급!" % new_tier
	return text + "  → 적립 후: %s" % _progress_text(progress)


static func _progress_text(progress: Dictionary) -> String:
	var parts: Array[String] = []
	for tier: String in Tier.ORDER:
		if int(progress.get(tier, 0)) > 0:
			parts.append("%s %d장" % [tier, int(progress[tier])])
	return "없음" if parts.is_empty() else ", ".join(parts)
