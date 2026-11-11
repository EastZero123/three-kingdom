class_name Expedition
extends RefCounted
## 토벌 선택지 하나: 어떤 적 원정대와 싸우는지, 난이도와 보상이 어떤지.

var type: ExpeditionTypeDef = null
## 이 토벌의 편성 (인원·레벨·전력·티어·경험치 배율을 정한다).
var formation: FormationDef = null
## 화면에 보일 이름. 보통은 토벌 종류 이름이고, 현상금 토벌이면 앞에 세력이 붙는다. 예: "위 현상금 토벌"
var title: String = ""
var era: EraDef = null
## 적 장수들의 레벨.
var enemy_level: int = 1
## 적 원정대. 순서가 곧 자리(앞의 3명이 전열). 각 항목: {general_id: String, tier: String, level: int}
var enemies: Array[Dictionary] = []
## 이 토벌에서 벌어질 전투의 시드.
var battle_seed: int = 0


func enemy_count() -> int:
	return enemies.size()


## 선택 화면에 보일 한 줄 요약. 예: "[보통] 적 6명 (Lv.3) · 경험치 ×1.3 — 주창(F), 장각(E), …"
func summary(db: GameDatabase) -> String:
	var names: Array[String] = []
	for enemy: Dictionary in enemies:
		names.append("%s(%s)" % [db.get_general(String(enemy["general_id"])).name, enemy["tier"]])
	var chest_text: String = " · 보물상자" if not type.chest_pool.is_empty() else ""
	return "[%s] 적 %d명 (Lv.%d, 전력 %d%%) · 경험치 ×%.1f%s — %s" % [
		title, enemy_count(), enemy_level, roundi(formation.enemy_stat_multiplier * 100.0), formation.reward_exp_multiplier, chest_text, ", ".join(names),
	]
