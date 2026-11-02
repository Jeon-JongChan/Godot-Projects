extends CanvasLayer

## 인게임 ESC 일시정지 팝업 (1차 피드백 2번 항목 반영).
## 재개 / 환경설정 / 저장 후 메인메뉴로 / 저장 후 게임종료 (2차 확인 팝업 포함) 제공.

var _confirm_modal: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	get_tree().paused = true
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		if _confirm_modal != null and _confirm_modal.visible:
			_confirm_modal.visible = false
		else:
			_resume_game()


## 일시정지 메인 패널 및 2차 종료 확인 모달 생성
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := UiKit.panel(UiKit.BG2, UiKit.GOLD, 12)
	panel.custom_minimum_size = Vector2(380, 340)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title_lbl := UiKit.title("⏸ 일시정지", 24, UiKit.GOLD2)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var sub_lbl := UiKit.label("영지 진행 상황은 언제든 안전하게 저장할 수 있습니다.", 12, UiKit.TEXT2)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_lbl)

	vbox.add_child(UiKit.hsep(6))

	var btn_resume := UiKit.primary_button("▶ 게임 재개 (ESC)", UiKit.GREEN)
	btn_resume.custom_minimum_size = Vector2(0, 42)
	btn_resume.pressed.connect(_resume_game)
	vbox.add_child(btn_resume)

	var btn_settings := UiKit.button("⚙ 환경설정", UiKit.GOLD)
	btn_settings.custom_minimum_size = Vector2(0, 40)
	btn_settings.pressed.connect(_open_settings)
	vbox.add_child(btn_settings)

	var btn_main := UiKit.button("🏰 저장 후 메인메뉴로", UiKit.BLUE)
	btn_main.custom_minimum_size = Vector2(0, 40)
	btn_main.pressed.connect(_save_and_go_title)
	vbox.add_child(btn_main)

	var btn_quit := UiKit.button("🚪 저장 후 게임종료", UiKit.RED)
	btn_quit.custom_minimum_size = Vector2(0, 40)
	btn_quit.pressed.connect(func():
		if _confirm_modal != null:
			_confirm_modal.visible = true
	)
	vbox.add_child(btn_quit)

	_build_quit_confirm_modal(root)


## '저장 후 게임종료' 선택 시 표시되는 2차 확인 팝업 생성
func _build_quit_confirm_modal(parent: Control) -> void:
	_confirm_modal = Control.new()
	_confirm_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_modal.visible = false
	parent.add_child(_confirm_modal)

	var dim2 := ColorRect.new()
	dim2.color = Color(0.0, 0.0, 0.0, 0.78)
	dim2.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_modal.add_child(dim2)

	var center2 := CenterContainer.new()
	center2.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_modal.add_child(center2)

	var box := UiKit.panel(UiKit.BG3, UiKit.RED, 10)
	box.custom_minimum_size = Vector2(400, 200)
	center2.add_child(box)

	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 14)
	box.add_child(cv)

	var q_title := UiKit.title("정말 게임을 종료하시겠습니까?", 18, UiKit.WHITE)
	q_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(q_title)

	var q_desc := UiKit.label("현재 진행 상태를 자동 저장한 뒤 게임을 닫습니다.", 13, UiKit.TEXT2)
	q_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(q_desc)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	cv.add_child(btn_row)

	var btn_cancel := UiKit.button("취소", UiKit.GOLD)
	btn_cancel.custom_minimum_size = Vector2(140, 38)
	btn_cancel.pressed.connect(func():
		_confirm_modal.visible = false
	)
	btn_row.add_child(btn_cancel)

	var btn_confirm := UiKit.primary_button("저장 후 종료", UiKit.RED)
	btn_confirm.custom_minimum_size = Vector2(140, 38)
	btn_confirm.pressed.connect(func():
		GameState.save_game()
		get_tree().paused = false
		get_tree().quit()
	)
	btn_row.add_child(btn_confirm)


func _resume_game() -> void:
	get_tree().paused = false
	queue_free()


func _open_settings() -> void:
	var scene: PackedScene = load("res://scenes/popups/settings_popup.tscn")
	if scene != null:
		var inst: Node = scene.instantiate()
		add_child(inst)


func _save_and_go_title() -> void:
	GameState.save_game()
	get_tree().paused = false
	queue_free()
	get_tree().change_scene_to_file(GameState.SCENE_TITLE)
