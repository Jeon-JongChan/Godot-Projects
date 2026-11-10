class_name EstateWorld
extends Control

const VillageVisuals = preload("res://scripts/village_visuals.gd")

## 영지 메인 화면 — 클래시 오브 클랜 / 다키스트 던전 스타일의 2.5D 마을 월드 및 대형 건물 팝업 시스템.
## 기획 문서(면기본 메인화.docx) 반영:
## - 가로로 길쭉한 영지 마을(2500x720)이 부드러운 카메라 스크롤로 흐르듯 연결됨
## - 10개 건물 + 어둠의 균열(차원문)이 텍스트 박스가 아닌 실제 2.5D 마을 건축물로 여백을 두고 배치됨
## - 하단 스크롤바의 노란색 창 1칸(현재 화면 크기 비율 핸들)으로 마을 시점을 자유롭게 조정
## - 건물을 클릭하면 화면 자체가 건물로 부드럽게 줌인되며 대형 기능 팝업창(1060x600)이 열림

const WORLD_WIDTH: float = 2500.0
const WORLD_HEIGHT: float = 720.0
const VIEWPORT_WIDTH: float = 1280.0
const VIEWPORT_HEIGHT: float = 720.0
const MAX_SCROLL_X: float = WORLD_WIDTH - VIEWPORT_WIDTH # 1220.0

## [유한 상태 기계] 영지 월드 카메라 및 모달 뷰 상태
enum ViewState { BROWSING, ZOOMING_IN, MODAL_OPEN, ZOOMING_OUT }

# ── 카메라 및 스크롤 상태 ──
var _target_scroll_x: float = 220.0
var _current_scroll_x: float = 220.0
var _is_dragging_world: bool = false
var _drag_start_mouse_x: float = 0.0
var _drag_start_scroll_x: float = 0.0
var _drag_moved_distance: float = 0.0

var _is_dragging_scrollbar: bool = false
var _is_zooming: bool = false
var _view_fsm: StateMachine = StateMachine.new()
var _active_modal: Control = null
var _current_open_def: Dictionary = {}
var _popup_notice: String = ""
var _selected_forge_merc: Mercenary = null
var _selected_forge_slot: String = "weapon"
var _active_blacksmith_canvas: Control = null
var _roster_dock_expanded: bool = true
var _roster_dock_panel: Control = null

# ── 노드 참조 ([업데이트 메서드] 대상 컬렉션 포함) ──
var _world_container: Control
var _terrain_canvas: VillageVisuals.VillageTerrainCanvas
var _buildings_layer: Control
var _building_canvases: Array[VillageVisuals.VillageBuildingCanvas] = []
var _active_interior_canvas: VillageVisuals.BuildingInteriorCanvas = null
var _hud_layer: CanvasLayer
var _top_bar_holder: Control
var _status_Row_holder: HBoxContainer
var _scroll_track: Panel
var _scroll_thumb: Panel
var _scroll_track_width: float = 880.0
var _scroll_track_height: float = 30.0
var _floating_bubbles: Array[Control] = []
var _bubble_base_y: Array[float] = []
var _anim_clock: float = 0.0

# ── [경량화] 기획서 스케치 11개 마을 건물 정적 정의는 BuildingDb 가 공유한다 ──
var _building_defs: Array[Dictionary] = BuildingDb.DEFS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_view_fsm()

	# 1. 파노라마 마을 월드 컨테이너 (2500 x 720)
	_world_container = Control.new()
	_world_container.custom_minimum_size = Vector2(WORLD_WIDTH, WORLD_HEIGHT)
	_world_container.size = Vector2(WORLD_WIDTH, WORLD_HEIGHT)
	add_child(_world_container)

	# 2. 마을 지형/도로/나무/가로등 캔버스
	_terrain_canvas = VillageVisuals.VillageTerrainCanvas.new()
	_terrain_canvas.building_defs = _building_defs
	_terrain_canvas.size = Vector2(WORLD_WIDTH, WORLD_HEIGHT)
	_terrain_canvas.mouse_filter = MOUSE_FILTER_IGNORE
	_world_container.add_child(_terrain_canvas)

	# 3. 2.5D 마을 건축물 레이어
	_buildings_layer = Control.new()
	_buildings_layer.size = Vector2(WORLD_WIDTH, WORLD_HEIGHT)
	_buildings_layer.mouse_filter = MOUSE_FILTER_PASS
	_world_container.add_child(_buildings_layer)
	_build_village_structures()

	# 4. 상단 HUD 및 하단 스크롤바 레이어
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	_build_hud()

	# 5. [옵저버] GameState 시그널 구독 — 상태가 바뀌면 자동으로 HUD 와 건물 배지가 갱신된다
	GameState.resources_changed.connect(_on_state_updated)
	GameState.stress_changed.connect(_on_state_updated)
	GameState.party_changed.connect(_on_state_updated)
	GameState.roster_changed.connect(_on_state_updated)
	GameState.game_over.connect(_on_game_over)

	# 시작 시 마을 중심부(용병모집소~영주저택~창고가 한눈에 들어오는 구도)로 스크롤 설정
	_target_scroll_x = 180.0
	_current_scroll_x = 180.0
	_update_scroll_position()


## [유한 상태 기계] 마을 탐색 ↔ 줌인 ↔ 대형 팝업 ↔ 줌아웃 상태 전이 규칙 등록
func _setup_view_fsm() -> void:
	_view_fsm.add(ViewState.BROWSING, func(): _is_zooming = false, Callable(), [ViewState.ZOOMING_IN, ViewState.MODAL_OPEN])
	_view_fsm.add(ViewState.ZOOMING_IN, func(): _is_zooming = true, Callable(), [ViewState.MODAL_OPEN, ViewState.BROWSING])
	_view_fsm.add(ViewState.MODAL_OPEN, func(): _is_zooming = false, Callable(), [ViewState.MODAL_OPEN, ViewState.ZOOMING_OUT, ViewState.BROWSING])
	_view_fsm.add(ViewState.ZOOMING_OUT, func(): _is_zooming = true, Callable(), [ViewState.BROWSING])
	_view_fsm.go(ViewState.BROWSING)


## [업데이트 메서드] 단일 중앙 게임 루프에서 지형·건물·내부 쇼케이스·말풍선·카메라를 일괄 갱신한다.
func _process(delta: float) -> void:
	_anim_clock += delta

	if is_instance_valid(_terrain_canvas):
		_terrain_canvas.update_tick(delta)
	for bc in _building_canvases:
		if is_instance_valid(bc):
			bc.update_tick(delta)
	if is_instance_valid(_active_interior_canvas):
		_active_interior_canvas.update_tick(delta)
	if is_instance_valid(_active_blacksmith_canvas) and _active_blacksmith_canvas.has_method("update_tick"):
		_active_blacksmith_canvas.update_tick(delta)

	# 건물 머리 위 상태 말풍선 부드러운 상하 부유 애니메이션
	for i in range(_floating_bubbles.size()):
		var b := _floating_bubbles[i]
		if is_instance_valid(b):
			b.position.y = _bubble_base_y[i] + sin(_anim_clock * 3.0 + float(i) * 0.9) * 3.5

	if not _view_fsm.is_in(ViewState.BROWSING):
		return

	# 키보드 A/D 및 좌/우 방향키 카메라 스크롤
	var move_dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir += 1.0

	if move_dir != 0.0:
		_target_scroll_x = clampf(_target_scroll_x + move_dir * 1100.0 * delta, 0.0, MAX_SCROLL_X)

	# 부드러운 카메라 감속 보간(Lerp)
	if absf(_current_scroll_x - _target_scroll_x) > 0.3:
		_current_scroll_x = lerpf(_current_scroll_x, _target_scroll_x, 12.0 * delta)
		_update_scroll_position()


## [책임 연쇄] PauseManager 의 ESC 체인에서 호출. 대형 팝업이 열려 있으면 닫고 true 를 반환한다.
func try_handle_cancel() -> bool:
	if _active_modal != null:
		_zoom_out_and_return()
		return true
	return false


## 마우스 드래그 패닝, 마우스 휠 스크롤, ESC 팝업 닫기 입력 처리
func _input(event: InputEvent) -> void:
	if _active_modal != null:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			_zoom_out_and_return()
		return

	if _is_zooming:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_target_scroll_x = clampf(_target_scroll_x - 150.0, 0.0, MAX_SCROLL_X)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_target_scroll_x = clampf(_target_scroll_x + 150.0, 0.0, MAX_SCROLL_X)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.position.y > 52 and event.position.y < VIEWPORT_HEIGHT - 68:
					_is_dragging_world = true
					_drag_start_mouse_x = event.position.x
					_drag_start_scroll_x = _target_scroll_x
					_drag_moved_distance = 0.0
			else:
				_is_dragging_world = false
				_is_dragging_scrollbar = false

	elif event is InputEventMouseMotion:
		if _is_dragging_world:
			var dx: float = _drag_start_mouse_x - event.position.x
			_drag_moved_distance = maxf(_drag_moved_distance, absf(dx))
			if _drag_moved_distance > 6.0:
				_target_scroll_x = clampf(_drag_start_scroll_x + dx, 0.0, MAX_SCROLL_X)
				_current_scroll_x = _target_scroll_x
				_update_scroll_position()
		elif _is_dragging_scrollbar:
			_handle_scrollbar_motion(event.position.x)
			get_viewport().set_input_as_handled()


## 월드 카메라 X좌표와 하단 스크롤바 노란색 뷰포트 핸들 동기화
func _update_scroll_position() -> void:
	_world_container.position.x = -_current_scroll_x

	if _scroll_thumb != null and _scroll_track != null:
		var ratio := clampf(_current_scroll_x / MAX_SCROLL_X, 0.0, 1.0)
		var max_thumb_x := _scroll_track_width - _scroll_thumb.size.x
		_scroll_thumb.position.x = ratio * max_thumb_x


# ── 클래시 오브 클랜 스타일 2.5D 마을 건물 배치 생성 ──
func _build_village_structures() -> void:
	for c in _buildings_layer.get_children():
		c.queue_free()
	_building_canvases.clear()
	_floating_bubbles.clear()
	_bubble_base_y.clear()

	for def in _building_defs:
		var node := _create_village_building_node(def)
		_buildings_layer.add_child(node)


