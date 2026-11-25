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
var _active_blacksmith_canvas: Control = null
var _roster_dock_expanded: bool = true
var _roster_dock_panel: Control = null

# ── 노드 참조 ([업데이트 메서드] 대상 컬렉션 포함) ──
var village: EstateVillage
## 건물 종류(def.type) → 팝업 인스턴스 캐시(선택 상태가 영지 세션 동안 유지되도록 재사용)
var _popups: Dictionary = {}
var _active_interior_canvas: VillageVisuals.BuildingInteriorCanvas = null
var _interior_canvas: Control = null
var _hud_layer: CanvasLayer
var _modal_layer: CanvasLayer
var _top_bar_holder: Control
var _status_strip_holder: Control = null
var _curse_popover: Control = null
var _succession_banner: Control = null
var _confirm_overlay: Control = null
var _btn_rest_day: Button = null
var _sfx_player: AudioStreamPlayer = null
var _village_dirty: bool = false
var _game_over_transitioning: bool = false
var _status_Row_holder: HBoxContainer
var _scroll_track: Panel
var _scroll_thumb: Panel
var _scroll_track_width: float = 880.0
var _scroll_track_height: float = 26.0
var _atmosphere_overlay: ColorRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_view_fsm()

	# 1~3. 마을 월드 컨테이너·지형·건물 레이어 (EstateVillage 가 구성)
	village = EstateVillage.new(self)
	village.build_world()

	# 4. 상단 HUD·하단 스크롤바 레이어(layer=1) 및 건물 대형 모달 전용 상위 레이어(layer=20)
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 1
	add_child(_hud_layer)
	_atmosphere_overlay = UiKit.attach_gothic_atmosphere(_hud_layer, 0.36, 0.14, 0.0)
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 20
	add_child(_modal_layer)
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)
	_build_hud()
	_maybe_show_unseen_succession_banner()

	# 5. [옵저버] GameState 시그널 구독 — 상태가 바뀌면 자동으로 HUD 와 건물 배지가 갱신된다
	GameState.resources_changed.connect(_on_resources_changed)
	GameState.stress_changed.connect(_on_stress_changed)
	GameState.relics_changed.connect(_on_relics_changed)
	GameState.party_changed.connect(_on_roster_or_party_changed)
	GameState.roster_changed.connect(_on_roster_or_party_changed)
	GameState.game_over.connect(_on_game_over)
	var dc := get_node_or_null("/root/DebugConsole")
	if dc != null and dc.has_signal("cheat_applied"):
		dc.connect("cheat_applied", _on_debug_cheat_applied)

	# 시작 시 마을 중심부(용병모집소~영주저택~창고가 한눈에 들어오는 구도)로 스크롤 설정
	_target_scroll_x = 180.0
	_current_scroll_x = 180.0
	_update_scroll_position()


## [유한 상태 기계] 마을 탐색 ↔ 줌인 ↔ 대형 팝업 ↔ 줌아웃 상태 전이 규칙 등록
func _setup_view_fsm() -> void:
	_view_fsm.add(ViewState.BROWSING, func(): _is_zooming = false, Callable(), [ViewState.ZOOMING_IN, ViewState.MODAL_OPEN])
	_view_fsm.add(ViewState.ZOOMING_IN, func(): _is_zooming = true, Callable(), [ViewState.MODAL_OPEN, ViewState.BROWSING])
	_view_fsm.add(ViewState.MODAL_OPEN, func(): _is_zooming = false, Callable(), [ViewState.MODAL_OPEN, ViewState.ZOOMING_OUT, ViewState.BROWSING])
	_view_fsm.add(ViewState.ZOOMING_OUT, func(): _is_zooming = true, Callable(), [ViewState.BROWSING, ViewState.MODAL_OPEN])
	_view_fsm.go(ViewState.BROWSING)


## [업데이트 메서드] 단일 중앙 게임 루프에서 지형·건물·내부 쇼케이스·말풍선·카메라를 일괄 갱신한다.
func _process(delta: float) -> void:
	village.tick(delta)
	if is_instance_valid(_active_interior_canvas):
		_active_interior_canvas.update_tick(delta)
	if is_instance_valid(_active_blacksmith_canvas) and _active_blacksmith_canvas.has_method("update_tick"):
		_active_blacksmith_canvas.update_tick(delta)

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


