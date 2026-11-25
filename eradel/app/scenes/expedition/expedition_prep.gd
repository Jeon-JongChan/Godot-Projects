## 원정 출정 준비 화면 (expedition_prep.gd)
## 던전 입장 전 최대 4인의 탐험 파티를 구성하고, 목표 던전의 활성도 및 예상 난이도를 점검하는 화면.
extends Control

var _root: MarginContainer
## 5명 미만 편성 출발 시 표시되는 확인 팝업 오버레이
var _confirm_overlay: Control = null


## ESC 입력 시 5명 미만 출발 확인 팝업을 닫는다.
func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_confirm_overlay):
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			_close_confirm_popup()


## 화면 진입 시 초기화: 고딕 배경 구성 및 파티/로스터 상태 변경 시그널 구독
func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)
	GameState.party_changed.connect(_rebuild)
	GameState.roster_changed.connect(_rebuild)
	_rebuild()


## UI 전체 재구성: 상단바, 목표 던전 위험도 패널, 좌측 파티 슬롯, 우측 대기 용병 목록, 하단 입장 버튼 생성
func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	vbox.add_child(UiKit.top_bar("던전 원정 준비", func(): get_tree().change_scene_to_file(GameState.SCENE_ESTATE)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	# 목표 던전 패널 (어둠의 균열 도트 일러스트 썸네일 포함)
	var dungeon_panel := UiKit.panel(UiKit.BG2, UiKit.BORDER2)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 14)
	dungeon_panel.add_child(dh)

	if ResourceLoader.exists("res://assets/sprites/interiors/dungeon_bg.png"):
		var thumb_frame := UiKit.panel(UiKit.BG, UiKit.BORDER2, 4)
		thumb_frame.add_theme_stylebox_override("panel", UiKit.style(UiKit.BG, UiKit.BORDER2, 4, 1, 2, 2))
		var thumb := TextureRect.new()
		thumb.texture = load("res://assets/sprites/interiors/dungeon_bg.png")
		thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.custom_minimum_size = Vector2(140, 74)
		thumb_frame.add_child(thumb)
		dh.add_child(thumb_frame)

	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = SIZE_EXPAND_FILL
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dh.add_child(dv)
	dv.add_child(UiKit.label("목표 던전 — 어둠의 균열 (3개 회랑 연속 돌파)", 14, UiKit.WHITE))
	dv.add_child(UiKit.label("\"한번 들어간 자는 같은 모습으로 돌아오지 않는다\"", 11, UiKit.TEXT3))
	var act_color := UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GOLD
	dv.add_child(UiKit.label("활성도 %d%% — 예상 난이도 %s" % [GameState.dungeon_activity, _difficulty_text()], 12, act_color))
	content.add_child(dungeon_panel)

	# 본문 2단: 좌측(현재 파티) + 우측(대기 용병)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(body)

	body.add_child(_build_formation())

	# 하단 푸터: 힌트 문구 및 던전 입장(일반 / 심층 보스) 액션 버튼
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	var hint := UiKit.label(_footer_hint(), 12, UiKit.TEXT2)
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(hint)

	var boss_unlocked := GameState.can_enter_boss_expedition()
	var btn_boss := UiKit.primary_button("👑 심층 보스 입장 ↗", UiKit.GOLD)
	btn_boss.custom_minimum_size = Vector2(180, 44)
	btn_boss.focus_mode = Control.FOCUS_ALL
	btn_boss.disabled = GameState.party.is_empty() or not boss_unlocked
	btn_boss.tooltip_text = "" if boss_unlocked else "해금 조건: 균열 활성도 30% 이하 또는 10일차 이상"
	btn_boss.pressed.connect(func(): _request_enter(true))
	footer.add_child(btn_boss)

	var enter := UiKit.primary_button("던전 입장 ↗", UiKit.GREEN)
	enter.custom_minimum_size = Vector2(160, 44)
	enter.focus_mode = Control.FOCUS_ALL
	enter.disabled = GameState.party.is_empty()
	enter.pressed.connect(func(): _request_enter(false))
	footer.add_child(enter)
	content.add_child(footer)


## 던전 활성도와 몬스터 티어를 종합하여 난이도 등급(상/중상/중/하) 문자열 계산
func _difficulty_text() -> String:
	var a := GameState.dungeon_activity + GameState.monster_tier * 15
	if a >= 80: return "상"
	if a >= 50: return "중상"
	if a >= 30: return "중"
	return "하"


## 하단 안내 문구 생성: 파티 편성 인원수 또는 미편성 경고 안내
func _footer_hint() -> String:
	if GameState.party.is_empty():
		return "⚠ 최소 1명의 용병을 파티에 편성하세요."
	return "파티 %d명 편성됨. 입장하면 그 날의 원정이 시작됩니다." % GameState.party.size()


## 던전 입장 전 편성 보드: 전열/중열/후열 3열 × 열당 3슬롯. 용병은 자신의 위치값 열에만 배치할 수 있다.
func _build_formation() -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UiKit.label("진형 편성 (%d/%d) — 입장 후에는 위치를 바꿀 수 없습니다" % [GameState.party.size(), GameState.MAX_PARTY], 11, UiKit.TEXT2))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(cols)
	for r in Mercenary.ROW_NAMES.size():
		cols.add_child(_build_row_column(r))
	return panel