## 각 건물을 텍스트 카드가 아닌 실제 2.5D 건축물 + 상단 부유 말풍선 + 하단 명패 배지로 구성
func _create_village_building_node(def: Dictionary) -> Control:
	var r: Rect2 = def.rect
	var root := Control.new()
	root.position = r.position
	root.size = r.size
	root.pivot_offset = r.size * 0.5
	root.mouse_filter = MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var is_dungeon: bool = (def.id == "dungeon_gate")
	var lv: int = GameState.buildings.get(def.name, 1)

	# 1. 2.5D 건축물 그래픽 캔버스 ([업데이트 메서드] 대상 목록에 등록)
	var art_canvas := VillageVisuals.VillageBuildingCanvas.new()
	art_canvas.def = def
	art_canvas.size = r.size
	art_canvas.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(art_canvas)
	_building_canvases.append(art_canvas)

	# 2. 지붕 위 부유하는 액션/상태 말풍선 ([경량화] 공유 StyleBox 캐시 사용)
	var bubble := PanelContainer.new()
	var bubble_col := UiKit.RED if is_dungeon else UiKit.GOLD
	var bubble_sb := UiKit.style(Color(0.09, 0.08, 0.06, 0.92), bubble_col, 14, 1, 10, 3)
	bubble.add_theme_stylebox_override("panel", bubble_sb)
	bubble.mouse_filter = MOUSE_FILTER_IGNORE

	var bubble_text := _get_building_bubble_text(def)
	var b_lbl := UiKit.label(bubble_text, 11, UiKit.GOLD2 if not is_dungeon else Color("ff8098"))
	b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.add_child(b_lbl)
	bubble.position = Vector2((r.size.x - 130) * 0.5, -18)
	bubble.custom_minimum_size = Vector2(130, 24)
	root.add_child(bubble)
	_floating_bubbles.append(bubble)
	_bubble_base_y.append(-18.0)

	# 3. 건물 하단 마을 명패 배지 ([경량화] 공유 StyleBox 캐시 사용)
	var plate := PanelContainer.new()
	var plate_border := UiKit.RED if is_dungeon else UiKit.BORDER2
	var plate_sb := UiKit.style(Color(0.08, 0.07, 0.05, 0.94), plate_border, 8, 2, 10, 3)
	plate.add_theme_stylebox_override("panel", plate_sb)
	plate.mouse_filter = MOUSE_FILTER_IGNORE

	var ph := HBoxContainer.new()
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	ph.add_theme_constant_override("separation", 6)
	plate.add_child(ph)

	var name_lbl := UiKit.title(def.name, 14, UiKit.WHITE if not is_dungeon else Color("ff7088"))
	ph.add_child(name_lbl)

	if not is_dungeon:
		var lv_lbl := UiKit.label("Lv.%d" % lv, 12, UiKit.GOLD2)
		ph.add_child(lv_lbl)
	else:
		var danger_lbl := UiKit.label("출진", 11, UiKit.RED)
		ph.add_child(danger_lbl)

	plate.custom_minimum_size = Vector2(156, 28)
	plate.position = Vector2((r.size.x - 156) * 0.5, r.size.y - 24)
	root.add_child(plate)

	# 호버 시 건물 확대 및 황금 아웃라인 하이라이트
	var hover_tw: Tween = null
	root.mouse_entered.connect(func():
		if _is_zooming or _active_modal != null:
			return
		art_canvas.is_hovered = true
		art_canvas.queue_redraw()
		plate.add_theme_stylebox_override("panel", UiKit.style(Color(0.16, 0.13, 0.08, 0.98), UiKit.GOLD2, 8, 2))
		if hover_tw:
			hover_tw.kill()
		hover_tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		hover_tw.tween_property(root, "scale", Vector2(1.07, 1.07), 0.16)
	)
	root.mouse_exited.connect(func():
		art_canvas.is_hovered = false
		art_canvas.queue_redraw()
		plate.add_theme_stylebox_override("panel", plate_sb)
		if hover_tw:
			hover_tw.kill()
		hover_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		hover_tw.tween_property(root, "scale", Vector2.ONE, 0.15)
	)

	# 클릭 시(드래그가 아닐 때) 해당 건물로 카메라 줌인 후 대형 팝업창 오픈
	root.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			if _drag_moved_distance <= 8.0:
				_on_building_selected(def)
	)

	return root


## 건물 지붕 위 말풍선에 표시할 실시간 상태 요약 텍스트 반환
func _get_building_bubble_text(def: Dictionary) -> String:
	match def.type:
		"guild":
			return "📜 용병 모집 (%d명)" % GameState.roster.size()
		"lodge":
			return "🛏️ 원정대 (%d/%d)" % [GameState.party.size(), GameState.MAX_PARTY]
		"treatment":
			var inj := GameState.injured_mercs().size()
			return ("⚕️ 부상자 %d명!" % inj) if inj > 0 else ("⚕️ 성공률 %d%%" % GameState.heal_success_rate())
		"manor":
			return "👑 행동력 %d/%d" % [GameState.action_points, GameState.max_action_points]
		"store":
			var disc: int = (int(GameState.buildings.get("잡화점", 1)) - 1) * 10
			return "⚖️ 보급품" + (" (-%d%%)" % disc if disc > 0 else " 상점")
		"warehouse":
			return "📦 마나석 %d개" % GameState.manastone
		"blacksmith":
			return "⚒️ 공격력 +%d" % GameState.party_attack_bonus()
		"magic":
			return "🔮 활성도 %d%%" % GameState.dungeon_activity
		"training":
			return "🎯 영웅 특훈"
		"memorial":
			return "🏛️ 위령비 (%d위)" % GameState.death_log.size()
		"dungeon":
			return "⚔️ 원정 출진!"
	return def.icon + " " + def.name


# ── 건물 선택 시 부드러운 카메라 줌인(Zoom-in) & 대형 팝업 오픈 ([유한 상태 기계]) ──
func _on_building_selected(def: Dictionary) -> void:
	if not _view_fsm.go(ViewState.ZOOMING_IN):
		return

	_current_open_def = def
	_popup_notice = ""

	var b_rect: Rect2 = def.rect
	var target_center := b_rect.position + b_rect.size * 0.5
	var desired_scroll_x := clampf(target_center.x - (VIEWPORT_WIDTH * 0.5), 0.0, MAX_SCROLL_X)
	_target_scroll_x = desired_scroll_x

	# 건물 중심을 피벗으로 삼아 마을 화면 자체가 건물 내부로 부드럽게 줌인되는 연출
	_world_container.pivot_offset = target_center

	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_current_scroll_x", desired_scroll_x, 0.38)
	tw.tween_property(_world_container, "position:x", -desired_scroll_x, 0.38)
	tw.tween_property(_world_container, "scale", Vector2(1.82, 1.82), 0.38)

	tw.chain().tween_callback(func():
		_update_scroll_position()
		_open_large_building_popup(def)
	)


## 줌인 완료 후 열리는 대형 건물 기능 팝업창 (1060 x 600)
func _open_large_building_popup(def: Dictionary) -> void:
	_view_fsm.go(ViewState.MODAL_OPEN)
	if _active_modal != null:
		_active_modal.queue_free()
		_active_modal = null

	_current_open_def = def
	var is_dungeon: bool = (def.id == "dungeon_gate")
	var bname: String = def.name
	var cur_lv: int = GameState.buildings.get(bname, 1)

	_active_modal = Control.new()
	_active_modal.set_anchors_preset(PRESET_FULL_RECT)
	_hud_layer.add_child(_active_modal)

	# 배경 반투명 딤 오버레이 (바깥 영역 클릭 시 닫기)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_zoom_out_and_return()
	)
	_active_modal.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_PASS
	_active_modal.add_child(center)

	# 대형 팝업 메인 프레임 (대장간은 1220 x 660, 일반 건물은 1060 x 600)
	var frame_border := UiKit.RED if is_dungeon else UiKit.GOLD
	var main_panel := UiKit.panel(UiKit.BG, frame_border, 14)
	var panel_size := Vector2(1220, 660) if def.type == "blacksmith" else Vector2(1060, 600)
	main_panel.custom_minimum_size = panel_size
	main_panel.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(main_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	main_panel.add_child(root_vbox)

	# ── 1. 일반 건물 상단 헤더 바 (대장간은 image2.png 기획에 따라 자체 상단바를 가짐) ──
	if def.type != "blacksmith":
		var header_bar := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 10)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		header_bar.add_child(hbox)

		hbox.add_child(UiKit.label(def.icon, 28, UiKit.WHITE))

		var title_col := VBoxContainer.new()
		title_col.add_theme_constant_override("separation", 2)
		var stars := ""
		for s in range(5):
			stars += "★" if s < cur_lv else "☆"
		var head_title := "%s" % bname if is_dungeon else "%s   %s (Lv.%d)" % [bname, stars, cur_lv]
		title_col.add_child(UiKit.title(head_title, 20, UiKit.GOLD2 if not is_dungeon else Color("ff6880")))
		title_col.add_child(UiKit.label(def.tag, 12, UiKit.TEXT2))
		hbox.add_child(title_col)

		var spacer := Control.new()
		spacer.size_flags_horizontal = SIZE_EXPAND_FILL
		hbox.add_child(spacer)

		# 팝업 내 실시간 자원/지표 칩 표시
		hbox.add_child(UiKit.chip("🪙 금화 %d" % GameState.gold, UiKit.GOLD))
		hbox.add_child(UiKit.chip("💎 마나석 %d" % GameState.manastone, UiKit.BLUE))
		hbox.add_child(UiKit.chip("⚡ 행동력 %d/%d" % [GameState.action_points, GameState.max_action_points], UiKit.GREEN))
		hbox.add_child(UiKit.chip("민심 %d%%" % GameState.morale, UiKit.GOLD))
		hbox.add_child(UiKit.chip("스트레스 %d/100" % GameState.total_stress(), GameState.stress_color()))

		var btn_close := UiKit.button("✕ 마을로 복귀 (ESC)", UiKit.GOLD)
		btn_close.custom_minimum_size = Vector2(150, 38)
		btn_close.pressed.connect(_zoom_out_and_return)
		hbox.add_child(btn_close)

		root_vbox.add_child(header_bar)

	# 알림 배너 (행동 결과 피드백 메시지)
	if _popup_notice != "":
		var notice_bar := UiKit.panel(Color("1c2b1e"), UiKit.GREEN, 8)
		var nh := HBoxContainer.new()
		notice_bar.add_child(nh)
		nh.add_child(UiKit.label("✨ " + _popup_notice, 13, UiKit.GOLD2))
		root_vbox.add_child(notice_bar)

	# ── 2. 본문 2단 레이아웃: 좌측(건물 내부 일러스트 & 증축 패널) + 우측(건물 핵심 기능 영역) ──
	var body_hbox := HBoxContainer.new()
	body_hbox.add_theme_constant_override("separation", 14)
	body_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_vbox.add_child(body_hbox)

	if def.type == "blacksmith":
		# 대장간은 기획서(대장간.docx) 레이아웃에 맞춰 전용 3단 패널(영웅목록+장비, 용광로/모루 드워프, 강화컨트롤)로 단독 구성
		body_hbox.add_child(_build_popup_right_content(def))
	else:
		body_hbox.add_child(_build_popup_left_showcase(def))
		body_hbox.add_child(_build_popup_right_content(def))


