class_name RunSave
extends RefCounted
## 진행 중인 런의 저장 형식.
## 런은 "시드 + 행동 기록"만 있으면 처음부터 똑같이 다시 진행할 수 있으므로(시드 재현), 저장 파일에는 이것만 남긴다.
## 불러올 때는 ExpeditionRun.replay()로 처음부터 다시 진행해 복원한다.
## 장점: 저장 형식이 작고 단순하며, 2차의 서버 검증(같은 기록으로 다시 실행)과 같은 방식이다.

## 저장 형식 버전. 형식이 바뀌면 올리고, 다른 버전의 저장은 불러오지 않는다.
const VERSION: int = 1


static func to_dict(run: ExpeditionRun) -> Dictionary:
	return {
		"version": VERSION,
		"seed": run.run_seed,
		"history": run.history.duplicate(true),
		# 아래 값은 복원에는 쓰지 않는다. 시작 화면 표시와 복원 결과 확인용.
		"year": run.year,
		"round": run.round_number,
		"phase": run.phase,
	}


## 저장 내용으로 런을 복원한다. 버전이 다르거나, 데이터가 바뀌어 기록을 끝까지 재현하지 못하면 null.
static func restore(db: GameDatabase, data: Dictionary) -> ExpeditionRun:
	if int(data.get("version", 0)) != VERSION or not data.has("seed") or not data.has("history"):
		return null
	var history: Array[Dictionary] = []
	for item: Variant in data["history"]:
		if typeof(item) != TYPE_DICTIONARY:
			return null
		history.append(item as Dictionary)
	var run: ExpeditionRun = ExpeditionRun.replay(db, int(data["seed"]), history)
	if run.history.size() != history.size():
		return null
	if data.has("year") and (int(data["year"]) != run.year or int(data["round"]) != run.round_number):
		return null
	return run
