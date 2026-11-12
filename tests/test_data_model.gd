extends GutTest
## 2단계 데이터 모델 테스트: 실제 data/ JSON이 올바른지, 로더가 잘못된 데이터를 잡아내는지 확인한다.
## GUT 규칙: 파일 이름과 함수 이름이 test_로 시작하면 자동으로 실행된다.

var _db: GameDatabase


# before_all(): 이 파일의 테스트를 시작하기 전에 한 번 호출된다.
func before_all() -> void:
	_db = GameDatabase.load_from_dir("res://data")


# ---------- 실제 데이터 ----------

func test_real_data_loads_without_errors() -> void:
	assert_eq(_db.errors, [] as Array[String], "data/ JSON에 오류가 없어야 한다")
	assert_true(_db.is_valid())


func test_sample_generals_count() -> void:
	assert_eq(_db.generals.size(), 66, "장수는 66명 (직접 만든 16명 + 확장 50명)")


func test_every_tier_is_covered_by_samples() -> void:
	for tier: String in Tier.ORDER:
		var found: bool = false
		for general_id: String in _db.generals:
			if _db.generals[general_id].has_tier(tier):
				found = true
				break
		assert_true(found, "%s 티어를 가진 샘플 장수가 있어야 한다" % tier)


func test_same_general_differs_by_tier() -> void:
	var dong_zhuo: GeneralDef = _db.get_general("dong_zhuo")
	assert_eq(dong_zhuo.available_tiers(), ["B", "A", "S"] as Array[String])
	assert_eq(dong_zhuo.lowest_tier(), "B")
	assert_eq(dong_zhuo.highest_tier(), "S")
	assert_ne(dong_zhuo.get_tier("B").title, dong_zhuo.get_tier("S").title, "티어마다 다른 시기의 인물")
	assert_gt(dong_zhuo.get_tier("S").base_stats.hp, dong_zhuo.get_tier("B").base_stats.hp)


func test_higher_tier_is_stronger_for_every_general() -> void:
	for general_id: String in _db.generals:
		var tiers: Array[String] = _db.generals[general_id].available_tiers()
		for i: int in range(1, tiers.size()):
			var lower: Stats = _db.generals[general_id].get_tier(tiers[i - 1]).base_stats
			var higher: Stats = _db.generals[general_id].get_tier(tiers[i]).base_stats
			for key: String in Stats.KEYS:
				assert_gt(higher.get_value(key), lower.get_value(key), "%s %s→%s %s" % [general_id, tiers[i - 1], tiers[i], key])


func test_base_abilities_are_within_scale() -> void:
	# 모든 장수의 기본 능력치는 1~100 (데이터 검사가 이미 막지만, 데이터 자체도 한 번 더 확인).
	for general_id: String in _db.generals:
		var general: GeneralDef = _db.generals[general_id]
		for tier: String in general.tiers:
			for key: String in Stats.KEYS:
				var value: int = general.get_tier(tier).base_stats.get_value(key)
				assert_between(value, 1, 100, "%s %s %s" % [general_id, tier, key])


func test_auto_invest_follows_tendency() -> void:
	var tier_def: GeneralTierDef = _db.get_general("guan_yu").get_tier("C")
	# 레벨 1은 포인트가 없어 기본 능력치 그대로. 실제 체력 = 체력 능력치 × 5.
	var level_1: Stats = AbilityBuild.enemy_combat_stats(_db.balance, tier_def, 1)
	assert_eq(level_1.attack, tier_def.base_stats.attack)
	assert_eq(level_1.hp, tier_def.base_stats.hp * 5)
	# 레벨 11: 50포인트가 성향 비율대로 나뉘고, 합은 정확히 50.
	var build: Dictionary = AbilityBuild.auto_invest(_db.balance, tier_def, 11)
	var total: int = int(build["overflow"])
	for key: String in Stats.KEYS:
		total += int(build["invested"][key])
	assert_eq(total, 50)
	assert_gt(int(build["invested"]["attack"]), int(build["invested"]["intellect"]), "무장은 공격이 지략보다 잘 큰다")
	# 같은 입력이면 항상 같은 결과 (난수 없음).
	assert_eq(AbilityBuild.auto_invest(_db.balance, tier_def, 11), build)
	# 만렙에서도 능력치는 100을 넘지 않는다.
	var max_level: int = _db.balance.get_int("level.max_level")
	var top: Dictionary = AbilityBuild.auto_invest(_db.balance, _db.get_general("lu_bu").get_tier("S"), max_level)
	var ability: Stats = AbilityBuild.abilities(_db.get_general("lu_bu").get_tier("S").base_stats, top["invested"])
	for key: String in Stats.KEYS:
		assert_lte(ability.get_value(key), 100, key)


func test_healer_and_roles() -> void:
	assert_true(_db.get_general("hua_tuo").is_healer(), "화타는 힐러")
	assert_false(_db.get_general("diao_chan").is_healer(), "초선은 방해형 보조라 힐러가 아니다")
	assert_eq(_db.get_general("diao_chan").role, "support")


