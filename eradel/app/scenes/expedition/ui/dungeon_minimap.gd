## 하단 우측 미니맵·전투 로그 탭 패널(자동 진행/철수 버튼 포함)을 소유하는 UI 헬퍼.
## 버튼 입력은 시그널로 던전 씬에 전달되며, 로그 원본 배열은 던전 씬이 보유합니다.
class_name DungeonMinimap
extends RefCounted

signal auto_turn_pressed
signal retreat_pressed

var _current_stage: int = 1
var _finished: bool = false
var _max_stage: int = 4
var _log_lines: Array[String] = []
var _tab_map_btn: Button
var _tab_log_btn: Button
var _minimap_container: Control
var _minimap_layout: HBoxContainer = null
var _minimap_area_label: Label = null
var _log_container: Control
var _log_vbox: VBoxContainer
var _log_scroll: ScrollContainer
var _btn_auto_turn: Button
var _btn_retreat: Button


## 현재 단계/종료 여부를 반영해 미니맵을 다시 그립니다.
func refresh(stage: int, finished: bool) -> void:
	_current_stage = stage
	_finished = finished
	_refresh_minimap()


## 철수 버튼의 비활성 상태를 설정합니다.
func set_retreat_disabled(value: bool) -> void:
	if _btn_retreat != null:
		_btn_retreat.disabled = value


## 자동 진행 버튼의 비활성 상태를 설정합니다.
func set_auto_disabled(value: bool) -> void:
	if _btn_auto_turn != null:
		_btn_auto_turn.disabled = value


## 하단 우측 미니맵 & 전투 로그 탭 전환 패널을 생성합니다.
func build(max_stage: int, log_lines: Array[String]) -> Control:
	_max_stage = max_stage
	_log_lines = log_lines
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(480, 234)
	var p_sb := StyleBoxFlat.new()
	p_sb.bg_color = Color("100e0b")
	p_sb.border_color = Color("3d3324")
	p_sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", p_sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	p.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# 탭 바 및 액션 버튼들
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(tab_bar)

	_tab_map_btn = Button.new()
	_tab_map_btn.text = "🗺 미니맵"
	_tab_map_btn.custom_minimum_size = Vector2(85, 26)
	_tab_map_btn.pressed.connect(func(): switch_right_tab(true))
	tab_bar.add_child(_tab_map_btn)

	_tab_log_btn = Button.new()
	_tab_log_btn.text = "📜 전투 기록"
	_tab_log_btn.custom_minimum_size = Vector2(95, 26)
	_tab_log_btn.pressed.connect(func(): switch_right_tab(false))
	tab_bar.add_child(_tab_log_btn)

	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(tab_spacer)

	_btn_auto_turn = UiKit.button("▶ 자동 진행", UiKit.GREEN)
	_btn_auto_turn.custom_minimum_size = Vector2(95, 26)
	_btn_auto_turn.pressed.connect(func(): auto_turn_pressed.emit())
	tab_bar.add_child(_btn_auto_turn)

	_btn_retreat = UiKit.button("철수", UiKit.RED)
	_btn_retreat.custom_minimum_size = Vector2(65, 26)
	_btn_retreat.pressed.connect(func(): retreat_pressed.emit())
	tab_bar.add_child(_btn_retreat)

	# 내용물 영역 (미니맵 컨테이너 vs 전투 로그 컨테이너)
	var content_area := PanelContainer.new()
	content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var c_sb := StyleBoxFlat.new()
	c_sb.bg_color = Color("0a0807")
	content_area.add_theme_stylebox_override("panel", c_sb)
	vbox.add_child(content_area)

	# 1. 미니맵 컨테이너
	_minimap_container = _build_darkest_minimap()
	content_area.add_child(_minimap_container)

	# 2. 전투 로그 스크롤 컨테이너
	_log_container = Control.new()
	_log_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_container.visible = false
	content_area.add_child(_log_container)

	_log_scroll = ScrollContainer.new()
	_log_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_container.add_child(_log_scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_vbox)

	switch_right_tab(true)
	refresh_log()
	return p


## 우측 패널 탭(미니맵 vs 전투 로그)을 전환합니다.
func switch_right_tab(show_map: bool) -> void:
	if _minimap_container:
		_minimap_container.visible = show_map
	if _log_container:
		_log_container.visible = not show_map

	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = Color("2d251d")
	active_sb.border_color = Color("c7a13c")
	active_sb.set_border_width_all(1)

	var inactive_sb := StyleBoxFlat.new()
	inactive_sb.bg_color = Color("14110e")
	inactive_sb.border_color = Color("2b241c")
	inactive_sb.set_border_width_all(1)

	_tab_map_btn.add_theme_stylebox_override("normal", active_sb if show_map else inactive_sb)
	_tab_log_btn.add_theme_stylebox_override("normal", inactive_sb if show_map else active_sb)


