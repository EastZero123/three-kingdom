class_name Stats
extends RefCounted
## 장수의 기본 스탯 5종: 체력, 공격, 방어, 속도, 지략.
## RefCounted: 노드(화면 요소)가 아닌 순수 데이터 객체의 기본 부모.
## 아무도 참조하지 않으면 자동으로 메모리에서 사라진다.

## JSON과 코드에서 쓰는 스탯 이름 목록.
const KEYS: Array[String] = ["hp", "attack", "defense", "speed", "intellect"]

var hp: int = 0
var attack: int = 0
var defense: int = 0
var speed: int = 0
var intellect: int = 0


static func is_valid_key(key: String) -> bool:
	return KEYS.has(key)


## 이름으로 스탯 값을 읽는다. 예: get_value("attack")
func get_value(key: String) -> int:
	match key:
		"hp":
			return hp
		"attack":
			return attack
		"defense":
			return defense
		"speed":
			return speed
		"intellect":
			return intellect
	push_error("알 수 없는 스탯 이름: %s" % key)
	return 0


func set_value(key: String, value: int) -> void:
	match key:
		"hp":
			hp = value
		"attack":
			attack = value
		"defense":
			defense = value
		"speed":
			speed = value
		"intellect":
			intellect = value
		_:
			push_error("알 수 없는 스탯 이름: %s" % key)


func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for key: String in KEYS:
		result[key] = get_value(key)
	return result