## [책임 연쇄] PauseManager 의 ESC 체인에서 호출. 중첩 확인 모달 → 대형 팝업 순으로 최상위 1단계만 닫고 true 를 반환한다.
func try_handle_cancel() -> bool:
	if is_instance_valid(_confirm_overlay):
		_close_confirm_modal()
		return true
	if _active_modal != null:
		_zoom_out_and_return()
		return true
	return false


## 마우스 드래그 패닝, 마우스 휠 스크롤, ESC 팝업 닫기 입력 처리
func _input(event: InputEvent) -> void:
	if is_instance_valid(_confirm_overlay):
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			_close_confirm_modal()
		return

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
				# 1행 상단바(48px) + 2행 상태 스트립(28px) = 76px 이하는 드래그에서 제외
				if event.position.y > 80 and event.position.y < VIEWPORT_HEIGHT - 68:
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
	village.world_container.position.x = -_current_scroll_x

	if _scroll_thumb != null and _scroll_track != null:
		var ratio := clampf(_current_scroll_x / MAX_SCROLL_X, 0.0, 1.0)
		var max_thumb_x := _scroll_track_width - _scroll_thumb.size.x
		_scroll_thumb.position.x = ratio * max_thumb_x














































## 대형 팝업 닫기 및 마을 카메라 부드러운 줌아웃 복귀 ([유한 상태 기계])
func _zoom_out_and_return() -> void:
	if _active_modal != null:
		_active_modal.queue_free()
		_active_modal = null
	_active_interior_canvas = null
	_interior_canvas = null
	_active_blacksmith_canvas = null
	_current_open_def = {}

	_view_fsm.go(ViewState.ZOOMING_OUT)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(village.world_container, "scale", Vector2.ONE, 0.32)
	tw.chain().tween_callback(func():
		_view_fsm.go(ViewState.BROWSING)
	)


# ── 상단 HUD 및 하단 노란색 창 1칸 스크롤바 빌드 (한 번만 호출. 값이 바뀌는 상단바·로스터 덱은 시그널로 각자 갱신) ──
func _build_hud() -> void:
	if is_instance_valid(_atmosphere_overlay):
		_hud_layer.move_child(_atmosphere_overlay, 0)

	# 1~2. 상단바와 우측 영웅 로스터 덱 (이후 상태 변동 시 각각 따로 다시 그린다)
	_rebuild_top_bar()
	_rebuild_roster_dock()

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

	# 4. 하단 네비게이션 스크롤바 및 시그니처 원정 출진(EMBARK) 컴팩트 바 (하단 바닥 테두리 비잘림 여백 확보)
	var btm_container := VBoxContainer.new()
	btm_container.position = Vector2((VIEWPORT_WIDTH - _scroll_track_width) * 0.5, VIEWPORT_HEIGHT - 84)
	btm_container.custom_minimum_size = Vector2(_scroll_track_width, 68)
	btm_container.add_theme_constant_override("separation", 4)
	btm_container.mouse_filter = MOUSE_FILTER_PASS
	_hud_layer.add_child(btm_container)

	# 다키스트 던전 시그니처 붉은색 EMBARK (원정 출진) 버튼
	var embark_h := HBoxContainer.new()
	embark_h.alignment = BoxContainer.ALIGNMENT_CENTER
	btm_container.add_child(embark_h)

	var btn_embark := Button.new()
	btn_embark.text = "⚔️  E M B A R K  ·  어둠의 균열 원정 출진  ⚔️"
	btn_embark.custom_minimum_size = Vector2(360, 30)
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
		village.zoom_to(BuildingDb.DEFS[BuildingDb.DEFS.size() - 1])
	)
	embark_h.add_child(btn_embark)

	# 전멸 소프트락 방지용 비상 구제 [하루 휴식] 버튼 (조건 미충족 시 숨김)
	_btn_rest_day = UiKit.button("🕯️ 비상 휴식 (하루 넘기기)", UiKit.GOLD)
	_btn_rest_day.custom_minimum_size = Vector2(200, 30)
	_btn_rest_day.focus_mode = FOCUS_ALL
	_btn_rest_day.visible = GameState.can_rest_estate_day()
	_btn_rest_day.pressed.connect(_on_rest_day_pressed)
	embark_h.add_child(_btn_rest_day)

	# 하단 네비게이션 미니 트랙 스크롤바
	var scroll_root := Control.new()
	scroll_root.custom_minimum_size = Vector2(_scroll_track_width, _scroll_track_height)
	btm_container.add_child(scroll_root)

	_scroll_track = Panel.new()
	_scroll_track.size = Vector2(_scroll_track_width, _scroll_track_height)
	_scroll_track.add_theme_stylebox_override("panel", UiKit.style(Color(0.08, 0.07, 0.05, 0.92), Color("b84038"), 8, 2))
	scroll_root.add_child(_scroll_track)

	# 노란색 창 1칸 (현재 화면 1280px / 전체 2500px 비율 사각 핸들 — 내부 글씨·위치 마커 제거)
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


