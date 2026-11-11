class_name DataReader
extends RefCounted
## JSON에서 읽은 Dictionary에서 값을 꺼내며 형식을 검사하는 도우미.
## 문제가 있으면 멈추지 않고 errors 배열에 한국어 메시지를 쌓는다.
## (Array는 참조로 전달되므로 함수 안에서 추가한 내용이 호출한 쪽에도 보인다.)


static func is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func read_string(data: Dictionary, key: String, context: String, errors: Array[String]) -> String:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING or String(data[key]).is_empty():
		errors.append("%s: '%s' 문자열이 없거나 비어 있다" % [context, key])
		return ""
	return String(data[key])


static func read_float(data: Dictionary, key: String, context: String, errors: Array[String]) -> float:
	if not data.has(key) or not is_number(data[key]):
		errors.append("%s: '%s' 숫자가 없다" % [context, key])
		return 0.0
	return float(data[key])


## 정수를 읽는다. JSON 숫자는 모두 실수로 들어오므로 소수점이 있으면 오류로 본다.
static func read_int(data: Dictionary, key: String, context: String, errors: Array[String]) -> int:
	var value: float = read_float(data, key, context, errors)
	if value != floorf(value):
		errors.append("%s: '%s'는 정수여야 한다 (현재 %s)" % [context, key, value])
	return int(value)


static func read_bool(data: Dictionary, key: String, context: String, errors: Array[String]) -> bool:
	if not data.has(key) or typeof(data[key]) != TYPE_BOOL:
		errors.append("%s: '%s' 참/거짓 값이 없다" % [context, key])
		return false
	return bool(data[key])


static func read_dict(data: Dictionary, key: String, context: String, errors: Array[String]) -> Dictionary:
	if not data.has(key) or typeof(data[key]) != TYPE_DICTIONARY:
		errors.append("%s: '%s' 객체가 없다" % [context, key])
		return {}
	var result: Dictionary = data[key]
	return result


static func read_array(data: Dictionary, key: String, context: String, errors: Array[String]) -> Array:
	if not data.has(key) or typeof(data[key]) != TYPE_ARRAY:
		errors.append("%s: '%s' 배열이 없다" % [context, key])
		return []
	var result: Array = data[key]
	return result


## 값이 허용 목록 안에 있는지 검사한다.
static func check_one_of(value: String, allowed: Array[String], key: String, context: String, errors: Array[String]) -> void:
	if not value.is_empty() and not allowed.has(value):
		errors.append("%s: '%s' 값 '%s'는 허용되지 않는다 (가능: %s)" % [context, key, value, ", ".join(allowed)])
