class_name SaveLoadPopup
extends Control

## 세이브/로드 팝업 — 3개의 저장 슬롯을 표시하고 불러오기/이름변경/삭제 기능을 수행한다.
## 기획서 4장 및 그림2 스케치 기반.

signal closed
signal game_started

@onready var slots_container: VBoxContainer
var _slot_edits: Array[LineEdit] = []
var _slot_v_btns: Array[Button] = []
var _slot_x_btns: Array[Button] = []
var _slot_info_labels: Array[Label] = []
var _confirm_dialog: PanelContainer = null

const MAX_SAVE_SLOTS: int = 3

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
	# 배경 어두운 딤 오버레이
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	# 메인 팝업 패널 (스케치 스타일)
	var panel := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 12)
	panel.custom_minimum_size = Vector2(580, 460)
	center.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	panel.add_child(main_vbox)

	# 상단 헤더: 타이틀 + 닫기 버튼
	var header := HBoxContainer.new()
	var title_lbl := UiKit.title("기록 보관소 (저장 슬롯)", 22, UiKit.GOLD)
	header.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := UiKit.button("✕", UiKit.RED)
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(close_popup)
	header.add_child(close_btn)
	main_vbox.add_child(header)

	main_vbox.add_child(UiKit.hsep(4))

	# 3개 슬롯 컨테이너
	slots_container = VBoxContainer.new()
	slots_container.add_theme_constant_override("separation", 14)
	main_vbox.add_child(slots_container)

	_build_slots()

	main_vbox.add_child(UiKit.hsep(8))

	# 하단 안내 문구
	var footer := UiKit.label("✓ 버튼을 누르면 이름을 저장하고 해당 슬롯을 시작합니다. (ESC: 닫기)", 12, UiKit.TEXT2)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(footer)

	refresh_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if _confirm_dialog != null and _confirm_dialog.visible:
			_dismiss_confirm()
		else:
			close_popup()
		get_viewport().set_input_as_handled()


## 슬롯 3개의 UI 행을 생성한다.
func _build_slots() -> void:
	_slot_edits.clear()
	_slot_v_btns.clear()
	_slot_x_btns.clear()
	_slot_info_labels.clear()

	for slot_idx in range(1, MAX_SAVE_SLOTS + 1):
		var card := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 6)
		card.add_child(card_vbox)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card_vbox.add_child(row)

		# 슬롯 번호 태그
		var tag := UiKit.chip("슬롯 %d" % slot_idx, UiKit.GOLD)
		row.add_child(tag)

		# LD-01: 슬롯 이름 입력란
		var edit := LineEdit.new()
		edit.size_flags_horizontal = SIZE_EXPAND_FILL
		edit.custom_minimum_size = Vector2(260, 40)
		edit.max_length = 20
		edit.placeholder_text = "영지 이름을 입력하세요"
		edit.add_theme_font_size_override("font_size", 15)
		edit.add_theme_color_override("font_color", UiKit.WHITE)
		edit.add_theme_stylebox_override("normal", UiKit.style(UiKit.BG2, UiKit.BORDER2, 6))
		row.add_child(edit)
		_slot_edits.append(edit)

		# LD-02: ✓ 버튼 (저장 및 불러오기)
		var v_btn := UiKit.primary_button("✓ 시작", UiKit.GREEN)
		v_btn.custom_minimum_size = Vector2(74, 40)
		var current_slot := slot_idx
		v_btn.pressed.connect(func(): _on_v_pressed(current_slot))
		row.add_child(v_btn)
		_slot_v_btns.append(v_btn)

		# LD-03: ✗ 버튼 (삭제)
		var x_btn := UiKit.button("✗ 삭제", UiKit.RED)
		x_btn.custom_minimum_size = Vector2(70, 40)
		x_btn.pressed.connect(func(): _on_x_pressed(current_slot))
		row.add_child(x_btn)
		_slot_x_btns.append(x_btn)

		# 슬롯 부가 정보 라벨 (날짜, 진행 일자, 골드)
		var info_lbl := UiKit.label("", 12, UiKit.TEXT3)
		card_vbox.add_child(info_lbl)
		_slot_info_labels.append(info_lbl)

		slots_container.add_child(card)


