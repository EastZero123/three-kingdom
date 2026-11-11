class_name ExpeditionTypeDef
extends RefCounted
## 토벌 종류 정의 (data/enemies.json의 expedition_types 항목). 난이도와 적 규모, 특별 보상을 정한다.

## normal = 일반 토벌, imperial_requisition = 한나라 왕실 조달 명령, bounty = 각국의 현상금 토벌.
const KINDS: Array[String] = ["normal", "imperial_requisition", "bounty"]

var id: String = ""
## 화면에 보이는 이름. 예: "쉬움", "왕실 조달 명령"
var name: String = ""
var kind: String = ""
var enemy_count_min: int = 0
var enemy_count_max: int = 0
## 기준 적 레벨에 더하는 값.
var level_offset: int = 0
## 적 장수 스탯에 곱하는 배율. 레벨이 같아도 난이도 차이가 나게 한다.
var enemy_stat_multiplier: float = 1.0
## 적을 뽑을 때 티어가 한 단계 높을수록 가중치에 곱하는 값. 1보다 크면 높은 티어 적(=좋은 카드)이 자주 나온다.
var tier_weight_per_step: float = 1.0
## 승리 시 경험치 보상 배율.
var reward_exp_multiplier: float = 1.0
## 선택지로 뽑힐 가중치.
var weight: float = 1.0
## 이 연도부터 등장한다 (특별 토벌용). 0이면 처음부터.
var from_year: int = 0
## 승리 보상에 들어갈 보물상자 후보. 각 항목: {chest_id: String, weight: float}. 비어 있으면 상자 없음.
var chest_pool: Array[Dictionary] = []
## 현상금을 건 세력 후보 (이름 앞에 붙는다). 예: ["위", "촉", "오"]
var issuers: Array[String] = []
## 이 난이도 안의 편성 후보. 정의가 없으면 토벌 종류 값으로 만든 기본 편성 하나.
var formations: Array[FormationDef] = []


func is_special() -> bool:
	return kind != "normal"


static func parse(data: Dictionary, context: String, errors: Array[String]) -> ExpeditionTypeDef:
	var def: ExpeditionTypeDef = ExpeditionTypeDef.new()
	def.id = DataReader.read_string(data, "id", context, errors)
	var ctx: String = "%s(%s)" % [context, def.id]
	def.name = DataReader.read_string(data, "name", ctx, errors)
	def.kind = DataReader.read_string(data, "kind", ctx, errors)
	DataReader.check_one_of(def.kind, KINDS, "kind", ctx, errors)
	def.enemy_count_min = DataReader.read_int(data, "enemy_count_min", ctx, errors)
	def.enemy_count_max = DataReader.read_int(data, "enemy_count_max", ctx, errors)
	if def.enemy_count_min < 1 or def.enemy_count_max < def.enemy_count_min:
		errors.append("%s: 적 인원 범위가 잘못됐다" % ctx)
	def.level_offset = DataReader.read_int(data, "level_offset", ctx, errors)
	def.enemy_stat_multiplier = DataReader.read_float(data, "enemy_stat_multiplier", ctx, errors)
	if def.enemy_stat_multiplier <= 0.0:
		errors.append("%s: 'enemy_stat_multiplier'는 0보다 커야 한다" % ctx)
	def.reward_exp_multiplier = DataReader.read_float(data, "reward_exp_multiplier", ctx, errors)
	def.weight = DataReader.read_float(data, "weight", ctx, errors)
	if def.weight <= 0.0:
		errors.append("%s: 'weight'는 0보다 커야 한다" % ctx)

	# 아래는 선택 항목이다.
	if data.has("tier_weight_per_step"):
		def.tier_weight_per_step = DataReader.read_float(data, "tier_weight_per_step", ctx, errors)
		if def.tier_weight_per_step <= 0.0:
			errors.append("%s: 'tier_weight_per_step'는 0보다 커야 한다" % ctx)
	if data.has("from_year"):
		def.from_year = DataReader.read_int(data, "from_year", ctx, errors)
	if data.has("chest_pool"):
		var raw_pool: Array = DataReader.read_array(data, "chest_pool", ctx, errors)
		for i: int in raw_pool.size():
			var entry_ctx: String = "%s.chest_pool[%d]" % [ctx, i]
			if typeof(raw_pool[i]) != TYPE_DICTIONARY:
				errors.append("%s: 객체가 아니다" % entry_ctx)
				continue
			var raw_entry: Dictionary = raw_pool[i]
			def.chest_pool.append({
				"chest_id": DataReader.read_string(raw_entry, "chest_id", entry_ctx, errors),
				"weight": DataReader.read_float(raw_entry, "weight", entry_ctx, errors),
			})
	if data.has("issuers"):
		for raw_issuer: Variant in DataReader.read_array(data, "issuers", ctx, errors):
			def.issuers.append(String(raw_issuer))
	if def.is_special() and def.chest_pool.is_empty():
		errors.append("%s: 특별 토벌에는 'chest_pool'이 있어야 한다" % ctx)

	if data.has("formations"):
		var raw_formations: Array = DataReader.read_array(data, "formations", ctx, errors)
		for i: int in raw_formations.size():
			var formation_ctx: String = "%s.formations[%d]" % [ctx, i]
			if typeof(raw_formations[i]) != TYPE_DICTIONARY:
				errors.append("%s: 객체가 아니다" % formation_ctx)
				continue
			var formation_data: Dictionary = raw_formations[i]
			def.formations.append(FormationDef.parse(formation_data, def, formation_ctx, errors))
	if def.formations.is_empty():
		def.formations.append(FormationDef.from_type(def))
	return def