## 대형 팝업 좌측 컬럼: 건물 내부 아트워크 캔버스 + 레벨 효과 + 건물 증축 카드
func _build_popup_left_showcase(def: Dictionary) -> Control:
	var is_dungeon: bool = (def.id == "dungeon_gate")
	var bname: String = def.name
	var cur_lv: int = GameState.buildings.get(bname, 1)

	var left_panel := UiKit.panel(UiKit.BG2, UiKit.BORDER, 10)
	left_panel.custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	left_panel.add_child(v)

	# 1. 건물 내부/외관 아트워크 쇼케이스 캔버스
	var art_holder := Control.new()
	art_holder.custom_minimum_size = Vector2(276, 175)
	v.add_child(art_holder)

	var interior_bg := VillageVisuals.BuildingInteriorCanvas.new()
	interior_bg.btype = def.type
	interior_bg.size = Vector2(276, 175)
	art_holder.add_child(interior_bg)
	_active_interior_canvas = interior_bg

	var b_art := VillageVisuals.VillageBuildingCanvas.new()
	b_art.def = def
	b_art.position = Vector2(18, 6)
	b_art.size = Vector2(240, 165)
	art_holder.add_child(b_art)

	# 2. 건물 고유 효과 카드
	var eff_card := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 6)
	eff_card.add_child(ev)
	ev.add_child(UiKit.label("🏛️ 시설 효과", 13, UiKit.GOLD))
	var eff_lbl := UiKit.label(def.get("effect_desc", ""), 12, UiKit.TEXT)
	eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(eff_lbl)
	v.add_child(eff_card)

	# 3. 건물 증축(Upgrade) 컨트롤 카드
	var up_card := UiKit.panel(UiKit.BG3, UiKit.GOLD if not is_dungeon else UiKit.RED, 8)
	var uv := VBoxContainer.new()
	uv.add_theme_constant_override("separation", 8)
	up_card.add_child(uv)

	if not is_dungeon:
		uv.add_child(UiKit.label("🔼 시설 증축 (Lv.%d / 5)" % cur_lv, 13, UiKit.GOLD2))
		uv.add_child(UiKit.progress(cur_lv, 5, UiKit.GOLD, 8))

		if cur_lv >= 5:
			uv.add_child(UiKit.label("★ 최고 단계(Lv.5) 증축 완료!", 12, UiKit.GREEN))
		else:
			var cost := GameState.upgrade_cost(bname)
			var cost_str := "필요 자원: 금화 %dG" % cost.gold
			if cost.mana > 0:
				cost_str += " · 마나석 %d개" % cost.mana
			uv.add_child(UiKit.label(cost_str, 12, UiKit.TEXT2))

			var btn_up := UiKit.primary_button("건물 증축 (Lv.%d → Lv.%d)" % [cur_lv, cur_lv + 1], UiKit.GOLD)
			btn_up.custom_minimum_size = Vector2(0, 38)
			btn_up.disabled = not GameState.can_upgrade(bname)
			btn_up.pressed.connect(func():
				if GameState.upgrade_building(bname):
					_popup_notice = "%s 시설이 Lv.%d(으)로 증축되었습니다!" % [bname, cur_lv + 1]
					_build_village_structures()
					_open_large_building_popup(def)
			)
			uv.add_child(btn_up)
	else:
		uv.add_child(UiKit.label("⚠ 차원 균열 경보", 13, UiKit.RED))
		uv.add_child(UiKit.label("던전 활성도: %d%%  ·  몬스터 강화 +%d단계" % [GameState.dungeon_activity, GameState.monster_tier], 12, UiKit.TEXT))
		uv.add_child(UiKit.progress(GameState.dungeon_activity, 100, UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GOLD, 8))

	v.add_child(up_card)
	return left_panel


## 대형 팝업 우측 컬럼: 건물별 전용 비주얼 기능 컨텐츠
func _build_popup_right_content(def: Dictionary) -> Control:
	var right_panel := UiKit.panel(UiKit.BG2, UiKit.BORDER, 10)
	right_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_vertical = SIZE_EXPAND_FILL
	right_panel.add_child(vbox)

	match def.type:
		"guild":
			_populate_guild_popup(vbox, def)
		"lodge":
			_populate_lodge_popup(vbox, def)
		"treatment":
			_populate_treatment_popup(vbox, def)
		"manor":
			_populate_manor_popup(vbox, def)
		"store":
			_populate_store_popup(vbox, def)
		"warehouse":
			_populate_warehouse_popup(vbox, def)
		"blacksmith":
			_populate_blacksmith_popup(vbox, def)
		"magic":
			_populate_magic_popup(vbox, def)
		"training":
			_populate_training_popup(vbox, def)
		"memorial":
			_populate_memorial_popup(vbox, def)
		"dungeon":
			_populate_dungeon_popup(vbox, def)

	return right_panel


# ── [1] 용병모집소 대형 팝업 컨텐츠 ──
func _populate_guild_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	vbox.add_child(UiKit.label("📜 용병 영입 봉인서 (행동력 1 소모 · 모집소 레벨에 따라 초기 최대 체력 보너스 부여)", 13, UiKit.GOLD))

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 10)
	vbox.add_child(cards_row)

	var grade_info := [
		{"grade": "일반", "desc": "검증된 기본 전투원\n전사 · 레인저 · 마법사 · 성직자", "icon": "🛡️"},
		{"grade": "정예", "desc": "숙련된 베테랑 모험가\n높은 초기 전투력과 생존력", "icon": "⚔️"},
		{"grade": "특수", "desc": "영웅급 희귀 전설 전력\n압도적인 능력치 보유", "icon": "👑"},
	]
	var bonus_hp: int = (GameState.buildings.get("용병모집소", 1) - 1) * 5

	for info in grade_info:
		var grade: String = info.grade
		var cost: int = JobDb.RECRUIT_COST[grade]
		var col := JobDb.grade_color(grade)
		var card := UiKit.panel(UiKit.BG3, col, 10)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)

		var ic := UiKit.label(info.icon, 26, col)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(ic)

		var gt := UiKit.title("%s 용병 봉인서" % grade, 15, col.lightened(0.25))
		gt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(gt)

		var gd := UiKit.label(info.desc, 11, UiKit.TEXT2)
		gd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(gd)

		var btn := UiKit.primary_button("봉인 해제 (%dG · ⚡1)" % cost, col)
		btn.custom_minimum_size = Vector2(0, 36)
		btn.disabled = not GameState.can_afford(cost) or GameState.action_points <= 0
		btn.pressed.connect(func():
			var m := GameState.recruit(grade)
			if m != null:
				if bonus_hp > 0:
					m.max_hp += bonus_hp
					m.hp += bonus_hp
				_popup_notice = "[%s] %s (%s Lv.%d, HP %d, 공격력 %d) 용병이 합류했습니다!" % [m.grade, m.merc_name, m.job, m.level, m.max_hp, m.attack]
				_build_village_structures()
				_open_large_building_popup(def)
		)
		cv.add_child(btn)
		cards_row.add_child(card)

	vbox.add_child(UiKit.label("📋 현재 보유 용병 명단 (%d명)" % GameState.roster.size(), 13, UiKit.GOLD))
	vbox.add_child(_build_visual_roster_scroll(false, def))


# ── [2] 영웅숙소 대형 팝업 컨텐츠 ──
## [커맨드] 영지 행동 커맨드를 실행하고 안내 문구와 팝업을 갱신하는 공통 실행기(Invoker)
func _run_estate_command(cmd: EstateCommand, def: Dictionary) -> void:
	if cmd != null and cmd.execute():
		_popup_notice = cmd.notice_text()
		_open_large_building_popup(def)


# ── [2] 영웅숙소 대형 팝업 컨텐츠 ──
func _populate_lodge_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 10)
	vbox.add_child(top_h)

	var p_lbl := UiKit.label("🛡️ 현재 원정 출진 파티 (%d / %d명)" % [GameState.party.size(), GameState.MAX_PARTY], 14, UiKit.GOLD)
	p_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	top_h.add_child(p_lbl)

	var feast_cmd: EstateCommand = EstateCommand.catalog("lodge")[0]
	var btn_feast := UiKit.button("%s (%s → %s)" % [feast_cmd.title, feast_cmd.cost_text(), feast_cmd.desc], UiKit.GREEN)
	btn_feast.disabled = not feast_cmd.can_execute() or GameState.roster.is_empty()
	btn_feast.pressed.connect(func(): _run_estate_command(feast_cmd, def))
	top_h.add_child(btn_feast)

	# 상단 5인 원정 파티 시각 슬롯
	vbox.add_child(_build_visual_party_slots(def))

	vbox.add_child(UiKit.label("🛏️ 숙소 대기 용병 로스터 (클릭하여 원정 파티에 편성/제외)", 13, UiKit.TEXT2))
	vbox.add_child(_build_visual_roster_scroll(true, def))