## 상단바(영지 타이틀·일차·자원 칩)만 새로 만든다. 자원/스트레스 변동 시 호출되며 다른 HUD 요소는 건드리지 않는다.
func _rebuild_top_bar() -> void:
	if is_instance_valid(_top_bar_holder):
		_top_bar_holder.queue_free()
	# 1. 상단바 (다키스트 던전 스타일 고딕 문장 엠블럼 + 영지 타이틀 및 실시간 자원 칩)
	var top_bar := PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(VIEWPORT_WIDTH, 48)
	top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	top_bar.add_theme_stylebox_override("panel", UiKit.style(Color("0c0a08"), UiKit.BORDER2, 0, 2, 10, 6))
	_hud_layer.add_child(top_bar)
	_top_bar_holder = top_bar

	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 8)
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

	# 다키스트 던전 스타일 도트 아이콘 자원/지표 카운터 바 (민심은 2행 상태 스트립에서 상세 표시해 우측 오버플로우 방지)
	top_h.add_child(UiKit.icon_chip("res://assets/sprites/ui/icon_gold.png", "%d G" % GameState.gold, UiKit.GOLD))
	top_h.add_child(UiKit.icon_chip("res://assets/sprites/ui/icon_ruby.png", "마나석 %d" % GameState.manastone, UiKit.BLUE))
	top_h.add_child(UiKit.icon_chip("res://assets/sprites/ui/icon_ore.png", "철광석 %d" % GameState.iron_ore, UiKit.TEXT2))
	var act_col := UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GREEN
	top_h.add_child(UiKit.chip("균열 활성 %d%%" % GameState.dungeon_activity, act_col))
	var crown_tag := " 👑10잠금" if GameState.active_curses.has("curse_heavy_crown") else ""
	top_h.add_child(UiKit.chip("스트레스 %d/100%s" % [GameState.total_stress(), crown_tag], GameState.stress_color()))
	# 갱신 후에도 원래 렌더 순서(대기 중인 화살표 버튼보다 아래)를 유지한다
	_hud_layer.move_child(top_bar, 1)
	_rebuild_status_strip()
	if is_instance_valid(_btn_rest_day):
		_btn_rest_day.visible = GameState.can_rest_estate_day()


