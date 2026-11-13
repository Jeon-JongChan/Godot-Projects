extends Control

## 타이틀 화면 — 기획서 3장 및 그림1 스케치 기반 메인 메뉴.
## New Game, Load, Setting, Exit 4버튼 세로 배치 및 키보드(↑, ↓, Enter) 조작 지원.

var _buttons: Array[Button] = []
var _active_popup: Control = null
var _slot_full_alert: Control = null

var _save_manager: Node:
	get:
		var node = get_node_or_null("/root/SaveManager")
		if node != null:
			return node
		var ml = Engine.get_main_loop()
		if ml != null and "root" in ml and ml.root != null:
			return ml.root.get_node_or_null("SaveManager")
		return null

var _game_state: Node:
	get:
		var node = get_node_or_null("/root/GameState")
		if node != null:
			return node
		var ml = Engine.get_main_loop()
		if ml != null and "root" in ml and ml.root != null:
			return ml.root.get_node_or_null("GameState")
		return null


func _ready() -> void:
	UiKit.background(self, UiKit.BG)

	# 배경 아트
	var art := TextureRect.new()
	art.texture = load(UiKit.TITLE_ART)
	art.set_anchors_preset(PRESET_FULL_RECT)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(1, 1, 1, 0.55)
	art.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(art)

	# 어두운 비네팅 오버레이 + 고딕 셰이더 후처리
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.04, 0.03, 0.45)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(overlay)
	UiKit.attach_gothic_atmosphere(self, 0.48, 0.20, 0.0)

	# 중앙 컨테이너 (스케치 그림 1 세로 정렬)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	# MM-00: 게임 타이틀 영역
	var tag := UiKit.label("로그라이크 턴제 영지 경영 RPG", 14, UiKit.GOLD)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)

	var name_label := UiKit.title("영지의 군주", 64, UiKit.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var lore := UiKit.label("아무도 원하지 않아서, 아무도 빼앗지 않은 그 자리에.", 14, UiKit.TEXT2)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lore)

	box.add_child(UiKit.hsep(20))

	# ① New Game 버튼 (MM-01)
	var new_btn := _create_menu_button("New Game", true)
	new_btn.pressed.connect(_on_new_game)
	box.add_child(new_btn)
	_buttons.append(new_btn)

	# ② Load 버튼 (MM-02)
	var load_btn := _create_menu_button("Load", false)
	load_btn.pressed.connect(_on_load_pressed)
	box.add_child(load_btn)
	_buttons.append(load_btn)

	# ③ Setting 버튼 (MM-03)
	var setting_btn := _create_menu_button("Setting", false)
	setting_btn.pressed.connect(_on_setting_pressed)
	box.add_child(setting_btn)
	_buttons.append(setting_btn)

	# ④ Exit 버튼 (MM-04)
	var exit_btn := _create_menu_button("Exit", false)
	exit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(exit_btn)
	_buttons.append(exit_btn)

	# 키보드 상/하 포커스 순환 설정
	_setup_focus_neighbors()

	box.add_child(UiKit.hsep(16))
	var ver := UiKit.label("v0.1 초안 · UI 수정제안서 스케치 적용판", 11, UiKit.TEXT3)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ver)

	# 첫 버튼에 포커스 부여
	new_btn.grab_focus()


## 메인 메뉴 버튼 스타일 생성
func _create_menu_button(text: String, is_primary: bool) -> Button:
	var btn := UiKit.primary_button(text, UiKit.GOLD) if is_primary else UiKit.button(text)
	btn.custom_minimum_size = Vector2(240, 44)
	btn.focus_mode = Control.FOCUS_ALL
	return btn


## 키보드 상/하 네비게이션 연결
func _setup_focus_neighbors() -> void:
	var count := _buttons.size()
	for i in count:
		var prev_btn := _buttons[(i - 1 + count) % count]
		var next_btn := _buttons[(i + 1) % count]
		_buttons[i].focus_neighbor_top = prev_btn.get_path()
		_buttons[i].focus_neighbor_bottom = next_btn.get_path()


## ① New Game: 빈 슬롯 1개 자동 선택 후 새 게임 시작
func _on_new_game() -> void:
	if _active_popup != null:
		return

	var sm = _save_manager
	var gs = _game_state
	var empty_slot: int = sm.get_first_empty_slot() if sm != null else -1
	if empty_slot != -1:
		# 빈 슬롯이 있으면 즉시 새 게임 초기화 후 저장 및 씬 전환
		if gs != null:
			gs.new_game()
		if sm != null:
			sm.save_slot(empty_slot, "영주 #%d" % empty_slot)
		if gs != null:
			get_tree().change_scene_to_file(gs.SCENE_ESTATE)
	else:
		# 모든 슬롯(3개)이 차 있는 경우: 안내 팝업 후 Load 팝업으로 유도
		_show_slots_full_dialog()


## ② Load: Load 팝업 열기
func _on_load_pressed() -> void:
	if _active_popup != null:
		return

	var popup_scene := load("res://scenes/popups/save_load_popup.tscn")
	var popup = popup_scene.instantiate()
	_active_popup = popup
	popup.closed.connect(func():
		_active_popup = null
		if _buttons.size() > 1:
			_buttons[1].grab_focus()
	)
	add_child(popup)


## ③ Setting: Setting 팝업 열기
func _on_setting_pressed() -> void:
	if _active_popup != null:
		return

	var popup_scene := load("res://scenes/popups/settings_popup.tscn")
	var popup = popup_scene.instantiate()
	_active_popup = popup
	popup.closed.connect(func():
		_active_popup = null
		if _buttons.size() > 2:
			_buttons[2].grab_focus()
	)
	add_child(popup)


## 슬롯이 모두 가득 찼을 때의 안내 모달 다이얼로그
func _show_slots_full_dialog() -> void:
	if _slot_full_alert != null:
		_slot_full_alert.queue_free()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	dim.add_child(center)

	var box := UiKit.panel(UiKit.BG, UiKit.GOLD, 10)
	box.custom_minimum_size = Vector2(420, 200)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	box.add_child(vbox)

	var t := UiKit.title("모든 저장 슬롯이 가득 찼습니다", 18, UiKit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)

	var desc := UiKit.label("기록 보관소의 3개 슬롯이 모두 사용 중입니다.\n기존 슬롯을 비우거나 선택하여 덮어쓰시겠습니까?", 13, UiKit.TEXT)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	vbox.add_child(btns)

	var ok_btn := UiKit.primary_button("슬롯 관리 열기", UiKit.GOLD)
	ok_btn.custom_minimum_size = Vector2(140, 38)
	ok_btn.pressed.connect(func():
		dim.queue_free()
		_slot_full_alert = null
		_on_load_pressed()
	)
	btns.add_child(ok_btn)

	var cancel_btn := UiKit.button("취소")
	cancel_btn.custom_minimum_size = Vector2(90, 38)
	cancel_btn.pressed.connect(func():
		dim.queue_free()
		_slot_full_alert = null
		_buttons[0].grab_focus()
	)
	btns.add_child(cancel_btn)

	_slot_full_alert = dim
	ok_btn.grab_focus()