func test_healer_reserve_effect_is_late_game_only() -> void:
	var hua_tuo: GeneralDef = _db.get_general("hua_tuo")
	for tier: String in hua_tuo.available_tiers():
		var effect: ReserveEffectDef = hua_tuo.get_tier(tier).reserve_effect
		assert_true(effect.is_conditional())
		assert_eq(effect.condition_kind, "late_game", "힐러의 보유효과는 최후반부 조건")


func test_reserve_slot_bonus_only_on_s_tier() -> void:
	var count: int = 0
	for general_id: String in _db.generals:
		var general: GeneralDef = _db.generals[general_id]
		for tier: String in general.available_tiers():
			if general.get_tier(tier).reserve_effect.reserve_slot_bonus() > 0:
				count += 1
				assert_eq(tier, "S", "슬롯 확장은 S티어에만 (%s)" % general_id)
	assert_eq(count, 2, "슬롯 확장은 조조 S와 사마의 S뿐 (희소성 유지)")
	assert_eq(_db.get_general("cao_cao").get_tier("S").reserve_effect.reserve_slot_bonus(), 1)
	assert_eq(_db.get_general("sima_yi").get_tier("S").reserve_effect.reserve_slot_bonus(), 1)


func test_expanded_roster_has_every_role_and_more_healers() -> void:
	var roles: Dictionary[String, int] = {}
	for general_id: String in _db.generals:
		var role: String = _db.generals[general_id].role
		roles[role] = roles.get(role, 0) + 1
	for role: String in GeneralDef.ROLES:
		assert_gt(roles.get(role, 0), 2, "%s 역할 장수가 3명 이상" % role)
	assert_eq(roles["healer"], 4, "힐러: 화타 + 동봉 · 길평 · 장중경")


func test_every_era_has_enough_variety() -> void:
	# 첫 시대는 D티어 상한 때문에 후보가 적다.
	for era: EraDef in _db.eras:
		var minimum: int = 8 if era.id == "yellow_turban_rising" else 13
		assert_true(era.distinct_general_count() >= minimum, "%s: 후보 장수가 충분하다 (%d명)" % [era.name, era.distinct_general_count()])


func test_early_eras_respect_tier_cap() -> void:
	for entry: Dictionary in _db.era_for_year(184).pool:
		assert_false(Tier.is_higher(String(entry["tier"]), "D"), "황건적의 난에는 D티어까지만 (%s %s)" % [entry["general_id"], entry["tier"]])
	for entry: Dictionary in _db.era_for_year(195).pool:
		assert_false(Tier.is_higher(String(entry["tier"]), "B"), "군웅할거에는 B티어까지만")


func test_skill_lookup() -> void:
	var slash: SkillDef = _db.get_skill("green_dragon_slash")
	assert_eq(slash.name, "청룡언월 베기")
	assert_true(slash.deals_damage())
	var charm: SkillDef = _db.get_skill("charm")
	assert_false(charm.deals_damage())
	assert_eq(charm.effects.size(), 1)
	assert_lt(charm.effects[0].percent, 0.0, "매혹은 디버프")


func test_balance_defaults_match_design_doc() -> void:
	var balance: Balance = _db.balance
	assert_eq(balance.get_int("roster.active_slots"), 6)
	assert_eq(balance.get_int("roster.reserve_slots_base"), 2)
	assert_eq(balance.get_int("roster.reserve_slots_max"), 5)
	assert_eq(balance.get_int("level.max_level"), 50)
	assert_eq(balance.get_int("merge.cards_per_promotion"), 3)
	assert_almost_eq(balance.get_float("inheritance.ratio"), 0.75, 0.0001)
	assert_eq(balance.get_int("run.rounds_per_year"), 10)
	assert_eq(balance.get_int("run.expedition_choices"), 3)
	assert_eq(balance.get_int("reward.choices"), 3)
	assert_true(balance.get_bool("run.defeat_ends_run"))
	assert_true(balance.get_bool("healer.stacking"))
	assert_almost_eq(balance.get_float("roster.reserve_rest_heal_ratio"), 0.0, 0.0001)
	assert_eq(balance.get_int("reserve_effect.late_game_allies_alive_at_most"), 2)


# ---------- 티어 도우미 ----------

func test_tier_order() -> void:
	assert_eq(Tier.ORDER.size(), 7)
	assert_eq(Tier.next_of("F"), "E")
	assert_eq(Tier.next_of("A"), "S")
	assert_eq(Tier.next_of("S"), "", "S 위는 없다")
	assert_true(Tier.is_higher("S", "A"))
	assert_false(Tier.is_higher("F", "E"))
	assert_false(Tier.is_valid("SS"))


# ---------- 잘못된 데이터 검출 ----------

