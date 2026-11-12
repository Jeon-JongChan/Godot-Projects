extends Node

## 세이브/로드 관리자 — 총 3개의 고정 슬롯을 관리하고 직렬화/역직렬화를 수행한다.
## 기획서 4장(Load 팝업) 및 스케치 기반.

const MAX_SAVE_SLOTS: int = 3
const SAVE_PATH_FORMAT: String = "user://save_slot_%d.json"

signal slot_saved(slot_index: int)
signal slot_loaded(slot_index: int)
signal slot_deleted(slot_index: int)

## 테스트 또는 외부 주입용 GameState 오버라이드
var game_state_override: Node = null

## 현재 활성화(플레이/저장/로드) 중인 세이브 슬롯 번호 (1~3)
var current_slot_index: int = 1


## 슬롯 번호(1~3)에 해당하는 세이브 파일 경로를 반환한다.
func get_slot_path(slot_index: int) -> String:
	return SAVE_PATH_FORMAT % slot_index


## 특정 슬롯의 파일이 존재하는지 여부를 확인한다.
func has_slot(slot_index: int) -> bool:
	if slot_index < 1 or slot_index > MAX_SAVE_SLOTS:
		return false
	return FileAccess.file_exists(get_slot_path(slot_index))


## 특정 슬롯의 메타데이터(이름, 날짜, 일차, 골드 등)를 반환한다.
## 슬롯이 비어있으면 is_empty = true인 딕셔너리를 반환한다.
func get_slot_meta(slot_index: int) -> Dictionary:
	if not has_slot(slot_index):
		return {
			"slot_index": slot_index,
			"is_empty": true,
			"name": "빈 슬롯",
			"saved_at": "",
			"day": 0,
			"gold": 0,
			"roster_count": 0,
		}

	var path := get_slot_path(slot_index)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"slot_index": slot_index, "is_empty": true, "name": "빈 슬롯"}

	var json_str := file.get_as_text()
	file.close()

	var parse_res = JSON.parse_string(json_str)
	if not (parse_res is Dictionary):
		return {"slot_index": slot_index, "is_empty": true, "name": "손상된 데이터"}

	var data: Dictionary = parse_res
	return {
		"slot_index": slot_index,
		"is_empty": false,
		"name": str(data.get("name", "이름 없는 영지")),
		"saved_at": str(data.get("saved_at", "")),
		"day": int(data.get("day", 1)),
		"gold": int(data.get("gold", 0)),
		"roster_count": int(data.get("roster_count", 0)),
	}


## 빈 슬롯 중 가장 번호가 작은 슬롯(1~3)을 반환한다. 모두 차있으면 -1을 반환한다.
func get_first_empty_slot() -> int:
	for slot in range(1, MAX_SAVE_SLOTS + 1):
		if not has_slot(slot):
			return slot
	return -1


## GameState 인스턴스를 안전하게 조회한다.
func _get_game_state() -> Node:
	if game_state_override != null:
		return game_state_override
	var main_loop = Engine.get_main_loop()
	if main_loop != null and "root" in main_loop and main_loop.root != null:
		return main_loop.root.get_node_or_null("GameState")
	return null


## 현재 GameState 상태를 지정된 슬롯에 저장한다.
func save_slot(slot_index: int, save_name: String) -> bool:
	if slot_index < 1 or slot_index > MAX_SAVE_SLOTS:
		push_warning("save_slot: slot_index out of range: %d" % slot_index)
		return false

	var gs = _get_game_state()
	if gs == null:
		push_warning("save_slot: GameState is null")
		return false

	var trimmed_name := save_name.strip_edges()
	if trimmed_name.is_empty():
		trimmed_name = "영주 #%d" % slot_index
	if trimmed_name.length() > 20:
		trimmed_name = trimmed_name.substr(0, 20)

	var time_dict := Time.get_datetime_dict_from_system()
	var time_str := "%04d-%02d-%02d %02d:%02d" % [
		time_dict.year, time_dict.month, time_dict.day,
		time_dict.hour, time_dict.minute
	]

	var save_payload := {
		"name": trimmed_name,
		"saved_at": time_str,
		"day": gs.day,
		"gold": gs.gold,
		"roster_count": gs.roster.size(),
		"game_data": gs.to_dict(),
	}

	var json_str := JSON.stringify(save_payload, "\t")
	var file := FileAccess.open(get_slot_path(slot_index), FileAccess.WRITE)
	if file == null:
		push_warning("save_slot: Failed to open file for write: %s" % get_slot_path(slot_index))
		return false

	file.store_string(json_str)
	file.close()

	current_slot_index = slot_index
	slot_saved.emit(slot_index)
	return true


## 지정된 슬롯에서 게임 데이터를 불러와 GameState에 복원한다.
func load_slot(slot_index: int) -> bool:
	if not has_slot(slot_index):
		return false

	var gs = _get_game_state()
	if gs == null:
		return false

	var file := FileAccess.open(get_slot_path(slot_index), FileAccess.READ)
	if file == null:
		return false

	var json_str := file.get_as_text()
	file.close()

	var parse_res = JSON.parse_string(json_str)
	if not (parse_res is Dictionary):
		return false

	var data: Dictionary = parse_res
	var game_data = data.get("game_data", null)
	if not (game_data is Dictionary):
		return false

	gs.from_dict(game_data)
	current_slot_index = slot_index
	slot_loaded.emit(slot_index)
	return true


## 슬롯의 저장 데이터는 그대로 유지하고 이름만 업데이트한다.
func update_slot_name(slot_index: int, new_name: String) -> bool:
	if not has_slot(slot_index):
		return false

	var trimmed_name := new_name.strip_edges()
	if trimmed_name.is_empty():
		return false
	if trimmed_name.length() > 20:
		trimmed_name = trimmed_name.substr(0, 20)

	var file := FileAccess.open(get_slot_path(slot_index), FileAccess.READ)
	if file == null:
		return false
	var json_str := file.get_as_text()
	file.close()

	var parse_res = JSON.parse_string(json_str)
	if not (parse_res is Dictionary):
		return false

	var data: Dictionary = parse_res
	data["name"] = trimmed_name

	var write_file := FileAccess.open(get_slot_path(slot_index), FileAccess.WRITE)
	if write_file == null:
		return false
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

	slot_saved.emit(slot_index)
	return true


## 지정된 슬롯의 세이브 파일을 완전히 삭제한다.
func delete_slot(slot_index: int) -> bool:
	if not has_slot(slot_index):
		return false

	var path := get_slot_path(slot_index)
	var err := DirAccess.remove_absolute(path)
	if err == OK:
		slot_deleted.emit(slot_index)
		return true
	return false


## 현재 활성 슬롯에 대해 자동 저장(Auto Save)을 수행한다.
## 슬롯에 기존 이름이 있다면 유지하고, 없다면 기본 영주 이름을 부여한다.
func auto_save() -> bool:
	var target_slot := clampi(current_slot_index, 1, MAX_SAVE_SLOTS)
	var save_name: String = "영주 #%d" % target_slot
	if has_slot(target_slot):
		var meta := get_slot_meta(target_slot)
		var existing_name: String = str(meta.get("name", "")).strip_edges()
		if not existing_name.is_empty() and existing_name != "빈 슬롯":
			save_name = existing_name
	return save_slot(target_slot, save_name)


## 현재 활성화된 슬롯에 즉시 저장한다 (auto_save의 별칭)
func save_current() -> bool:
	return auto_save()