## 다키스트 던전 1 정통 스타일의 미니맵(Grid 형태의 방과 복도, 현재 방 횃불 표시, 탐험 체크 표시)을 생성합니다.
func _build_darkest_minimap() -> Control:
	var map_root := Control.new()
	map_root.set_anchors_preset(Control.PRESET_FULL_RECT)

	# 배경 눈금선 (그리드 도트 패턴 느낌)
	var grid_bg := ColorRect.new()
	grid_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid_bg.color = Color("0a0907")
	map_root.add_child(grid_bg)

	var map_center := CenterContainer.new()
	map_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_root.add_child(map_center)

	_minimap_layout = HBoxContainer.new()
	_minimap_layout.add_theme_constant_override("separation", 0)
	_minimap_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	map_center.add_child(_minimap_layout)

	# 미니맵 좌측 하단 구역 텍스트
	_minimap_area_label = Label.new()
	_minimap_area_label.position = Vector2(10, 140)
	_minimap_area_label.add_theme_font_size_override("font_size", 10)
	_minimap_area_label.add_theme_color_override("font_color", Color("9a8b76"))
	map_root.add_child(_minimap_area_label)

	_refresh_minimap()
	return map_root


## 현재 진행 단계(_current_stage: 1~3)에 맞춰 미니맵의 방·복도 상태와 구역명을 즉시 다시 그립니다.
func _refresh_minimap() -> void:
	if _minimap_layout == null:
		return
	for c in _minimap_layout.get_children():
		_minimap_layout.remove_child(c)
		c.queue_free()

	# 0. 입구 (항상 돌파 완료)
	_minimap_layout.add_child(_create_room_node(false, true, "✔", Color("c8a24a")))
	_minimap_layout.add_child(_create_corridor_node(true))

	# 1~3. 제 1/2/3 회랑 노드 동적 구성
	for st in range(1, _max_stage + 1):
		var is_cur := (st == _current_stage) and not _finished
		var is_cleared := (st < _current_stage) or (_finished and st <= _current_stage)
		var icon := "⚔" if st < _max_stage else "☠"
		var border_col := Color("5c5142")
		if is_cleared:
			icon = "✔"
			border_col = Color("c8a24a")
		elif is_cur:
			icon = "🔥" if st < _max_stage else "☠"
			border_col = Color("e07b39") if st < _max_stage else Color("c84a42")
		_minimap_layout.add_child(_create_room_node(is_cur, is_cleared, icon, border_col))
		if st < _max_stage:
			_minimap_layout.add_child(_create_corridor_node(_current_stage > st))

	if _minimap_area_label != null:
		_minimap_area_label.text = "현재 구역: 어둠의 균열 제 %d 회랑 (%d / %d 단계)" % [_current_stage, _current_stage, _max_stage]


## 미니맵 방(Room) 노드를 생성합니다.
func _create_room_node(is_current: bool, is_cleared: bool, icon: String, border_col: Color) -> Control:
	var room := PanelContainer.new()
	room.custom_minimum_size = Vector2(44, 44)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1a1612") if not is_current else Color("2a1a10")
	sb.border_color = border_col
	sb.set_border_width_all(2 if is_current else 1)
	sb.set_corner_radius_all(2)
	room.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = icon
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16 if is_current else 14)
	if is_current:
		lbl.add_theme_color_override("font_color", Color("ffd700"))
	elif is_cleared:
		lbl.add_theme_color_override("font_color", Color("c79c38"))
	else:
		lbl.add_theme_color_override("font_color", Color("5c5142"))
	room.add_child(lbl)

	return room


## 미니맵 복도(Corridor) 노드를 생성합니다. (3개의 작은 점 연결선)
func _create_corridor_node(is_explored: bool) -> Control:
	var corridor := HBoxContainer.new()
	corridor.custom_minimum_size = Vector2(36, 44)
	corridor.alignment = BoxContainer.ALIGNMENT_CENTER
	corridor.add_theme_constant_override("separation", 4)

	for i in 3:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(5, 5)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Color("c79c38") if is_explored else Color("2d2720")
		corridor.add_child(dot)

	return corridor


## 로그 스크롤 창 갱신
func refresh_log() -> void:
	if _log_vbox == null:
		return
	for c in _log_vbox.get_children():
		c.queue_free()

	var recent := _log_lines.slice(maxi(0, _log_lines.size() - 30))
	for line in recent:
		var col := Color("c9bea9")
		if line.begins_with("★"): col = Color("ffd700")
		elif line.begins_with("☠") or line.begins_with("✝"): col = Color("ff4444")
		elif line.begins_with("[제"): col = Color("e0a548")
		elif line.begins_with("---"): col = Color("f08080")
		elif line.begins_with("🛡"): col = Color("70a1ff")
		elif line.begins_with("✦"): col = Color("2ed573")
		_log_vbox.add_child(UiKit.label(line, 11, col))

	if _log_scroll:
		_log_scroll.call_deferred("set_v_scroll", 99999)