## 각 슬롯의 파일 상태를 읽어 UI를 새로고침한다.
func refresh_slots() -> void:
	var sm = _save_manager
	for slot_idx in range(1, MAX_SAVE_SLOTS + 1):
		var i := slot_idx - 1
		var meta: Dictionary = sm.get_slot_meta(slot_idx) if sm != null else {"is_empty": true, "name": "빈 슬롯"}
		var edit := _slot_edits[i]
		var v_btn := _slot_v_btns[i]
		var x_btn := _slot_x_btns[i]
		var info_lbl := _slot_info_labels[i]

		if meta.get("is_empty", true):
			# 빈 슬롯 상태
			edit.text = "빈 슬롯"
			edit.editable = false
			edit.modulate = Color(0.6, 0.6, 0.6, 0.7)
			v_btn.disabled = true
			x_btn.disabled = true
			info_lbl.text = "저장된 기록이 없습니다. 메인 화면의 '새 게임'으로 시작할 수 있습니다."
		else:
			# 저장 데이터가 있는 상태
			edit.text = str(meta.get("name", "이름 없는 영지"))
			edit.editable = true
			edit.modulate = Color(1, 1, 1, 1)
			v_btn.disabled = false
			x_btn.disabled = false
			info_lbl.text = "진행: %d일차  |  보유 금화: %dG  |  용병단: %d명  |  저장: %s" % [
				int(meta.get("day", 1)), int(meta.get("gold", 0)), int(meta.get("roster_count", 0)), str(meta.get("saved_at", ""))
			]


## ✓ 버튼 클릭 시: 이름 검증 및 저장 후 해당 슬롯 데이터 로드
func _on_v_pressed(slot_idx: int) -> void:
	var sm = _save_manager
	var gs = _game_state
	var edit := _slot_edits[slot_idx - 1]
	var new_name := edit.text.strip_edges()
	if new_name.is_empty():
		new_name = "영주 #%d" % slot_idx

	# 이름 변경 반영
	if sm != null:
		sm.update_slot_name(slot_idx, new_name)

	# 슬롯 데이터 로드
	if sm != null and sm.load_slot(slot_idx):
		game_started.emit()
		var scene_path = gs.SCENE_ESTATE if gs != null else "res://scenes/estate/estate.tscn"
		get_tree().change_scene_to_file(scene_path)
	else:
		_show_alert("오류", "데이터를 불러오는 데 실패했습니다.")


## ✗ 버튼 클릭 시: 삭제 확인 팝업 표시
func _on_x_pressed(slot_idx: int) -> void:
	var sm = _save_manager
	var meta: Dictionary = sm.get_slot_meta(slot_idx) if sm != null else {"name": "알 수 없음"}
	var prompt := "'%s' (슬롯 %d)의 저장 데이터를 삭제하시겠습니까?\n되돌릴 수 없습니다." % [meta.get("name", ""), slot_idx]
	_show_confirm("슬롯 삭제 확인", prompt, func():
		if sm != null:
			sm.delete_slot(slot_idx)
		refresh_slots()
	)


## 삭제 등 주요 동작 전 모달 확인창을 띄운다.
func _show_confirm(title_text: String, msg: String, on_confirm: Callable) -> void:
	_dismiss_confirm()

	var modal_bg := ColorRect.new()
	modal_bg.name = "ModalDim"
	modal_bg.color = Color(0, 0, 0, 0.6)
	modal_bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(modal_bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	modal_bg.add_child(center)

	var box := UiKit.panel(UiKit.BG, UiKit.RED, 10)
	box.custom_minimum_size = Vector2(380, 180)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	box.add_child(vbox)

	var t := UiKit.title(title_text, 18, UiKit.RED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)

	var body := UiKit.label(msg, 13, UiKit.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	vbox.add_child(btns)

	var ok_btn := UiKit.primary_button("삭제", UiKit.RED)
	ok_btn.custom_minimum_size = Vector2(100, 36)
	ok_btn.pressed.connect(func():
		_dismiss_confirm()
		on_confirm.call()
	)
	btns.add_child(ok_btn)

	var cancel_btn := UiKit.button("취소")
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.pressed.connect(_dismiss_confirm)
	btns.add_child(cancel_btn)

	_confirm_dialog = box


## 단순 알림 팝업
func _show_alert(title_text: String, msg: String) -> void:
	_dismiss_confirm()

	var modal_bg := ColorRect.new()
	modal_bg.name = "ModalDim"
	modal_bg.color = Color(0, 0, 0, 0.6)
	modal_bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(modal_bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	modal_bg.add_child(center)

	var box := UiKit.panel(UiKit.BG, UiKit.GOLD, 10)
	box.custom_minimum_size = Vector2(360, 160)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	box.add_child(vbox)

	var t := UiKit.title(title_text, 18, UiKit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)

	var body := UiKit.label(msg, 13, UiKit.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(body)

	var ok_btn := UiKit.primary_button("확인", UiKit.GOLD)
	ok_btn.custom_minimum_size = Vector2(100, 36)
	ok_btn.pressed.connect(_dismiss_confirm)
	vbox.add_child(ok_btn)

	_confirm_dialog = box


func _dismiss_confirm() -> void:
	var existing = get_node_or_null("ModalDim")
	if existing != null:
		existing.queue_free()
	_confirm_dialog = null


## 팝업을 닫는다.
func close_popup() -> void:
	closed.emit()
	queue_free()