## 한 열(전열/중열/후열) 컬럼: 편성된 용병 슬롯 3칸 + 해당 열 소속 대기 용병 목록
func _build_row_column(row: int) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.add_child(UiKit.label("▍%s" % Mercenary.ROW_NAMES[row], 13, UiKit.GOLD))
	var placed: Array[Mercenary] = []
	for m in GameState.party:
		if m.row == row:
			placed.append(m)
	for i in Mercenary.ROW_SLOTS:
		if i < placed.size():
			col.add_child(_slot(placed[i], true))
		else:
			var empty := UiKit.panel(UiKit.BG, UiKit.BORDER, 6)
			empty.custom_minimum_size = Vector2(0, 40)
			empty.add_child(UiKit.label("빈 슬롯", 11, UiKit.TEXT3))
			col.add_child(empty)
	col.add_child(UiKit.label("대기 용병 (%s)" % Mercenary.ROW_NAMES[row], 11, UiKit.TEXT2))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var any := false
	for m in GameState.available_mercs():
		if m.row == row:
			any = true
			list.add_child(_slot(m, false))
	if not any:
		list.add_child(UiKit.label("없음", 11, UiKit.TEXT3))
	return col


## 단일 용병 슬롯 UI 카드 생성: UiKit.merc_card 공용 위젯으로 통합
func _slot(m: Mercenary, in_party: bool) -> Control:
	return UiKit.merc_card(m, {
		"bg_color": UiKit.BG3,
		"border_color": UiKit.BORDER2 if in_party else UiKit.BORDER,
		"portrait_size": 44,
		"color_name_by_grade": true,
		"title_size": 13,
		"show_hp_bar": true,
		"hp_color": UiKit.RED,
		"show_penalties": true,
		"action_text": "빼기" if in_party else "추가",
		"action_color": UiKit.RED if in_party else UiKit.GOLD,
		"action_disabled": false if in_party else (GameState.party.size() >= GameState.MAX_PARTY or GameState.party_row_count(m.row) >= Mercenary.ROW_SLOTS),
		"on_action": func(target: Mercenary):
			if in_party:
				GameState.remove_from_party(target)
			else:
				GameState.add_to_party(target),
	})


## 던전 입장 요청: 5명 미만 편성 시 안내 확인 팝업을 띄우고, 5명 편성 완료 시 즉시 출진한다.
func _request_enter(boss_mode: bool) -> void:
	if GameState.party.is_empty():
		return
	if GameState.party.size() < GameState.MAX_PARTY:
		_show_understaffed_confirm(boss_mode)
		return
	_on_enter(boss_mode)


## 편성 인원이 5명 미만일 때 표시하는 출발 확인 팝업 ("인원이 5명 미만입니다. 이대로 출발하시겠습니까?").
func _show_understaffed_confirm(boss_mode: bool) -> void:
	_close_confirm_popup()
	var overlay := Control.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	add_child(overlay)
	_confirm_overlay = overlay

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.68)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			get_viewport().set_input_as_handled()
			_close_confirm_popup()
	)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card := UiKit.panel(UiKit.BG, UiKit.GOLD, 10)
	card.custom_minimum_size = Vector2(460, 0)
	card.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)

	# 상단 헤더: ⚠ 안내 + [X] 닫기
	var head := HBoxContainer.new()
	var title_lbl := UiKit.title("⚠ 안내", 17, UiKit.GOLD2)
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title_lbl)
	var btn_x := UiKit.button("✕", UiKit.BORDER2)
	btn_x.custom_minimum_size = Vector2(34, 30)
	btn_x.focus_mode = Control.FOCUS_ALL
	btn_x.pressed.connect(_close_confirm_popup)
	head.add_child(btn_x)
	v.add_child(head)

	v.add_child(UiKit.divider())

	var msg := UiKit.label("인원이 5명 미만입니다. (현재 %d / %d명)\n이대로 출발하시겠습니까?" % [GameState.party.size(), GameState.MAX_PARTY], 15, UiKit.WHITE)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 18)
	v.add_child(btn_row)

	var btn_cancel := UiKit.button("취소", UiKit.BORDER2)
	btn_cancel.custom_minimum_size = Vector2(140, 44)
	btn_cancel.focus_mode = Control.FOCUS_ALL
	btn_cancel.pressed.connect(_close_confirm_popup)
	btn_row.add_child(btn_cancel)

	var btn_go := UiKit.primary_button("출발", UiKit.GOLD if boss_mode else UiKit.GREEN)
	btn_go.custom_minimum_size = Vector2(140, 44)
	btn_go.focus_mode = Control.FOCUS_ALL
	btn_go.pressed.connect(func():
		_close_confirm_popup()
		_on_enter(boss_mode)
	)
	btn_row.add_child(btn_go)

	btn_cancel.grab_focus()


## 5명 미만 확인 팝업을 닫는다.
func _close_confirm_popup() -> void:
	if is_instance_valid(_confirm_overlay):
		_confirm_overlay.queue_free()
	_confirm_overlay = null


## 던전 입장 실행: GameState.start_expedition() 단일 진입점으로 파티 상태를 전환하고 던전 씬으로 이동한다.
func _on_enter(boss_mode: bool = false) -> void:
	if GameState.start_expedition(boss_mode):
		get_tree().change_scene_to_file(GameState.SCENE_DUNGEON)
