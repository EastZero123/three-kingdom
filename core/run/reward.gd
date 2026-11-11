class_name Reward
extends RefCounted
## 승리 보상 선택지 하나.

const KIND_EXP: String = "exp"
const KIND_GENERAL_CARD: String = "general_card"
const KIND_CHEST: String = "chest"

var kind: String = ""
## 경험치 보상일 때의 양.
var exp_amount: int = 0
## 장수 카드일 때의 장수와 티어, 그리고 카드가 나온 적의 레벨.
var general_id: String = ""
var tier: String = ""
var enemy_level: int = 1
## 보물상자일 때의 상자 id.
var chest_id: String = ""


static func make_exp(amount: int) -> Reward:
	var reward: Reward = Reward.new()
	reward.kind = KIND_EXP
	reward.exp_amount = amount
	return reward


static func make_card(p_general_id: String, p_tier: String, p_enemy_level: int = 1) -> Reward:
	var reward: Reward = Reward.new()
	reward.kind = KIND_GENERAL_CARD
	reward.general_id = p_general_id
	reward.tier = p_tier
	reward.enemy_level = p_enemy_level
	return reward


## 이 카드로 새로 영입하면 들어오는 레벨: 적 레벨 × reward.card_level_ratio (내림, 최소 1, 최대 만렙).
func recruit_level(db: GameDatabase) -> int:
	var level: int = floori(float(enemy_level) * db.balance.get_float("reward.card_level_ratio"))
	return clampi(level, 1, db.balance.get_int("level.max_level"))


static func make_chest(p_chest_id: String) -> Reward:
	var reward: Reward = Reward.new()
	reward.kind = KIND_CHEST
	reward.chest_id = p_chest_id
	return reward


func is_exp() -> bool:
	return kind == KIND_EXP


func is_card() -> bool:
	return kind == KIND_GENERAL_CARD


func is_chest() -> bool:
	return kind == KIND_CHEST


## 선택 화면에 보일 한 줄. 로스터가 가득 찼을 때 경험치 보상은 "경험치 전수"라고 부른다.
func summary(db: GameDatabase, roster_is_full: bool) -> String:
	if is_exp():
		return "%s %d" % ["경험치 전수" if roster_is_full else "경험치 지급", exp_amount]
	if is_chest():
		var chest: ChestDef = db.get_chest(chest_id)
		return "보물상자: %s (%s %d장)" % [chest.name, chest.scope_label(), chest.card_count]
	return "장수 카드: %s(%s) Lv.%d" % [db.get_general(general_id).name, tier, recruit_level(db)]
