extends Node

## [책임 연쇄] 전역 ESC(ui_cancel) 입력을 우선순위 핸들러 체인으로 처리한다.
## 1) 열려 있는 시스템 모달(Pause/Settings/SaveLoad) 확인 → 2) 현재 씬의 자체 취소(예: 영지 건물 팝업 닫기) →
## 3) 타이틀 화면 예외 처리 → 4) 인게임 일시정지 팝업 오픈 순으로 책임을 넘긴다.

const PAUSE_POPUP_SCENE = preload("res://scenes/popups/pause_popup.tscn")

var _chain: Array[Callable] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_chain = [
		_handle_existing_modal,
		_handle_scene_cancel,
		_handle_title_scene,
		_handle_open_pause_popup,
	]


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	for step in _chain:
		if step.call(tree.current_scene):
			return


## 1단계: 이미 일시정지/환경설정/저장불러오기 모달이 열려 있으면 해당 모달이 처리하도록 소비한다.
func _handle_existing_modal(scene: Node) -> bool:
	for child in scene.get_children():
		if child.name.contains("Pause") or child.name.contains("Settings") or child.name.contains("SaveLoad"):
			return true
	return false


## 2단계: 현재 씬이 자체 취소 핸들러(try_handle_cancel)를 제공하면 위임한다.
func _handle_scene_cancel(scene: Node) -> bool:
	if scene.has_method("try_handle_cancel") and scene.call("try_handle_cancel"):
		get_viewport().set_input_as_handled()
		return true
	return false


## 3단계: 메인 타이틀 화면에서는 일시정지 팝업을 띄우지 않는다.
func _handle_title_scene(scene: Node) -> bool:
	return scene.scene_file_path.ends_with("title.tscn")


## 4단계: 일반 인게임 화면에서는 일시정지 팝업을 생성하고 트리를 일시정지한다.
func _handle_open_pause_popup(scene: Node) -> bool:
	var popup: Node = PAUSE_POPUP_SCENE.instantiate()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(popup)
	get_tree().paused = true
	get_viewport().set_input_as_handled()
	return true