# ── [3] 치료소 대형 팝업 컨텐츠 ──
func _populate_treatment_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	var care_row := HBoxContainer.new()
	care_row.add_theme_constant_override("separation", 10)
	vbox.add_child(care_row)

	var colors := {"pray": UiKit.BLUE, "ward": UiKit.GREEN}
	for cmd in EstateCommand.catalog("treatment"):
		var col: Color = colors.get(cmd.id, UiKit.BLUE)
		var card := UiKit.panel(UiKit.BG3, col, 8)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		cv.add_child(UiKit.title(cmd.title, 14, col.lightened(0.3)))
		cv.add_child(UiKit.label(cmd.desc, 11, UiKit.TEXT2))
		var btn := UiKit.button("%s (%s)" % [cmd.title, cmd.cost_text()], col)
		btn.disabled = not cmd.can_execute() or (cmd.id == "pray" and GameState.stress_resolvable <= 0)
		var c_ref: EstateCommand = cmd
		btn.pressed.connect(func(): _run_estate_command(c_ref, def))
		cv.add_child(btn)
		care_row.add_child(card)

	# 하단 후유증/패널티 치료 목록
	vbox.add_child(UiKit.label("⚕️ 영구 부상 · 트라우마 시술 대상 (현재 치료소 성공률: %d%%)" % GameState.heal_success_rate(), 13, UiKit.GOLD))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	var injured := GameState.injured_mercs()
	if injured.is_empty():
		var empty_p := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
		empty_p.add_child(UiKit.label("✅ 현재 심각한 부상(패널티)을 입은 용병이 없습니다.", 13, UiKit.GREEN))
		list.add_child(empty_p)
		return

	for m in injured:
		for pen in m.penalties.duplicate():
			var row := UiKit.panel(UiKit.BG3, UiKit.RED, 8)
			var rh := HBoxContainer.new()
			rh.add_theme_constant_override("separation", 10)
			row.add_child(rh)

			var port := VillageVisuals.HeroPortraitCanvas.new()
			port.category = m.category
			port.grade = m.grade
			port.custom_minimum_size = Vector2(42, 42)
			rh.add_child(port)

			var info := VBoxContainer.new()
			info.size_flags_horizontal = SIZE_EXPAND_FILL
			info.add_child(UiKit.label("%s (%s Lv.%d)" % [m.merc_name, m.job, m.level], 13, UiKit.WHITE))
			info.add_child(UiKit.label("후유증: %s" % pen, 12, UiKit.RED))
			rh.add_child(info)

			var btn_cure := UiKit.primary_button("외과 시술 (80G · %d%%)" % GameState.heal_success_rate(), UiKit.GOLD)
			btn_cure.disabled = not GameState.can_afford(80)
			btn_cure.pressed.connect(func():
				var ok := GameState.treat_penalty(m, pen, 80)
				_popup_notice = "%s의 [%s] 치료 %s!" % [m.merc_name, pen, "성공 (완치됨)" if ok else "실패 (흉터가 남음)"]
				_open_large_building_popup(def)
			)
			rh.add_child(btn_cure)
			list.add_child(row)


# ── [4] 영주저택 대형 팝업 컨텐츠 (영주 통치 결단 + 전 시설 증축 총람) ──
func _populate_manor_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	vbox.add_child(UiKit.label("👑 영주 통치 결단 (행동력을 소비하여 영지 위기를 관리합니다)", 13, UiKit.GOLD))

	var decree_row := HBoxContainer.new()
	decree_row.add_theme_constant_override("separation", 10)
	vbox.add_child(decree_row)

	for cmd in EstateCommand.catalog("manor"):
		var dc := UiKit.panel(UiKit.BG3, UiKit.BORDER2, 8)
		dc.size_flags_horizontal = SIZE_EXPAND_FILL
		var dv := VBoxContainer.new()
		dv.add_theme_constant_override("separation", 5)
		dc.add_child(dv)
		dv.add_child(UiKit.title(cmd.title, 14, UiKit.GOLD2))
		dv.add_child(UiKit.label(cmd.desc, 11, UiKit.TEXT2))
		var b := UiKit.button("집행 (%s)" % cmd.cost_text(), UiKit.GOLD)
		b.disabled = not cmd.can_execute()
		var c_ref: EstateCommand = cmd
		b.pressed.connect(func(): _run_estate_command(c_ref, def))
		dv.add_child(b)
		decree_row.add_child(dc)

	vbox.add_child(UiKit.label("🏗️ 영지 10대 시설 증축 총람", 13, UiKit.GOLD))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for bdef in _building_defs:
		if bdef.id == "dungeon_gate":
			continue
		var bn: String = bdef.name
		var blv: int = GameState.buildings.get(bn, 1)
		var card := UiKit.panel(UiKit.BG3, UiKit.BORDER, 6)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 8)
		card.add_child(ch)

		ch.add_child(UiKit.label(bdef.icon, 20, UiKit.WHITE))
		var cv := VBoxContainer.new()
		cv.size_flags_horizontal = SIZE_EXPAND_FILL
		cv.add_child(UiKit.label("%s  Lv.%d" % [bn, blv], 13, UiKit.WHITE))
		cv.add_child(UiKit.label(bdef.tag, 10, UiKit.TEXT2))
		ch.add_child(cv)

		if blv >= 5:
			ch.add_child(UiKit.chip("MAX", UiKit.GOLD))
		else:
			var c := GameState.upgrade_cost(bn)
			var up_btn := UiKit.button("증축 (%dG)" % c.gold, UiKit.GOLD)
			up_btn.disabled = not GameState.can_upgrade(bn)
			up_btn.pressed.connect(func():
				if GameState.upgrade_building(bn):
					_popup_notice = "%s 시설을 Lv.%d(으)로 증축했습니다!" % [bn, blv + 1]
					_open_large_building_popup(def)
			)
			ch.add_child(up_btn)
		grid.add_child(card)


# ── [5] 잡화점 대형 팝업 컨텐츠 ──
func _populate_store_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	var store_lv: int = GameState.buildings.get("잡화점", 1)
	vbox.add_child(UiKit.label("⚖️ 만물상 보급품 진열대 (잡화점 Lv.%d 할인 적용 중: %d%% 할인)" % [store_lv, (store_lv - 1) * 10], 13, UiKit.GOLD))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(grid)

	var item_colors := {"potion": UiKit.GREEN, "incense": UiKit.BLUE, "scroll": UiKit.GOLD, "mana": UiKit.PURPLE}
	for cmd in EstateCommand.catalog("store"):
		var col: Color = item_colors.get(cmd.id, UiKit.GOLD)
		var card := UiKit.panel(UiKit.BG3, col, 10)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		card.size_flags_vertical = SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)

		cv.add_child(UiKit.title(cmd.title, 15, col.lightened(0.3)))
		var dl := UiKit.label(cmd.desc, 12, UiKit.TEXT2)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.size_flags_vertical = SIZE_EXPAND_FILL
		cv.add_child(dl)

		var btn := UiKit.primary_button("구입 및 즉시 사용 (%s)" % cmd.cost_text(), col)
		btn.custom_minimum_size = Vector2(0, 38)
		btn.disabled = not cmd.can_execute()
		var c_ref: EstateCommand = cmd
		btn.pressed.connect(func(): _run_estate_command(c_ref, def))
		cv.add_child(btn)
		grid.add_child(card)


# ── [6] 창고 대형 팝업 컨텐츠 ──
func _populate_warehouse_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	var wh_lv: int = GameState.buildings.get("창고", 1)
	vbox.add_child(UiKit.label("📦 영지 전략 비축고 & 제국 황실 교역소 (창고 Lv.%d)" % wh_lv, 13, UiKit.GOLD))

	var trade_row := HBoxContainer.new()
	trade_row.add_theme_constant_override("separation", 12)
	vbox.add_child(trade_row)

	var wh_colors := {"sell": UiKit.GOLD, "relief": UiKit.BLUE}
	for cmd in EstateCommand.catalog("warehouse"):
		var col: Color = wh_colors.get(cmd.id, UiKit.GOLD)
		var card := UiKit.panel(UiKit.BG3, col, 10)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(UiKit.title(cmd.title, 15, col.lightened(0.3)))
		cv.add_child(UiKit.label(cmd.desc, 12, UiKit.TEXT2))
		var btn := UiKit.primary_button("%s (%s)" % [cmd.title, cmd.cost_text()], col)
		btn.custom_minimum_size = Vector2(0, 38)
		btn.disabled = not cmd.can_execute()
		var c_ref: EstateCommand = cmd
		btn.pressed.connect(func(): _run_estate_command(c_ref, def))
		cv.add_child(btn)
		trade_row.add_child(card)

	# 하단 영지 자산 상세 대시보드
	var dash := UiKit.panel(UiKit.BG3, UiKit.BORDER, 10)
	dash.size_flags_vertical = SIZE_EXPAND_FILL
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	dash.add_child(dv)
	dv.add_child(UiKit.label("📊 영지 재정 및 위기 관리 지표", 14, UiKit.GOLD))
	dv.add_child(UiKit.label("• 보유 금화: %d G   |   보유 마나석: %d 개   |   고용 용병: %d 명" % [GameState.gold, GameState.manastone, GameState.roster.size()], 13, UiKit.WHITE))
	dv.add_child(UiKit.label("• 영지 민심 (%d / 100)" % GameState.morale, 12, UiKit.GOLD))
	dv.add_child(UiKit.progress(GameState.morale, 100, UiKit.GOLD, 10))
	dv.add_child(UiKit.label("• 영지 스트레스 (%d / 100 — 상태: %s)" % [GameState.total_stress(), GameState.stress_stage()], 12, GameState.stress_color()))
	dv.add_child(UiKit.progress(GameState.total_stress(), 100, GameState.stress_color(), 10))
	vbox.add_child(dash)


