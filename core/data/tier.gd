class_name Tier
extends RefCounted
## 티어(F~S) 순서를 다루는 도우미.
## static 함수만 있어서 Tier.next_of("F")처럼 객체를 만들지 않고 바로 부른다.

## 낮은 티어부터 높은 티어 순서. 티어 7단계는 게임의 정체성이라 코드에 고정한다.
const ORDER: Array[String] = ["F", "E", "D", "C", "B", "A", "S"]


static func is_valid(tier: String) -> bool:
	return ORDER.has(tier)


## 티어의 순번(F=0 … S=6). 없는 티어면 -1.
static func index_of(tier: String) -> int:
	return ORDER.find(tier)


## 한 단계 위 티어. 최상위(S)이거나 없는 티어면 빈 문자열.
static func next_of(tier: String) -> String:
	var index: int = index_of(tier)
	if index < 0 or index >= ORDER.size() - 1:
		return ""
	return ORDER[index + 1]


## a가 b보다 높은 티어인지.
static func is_higher(a: String, b: String) -> bool:
	return index_of(a) > index_of(b)