## 2행 슬림 상태 스트립(1280x28px, y=48..76): 민심 임계 구간, 착취 낙인, 미처리 유품, 원정 축복, 비상 휴식 배너를 표시한다.
func _rebuild_status_strip() -> void:
	if is_instance_valid(_status_strip_holder):
		_status_strip_holder.queue_free()
	var strip := PanelContainer.new()
	strip.position = Vector2(0, 48)
	strip.custom_minimum_size = Vector2(VIEWPORT_WIDTH, 28)
	strip.size = Vector2(VIEWPORT_WIDTH, 28)
	strip.add_theme_stylebox_override("panel", UiKit.style(Color("120e0cee"), UiKit.BORDER, 0, 1, 14, 2))
	_hud_layer.add_child(strip)
	_status_strip_holder = strip
	_hud_layer.move_child(strip, 2)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	strip.add_child(h)

	# 제 N대 세대 배지 + 최대 3개 컴팩트 저주 아이콘 버튼 (24x24, 키보드/마우스 공용 팝오버)
	h.add_child(UiKit.label("제 %d대" % GameState.generation_number, 11, UiKit.GOLD2))
	if GameState.boss_sealed_count > 0 or GameState.endless_cycle > 0:
		h.add_child(UiKit.label("✦봉인 %d · 심연 +%d(×%.1f)" % [GameState.boss_sealed_count, GameState.endless_cycle, GameState.endless_monster_mult()], 11, UiKit.BLUE.lightened(0.3)))
	for cid in GameState.active_curses:
		var info: Dictionary = GameState.CURSE_INFO.get(cid, {"name": cid, "icon": "☠", "desc": ""})
		var cbtn := Button.new()
		cbtn.text = str(info["icon"])
		cbtn.custom_minimum_size = Vector2(24, 22)
		cbtn.focus_mode = FOCUS_ALL
		cbtn.add_theme_font_size_override("font_size", 12)
		cbtn.add_theme_stylebox_override("normal", UiKit.style(Color("261214"), UiKit.RED, 4, 1, 2, 0))
		var cur_cid: String = cid
		cbtn.mouse_entered.connect(func(): _show_curse_popover(cur_cid, cbtn.global_position))
		cbtn.mouse_exited.connect(_hide_curse_popover)
		cbtn.focus_entered.connect(func(): _show_curse_popover(cur_cid, cbtn.global_position))
		cbtn.focus_exited.connect(_hide_curse_popover)
		cbtn.pressed.connect(func(): _show_curse_popover(cur_cid, cbtn.global_position))
		h.add_child(cbtn)

	# 민심 구간 임계 라벨 (75+ 고양 / 25- 동요 / 0 붕괴)
	var m_state := "안정"
	var m_col := UiKit.TEXT2
	if GameState.morale >= 75:
		m_state = "고양 (모집 -10%)"
		m_col = UiKit.GREEN
	elif GameState.morale == 0:
		m_state = "붕괴 (모집 +20% · 스트레스 +4/일)"
		m_col = UiKit.RED
	elif GameState.morale <= 25:
		m_state = "동요 (스트레스 +2/일)"
		m_col = UiKit.GOLD
	h.add_child(UiKit.label("민심 %d%% [%s]" % [GameState.morale, m_state], 11, m_col))

	# 착취 낙인 문양 (색맹 대응: 숫자 + 균열선 | / || / |||)
	if GameState.brand_stacks > 0:
		var cracks := "|||" if GameState.brand_stacks >= 6 else ("||" if GameState.brand_stacks >= 3 else "|")
		var b_title := "타락한 영주" if GameState.brand_stacks >= 6 else ("불신의 낙인" if GameState.brand_stacks >= 3 else "착취 낙인")
		var b_lbl := UiKit.label("🔥 %s %d (%s · 일일 민심 -%d)" % [b_title, GameState.brand_stacks, cracks, GameState.brand_daily_morale_loss()], 11, UiKit.RED.lightened(0.2))
		h.add_child(b_lbl)

	# 미처리 유품 클릭 배지 (0이면 숨김, 클릭 시 기념관 [유품 처리] 탭 직행)
	var unres := GameState.unresolved_relic_count()
	if unres > 0:
		var btn_relic := UiKit.button("🕯️ 미처리 유품 %d (방치 +%d/일)" % [unres, GameState.unresolved_daily_stress()], UiKit.RED)
		btn_relic.custom_minimum_size = Vector2(0, 22)
		btn_relic.focus_mode = FOCUS_ALL
		btn_relic.pressed.connect(_open_memorial_relics_tab)
		h.add_child(btn_relic)

	# 활성 원정 축복 배지
	if bool(GameState.active_exploit_buff.get("active", false)):
		var atk_b := GameState.exploit_attack_bonus()
		var crit_b := GameState.party_crit_bonus()
		h.add_child(UiKit.label("⚔️ 원정 축복: ATK +%d · CRIT +%.1f%%" % [atk_b, crit_b], 11, UiKit.GOLD2))

	# 비상 구제 강조 안내
	if GameState.can_rest_estate_day():
		h.add_child(UiKit.label("⚠ 출진 가능 용병 없음 · 하단 [비상 휴식]으로 복구 가능", 11, UiKit.GOLD))


## 상단 유품 배지 클릭 시 기념관 팝업의 [유품 처리] 탭으로 바로 이동한다.
func _open_memorial_relics_tab() -> void:
	for d in BuildingDb.DEFS:
		if str(d.get("type", "")) == "memorial":
			var pop: BaseBuildingPopup = get_popup(d)
			if pop.has_method("select_tab"):
				pop.call("select_tab", "relics")
			village.zoom_to(d)
			return


