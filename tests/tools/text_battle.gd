extends SceneTree
## 텍스트 전투 실행 도구: 1대1과 6대6 전투를 돌려 로그를 출력한다.
## 실행: godot --headless --path . -s tests/tools/text_battle.gd -- <시드>
## 시드를 생략하면 12345를 쓴다. 같은 시드면 항상 같은 로그가 나온다.

const DEFAULT_SEED: int = 12345


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if not args.is_empty() else DEFAULT_SEED

	var db: GameDatabase = GameDatabase.load_from_dir("res://data")
	if not db.is_valid():
		for message: String in db.errors:
			printerr(message)
		quit(1)
		return

	print("========== 1대1: 관우(B) 대 여포(B) ==========")
	_run(db, [["guan_yu", "B", 10]], [["lu_bu", "B", 10]], seed_value)

	print("")
	print("========== 6대6 ==========")
	# 앞의 3명이 전열, 뒤의 3명이 후열.
	var allies: Array = [
		["guan_yu", "C", 5], ["zhang_fei", "C", 5], ["sun_quan", "C", 5],
		["liu_bei", "C", 5], ["hua_tuo", "C", 5], ["diao_chan", "C", 5],
	]
	var enemies: Array = [
		["dong_zhuo", "B", 3], ["lu_bu", "B", 3], ["zhou_cang", "D", 8],
		["zhang_jue", "C", 5], ["cao_cao", "B", 3], ["zhuge_liang", "B", 3],
	]
	_run(db, allies, enemies, seed_value)
	quit(0)


func _run(db: GameDatabase, ally_specs: Array, enemy_specs: Array, seed_value: int) -> void:
	var engine: BattleEngine = BattleEngine.new(db.balance, _make_units(db, ally_specs), _make_units(db, enemy_specs), seed_value)
	engine.run()
	for line: String in engine.log_lines:
		print(line)
	print("생존자:")
	for unit: BattleUnit in engine.units:
		if unit.is_alive():
			print("  %s (%s Lv.%d) 체력 %d/%d" % [unit.label(), unit.tier, unit.level, unit.hp, unit.max_hp])


## [장수 id, 티어, 레벨] 목록으로 전투 유닛을 만든다.
func _make_units(db: GameDatabase, specs: Array) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for spec: Array in specs:
		result.append(BattleUnit.create(db, String(spec[0]), String(spec[1]), int(spec[2])))
	return result
