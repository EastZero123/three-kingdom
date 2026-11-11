class_name Roster
extends RefCounted
## 로스터: 출전 슬롯과 보유효과 슬롯을 합친 전체.
## 슬롯은 번호 하나로 다룬다. 0부터 active_count - 1까지가 출전 슬롯, 그 뒤가 보유효과 슬롯이다.
## 빈 칸은 null. 영입·교체 판단은 항상 이 전체를 기준으로 한다.

## 출전 슬롯 수 (고정 6).
var active_count: int = 0
## 모든 슬롯. 출전 슬롯 다음에 보유효과 슬롯이 이어진다.
var slots: Array[RosterMember] = []


func _init(p_active_count: int = 0, reserve_count: int = 0) -> void:
	active_count = p_active_count
	slots.resize(p_active_count + reserve_count)


func size() -> int:
	return slots.size()


func reserve_count() -> int:
	return slots.size() - active_count


func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < slots.size()


func is_active_slot(slot: int) -> bool:
	return slot >= 0 and slot < active_count


func get_member(slot: int) -> RosterMember:
	return slots[slot] if is_valid_slot(slot) else null


func set_member(slot: int, member: RosterMember) -> void:
	slots[slot] = member


## 로스터에 있는 모든 장수 (빈 칸 제외).
func members() -> Array[RosterMember]:
	var result: Array[RosterMember] = []
	for member: RosterMember in slots:
		if member != null:
			result.append(member)
	return result


func member_count() -> int:
	return members().size()


## 출전 슬롯에 있는 장수 수.
func active_member_count() -> int:
	var count: int = 0
	for slot: int in active_count:
		if slots[slot] != null:
			count += 1
	return count


## 장수가 있는 슬롯 번호. 로스터에 없으면 -1. (같은 장수는 티어가 달라도 한 명만 둘 수 있다.)
func find_general(general_id: String) -> int:
	for slot: int in slots.size():
		if slots[slot] != null and slots[slot].general_id == general_id:
			return slot
	return -1


func has_general(general_id: String) -> bool:
	return find_general(general_id) >= 0


## 가장 앞의 빈 칸. 출전 슬롯을 먼저 보고 그다음 보유효과 슬롯을 본다. 없으면 -1.
func first_empty_slot() -> int:
	for slot: int in slots.size():
		if slots[slot] == null:
			return slot
	return -1


func is_full() -> bool:
	return first_empty_slot() < 0


## 보유효과 슬롯 수를 바꾼다. 줄어들면 마지막 칸부터 없어지고, 그 칸의 장수를 돌려준다 (방출 대상).
func set_reserve_count(count: int) -> Array[RosterMember]:
	var released: Array[RosterMember] = []
	var new_size: int = active_count + count
	for slot: int in range(new_size, slots.size()):
		if slots[slot] != null:
			released.append(slots[slot])
	slots.resize(new_size)
	return released


## 두 슬롯의 내용을 맞바꾼다. 한쪽이 빈 칸이면 이동이 된다.
func swap(slot_a: int, slot_b: int) -> void:
	var temp: RosterMember = slots[slot_a]
	slots[slot_a] = slots[slot_b]
	slots[slot_b] = temp


func slot_label(slot: int) -> String:
	if is_active_slot(slot):
		return "출전 %d번" % (slot + 1)
	return "보유효과 %d번" % (slot - active_count + 1)