# ── [7] 대장간 대형 팝업 컨텐츠 (기획서: image1.jpeg & image2.png 100% 반영) ──
func _populate_blacksmith_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	# 대기 중인 유효 용병 목록 확인
	var available_mercs: Array[Mercenary] = []
	for m in GameState.roster:
		if m.status == Mercenary.Status.READY:
			available_mercs.append(m)

	# 기본 선택 용병 유효성 검사
	if _selected_forge_merc == null or not (_selected_forge_merc in available_mercs):
		_selected_forge_merc = available_mercs[0] if not available_mercs.is_empty() else null

	var target_m: Mercenary = _selected_forge_merc

	# ─────────────────────────────────────────────────────────
	# [상단 헤더]: < BACK TO TOWN  |  [골드] GOLD   [루비] RUBIES   [철광석] ORE
	# ─────────────────────────────────────────────────────────
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 16)
	top_h.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(top_h)

	var btn_back := UiKit.gothic_button("◀  BACK TO TOWN", UiKit.GOLD)
	btn_back.custom_minimum_size = Vector2(170, 36)
	btn_back.pressed.connect(func():
		_zoom_out_and_return()
	)
	top_h.add_child(btn_back)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	top_h.add_child(top_spacer)

	# 실시간 자원 HUD (도트 아이콘 적용)
	var res_card := UiKit.panel(Color("161214"), UiKit.BORDER2, 6)
	var res_h := HBoxContainer.new()
	res_h.add_theme_constant_override("separation", 14)
	res_card.add_child(res_h)

	var g_box := HBoxContainer.new()
	g_box.add_theme_constant_override("separation", 5)
	g_box.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_gold.png", 18))
	g_box.add_child(UiKit.label("%d GOLD" % GameState.gold, 13, UiKit.GOLD))
	res_h.add_child(g_box)

	var r_box := HBoxContainer.new()
	r_box.add_theme_constant_override("separation", 5)
	r_box.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ruby.png", 18))
	r_box.add_child(UiKit.label("%d RUBIES" % GameState.manastone, 13, Color("ff3b56")))
	res_h.add_child(r_box)

	var o_box := HBoxContainer.new()
	o_box.add_theme_constant_override("separation", 5)
	o_box.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ore.png", 18))
	o_box.add_child(UiKit.label("%d ORE" % GameState.iron_ore, 13, Color("a0b2c6")))
	res_h.add_child(o_box)
	top_h.add_child(res_card)

	# ─────────────────────────────────────────────────────────
	# [메인 본문]: 좌측 영웅 로스터 + 중앙 (캔버스 + 4종 장비 슬롯) + 우측 UPGRADE INFO 패널
	# ─────────────────────────────────────────────────────────
	var main_h := HBoxContainer.new()
	main_h.add_theme_constant_override("separation", 14)
	main_h.size_flags_horizontal = SIZE_EXPAND_FILL
	main_h.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(main_h)

	# [1. 좌측 로스터 컬럼] (너비 250)
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(250, 0)
	left_col.size_flags_vertical = SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	main_h.add_child(left_col)

	var roster_card := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
	roster_card.size_flags_vertical = SIZE_EXPAND_FILL
	var r_cv := VBoxContainer.new()
	r_cv.add_theme_constant_override("separation", 8)
	roster_card.add_child(r_cv)
	r_cv.add_child(UiKit.title("HERO ROSTER (%d)" % available_mercs.size(), 13, UiKit.GOLD))

	var hero_scroll := ScrollContainer.new()
	hero_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	r_cv.add_child(hero_scroll)

	var hero_list := VBoxContainer.new()
	hero_list.size_flags_horizontal = SIZE_EXPAND_FILL
	hero_list.add_theme_constant_override("separation", 6)
	hero_scroll.add_child(hero_list)

	if available_mercs.is_empty():
		hero_list.add_child(UiKit.label("대기 중인 영웅이 없습니다.", 12, UiKit.TEXT2))
	else:
		for m in available_mercs:
			var is_sel := (m == _selected_forge_merc)
			var b_col := Color("f6d355") if is_sel else UiKit.BORDER
			var bg_c := Color("2a2016") if is_sel else Color("141116")
			var h_panel := UiKit.panel(bg_c, b_col, 6)
			h_panel.mouse_filter = MOUSE_FILTER_PASS

			var hh := HBoxContainer.new()
			hh.add_theme_constant_override("separation", 8)
			h_panel.add_child(hh)

			var port := VillageVisuals.HeroPortraitCanvas.new()
			port.category = m.category
			port.grade = m.grade
			port.hero_name = m.merc_name
			port.custom_minimum_size = Vector2(44, 44)
			hh.add_child(port)

			var iv := VBoxContainer.new()
			iv.size_flags_horizontal = SIZE_EXPAND_FILL
			iv.add_theme_constant_override("separation", 2)
			iv.add_child(UiKit.title("%s" % m.merc_name, 12, UiKit.GOLD if is_sel else UiKit.WHITE))
			iv.add_child(UiKit.label("LVL %d %s" % [m.level, m.job], 10, UiKit.TEXT2))
			iv.add_child(UiKit.progress(m.hp, m.max_hp, Color("22b8ff"), 4))
			hh.add_child(iv)

			var cur_m: Mercenary = m
			h_panel.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
					_selected_forge_merc = cur_m
					_open_large_building_popup(def)
			)
			hero_list.add_child(h_panel)

	left_col.add_child(roster_card)

	# [2. 중앙 컬럼]: 대장간 내부 캔버스 + 하단 4종 장비 슬롯 패널
	var center_col := VBoxContainer.new()
	center_col.size_flags_horizontal = SIZE_EXPAND_FILL
	center_col.size_flags_vertical = SIZE_EXPAND_FILL
	center_col.add_theme_constant_override("separation", 8)
	main_h.add_child(center_col)

	# 2-A. 드워프 모루/화덕 캔버스 (상단 약 340px)
	var forge_holder := Control.new()
	forge_holder.custom_minimum_size = Vector2(0, 340)
	forge_holder.size_flags_horizontal = SIZE_EXPAND_FILL
	forge_holder.size_flags_vertical = SIZE_EXPAND_FILL
	center_col.add_child(forge_holder)

	var forge_interior := VillageVisuals.BlacksmithInteriorCanvas.new()
	forge_interior.set_anchors_preset(PRESET_FULL_RECT)
	forge_holder.add_child(forge_interior)
	_active_blacksmith_canvas = forge_interior

	# 2-B. 중앙 하단 4칸 장비 슬롯 (WEAPON, ARMOR, HELMET, RING)
	var eq_card := UiKit.panel(Color("161318"), UiKit.BORDER2, 8)
	eq_card.custom_minimum_size = Vector2(0, 110)
	center_col.add_child(eq_card)

	var eq_h := HBoxContainer.new()
	eq_h.alignment = BoxContainer.ALIGNMENT_CENTER
	eq_h.add_theme_constant_override("separation", 24)
	eq_card.add_child(eq_h)

	var slots_data := [
		{"id": "weapon", "label": "WEAPON", "level": target_m.weapon_level if target_m else 1},
		{"id": "armor", "label": "ARMOR", "level": target_m.armor_level if target_m else 1},
		{"id": "helmet", "label": "HELMET", "level": target_m.helmet_level if target_m else 1},
		{"id": "ring", "label": "RING", "level": target_m.ring_level if target_m else 1}
	]

	for s_info in slots_data:
		var sid: String = s_info.id
		var is_s_sel: bool = (_selected_forge_slot == sid)
		var s_box := VBoxContainer.new()
		s_box.alignment = BoxContainer.ALIGNMENT_CENTER
		s_box.add_theme_constant_override("separation", 4)
		s_box.mouse_filter = MOUSE_FILTER_PASS

		# 상단 슬롯 레이블
		s_box.add_child(UiKit.label(s_info.label, 10, UiKit.GOLD if is_s_sel else UiKit.TEXT2))

		# 아이콘 캔버스
		var icon_cv := VillageVisuals.EquipmentIconCanvas.new()
		icon_cv.slot_type = sid
		icon_cv.item_level = int(s_info.level)
		icon_cv.is_selected = is_s_sel
		icon_cv.custom_minimum_size = Vector2(58, 58)
		s_box.add_child(icon_cv)

		# 하단 레벨 레이블
		s_box.add_child(UiKit.label("+%d강" % int(s_info.level), 11, UiKit.GOLD2 if is_s_sel else UiKit.WHITE))

		# 클릭 시 장비 슬롯 전환
		var clicked_sid: String = sid
		s_box.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_selected_forge_slot = clicked_sid
				_open_large_building_popup(def)
		)
		eq_h.add_child(s_box)

	# [3. 우측 UPGRADE INFO 컬럼] (너비 290)
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(290, 0)
	right_col.size_flags_vertical = SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 8)
	main_h.add_child(right_col)

	var info_panel := UiKit.panel(Color("181419"), UiKit.BORDER2, 10)
	info_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 10)
	info_panel.add_child(iv)

	iv.add_child(UiKit.title("UPGRADE INFO", 15, UiKit.GOLD))
	iv.add_child(UiKit.divider())

	if target_m != null:
		var cur_slot_lv: int = 1
		var slot_kr_name := "무기"
		match _selected_forge_slot:
			"weapon":
				cur_slot_lv = target_m.weapon_level
				slot_kr_name = "무기"
			"armor":
				cur_slot_lv = target_m.armor_level
				slot_kr_name = "갑옷"
			"helmet":
				cur_slot_lv = target_m.helmet_level
				slot_kr_name = "투구"
			"ring":
				cur_slot_lv = target_m.ring_level
				slot_kr_name = "장신구"

		var next_slot_lv := cur_slot_lv + 1
		iv.add_child(UiKit.label("대상: %s (+%d → +%d강)" % [slot_kr_name, cur_slot_lv, next_slot_lv], 13, UiKit.WHITE))

		# 성공 확률: 기본 85%, 레벨당 -7%, 최소 40%
		var success_rate := clampi(85 - (cur_slot_lv - 1) * 7, 40, 95)
		iv.add_child(UiKit.label("SUCCESS RATE: %d%%" % success_rate, 12, UiKit.GREEN))
		iv.add_child(UiKit.progress(success_rate, 100, UiKit.GREEN, 8))

		iv.add_child(UiKit.divider())
		iv.add_child(UiKit.label("REQUIRED MATERIALS:", 11, UiKit.GOLD))

		# 요구 재료: 철광석 x10 (레벨당 +5), 마나석 x1 (3강 이상 시 x2), 골드 300G (레벨당 +150G)
		var req_ore := 10 + (cur_slot_lv - 1) * 5
		var req_mana := 1 if cur_slot_lv >= 2 else 0
		if cur_slot_lv >= 4:
			req_mana = 2
		var req_gold := 300 + (cur_slot_lv - 1) * 150

		var has_ore := (GameState.iron_ore >= req_ore)
		var has_mana := (GameState.manastone >= req_mana)
		var has_gold := (GameState.gold >= req_gold)
		var can_forge := has_ore and has_mana and has_gold

		# 1. 철광석 행 (도트 아이콘 + 부족 시 빨간색 글씨)
		var ore_c := UiKit.WHITE if has_ore else UiKit.RED
		var ore_txt := "IRON ORE  x%d  (보유: %d)" % [req_ore, GameState.iron_ore]
		if not has_ore:
			ore_txt += " [부족!]"
		var ore_row := HBoxContainer.new()
		ore_row.add_theme_constant_override("separation", 6)
		ore_row.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ore.png", 16))
		ore_row.add_child(UiKit.label(ore_txt, 12, ore_c))
		iv.add_child(ore_row)

		# 2. 마나석 행 (부족 시 빨간색 글씨)
		if req_mana > 0:
			var mana_c := UiKit.WHITE if has_mana else UiKit.RED
			var mana_txt := "MAGIC DUST  x%d  (보유: %d)" % [req_mana, GameState.manastone]
			if not has_mana:
				mana_txt += " [부족!]"
			var mana_row := HBoxContainer.new()
			mana_row.add_theme_constant_override("separation", 6)
			mana_row.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ruby.png", 16))
			mana_row.add_child(UiKit.label(mana_txt, 12, mana_c))
			iv.add_child(mana_row)

		# 3. 골드 행 (부족 시 빨간색 글씨)
		var gold_c := UiKit.GOLD2 if has_gold else UiKit.RED
		var gold_txt := "%d GOLD  (보유: %d)" % [req_gold, GameState.gold]
		if not has_gold:
			gold_txt += " [부족!]"
		var gold_row := HBoxContainer.new()
		gold_row.add_theme_constant_override("separation", 6)
		gold_row.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_gold.png", 16))
		gold_row.add_child(UiKit.label(gold_txt, 12, gold_c))
		iv.add_child(gold_row)

		var iv_spacer := Control.new()
		iv_spacer.size_flags_vertical = SIZE_EXPAND_FILL
		iv.add_child(iv_spacer)

		# 대형 황금 [ FORGE UPGRADE ] 버튼
		var btn_forge := UiKit.gothic_button("⚒️  FORGE UPGRADE", UiKit.GOLD)
		btn_forge.custom_minimum_size = Vector2(0, 52)
		btn_forge.disabled = not can_forge

		btn_forge.pressed.connect(func():
			if not can_forge:
				return
			if not GameState.spend_forge(req_gold, req_ore, req_mana):
				return

			btn_forge.disabled = true
			forge_interior.current_state = VillageVisuals.BlacksmithInteriorCanvas.DwarfState.HAMMERING

			var is_success := (GameState.rng().randi_range(1, 100) <= success_rate)

			# 4번의 모루질과 화면 전체 플래시 빛 연출 (타격 간격 0.35초)
			var tw := create_tween()
			for strike in range(4):
				tw.tween_callback(func():
					forge_interior.trigger_hammer_strike()
				)
				tw.tween_interval(0.35)

			# 4회 타격 종료 후 결과 연출 및 데이터 반영
			tw.chain().tween_callback(func():
				if is_success:
					match _selected_forge_slot:
						"weapon":
							target_m.weapon_level += 1
							target_m.attack += 2
						"armor":
							target_m.armor_level += 1
							target_m.max_hp += 8
							target_m.hp = mini(target_m.hp + 8, target_m.max_hp)
						"helmet":
							target_m.helmet_level += 1
							target_m.max_hp += 5
						"ring":
							target_m.ring_level += 1
							target_m.attack += 1

					forge_interior.current_state = VillageVisuals.BlacksmithInteriorCanvas.DwarfState.SUCCESS
					_popup_notice = "🎉 강화 대성공! [%s]의 %s가 +%d강이 되었습니다!" % [target_m.merc_name, slot_kr_name, cur_slot_lv + 1]
				else:
					forge_interior.current_state = VillageVisuals.BlacksmithInteriorCanvas.DwarfState.FAIL
					_popup_notice = "💨 강화 실패... 아쉽게도 이번 제련은 성공하지 못했습니다."

				GameState.roster_changed.emit()

				# 기획서 규칙: 강화 버튼 클릭 시 자동 저장
				var sm = get_node_or_null("/root/SaveManager")
				if sm != null and sm.has_method("auto_save"):
					sm.auto_save()

				# 1.5초 후 대장간 팝업 UI 상태 갱신
				var reset_tw := create_tween()
				reset_tw.tween_interval(1.5)
				reset_tw.tween_callback(func():
					_open_large_building_popup(def)
				)
			)
		)
		iv.add_child(btn_forge)
	else:
		iv.add_child(UiKit.label("좌측 목록에서 강화를 진행할 영웅을 먼저 선택해 주세요.", 12, UiKit.TEXT2))

	right_col.add_child(info_panel)



