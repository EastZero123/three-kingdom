class_name Balance
extends RefCounted
## data/balance.json의 밸런스 수치를 읽는 창구.
## 키는 "roster.active_slots"처럼 점으로 구분한 경로로 쓴다.

## 반드시 있어야 하는 키와 자료형. 기획서의 확정값과 미확정 항목의 기본값이 여기에 해당한다.
const REQUIRED: Dictionary[String, int] = {
	"roster.active_slots": TYPE_INT,
	"roster.reserve_slots_base": TYPE_INT,
	"roster.reserve_slots_max": TYPE_INT,
	"roster.release_last_reserve_on_shrink": TYPE_BOOL,
	"roster.reserve_rest_heal_ratio": TYPE_FLOAT,
	"level.max_level": TYPE_INT,
	"merge.cards_per_promotion": TYPE_INT,
	"inheritance.ratio": TYPE_FLOAT,
	"run.start_year": TYPE_INT,
	"run.rounds_per_year": TYPE_INT,
	"run.expedition_choices": TYPE_INT,
	"run.special_expedition_chance": TYPE_FLOAT,
	"run.defeat_ends_run": TYPE_BOOL,
	"reward.choices": TYPE_INT,
	"reward.exp_choices": TYPE_INT,
	"reward.exp_per_enemy_level": TYPE_FLOAT,
	"reward.card_level_ratio": TYPE_FLOAT,
	"level.exp_per_level_factor": TYPE_INT,
	"level.points_per_level": TYPE_INT,
	"ability.max": TYPE_INT,
	"ability.hp_per_point": TYPE_INT,
	"ability.overflow_hp_per_point": TYPE_INT,
	"ability.enemy_points_per_level": TYPE_FLOAT,
	"ability.enemy_points_per_year": TYPE_FLOAT,
	"healer.stacking": TYPE_BOOL,
	"healer.heal_ratio": TYPE_FLOAT,
	"reserve_effect.late_game_allies_alive_at_most": TYPE_INT,
	"battle.front_row_size": TYPE_INT,
	"battle.back_row_size": TYPE_INT,
	"battle.enemy_count_min": TYPE_INT,
	"battle.enemy_count_max": TYPE_INT,
	"battle.basic_attack_power": TYPE_FLOAT,
	"battle.defense_constant": TYPE_FLOAT,
	"battle.damage_variance": TYPE_FLOAT,
	"battle.min_damage": TYPE_INT,
	"battle.round_limit": TYPE_INT,
}

var _values: Dictionary = {}


func _init(values: Dictionary = {}) -> void:
	_values = values


## 필수 키가 모두 올바른 자료형으로 들어 있는지 검사해 오류 목록을 돌려준다.
func validate() -> Array[String]:
	var errors: Array[String] = []
	for key: String in REQUIRED:
		var value: Variant = _find(key)
		if value == null:
			errors.append("balance: '%s' 값이 없다" % key)
			continue
		match REQUIRED[key]:
			TYPE_BOOL:
				if typeof(value) != TYPE_BOOL:
					errors.append("balance: '%s'는 참/거짓이어야 한다" % key)
			TYPE_INT:
				if not DataReader.is_number(value) or float(value) != floorf(float(value)):
					errors.append("balance: '%s'는 정수여야 한다" % key)
			TYPE_FLOAT:
				if not DataReader.is_number(value):
					errors.append("balance: '%s'는 숫자여야 한다" % key)
	return errors


func has_key(key: String) -> bool:
	return _find(key) != null


func get_int(key: String) -> int:
	var value: Variant = _find(key)
	if not DataReader.is_number(value):
		push_error("balance: 정수 '%s'를 찾을 수 없다" % key)
		return 0
	return int(value)


func get_float(key: String) -> float:
	var value: Variant = _find(key)
	if not DataReader.is_number(value):
		push_error("balance: 숫자 '%s'를 찾을 수 없다" % key)
		return 0.0
	return float(value)


func get_bool(key: String) -> bool:
	var value: Variant = _find(key)
	if typeof(value) != TYPE_BOOL:
		push_error("balance: 참/거짓 '%s'를 찾을 수 없다" % key)
		return false
	return bool(value)


## 점으로 구분한 경로를 따라 내려가 값을 찾는다. 없으면 null.
func _find(key: String) -> Variant:
	var current: Variant = _values
	for part: String in key.split("."):
		if typeof(current) != TYPE_DICTIONARY:
			return null
		var dict: Dictionary = current
		if not dict.has(part):
			return null
		current = dict[part]
	return current
