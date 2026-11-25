class_name EstateVillage
extends RefCounted
## 영지 마을 월드: 지형 캔버스·2.5D 건물 노드·말풍선을 만들고, 건물 선택 시 카메라 줌인 연출을 담당한다.
## 카메라 스크롤 값과 뷰 FSM 은 EstateWorld 가 소유하며, 여기서는 연출 트윈만 걸어준다.

## 소유 영지 월드(트윈 생성과 카메라 상태 접근용)
var estate: EstateWorld
## 파노라마 마을 월드 컨테이너(스크롤·줌 대상)
var world_container: Control
var _terrain_canvas: VillageVisuals.VillageTerrainCanvas
var _buildings_layer: Control
var _building_canvases: Array[VillageVisuals.VillageBuildingCanvas] = []
var _floating_bubbles: Array[Control] = []
var _bubble_base_y: Array[float] = []
var _anim_clock: float = 0.0


## 소유 월드를 받아 둔다.
func _init(p_estate: EstateWorld) -> void:
	estate = p_estate


## 마을 월드 컨테이너·지형·건물 레이어를 생성해 영지 월드에 붙인다.
func build_world() -> void:
	# 1. 파노라마 마을 월드 컨테이너 (2500 x 720)
	world_container = Control.new()
	world_container.custom_minimum_size = Vector2(EstateWorld.WORLD_WIDTH, EstateWorld.WORLD_HEIGHT)
	world_container.size = Vector2(EstateWorld.WORLD_WIDTH, EstateWorld.WORLD_HEIGHT)
	estate.add_child(world_container)

	# 2. 마을 지형/도로/나무/가로등 캔버스
	_terrain_canvas = VillageVisuals.VillageTerrainCanvas.new()
	_terrain_canvas.building_defs = BuildingDb.DEFS
	_terrain_canvas.size = Vector2(EstateWorld.WORLD_WIDTH, EstateWorld.WORLD_HEIGHT)
	_terrain_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_container.add_child(_terrain_canvas)

	# 3. 2.5D 마을 건축물 레이어
	_buildings_layer = Control.new()
	_buildings_layer.size = Vector2(EstateWorld.WORLD_WIDTH, EstateWorld.WORLD_HEIGHT)
	_buildings_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	world_container.add_child(_buildings_layer)
	rebuild()


## [업데이트 메서드] 지형·건물 캔버스 애니메이션과 말풍선 부유 효과를 한 프레임 진행한다.
func tick(delta: float) -> void:
	_anim_clock += delta
	if is_instance_valid(_terrain_canvas):
		_terrain_canvas.update_tick(delta)
	for bc in _building_canvases:
		if is_instance_valid(bc):
			bc.update_tick(delta)
	# 건물 머리 위 상태 말풍선 부드러운 상하 부유 애니메이션
	for i in range(_floating_bubbles.size()):
		var b := _floating_bubbles[i]
		if is_instance_valid(b):
			b.position.y = _bubble_base_y[i] + sin(_anim_clock * 3.0 + float(i) * 0.9) * 3.5


# ── 클래시 오브 클랜 스타일 2.5D 마을 건물 배치 생성 ──
func rebuild() -> void:
	for c in _buildings_layer.get_children():
		c.queue_free()
	_building_canvases.clear()
	_floating_bubbles.clear()
	_bubble_base_y.clear()

	for def in BuildingDb.DEFS:
		var node := _create_building_node(def)
		_buildings_layer.add_child(node)