# ── [8] 마법사학회 대형 팝업 컨텐츠 ──
func _populate_magic_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	var mg_lv: int = GameState.buildings.get("마법사학회", 1)
	vbox.add_child(UiKit.label("🔮 비전 마법사학회 — 차원 균열 제어 및 마나 연성 연구실 (Lv.%d)" % mg_lv, 14, UiKit.GOLD))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(row)

	var mg_colors := {"suppress": UiKit.PURPLE, "synth": UiKit.BLUE}
	for cmd in EstateCommand.catalog("magic"):
		var col: Color = mg_colors.get(cmd.id, UiKit.PURPLE)
		var card := UiKit.panel(UiKit.BG3, col, 10)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		card.add_child(v)
		v.add_child(UiKit.title(cmd.title, 16, col.lightened(0.35)))
		v.add_child(UiKit.label(cmd.desc, 12, UiKit.TEXT2))
		if cmd.id == "suppress":
			v.add_child(UiKit.label("현재 던전 활성도: %d%%   |   몬스터 강화: +%d단계" % [GameState.dungeon_activity, GameState.monster_tier], 12, UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GOLD))
		else:
			v.add_child(UiKit.label("현재 보유 마나석: %d개" % GameState.manastone, 12, UiKit.BLUE.lightened(0.3)))
		var sp := Control.new()
		sp.size_flags_vertical = SIZE_EXPAND_FILL
		v.add_child(sp)
		var btn := UiKit.primary_button("%s (%s)" % [cmd.title, cmd.cost_text()], col)
		btn.custom_minimum_size = Vector2(0, 42)
		btn.disabled = not cmd.can_execute()
		var c_ref: EstateCommand = cmd
		btn.pressed.connect(func(): _run_estate_command(c_ref, def))
		v.add_child(btn)
		row.add_child(card)


# ── [9] 훈련장 대형 팝업 컨텐츠 ──
func _populate_training_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	var tr_lv: int = GameState.buildings.get("훈련장", 1)
	var hp_gain: int = 10 + (tr_lv - 1) * 4
	var atk_gain: int = 2 + int(tr_lv / 2)

	vbox.add_child(UiKit.label("🎯 전술 연병장 — 실전 모의 훈련 시 레벨 +1 상승, 최대 체력 +%d, 공격력 +%d 성장" % [hp_gain, atk_gain], 13, UiKit.GOLD))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for m in GameState.roster:
		if m.status != Mercenary.Status.READY:
			continue
		var card := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		card.add_child(h)

		var port := VillageVisuals.HeroPortraitCanvas.new()
		port.category = m.category
		port.grade = m.grade
		port.custom_minimum_size = Vector2(46, 46)
		h.add_child(port)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = SIZE_EXPAND_FILL
		info.add_child(UiKit.title("%s  (%s Lv.%d / 10)" % [m.merc_name, m.job, m.level], 14, UiKit.WHITE))
		info.add_child(UiKit.label("HP: %d/%d   ·   공격력: %d   ·   등급: %s" % [m.hp, m.max_hp, m.attack, m.grade], 12, UiKit.TEXT2))
		h.add_child(info)

		var train_cmd := EstateCommand.for_merc("train", m)
		var btn_train := UiKit.primary_button("%s (%s)" % [train_cmd.title, train_cmd.cost_text()], UiKit.GREEN)
		btn_train.custom_minimum_size = Vector2(190, 38)
		btn_train.disabled = not train_cmd.can_execute()
		btn_train.pressed.connect(func(): _run_estate_command(train_cmd, def))
		h.add_child(btn_train)
		list.add_child(card)


# ── [10] 기념관 대형 팝업 컨텐츠 ──
func _populate_memorial_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	var honor_cmd: EstateCommand = EstateCommand.catalog("memorial")[0]

	var top_card := UiKit.panel(UiKit.BG3, UiKit.BLUE, 10)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	top_card.add_child(th)

	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.add_child(UiKit.title(honor_cmd.title, 15, UiKit.GOLD2))
	tv.add_child(UiKit.label(honor_cmd.desc, 12, UiKit.TEXT2))
	th.add_child(tv)

	var btn_honor := UiKit.primary_button("헌화 의식 거행 (%s)" % honor_cmd.cost_text(), UiKit.BLUE)
	btn_honor.custom_minimum_size = Vector2(180, 40)
	btn_honor.disabled = not honor_cmd.can_execute()
	btn_honor.pressed.connect(func(): _run_estate_command(honor_cmd, def))
	th.add_child(btn_honor)
	vbox.add_child(top_card)

	vbox.add_child(UiKit.label("🏛️ 전사자 및 실종자 위령비 기록 (%d위)" % GameState.death_log.size(), 13, UiKit.GOLD))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if GameState.death_log.is_empty():
		var empty_p := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
		empty_p.add_child(UiKit.label("✨ 아직 희생된 영웅이 없습니다. 모든 원정대가 살아 돌아왔습니다.", 13, UiKit.TEXT2))
		list.add_child(empty_p)
		return

	for rec in GameState.death_log:
		var row := UiKit.panel(UiKit.BG3, UiKit.RED, 8)
		var rh := HBoxContainer.new()
		row.add_child(rh)
		var state_str := "실종" if rec.get("missing", false) else "전사"
		rh.add_child(UiKit.label("✝  %s  —  %s Lv.%d   (%d일차 원정 중 %s)" % [
			rec.get("name", "무명 용병"), rec.get("job", "전사"), int(rec.get("level", 1)), int(rec.get("day", 1)), state_str
		], 13, UiKit.TEXT))
		list.add_child(row)