## 비상 구제 [하루 휴식] 버튼 클릭 시 예상 정산 내역과 경고 확인 모달을 표시한다.
func _on_rest_day_pressed() -> void:
	if not GameState.can_rest_estate_day():
		return
	var prev := GameState.preview_return_settlement({}, true)
	var req_g := GameState.recruit_cost("일반")
	var body := "출진 가능한 용병이 없어 하루를 휴식합니다.\n"
	body += "• 예상 수입: +%d G (일반 용병 모집까지: %d / %d G)\n" % [int(prev["base_income"]), GameState.gold, req_g]
	body += "• 회복 행동력: 1 AP (모집 전용) · 균열 활성도: +5%\n"
	if int(prev["unresolved_stress"]) > 0 or int(prev["brand_morale_loss"]) > 0 or int(prev["morale_stress"]) > 0:
		body += "• 정산 경고: 유품 방치 +%d · 낙인 민심 -%d · 민심 동요 +%d\n" % [
			int(prev["unresolved_stress"]), int(prev["brand_morale_loss"]), int(prev["morale_stress"])
		]
	body += "• 예상 총 스트레스: %d / 100" % int(prev["final_total_stress"])
	if bool(prev["will_fall"]):
		body += "\n⚠ 경고: 이 휴식으로 총 스트레스가 100에 도달해 현 영주가 몰락합니다!"
	open_confirm_modal("비상 휴식 확인", body, "하루 휴식 실행", UiKit.GOLD, func():
		GameState.rest_estate_day()
	)


## 2단 중첩 확인 모달을 연다. 기본 포커스는 항상 [취소] 버튼에 고정되며 ESC·딤 클릭 시 이 모달만 닫힌다.
func open_confirm_modal(title_text: String, body_text: String, confirm_label: String, confirm_color: Color, on_confirm: Callable) -> void:
	_close_confirm_modal()
	var host: Node = _modal_layer if _modal_layer != null else _hud_layer
	var overlay := Control.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	host.add_child(overlay)
	_confirm_overlay = overlay

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			get_viewport().set_input_as_handled()
			_close_confirm_modal()
	)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_PASS
	overlay.add_child(center)

	var card := UiKit.panel(UiKit.BG, confirm_color, 12)
	card.custom_minimum_size = Vector2(540, 0)
	card.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	v.add_child(UiKit.title(title_text, 17, confirm_color.lightened(0.2)))
	v.add_child(UiKit.divider())
	var body_lbl := UiKit.label(body_text, 12, UiKit.TEXT)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body_lbl)
	v.add_child(UiKit.divider())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(btn_row)

	var btn_cancel := UiKit.button("취소 (ESC)", UiKit.BORDER2)
	btn_cancel.custom_minimum_size = Vector2(120, 38)
	btn_cancel.focus_mode = FOCUS_ALL
	btn_cancel.pressed.connect(_close_confirm_modal)
	btn_row.add_child(btn_cancel)

	var btn_ok := UiKit.gothic_button(confirm_label, confirm_color)
	btn_ok.custom_minimum_size = Vector2(160, 38)
	btn_ok.focus_mode = FOCUS_ALL
	btn_ok.pressed.connect(func():
		_close_confirm_modal()
		if on_confirm.is_valid():
			on_confirm.call()
	)
	btn_row.add_child(btn_ok)

	# 오조작 방지를 위해 기본 포커스를 반드시 [취소] 버튼에 고정한다.
	btn_cancel.grab_focus()


## 최상위 확인 모달만 안전하게 닫는다.
func _close_confirm_modal() -> void:
	if is_instance_valid(_confirm_overlay):
		_confirm_overlay.queue_free()
	_confirm_overlay = null


