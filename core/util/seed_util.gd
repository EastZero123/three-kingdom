class_name SeedUtil
extends RefCounted
## 런 시드에서 "몇 년 몇 라운드 몇 번째 선택지" 같은 하위 시드를 만들어 내는 도우미.
## 하위 시드가 지난 진행 과정에 영향받지 않으므로, 같은 시드와 같은 선택이면 항상 같은 결과가 나온다.
## 엔진의 내장 hash()에 기대지 않고 직접 계산해서 Windows와 Linux 서버에서 같은 값이 나오게 한다.

const MASK_31: int = 0x7FFFFFFF


## 시드와 숫자 세 개를 섞어 새 시드(0 이상 31비트 정수)를 만든다.
static func derive(seed_value: int, a: int, b: int, c: int) -> int:
	var h: int = seed_value & MASK_31
	h = _mix(h, (seed_value >> 31) & MASK_31)
	h = _mix(h, a)
	h = _mix(h, b)
	h = _mix(h, c)
	return h


static func _mix(h: int, value: int) -> int:
	# 31비트로 자른 뒤 곱하므로 64비트 정수 범위를 넘지 않는다.
	var mixed: int = (h & MASK_31) * 1103515245 + (value & MASK_31) * 40503 + 12345
	mixed = mixed ^ (mixed >> 29)
	mixed = (mixed & MASK_31) * 69069 + 1
	mixed = mixed ^ (mixed >> 15)
	return mixed & MASK_31


## 가중치 배열에서 하나를 뽑아 그 순번을 돌려준다. 가중치가 클수록 잘 뽑힌다.
static func pick_weighted(rng: RandomNumberGenerator, weights: Array[float]) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	var roll: float = rng.randf() * total
	for i: int in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return weights.size() - 1