# ── [11] 어둠의 균열(던전 원정 관문) 대형 팝업 컨텐츠 ──
func _populate_dungeon_popup(vbox: VBoxContainer, def: Dictionary) -> void:
	vbox.add_child(UiKit.label("⚔️ 원정 출진 파티 편성 (%d / %d명) — 최소 1명 이상의 용병을 편성하면 즉시 던전 전투로 진입합니다." % [GameState.party.size(), GameState.MAX_PARTY], 13, UiKit.GOLD2))

	# 1. 5인 파티 비주얼 슬롯
	vbox.add_child(_build_visual_party_slots(def))

	# 2. 대기 용병 빠른 편성 스크롤
	vbox.add_child(UiKit.label("🛡️ 출진 대기 용병 (클릭하여 원정대에 즉시 합류/제외)", 12, UiKit.TEXT2))
	vbox.add_child(_build_visual_roster_scroll(true, def))

	# 3. 하단 대형 출진 버튼 바
	var launch_bar := HBoxContainer.new()
	launch_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(launch_bar)

	var btn_prep_scene := UiKit.button("원정 준비 화면으로 보기 ↗", UiKit.GOLD)
	btn_prep_scene.custom_minimum_size = Vector2(210, 46)
	btn_prep_scene.pressed.connect(func():
		get_tree().change_scene_to_file(GameState.SCENE_PREP)
	)
	launch_bar.add_child(btn_prep_scene)

	var btn_launch := UiKit.primary_button("⚔️ 어둠의 균열로 원정 출진! (전투 개시)", UiKit.RED)
	btn_launch.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_launch.custom_minimum_size = Vector2(0, 46)
	btn_launch.disabled = GameState.party.is_empty()
	btn_launch.pressed.connect(func():
		if not GameState.party.is_empty():
			get_tree().change_scene_to_file(GameState.SCENE_DUNGEON)
	)
	launch_bar.add_child(btn_launch)


## 5인 원정 파티를 시각적인 캐릭터 초상화 카드로 가로 배치하는 공통 위젯
func _build_visual_party_slots(def: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	for i in range(GameState.MAX_PARTY):
		var slot := UiKit.panel(UiKit.BG3, UiKit.GOLD if i < GameState.party.size() else UiKit.BORDER, 8)
		slot.size_flags_horizontal = SIZE_EXPAND_FILL
		slot.custom_minimum_size = Vector2(0, 108)

		var sv := VBoxContainer.new()
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		sv.add_theme_constant_override("separation", 4)
		slot.add_child(sv)

		if i < GameState.party.size():
			var m: Mercenary = GameState.party[i]
			var top_h := HBoxContainer.new()
			top_h.alignment = BoxContainer.ALIGNMENT_CENTER
			top_h.add_theme_constant_override("separation", 6)
			sv.add_child(top_h)

			var port := VillageVisuals.HeroPortraitCanvas.new()
			port.category = m.category
			port.grade = m.grade
			port.custom_minimum_size = Vector2(36, 36)
			top_h.add_child(port)

			var nv := VBoxContainer.new()
			nv.add_child(UiKit.label(m.merc_name, 12, UiKit.WHITE))
			nv.add_child(UiKit.label("%s Lv.%d" % [m.job, m.level], 10, JobDb.category_color(m.category)))
			top_h.add_child(nv)

			sv.add_child(UiKit.progress(m.hp, m.max_hp, UiKit.GREEN, 5))

			var btn_rm := UiKit.button("파티 제외", UiKit.RED)
			btn_rm.custom_minimum_size = Vector2(0, 24)
			btn_rm.pressed.connect(func():
				GameState.remove_from_party(m)
				_build_village_structures()
				_open_large_building_popup(def)
			)
			sv.add_child(btn_rm)
		else:
			var empty_lbl := UiKit.label("빈 슬롯 #%d\n(대기 용병 추가)" % (i + 1), 11, UiKit.TEXT3)
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sv.add_child(empty_lbl)

		row.add_child(slot)

	return row


## 용병 로스터를 초상화 + 체력바 + 파티 편성 버튼이 있는 2열 비주얼 카드로 렌더링
func _build_visual_roster_scroll(allow_party_toggle: bool, def: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for m in GameState.roster:
		if m.status != Mercenary.Status.READY:
			continue
		var in_party := GameState.party.has(m)
		var card := UiKit.panel(UiKit.BG3, UiKit.GREEN if in_party else UiKit.BORDER, 8)
		card.size_flags_horizontal = SIZE_EXPAND_FILL

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		card.add_child(h)

		var port := VillageVisuals.HeroPortraitCanvas.new()
		port.category = m.category
		port.grade = m.grade
		port.custom_minimum_size = Vector2(44, 44)
		h.add_child(port)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		info.add_child(UiKit.label("[%s] %s (%s Lv.%d)" % [m.grade, m.merc_name, m.job, m.level], 12, UiKit.WHITE))
		info.add_child(UiKit.label("HP %d/%d · 공격력 %d" % [m.hp, m.max_hp, m.attack], 11, UiKit.TEXT2))
		info.add_child(UiKit.progress(m.hp, m.max_hp, UiKit.GREEN, 4))
		h.add_child(info)

		if allow_party_toggle:
			if in_party:
				var b_out := UiKit.button("제외", UiKit.RED)
				b_out.pressed.connect(func():
					GameState.remove_from_party(m)
					_build_village_structures()
					_open_large_building_popup(def)
				)
				h.add_child(b_out)
			else:
				var b_in := UiKit.button("편성", UiKit.GREEN)
				b_in.disabled = (GameState.party.size() >= GameState.MAX_PARTY)
				b_in.pressed.connect(func():
					GameState.add_to_party(m)
					_build_village_structures()
					_open_large_building_popup(def)
				)
				h.add_child(b_in)

		grid.add_child(card)

	return scroll


## 대형 팝업 닫기 및 마을 카메라 부드러운 줌아웃 복귀 ([유한 상태 기계])
func _zoom_out_and_return() -> void:
	if _active_modal != null:
		_active_modal.queue_free()
		_active_modal = null
	_active_interior_canvas = null

	_view_fsm.go(ViewState.ZOOMING_OUT)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_world_container, "scale", Vector2.ONE, 0.32)
	tw.chain().tween_callback(func():
		_view_fsm.go(ViewState.BROWSING)
	)


# ── 상단 HUD 및 하단 노란색 창 1칸 스크롤바 빌드 ──
func _build_hud() -> void:
	for c in _hud_layer.get_children():
		if c != _active_modal:
			c.queue_free()

	# 1. 상단바 (다키스트 던전 스타일 고딕 문장 엠블럼 + 영지 타이틀 및 실시간 자원 칩)
	var top_bar := PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(VIEWPORT_WIDTH, 48)
	top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	top_bar.add_theme_stylebox_override("panel", UiKit.style(Color("0c0a08"), UiKit.BORDER2, 0, 2, 16, 6))
	_hud_layer.add_child(top_bar)
	_top_bar_holder = top_bar

	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 14)
	top_bar.add_child(top_h)

	# 고딕 문장 도트 아이콘 & 영지 타이틀
	top_h.add_child(UiKit.icon_rect("res://assets/sprites/ui/skill_guard.png", 26))
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 1)
	title_box.add_child(UiKit.title("THE ERADEL ESTATE", 15, UiKit.GOLD2))
	title_box.add_child(UiKit.label("제 %d일차 · %s (행동력 %d/%d)" % [GameState.day, GameState.season(), GameState.action_points, GameState.max_action_points], 11, UiKit.TEXT2))
	top_h.add_child(title_box)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	top_h.add_child(spacer)

	# 다키스트 던전 스타일 도트 아이콘 자원/지표 카운터 바
	top_h.add_child(UiKit.icon_chip("res://assets/sprites/ui/icon_gold.png", "%d G" % GameState.gold, UiKit.GOLD))
	top_h.add_child(UiKit.icon_chip("res://assets/sprites/ui/icon_ruby.png", "마나석 %d" % GameState.manastone, UiKit.BLUE))
	top_h.add_child(UiKit.icon_chip("res://assets/sprites/ui/icon_ore.png", "철광석 %d" % GameState.iron_ore, UiKit.TEXT2))
	top_h.add_child(UiKit.chip("민심 %d%%" % GameState.morale, UiKit.GOLD2))
	var act_col := UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GREEN
	top_h.add_child(UiKit.chip("균열 활성 %d%%" % GameState.dungeon_activity, act_col))
	top_h.add_child(UiKit.chip("스트레스 %d/100" % GameState.total_stress(), GameState.stress_color()))

	# 2. 우측 상단 다키스트 던전 스타일 접이식 영웅 로스터 덱 (Hero Roster Dock)
	_build_roster_dock()

	# 3. 화면 양 끝단 카메라 스크롤 화살표 버튼
	var btn_left := Button.new()
	btn_left.text = "‹"
	btn_left.custom_minimum_size = Vector2(38, 68)
	btn_left.position = Vector2(10, (VIEWPORT_HEIGHT - 68) * 0.5)
	btn_left.focus_mode = FOCUS_NONE
	btn_left.add_theme_font_size_override("font_size", 24)
	btn_left.add_theme_stylebox_override("normal", UiKit.style(Color(0.06, 0.05, 0.04, 0.78), UiKit.BORDER2, 8))
	btn_left.pressed.connect(func():
		_target_scroll_x = clampf(_target_scroll_x - 520.0, 0.0, MAX_SCROLL_X)
	)
	_hud_layer.add_child(btn_left)

	var btn_right := Button.new()
	btn_right.text = "›"
	btn_right.custom_minimum_size = Vector2(38, 68)
	btn_right.position = Vector2(VIEWPORT_WIDTH - 48, (VIEWPORT_HEIGHT - 68) * 0.5)
	btn_right.focus_mode = FOCUS_NONE
	btn_right.add_theme_font_size_override("font_size", 24)
	btn_right.add_theme_stylebox_override("normal", UiKit.style(Color(0.06, 0.05, 0.04, 0.78), UiKit.BORDER2, 8))
	btn_right.pressed.connect(func():
		_target_scroll_x = clampf(_target_scroll_x + 520.0, 0.0, MAX_SCROLL_X)
	)
	_hud_layer.add_child(btn_right)

	# 4. 하단 네비게이션 스크롤바 및 시그니처 원정 출진(EMBARK) 대형 버튼
	var btm_container := VBoxContainer.new()
	btm_container.position = Vector2((VIEWPORT_WIDTH - _scroll_track_width) * 0.5, VIEWPORT_HEIGHT - 94)
	btm_container.custom_minimum_size = Vector2(_scroll_track_width, 88)
	btm_container.add_theme_constant_override("separation", 6)
	btm_container.mouse_filter = MOUSE_FILTER_PASS
	_hud_layer.add_child(btm_container)

	# 다키스트 던전 시그니처 붉은색 EMBARK (원정 출진) 대형 버튼
	var embark_h := HBoxContainer.new()
	embark_h.alignment = BoxContainer.ALIGNMENT_CENTER
	btm_container.add_child(embark_h)

	var btn_embark := Button.new()
	btn_embark.text = "⚔️  E M B A R K  ·  어둠의 균열 원정 출진  ⚔️"
	btn_embark.custom_minimum_size = Vector2(380, 36)
	btn_embark.focus_mode = FOCUS_NONE
	btn_embark.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_embark.add_theme_font_size_override("font_size", 14)
	btn_embark.add_theme_color_override("font_color", Color("fff0e8"))
	btn_embark.add_theme_color_override("font_hover_color", Color("ffffff"))
	var embark_sb := StyleBoxFlat.new()
	embark_sb.bg_color = Color("8c1f24")
	embark_sb.border_color = Color("e04c54")
	embark_sb.set_border_width_all(2)
	embark_sb.set_corner_radius_all(6)
	btn_embark.add_theme_stylebox_override("normal", embark_sb)
	var embark_hover_sb := embark_sb.duplicate()
	embark_hover_sb.bg_color = Color("a8272d")
	btn_embark.add_theme_stylebox_override("hover", embark_hover_sb)

	btn_embark.pressed.connect(func():
		_on_building_selected(_building_defs[_building_defs.size() - 1])
	)
	embark_h.add_child(btn_embark)

	# 하단 네비게이션 미니 트랙 스크롤바
	var scroll_root := Control.new()
	scroll_root.custom_minimum_size = Vector2(_scroll_track_width, _scroll_track_height)
	btm_container.add_child(scroll_root)

	_scroll_track = Panel.new()
	_scroll_track.size = Vector2(_scroll_track_width, _scroll_track_height)
	_scroll_track.add_theme_stylebox_override("panel", UiKit.style(Color(0.08, 0.07, 0.05, 0.92), Color("b84038"), 8, 2))
	scroll_root.add_child(_scroll_track)

	# 트랙 위 건물 미니 위치 마커 표시
	for def in _building_defs:
		var ratio_x: float = (def.rect.position.x + def.rect.size.x * 0.5) / WORLD_WIDTH
		var mx: float = ratio_x * _scroll_track_width
		var dot := ColorRect.new()
		dot.color = UiKit.RED if def.id == "dungeon_gate" else UiKit.GOLD
		dot.size = Vector2(4, 12)
		dot.position = Vector2(mx - 2, (_scroll_track_height - 12) * 0.5)
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		_scroll_track.add_child(dot)

	# 노란색 창 1칸 (현재 화면 1280px / 전체 2500px 비율 사각 핸들)
	var thumb_w: float = _scroll_track_width * (VIEWPORT_WIDTH / WORLD_WIDTH)
	_scroll_thumb = Panel.new()
	_scroll_thumb.size = Vector2(thumb_w, _scroll_track_height)
	_scroll_thumb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var thumb_sb := StyleBoxFlat.new()
	thumb_sb.bg_color = Color(0.96, 0.82, 0.28, 0.26)
	thumb_sb.border_color = Color("ffd84a")
	thumb_sb.set_border_width_all(3)
	thumb_sb.set_corner_radius_all(7)
	_scroll_thumb.add_theme_stylebox_override("panel", thumb_sb)
	scroll_root.add_child(_scroll_thumb)

	var thumb_lbl := UiKit.label("◀  드래그하여 영지 화면 이동  ▶", 10, Color("ffe888"))
	thumb_lbl.set_anchors_preset(PRESET_FULL_RECT)
	thumb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thumb_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumb_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	_scroll_thumb.add_child(thumb_lbl)

	_scroll_track.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_is_dragging_scrollbar = true
				_handle_scrollbar_motion(ev.global_position.x)
			else:
				_is_dragging_scrollbar = false
	)
	_scroll_thumb.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_is_dragging_scrollbar = true
			else:
				_is_dragging_scrollbar = false
	)

	_update_scroll_position()