## 각 건물을 텍스트 카드가 아닌 실제 2.5D 건축물 + 상단 부유 말풍선 + 하단 명패 배지로 구성
func _create_building_node(def: Dictionary) -> Control:
	var r: Rect2 = def.rect
	var root := Control.new()
	root.position = r.position
	root.size = r.size
	root.pivot_offset = r.size * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var is_dungeon: bool = (def.id == "dungeon_gate")
	var lv: int = GameState.buildings.get(def.name, 1)

	# 1. 2.5D 건축물 그래픽 캔버스 ([업데이트 메서드] 대상 목록에 등록)
	var art_canvas := VillageVisuals.VillageBuildingCanvas.new()
	art_canvas.def = def
	art_canvas.size = r.size
	art_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art_canvas)
	_building_canvases.append(art_canvas)

	# 2. 지붕 위 부유하는 액션/상태 말풍선 ([경량화] 공유 StyleBox 캐시 사용)
	var bubble := PanelContainer.new()
	var bubble_col := UiKit.RED if is_dungeon else UiKit.GOLD
	var bubble_sb := UiKit.style(Color(0.09, 0.08, 0.06, 0.92), bubble_col, 14, 1, 10, 3)
	bubble.add_theme_stylebox_override("panel", bubble_sb)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bubble_text := _bubble_text(def)
	var b_lbl := UiKit.label(bubble_text, 11, UiKit.GOLD2 if not is_dungeon else Color("ff8098"))
	b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.add_child(b_lbl)
	# 2행 상단 상태 스트립(y=48..76)에 최상단 건물 말풍선이 가려지지 않도록 최소 절대 Y=82를 보장한다.
	var base_by: float = maxf(-18.0, 82.0 - r.position.y)
	bubble.position = Vector2((r.size.x - 130) * 0.5, base_by)
	bubble.custom_minimum_size = Vector2(130, 24)
	root.add_child(bubble)
	_floating_bubbles.append(bubble)
	_bubble_base_y.append(base_by)

	# 3. 건물 하단 마을 명패 배지 ([경량화] 공유 StyleBox 캐시 사용)
	var plate := PanelContainer.new()
	var plate_border := UiKit.RED if is_dungeon else UiKit.BORDER2
	var plate_sb := UiKit.style(Color(0.08, 0.07, 0.05, 0.94), plate_border, 8, 2, 10, 3)
	plate.add_theme_stylebox_override("panel", plate_sb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
		if estate._is_zooming or estate._active_modal != null:
			return
		art_canvas.is_hovered = true
		art_canvas.queue_redraw()
		plate.add_theme_stylebox_override("panel", UiKit.style(Color(0.16, 0.13, 0.08, 0.98), UiKit.GOLD2, 8, 2))
		if hover_tw:
			hover_tw.kill()
		hover_tw = estate.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		hover_tw.tween_property(root, "scale", Vector2(1.07, 1.07), 0.16)
	)
	root.mouse_exited.connect(func():
		art_canvas.is_hovered = false
		art_canvas.queue_redraw()
		plate.add_theme_stylebox_override("panel", plate_sb)
		if hover_tw:
			hover_tw.kill()
		hover_tw = estate.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		hover_tw.tween_property(root, "scale", Vector2.ONE, 0.15)
	)

	# 클릭 시(드래그가 아닐 때) 해당 건물로 카메라 줌인 후 대형 팝업창 오픈
	root.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			if estate._drag_moved_distance <= 8.0:
				zoom_to(def)
	)

	return root


## 건물 지붕 위 말풍선에 표시할 실시간 상태 요약 텍스트 반환
func _bubble_text(def: Dictionary) -> String:
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
			return "⚒️ 공격력 +%d" % GameState.blacksmith_attack_bonus()
		"magic":
			return "🔮 활성도 %d%%" % GameState.dungeon_activity
		"training":
			return "🎯 영웅 특훈"
		"memorial":
			var unres := GameState.unresolved_relic_count()
			return ("🕯️ 미처리 유품 %d!" % unres) if unres > 0 else ("🏛️ 위령비 (%d위)" % GameState.death_log.size())
		"dungeon":
			return "⚔️ 원정 출진!"
	return def.icon + " " + def.name


# ── 건물 선택 시 부드러운 카메라 줌인(Zoom-in) & 대형 팝업 오픈 ([유한 상태 기계]) ──
func zoom_to(def: Dictionary) -> void:
	if not estate._view_fsm.go(EstateWorld.ViewState.ZOOMING_IN):
		return

	estate._current_open_def = def
	estate.get_popup(def).notice = ""

	var b_rect: Rect2 = def.rect
	var target_center := b_rect.position + b_rect.size * 0.5
	var desired_scroll_x := clampf(target_center.x - (EstateWorld.VIEWPORT_WIDTH * 0.5), 0.0, EstateWorld.MAX_SCROLL_X)
	estate._target_scroll_x = desired_scroll_x

	# 건물 중심을 피벗으로 삼아 마을 화면 자체가 건물 내부로 부드럽게 줌인되는 연출
	world_container.pivot_offset = target_center

	var tw := estate.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(estate, "_current_scroll_x", desired_scroll_x, 0.38)
	tw.tween_property(world_container, "position:x", -desired_scroll_x, 0.38)
	tw.tween_property(world_container, "scale", Vector2(1.82, 1.82), 0.38)

	tw.chain().tween_callback(func():
		estate._update_scroll_position()
		estate.open_building_popup(def)
	)
