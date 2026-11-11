class_name RunRecords
extends RefCounted
## 로컬 기록: 끝난 런마다 한 줄. 생존 연수가 기록의 기준이다.
## 행동 기록(actions)도 함께 남겨, 2차의 온라인 랭킹에서 시드와 함께 제출해 검증할 수 있게 한다.


## 끝난 런으로 기록 한 줄을 만든다. ended_at은 사람이 읽는 시각 문자열.
static func make(run: ExpeditionRun, ended_at: String) -> Dictionary:
	return {
		"seed": run.run_seed,
		"years": run.years_survived(),
		"year": run.year,
		"round": run.round_number,
		"ended_at": ended_at,
		"roster": run.last_battle_roster.duplicate(true),
		"fallen": run.fallen.size(),
		"actions": run.history.duplicate(true),
	}


## 기록을 넣고 순위대로 정렬한다: 생존 연수가 길수록, 같으면 더 먼 라운드까지 간 쪽이, 그래도 같으면 먼저 세운 기록이 위.
## 최대 limit개만 남긴다. 새 기록의 순위(1부터)를 돌려준다. 남지 못했으면 0.
static func insert(records: Array[Dictionary], record: Dictionary, limit: int) -> int:
	records.append(record)
	# sort_custom은 순서가 같은 항목의 순서를 보장하지 않으므로, 넣은 순서를 따로 매겨 비교한다.
	for i: int in records.size():
		records[i]["_order"] = i
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["years"]) != int(b["years"]):
			return int(a["years"]) > int(b["years"])
		var progress_a: int = int(a["year"]) * 100 + int(a["round"])
		var progress_b: int = int(b["year"]) * 100 + int(b["round"])
		if progress_a != progress_b:
			return progress_a > progress_b
		return int(a["_order"]) < int(b["_order"])
	)
	var rank: int = 0
	for i: int in records.size():
		if is_same(records[i], record):  # 내용이 아니라 같은 객체인지 비교
			rank = i + 1
		records[i].erase("_order")
	while records.size() > limit:
		records.pop_back()
	return rank if rank <= limit else 0
