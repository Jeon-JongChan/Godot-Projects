extends Node

## 전역 일시정지 관리자 — 인게임 중 ESC 키를 감지하여 일시정지 팝업을 띄운다.

const PAUSE_POPUP_SCENE = preload("res://scenes/ui/pause_popup.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		return

	var tree := get_tree()
	if tree == null:
		return

	var current := tree.current_scene
	if current == null:
		return

	# 메인 타이틀 화면에서는 일시정지 팝업을 띄우지 않음
	if current.scene_file_path.ends_with("title.tscn"):
		return

	# 이미 열려 있는 모달 팝업이 있는지 확인
	for child in current.get_children():
		if child.name.contains("Pause") or child.name.contains("Settings") or child.name.contains("SaveLoad"):
			return

	# 일시정지 팝업 오픈
	var popup = PAUSE_POPUP_SCENE.instantiate()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	current.add_child(popup)
	tree.paused = true
	get_viewport().set_input_as_handled()