## 저주 아이콘 배지 호버/포커스 시 정확한 이름과 수치 효과를 커스텀 팝오버로 표시한다.
func _show_curse_popover(curse_id: String, anchor_pos: Vector2) -> void:
	_hide_curse_popover()
	var info: Dictionary = GameState.CURSE_INFO.get(curse_id, {"name": curse_id, "icon": "☠", "desc": ""})
	var pop := UiKit.panel(Color("160e10f5"), UiKit.RED, 8)
	pop.position = Vector2(clampf(anchor_pos.x, 8.0, VIEWPORT_WIDTH - 320.0), 78.0)
	pop.custom_minimum_size = Vector2(300, 0)
	pop.mouse_filter = MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pop.add_child(v)
	v.add_child(UiKit.title("%s %s" % [str(info["icon"]), str(info["name"])], 12, UiKit.RED.lightened(0.25)))
	var d := UiKit.label(str(info["desc"]), 11, UiKit.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	_hud_layer.add_child(pop)
	_curse_popover = pop


## 저주 커스텀 팝오버를 숨긴다.
func _hide_curse_popover() -> void:
	if is_instance_valid(_curse_popover):
		_curse_popover.queue_free()
	_curse_popover = null


## 결산 화면을 건너뛰고(Alt+F4 등) 재접속한 경우 1회성 비차단 계승 안내 배너를 표시한다.
func _maybe_show_unseen_succession_banner() -> void:
	if not GameState.unseen_succession_notice:
		return
	var names: PackedStringArray = []
	for cid in GameState.active_curses:
		var info: Dictionary = GameState.CURSE_INFO.get(cid, {"name": cid})
		names.append(str(info["name"]))
	var curse_str := ", ".join(names) if not names.is_empty() else "없음 (청정 계승)"

	var bar := UiKit.panel(Color("1c140ef0"), UiKit.GOLD, 8)
	bar.position = Vector2(14, 80)
	bar.custom_minimum_size = Vector2(680, 34)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)
	var lbl := UiKit.label("👑 제 %d대 시작 · 활성 계승 저주: %s" % [GameState.generation_number, curse_str], 12, UiKit.GOLD2)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(lbl)
	var btn_ok := UiKit.button("확인", UiKit.GOLD)
	btn_ok.custom_minimum_size = Vector2(64, 24)
	btn_ok.focus_mode = FOCUS_ALL
	btn_ok.pressed.connect(func():
		GameState.unseen_succession_notice = false
		GameState.save_game()
		if is_instance_valid(_succession_banner):
			_succession_banner.queue_free()
		_succession_banner = null
	)
	h.add_child(btn_ok)
	_hud_layer.add_child(bar)
	_succession_banner = bar


## 추모(촛불·은빛 플래시 + 종소리 Chime) 또는 착취(암적색 비네트 펄스 + 심장 박동 SFX) 연출을 재생한다.
func play_soul_feedback(is_exploit: bool) -> void:
	var host: Node = _modal_layer if _modal_layer != null else _hud_layer
	var flash := ColorRect.new()
	flash.set_anchors_preset(PRESET_FULL_RECT)
	flash.mouse_filter = MOUSE_FILTER_IGNORE
	flash.color = Color(0.55, 0.05, 0.08, 0.36) if is_exploit else Color(0.95, 0.85, 0.55, 0.22)
	host.add_child(flash)
	var dur: float = 0.4 if is_exploit else 0.5
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)

	if is_instance_valid(_sfx_player):
		_sfx_player.stream = _generate_procedural_sfx(is_exploit)
		_sfx_player.volume_db = -8.0
		_sfx_player.play()


## 외부 오디오 파일 없이 추모 종소리(Chime) 또는 착취 심장 박동(Heartbeat) WAV 스트림을 프로시저럴 생성한다.
static func _generate_procedural_sfx(is_exploit: bool) -> AudioStreamWAV:
	var mix_rate: int = 22050
	var dur: float = 0.42 if is_exploit else 0.55
	var sample_count: int = int(float(mix_rate) * dur)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var s: float = 0.0
		if is_exploit:
			# 이중 심장 박동(65Hz 저주파 펄스 2회)
			var env1: float = exp(-absf(t - 0.07) * 32.0)
			var env2: float = exp(-absf(t - 0.24) * 28.0) * 0.85
			s = sin(TAU * 65.0 * t) * (env1 + env2) * 0.75
		else:
			# 맑은 추모 종소리(523Hz + 784Hz 감쇠 하모닉)
			var env: float = exp(-t * 5.2)
			s = (sin(TAU * 523.25 * t) * 0.6 + sin(TAU * 783.99 * t) * 0.35) * env * 0.65
		var pcm: int = clampi(int(round(s * 32767.0)), -32768, 32767)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav


