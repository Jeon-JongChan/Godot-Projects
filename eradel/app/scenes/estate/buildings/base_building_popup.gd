class_name BaseBuildingPopup
extends RefCounted
## 건물 대형 팝업 공통 틀. 모달 프레임(딤·헤더·알림 배너)을 만들고 본문은 하위 클래스의 populate() 가 채운다.
## 하위 클래스(예: LodgePopup)는 자신의 선택 상태를 멤버로 가지며, 상태 변경 후 rebuild() 로 자기 팝업만 다시 그린다.

## 팝업을 소유한 영지 월드(모달 레이어·카메라·FSM 접근용)
var estate: EstateWorld
## 이 팝업이 표현하는 건물 정의(BuildingDb.DEFS 항목)
var def: Dictionary
## 행동 결과 안내 문구(커맨드 실행 직후 헤더 아래 배너로 표시)
var notice: String = ""


## 팝업 생성 시 소유 월드와 건물 정의를 받는다.
func _init(p_estate: EstateWorld, p_def: Dictionary) -> void:
	estate = p_estate
	def = p_def


## 하위 클래스가 재정의: 우측 본문 VBox 에 건물별 기능 UI 를 채운다.
func populate(_vbox: VBoxContainer) -> void:
	pass


## 현재 상태로 팝업 전체를 다시 그린다(상태 변경 후 호출).
func rebuild() -> void:
	open()


## [커맨드] 영지 행동 커맨드를 실행하고 안내 문구와 함께 팝업을 갱신하는 공통 실행기(Invoker)
func run_command(cmd: EstateCommand) -> void:
	if cmd != null and cmd.execute():
		notice = cmd.notice_text()
		rebuild()


## 우측 본문 패널: 건물별 populate() 가 내용을 채우는 컨테이너를 만든다.
func _build_body() -> Control:
	var right_panel := UiKit.panel(UiKit.BG2, UiKit.BORDER, 10)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(vbox)

	populate(vbox)
	return right_panel


func open() -> void:
	estate._view_fsm.go(EstateWorld.ViewState.MODAL_OPEN)
	if estate._active_modal != null:
		estate._active_modal.queue_free()
		estate._active_modal = null

	estate._current_open_def = def
	var is_dungeon: bool = (def.id == "dungeon_gate")
	var bname: String = def.name
	var cur_lv: int = GameState.buildings.get(bname, 1)

	estate._active_modal = Control.new()
	estate._active_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	# HUD 갱신 시에도 슬라이더/상단바가 모달 위로 튀어나오지 않도록 전용 상위 CanvasLayer(layer=20)에 배치
	var modal_host: Node = estate._modal_layer if estate._modal_layer != null else estate._hud_layer
	modal_host.add_child(estate._active_modal)

	# 배경 반투명 딤 오버레이 (바깥 영역 클릭 시 닫기)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			estate._zoom_out_and_return()
	)
	estate._active_modal.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	estate._active_modal.add_child(center)

	# 대형 팝업 메인 프레임 (대장간 및 모든 건물을 1220 x 660 와이드 고딕 프레임으로 통일)
	var frame_border := UiKit.RED if is_dungeon else UiKit.GOLD
	var main_panel := UiKit.panel(UiKit.BG, frame_border, 14)
	var panel_size := Vector2(1220, 660)
	main_panel.custom_minimum_size = panel_size
	main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	main_panel.modulate = Color(1, 1, 1, 0.0)
	center.add_child(main_panel)
	var fade_tw := estate.create_tween()
	fade_tw.tween_property(main_panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
		title_col.add_child(UiKit.title(head_title, 20, UiKit.GOLD2 if not is_dungeon else UiKit.RED))
		title_col.add_child(UiKit.label(def.tag, 12, UiKit.TEXT2))
		hbox.add_child(title_col)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)

		# 팝업 내 실시간 자원/지표 칩 표시
		hbox.add_child(UiKit.chip("🪙 금화 %d" % GameState.gold, UiKit.GOLD))
		hbox.add_child(UiKit.chip("💎 마나석 %d" % GameState.manastone, UiKit.BLUE))
		hbox.add_child(UiKit.chip("⚡ 행동력 %d/%d" % [GameState.action_points, GameState.max_action_points], UiKit.GREEN))
		hbox.add_child(UiKit.chip("민심 %d%%" % GameState.morale, UiKit.GOLD))
		hbox.add_child(UiKit.chip("스트레스 %d/100" % GameState.total_stress(), GameState.stress_color()))

		var btn_close := UiKit.button("✕ 마을로 복귀 (ESC)", UiKit.GOLD)
		btn_close.custom_minimum_size = Vector2(150, 38)
		btn_close.pressed.connect(estate._zoom_out_and_return)
		hbox.add_child(btn_close)

		root_vbox.add_child(header_bar)

	# 알림 배너 (행동 결과 피드백 메시지)
	if notice != "":
		var notice_bar := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 8)
		var nh := HBoxContainer.new()
		notice_bar.add_child(nh)
		nh.add_child(UiKit.label("✨ " + notice, 13, UiKit.GOLD2))
		root_vbox.add_child(notice_bar)

	# ── 2. 본문 레이아웃: 대장간처럼 각 건물별 전용 빌더가 화면 전체(1220x660)를 활용해 3단 패널을 직접 구성 ──
	var body_hbox := HBoxContainer.new()
	body_hbox.add_theme_constant_override("separation", 14)
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body_hbox)

	body_hbox.add_child(_build_body())


func build_center_interior(canvas_h: float = 320.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, canvas_h)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var interior := VillageVisuals.BuildingInteriorCanvas.new()
	interior.btype = def.type
	interior.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(interior)
	estate._active_interior_canvas = interior
	estate._interior_canvas = interior
	return holder