## 다키스트 던전 1 스타일의 우측 접이식 영웅 로스터 패널 (초상화, 레벨 뱃지, 10칸 스트레스 핍, 장비 수치)
func _build_roster_dock() -> void:
	var dock_w: float = 230.0 if _roster_dock_expanded else 44.0
	var dock_panel := PanelContainer.new()
	dock_panel.position = Vector2(VIEWPORT_WIDTH - dock_w - 6, 56)
	dock_panel.size = Vector2(dock_w, 420)
	dock_panel.custom_minimum_size = Vector2(dock_w, 420)
	dock_panel.add_theme_stylebox_override("panel", UiKit.style(Color("0c0a08ee"), UiKit.BORDER2, 8, 2, 6, 6))
	_hud_layer.add_child(dock_panel)
	_roster_dock_panel = dock_panel

	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	dock_panel.add_child(dv)

	# 헤더 바 및 토글 버튼
	var dh := HBoxContainer.new()
	dv.add_child(dh)

	var btn_toggle := Button.new()
	btn_toggle.text = "▶" if not _roster_dock_expanded else "◀"
	btn_toggle.custom_minimum_size = Vector2(32, 26)
	btn_toggle.focus_mode = FOCUS_NONE
	btn_toggle.add_theme_stylebox_override("normal", UiKit.style(UiKit.BG3, UiKit.BORDER, 4))
	btn_toggle.pressed.connect(func():
		_roster_dock_expanded = not _roster_dock_expanded
		_build_hud()
	)
	dh.add_child(btn_toggle)

	if _roster_dock_expanded:
		var dock_title := UiKit.label("영웅 로스터 (%d명)" % GameState.roster.size(), 12, UiKit.GOLD2)
		dock_title.size_flags_horizontal = SIZE_EXPAND_FILL
		dh.add_child(dock_title)

		# 로스터 스크롤 리스트
		var r_scroll := ScrollContainer.new()
		r_scroll.size_flags_vertical = SIZE_EXPAND_FILL
		r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		dv.add_child(r_scroll)

		var r_list := VBoxContainer.new()
		r_list.size_flags_horizontal = SIZE_EXPAND_FILL
		r_list.add_theme_constant_override("separation", 5)
		r_scroll.add_child(r_list)

		for m in GameState.roster:
			var slot := PanelContainer.new()
			var in_party := GameState.party.has(m)
			var border_col := UiKit.GOLD if in_party else UiKit.BORDER
			slot.add_theme_stylebox_override("panel", UiKit.style(Color("16120e"), border_col, 6, 1, 6, 4))
			slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

			var sh := HBoxContainer.new()
			sh.add_theme_constant_override("separation", 8)
			slot.add_child(sh)

			# 초상화
			var port := VillageVisuals.HeroPortraitCanvas.new()
			port.category = m.category
			port.grade = m.grade
			port.custom_minimum_size = Vector2(32, 32)
			sh.add_child(port)

			# 영웅 정보 및 10칸 스트레스 핍 블록
			var info_v := VBoxContainer.new()
			info_v.size_flags_horizontal = SIZE_EXPAND_FILL
			info_v.add_theme_constant_override("separation", 2)
			sh.add_child(info_v)

			var name_h := HBoxContainer.new()
			info_v.add_child(name_h)
			var name_lbl := UiKit.label(m.merc_name, 11, UiKit.WHITE)
			name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			name_h.add_child(name_lbl)

			# 결의 레벨 뱃지 (Lv.N)
			var lv_badge := UiKit.label("Lv.%d" % m.level, 10, UiKit.GOLD2)
			name_h.add_child(lv_badge)

			# 장비 수치 (W: 무기, A: 방어구)
			var eq_lbl := UiKit.label("%s | ⚔+%d 🛡+%d" % [m.job, m.weapon_level, m.armor_level], 9, UiKit.TEXT2)
			info_v.add_child(eq_lbl)

			# 다키스트 던전 시그니처 10칸 분할 스트레스 핍 바
			var pips_h := HBoxContainer.new()
			pips_h.add_theme_constant_override("separation", 2)
			info_v.add_child(pips_h)
			# 영지 스트레스 비율(0~10)을 블록으로 시각화
			var filled_pips: int = mini(10, int(round(float(GameState.total_stress()) / 10.0)))
			for p_idx in range(10):
				var pip := ColorRect.new()
				pip.custom_minimum_size = Vector2(10, 4)
				pip.color = Color("e03838") if p_idx < filled_pips else Color("2a201a")
				pips_h.add_child(pip)

			r_list.add_child(slot)
	else:
		# 접힌 상태 아이콘
		var collapsed_lbl := UiKit.label("👥\n로\n스\n터", 11, UiKit.GOLD)
		collapsed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dv.add_child(collapsed_lbl)


## 하단 스크롤바 드래그/클릭 시 카메라 위치 즉시 갱신
func _handle_scrollbar_motion(global_mouse_x: float) -> void:
	if _scroll_track == null or _scroll_thumb == null:
		return
	var track_gx: float = _scroll_track.global_position.x
	var thumb_w: float = _scroll_thumb.size.x
	var max_tx: float = _scroll_track_width - thumb_w
	var clamped_x := clampf(global_mouse_x - track_gx - thumb_w * 0.5, 0.0, max_tx)
	var ratio := clamped_x / max_tx
	_target_scroll_x = ratio * MAX_SCROLL_X
	_current_scroll_x = _target_scroll_x
	_update_scroll_position()


## 자원/로스터/스트레스 변동 시 상단 HUD 및 마을 건물 배지 즉시 갱신
func _on_state_updated() -> void:
	_build_hud()
	_build_village_structures()


func _on_game_over() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_GAMEOVER)