func test_missing_files_are_reported() -> void:
	var db: GameDatabase = GameDatabase.load_from_dir("res://tests/no_such_dir")
	assert_false(db.is_valid())
	assert_true(_has_error(db, "파일이 없다"))


func test_unknown_skill_reference_is_reported() -> void:
	var general: Dictionary = _valid_general()
	var tier_d: Dictionary = general["tiers"]["D"]
	tier_d["skill_ids"] = ["no_such_skill"]
	var db: GameDatabase = _build([_valid_skill()], [general])
	assert_true(_has_error(db, "없는 스킬 'no_such_skill'"))


func test_tier_gap_is_reported() -> void:
	var general: Dictionary = _valid_general()
	var tiers: Dictionary = general["tiers"]
	tiers["B"] = _valid_tier()  # D 다음에 C 없이 B
	var db: GameDatabase = _build([_valid_skill()], [general])
	assert_true(_has_error(db, "티어는 연속이어야 한다"))


func test_invalid_tier_name_is_reported() -> void:
	var general: Dictionary = _valid_general()
	var tiers: Dictionary = general["tiers"]
	tiers["SS"] = _valid_tier()
	var db: GameDatabase = _build([_valid_skill()], [general])
	assert_true(_has_error(db, "없는 티어다"))


func test_duplicate_ids_are_reported() -> void:
	var db: GameDatabase = _build([_valid_skill(), _valid_skill()], [_valid_general(), _valid_general()])
	assert_true(_has_error(db, "스킬 id 'test_skill'가 중복"))
	assert_true(_has_error(db, "장수 id 'test_general'가 중복"))


func test_heal_skill_effect_is_rejected() -> void:
	var skill: Dictionary = _valid_skill()
	skill["effects"] = [{"kind": "heal", "stat": "hp", "percent": 20, "duration": 1}]
	var db: GameDatabase = _build([skill], [_valid_general()])
	assert_true(_has_error(db, "'kind' 값 'heal'는 허용되지 않는다"), "전투 중 회복 스킬은 만들 수 없다")


func test_missing_stat_is_reported() -> void:
	var general: Dictionary = _valid_general()
	var base_stats: Dictionary = general["tiers"]["D"]["base_stats"]
	base_stats.erase("speed")
	var db: GameDatabase = _build([_valid_skill()], [general])
	assert_true(_has_error(db, "'speed' 숫자가 없다"))


func test_conditional_reserve_effect_needs_condition() -> void:
	var general: Dictionary = _valid_general()
	var reserve: Dictionary = general["tiers"]["D"]["reserve_effect"]
	reserve["mode"] = "conditional"
	var db: GameDatabase = _build([_valid_skill()], [general])
	assert_true(_has_error(db, "조건부 효과에 'condition'이 없다"))


func test_missing_balance_key_is_reported() -> void:
	var db: GameDatabase = GameDatabase.from_dicts({}, {"skills": []}, {"generals": []})
	assert_true(_has_error(db, "balance: 'inheritance.ratio' 값이 없다"))


func test_valid_minimal_data_passes() -> void:
	var db: GameDatabase = _build([_valid_skill()], [_valid_general()])
	assert_eq(db.errors, [] as Array[String], "도우미가 만든 최소 데이터는 오류가 없어야 한다")


# ---------- 테스트용 도우미 ----------

func _has_error(db: GameDatabase, fragment: String) -> bool:
	for message: String in db.errors:
		if message.contains(fragment):
			return true
	return false


## 실제 balance.json과 주어진 스킬·장수로 데이터베이스를 만든다.
func _build(skill_list: Array, general_list: Array) -> GameDatabase:
	var balance_text: String = FileAccess.get_file_as_string("res://data/balance.json")
	var balance_data: Dictionary = JSON.parse_string(balance_text)
	return GameDatabase.from_dicts(balance_data, {"skills": skill_list}, {"generals": general_list})


func _valid_skill() -> Dictionary:
	return {
		"id": "test_skill", "name": "시험 베기", "description": "시험용", "target": "enemy_single",
		"scaling_stat": "attack", "power": 1.0, "cooldown": 2, "effects": [],
	}


func _valid_tier() -> Dictionary:
	return {
		"title": "시험 칭호", "era": "시험 시기",
		"base_stats": {"hp": 20, "attack": 10, "defense": 10, "speed": 10, "intellect": 10},
		"tendency": {"hp": 0.6, "attack": 0.5, "defense": 0.5, "speed": 0.2, "intellect": 0.2},
		"skill_ids": ["test_skill"],
		"reserve_effect": {
			"name": "시험 효과", "description": "시험용", "mode": "passive",
			"effect": {"kind": "stat_percent", "stat": "hp", "value": 5},
		},
	}


func _valid_general() -> Dictionary:
	return {
		"id": "test_general", "name": "시험 장수", "faction": "none", "role": "warrior",
		"tiers": {"D": _valid_tier()},
	}
