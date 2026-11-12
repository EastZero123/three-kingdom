class_name RosterMember
extends RefCounted
## 로스터에 있는 장수 한 명의 런 진행 상태. 체력은 전투가 끝나도 그대로 유지된다.

var general_id: String = ""
var tier: String = ""
var level: int = 1
var experience: int = 0
var hp: int = 1
var max_hp: int = 1
## 플레이어가 레벨업 포인트를 능력치별로 넣은 양. 키는 Stats.KEYS.
var invested: Dictionary = {"hp": 0, "attack": 0, "defense": 0, "speed": 0, "intellect": 0}
## 다섯 능력치가 모두 최대라 체력으로 넘어간 포인트 (AbilityBuild 참고).
var overflow_points: int = 0


## 가득 찬 체력으로 새 로스터 장수를 만든다.
static func create(db: GameDatabase, p_general_id: String, p_tier: String, p_level: int) -> RosterMember:
	var member: RosterMember = RosterMember.new()
	member.general_id = p_general_id
	member.tier = p_tier
	member.level = p_level
	member.refresh_max_hp(db)
	member.hp = member.max_hp
	return member


## 티어·배분이 바뀌었을 때 최대 체력을 다시 계산한다. 현재 체력은 최대 체력을 넘지 않게만 맞춘다.
func refresh_max_hp(db: GameDatabase) -> void:
	max_hp = combat_stats(db).hp
	hp = mini(hp, max_hp)


func tier_def(db: GameDatabase) -> GeneralTierDef:
	return db.get_general(general_id).get_tier(tier)


## 지금 능력치 (티어 기본 능력치 + 배분한 포인트, 0~100).
func abilities(db: GameDatabase) -> Stats:
	return AbilityBuild.abilities(tier_def(db).base_stats, invested)


## 전투에 쓰는 수치.
func combat_stats(db: GameDatabase) -> Stats:
	return AbilityBuild.combat_stats(db.balance, abilities(db), overflow_points)


## 배분한 포인트 합 (넘친 포인트 포함).
func spent_points() -> int:
	var total: int = overflow_points
	for key: String in Stats.KEYS:
		total += int(invested.get(key, 0))
	return total


## 아직 배분하지 않은 포인트.
func unspent_points(db: GameDatabase) -> int:
	return AbilityBuild.earned_points(db.balance, level) - spent_points()


## 포인트를 한 능력치에 넣는다. 못 넣으면(포인트 부족, 그 능력치가 최대) false이고 아무것도 바뀌지 않는다.
## 최대 체력이 늘면 현재 체력도 그만큼 늘어난다 (레벨업과 같은 규칙: 잃은 체력의 양은 그대로).
func invest(db: GameDatabase, stat: String, amount: int) -> bool:
	if amount <= 0 or amount > unspent_points(db):
		return false
	var plan: Dictionary = AbilityBuild.plan_invest(db.balance, tier_def(db).base_stats, invested, stat, amount)
	if not plan["ok"]:
		return false
	invested[stat] = int(invested.get(stat, 0)) + int(plan["to_stat"])
	overflow_points += int(plan["to_overflow"])
	var old_max_hp: int = max_hp
	refresh_max_hp(db)
	hp += max_hp - old_max_hp
	return true


## 티어가 바뀐 뒤 배분을 새 기본 능력치에 맞춘다 (배분 총량은 100% 유지). AbilityBuild.refit 참고.
func refit_build(db: GameDatabase) -> void:
	var fitted: Dictionary = AbilityBuild.refit(db.balance, tier_def(db).base_stats, invested, overflow_points)
	invested = fitted["invested"]
	overflow_points = int(fitted["overflow"])


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
	return {
		"general_id": general_id, "tier": tier, "level": level, "experience": experience, "hp": hp, "max_hp": max_hp,
		"invested": invested.duplicate(), "overflow_points": overflow_points,
	}
