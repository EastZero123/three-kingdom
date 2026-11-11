class_name RosterMember
extends RefCounted
## 로스터에 있는 장수 한 명의 런 진행 상태. 체력은 전투가 끝나도 그대로 유지된다.

var general_id: String = ""
var tier: String = ""
var level: int = 1
var experience: int = 0
var hp: int = 1
var max_hp: int = 1


## 가득 찬 체력으로 새 로스터 장수를 만든다.
static func create(db: GameDatabase, p_general_id: String, p_tier: String, p_level: int) -> RosterMember:
	var member: RosterMember = RosterMember.new()
	member.general_id = p_general_id
	member.tier = p_tier
	member.level = p_level
	member.refresh_max_hp(db)
	member.hp = member.max_hp
	return member


## 티어·레벨이 바뀌었을 때 최대 체력을 다시 계산한다. 현재 체력은 건드리지 않는다.
func refresh_max_hp(db: GameDatabase) -> void:
	var tier_def: GeneralTierDef = db.get_general(general_id).get_tier(tier)
	max_hp = tier_def.stats_at_level(level).hp
	hp = mini(hp, max_hp)


## 주어진 레벨에서 다음 레벨로 오르는 데 필요한 경험치: 레벨 × level.exp_per_level_factor.
static func exp_to_next(db: GameDatabase, p_level: int) -> int:
	return p_level * db.balance.get_int("level.exp_per_level_factor")


## 경험치를 얻는다. 오른 레벨 수를 돌려준다.
## 레벨이 올라 최대 체력이 늘면 현재 체력도 그만큼 늘어난다 (잃은 체력의 양은 그대로라 회복이 아니다).
func add_experience(db: GameDatabase, amount: int) -> int:
	var max_level: int = db.balance.get_int("level.max_level")
	var gained: int = 0
	experience += amount
	while level < max_level and experience >= exp_to_next(db, level):
		experience -= exp_to_next(db, level)
		level += 1
		gained += 1
	if level >= max_level:
		experience = 0
	if gained > 0:
		var old_max_hp: int = max_hp
		refresh_max_hp(db)
		hp += max_hp - old_max_hp
	return gained


## 레벨 1부터 지금까지 쌓은 경험치의 합. 계승 계산에 쓴다.
func total_experience(db: GameDatabase) -> int:
	var total: int = experience
	for past_level: int in range(1, level):
		total += exp_to_next(db, past_level)
	return total


## 체력이 0이 됐는지. 전투에서 쓰러진 장수는 전사해 로스터에서 빠진다.
func is_dead() -> bool:
	return hp <= 0


func display_name(db: GameDatabase) -> String:
	return db.get_general(general_id).name


func to_dict() -> Dictionary:
	return {"general_id": general_id, "tier": tier, "level": level, "experience": experience, "hp": hp, "max_hp": max_hp}