## 다키스트 던전 1 스타일의 우측 접이식 영웅 로스터 패널 (초상화, 레벨 뱃지, 10칸 스트레스 핍, 장비 수치)
func _rebuild_roster_dock() -> void:
	if is_instance_valid(_roster_dock_panel):
		_roster_dock_panel.queue_free()
	var dock_w: float = 264.0 if _roster_dock_expanded else 44.0
	var dock_panel := PanelContainer.new()
	# 2행 상태 스트립(y=48..76)과 겹치지 않도록 y=82에서 시작하고, Lv. 텍스트가 잘리지 않게 폭 264px 확보.
	dock_panel.position = Vector2(VIEWPORT_WIDTH - dock_w - 8, 82)
	dock_panel.size = Vector2(dock_w, 420)
	dock_panel.custom_minimum_size = Vector2(dock_w, 420)
	dock_panel.add_theme_stylebox_override("panel", UiKit.style(Color("0c0a08ee"), UiKit.BORDER2, 8, 2, 6, 6))
	_hud_layer.add_child(dock_panel)
	_roster_dock_panel = dock_panel
	_hud_layer.move_child(dock_panel, 3)

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
		_rebuild_roster_dock()
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
			var in_party := GameState.party.has(m)
			var slot := UiKit.merc_card(m, {
				"bg_color": Color("16120e"),
				"border_color": UiKit.GOLD if in_party else UiKit.BORDER,
				"pad_h": 6,
				"pad_v": 4,
				"portrait_size": 32,
				"grade_in_title": false,
				"title_size": 11,
				"subtitle_mode": "gear_stress",
			})
			slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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


## 다중 시그널 수신 시 village.rebuild()가 1프레임 내 중복 실행되지 않도록 deferred dirty flag로 병합한다.
func _schedule_village_rebuild() -> void:
	if _village_dirty:
		return
	_village_dirty = true
	call_deferred("_flush_village_rebuild")


func _flush_village_rebuild() -> void:
	_village_dirty = false
	if is_instance_valid(self) and village != null and not _game_over_transitioning:
		village.rebuild()


## 자원·일차·행동력 변동: 상단바와 마을 건물 배지(말풍선)만 갱신한다.
func _on_resources_changed() -> void:
	_rebuild_top_bar()
	_schedule_village_rebuild()


## 스트레스 변동: 상단바 스트레스 칩, 건물 배지, 화면 위험 연출(비네트 펄스)을 갱신한다.
func _on_stress_changed() -> void:
	_rebuild_top_bar()
	_schedule_village_rebuild()
	_update_danger_atmosphere()


## 유품·낙인·원정 축복 변동: 2행 상태 스트립과 마을 건물 배지를 갱신한다.
func _on_relics_changed() -> void:
	_rebuild_status_strip()
	_schedule_village_rebuild()


## 로스터/파티 변동: 우측 영웅 로스터 덱과 마을 건물 배지만 갱신한다(상단바는 그대로).
func _on_roster_or_party_changed() -> void:
	_rebuild_roster_dock()
	_rebuild_status_strip()
	if is_instance_valid(_btn_rest_day):
		_btn_rest_day.visible = GameState.can_rest_estate_day()
	_schedule_village_rebuild()
	_update_danger_atmosphere()


## 총 스트레스에 비례해 화면 위험 연출 셰이더 값(danger_pulse)을 갱신한다.
func _update_danger_atmosphere() -> void:
	if is_instance_valid(_atmosphere_overlay) and _atmosphere_overlay.material is ShaderMaterial:
		(_atmosphere_overlay.material as ShaderMaterial).set_shader_parameter("danger_pulse", clampf(float(GameState.total_stress() - 50) / 50.0, 0.0, 0.85))


## 건물 정의에 대응하는 팝업을 반환한다(없으면 생성해 캐시).
func get_popup(def: Dictionary) -> BaseBuildingPopup:
	var key: String = def.type
	if not _popups.has(key):
		_popups[key] = BuildingPopups.create(self, def)
	return _popups[key]


## 줌인 완료 후 해당 건물의 대형 기능 팝업(1220 x 660)을 연다.
func open_building_popup(def: Dictionary) -> void:
	get_popup(def).open()


## 기존 호출부 호환용 진입점 — open_building_popup 과 동일.
func _open_large_building_popup(def: Dictionary) -> void:
	open_building_popup(def)


## F1 디버그 치트 적용 시 열려 있는 건물 팝업 UI(버튼 활성 상태·보유 자원)도 즉시 재구성한다.
func _on_debug_cheat_applied() -> void:
	if _active_modal == null or not is_instance_valid(_active_modal) or _current_open_def.is_empty():
		return
	if is_instance_valid(_active_blacksmith_canvas) and _active_blacksmith_canvas.current_state == VillageVisuals.BlacksmithInteriorCanvas.DwarfState.HAMMERING:
		return
	_open_large_building_popup(_current_open_def)


func _on_game_over() -> void:
	if _game_over_transitioning:
		return
	_game_over_transitioning = true
	_close_confirm_modal()
	get_tree().change_scene_to_file.call_deferred(GameState.SCENE_GAMEOVER)
