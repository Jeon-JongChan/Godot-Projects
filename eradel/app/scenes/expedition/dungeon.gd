class_name DungeonScene
extends Control

## 다키스트 던전 1 스타일의 2D 사이드뷰 턴제 전투 씬.
## 상단 횃불 광원(Torchlight) 미터 게이지 및 원정 퀘스트 배너,
## 2단 고딕 컨트롤 패널(영웅 초상화, 4대 스킬 슬롯, 6대 스탯 그리드, 대장간 장비 정보, 미니맵/전투로그 탭)을 제공하며
## 캐릭터별 턴 진행, 돌진 공격, 피격 넉백, 플로팅 텍스트 등의 역동적인 연출을 수행합니다.

const BattleUnitScene = preload("res://scenes/expedition/entities/battle_unit.gd")
const FloatingTextScene = preload("res://scenes/expedition/entities/floating_text.gd")

## [유한 상태 기계] 전투 진행 단계 정의
enum BattleState { ROUND_START, ALLY_TURN, ALLY_ACTING, MONSTER_TURN, FINISHED }

# ── 노드 및 데이터 ──
var _root: MarginContainer
var _stage_panel: Control
var _stage_content: Control
var _party_units: Array = []
var _monster_units: Array = []

var _monsters_data: Array[Dictionary] = []
var _base_gold: int = 0
var _round: int = 0
var _log: Array[String] = []
var _finished: bool = false
var _is_busy: bool = false

# ── 횃불 광원(Torchlight) 시스템 (0 ~ 100) ──
var _torchlight: int = 85
var _torch_bar: ProgressBar
var _torch_value_label: Label
var _torch_stage_label: Label
var _quest_progress_label: Label

# ── [유한 상태 기계 / 책임 연쇄 / 오브젝트 풀] ──
var _fsm: StateMachine = StateMachine.new()
var _dmg_pipeline: DamagePipeline = DamagePipeline.new()
var _ft_pool: ObjectPool = null
var _sfx_pool: ObjectPool = null

# ── 턴 진행 변수 ──
var _current_actor = null
var _selected_target = null
var _auto_play: bool = false

# ── 하단 고딕 UI 패널 참조 ──
var _hero_info_box: Control
var _hero_portrait_rect: PanelContainer
var _hero_name_label: Label
var _hero_job_label: Label
var _hero_hp_bar: ProgressBar
var _hero_hp_label: Label
var _hero_stress_bar: ProgressBar
var _hero_stress_label: Label

# 6대 스탯 라벨들 (ACC, CRIT, DMG, DODGE, PROT, SPD)
var _stat_labels: Dictionary = {}
var _gear_labels: Dictionary = {}

# 4개 스킬 아이콘 슬롯 버튼
var _skill_buttons: Array[Button] = []

# 우측 패널 (미니맵 & 전투 로그 탭)
var _tab_map_btn: Button
var _tab_log_btn: Button
var _minimap_container: Control
var _log_container: Control
var _log_vbox: VBoxContainer
var _log_scroll: ScrollContainer
var _round_label: Label
var _btn_auto_turn: Button
var _btn_retreat: Button


func _ready() -> void:
	UiKit.background(self, UiKit.BG)

	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)

	# 원정 데이터 생성 (기존 게임 로직 준수)
	_monsters_data = GameState.generate_monsters()
	_base_gold = 120 + GameState.dungeon_activity + GameState.rng().randi_range(0, 60)
	_log.append("어둠의 균열에 들어섰다. 몬스터 %d마리가 모습을 드러낸다." % _monsters_data.size())

	_build_scene_layout()
	_setup_fsm_and_pools()
	_spawn_units()
	_start_next_round()


## [유한 상태 기계 & 오브젝트 풀] 전투 상태 전이 표와 데미지 텍스트/효과음 풀을 초기화합니다.
func _setup_fsm_and_pools() -> void:
	_fsm.add(BattleState.ROUND_START, func(): _is_busy = false, Callable(), [BattleState.ALLY_TURN, BattleState.MONSTER_TURN, BattleState.FINISHED])
	_fsm.add(BattleState.ALLY_TURN, func(): _is_busy = false, Callable(), [BattleState.ALLY_ACTING, BattleState.MONSTER_TURN, BattleState.FINISHED])
	_fsm.add(BattleState.ALLY_ACTING, func(): _is_busy = true; _set_controls_enabled(false), Callable(), [BattleState.ALLY_TURN, BattleState.MONSTER_TURN, BattleState.FINISHED])
	_fsm.add(BattleState.MONSTER_TURN, func(): _is_busy = true; _set_controls_enabled(false), Callable(), [BattleState.ROUND_START, BattleState.FINISHED])
	_fsm.add(BattleState.FINISHED, func(): _finished = true; _is_busy = false; _set_controls_enabled(false), Callable(), [BattleState.FINISHED])

	_ft_pool = ObjectPool.new(func(): return FloatingTextScene.new(), _stage_content, 6)
	_sfx_pool = ObjectPool.new(func():
		var p := AudioStreamPlayer.new()
		p.finished.connect(func(): _sfx_pool.release(p))
		return p, self, 4)


## 전체 화면 레이아웃 (상단 다키스트 횃불 및 퀘스트 배너, 중앙 배틀 스테이지, 하단 고딕 2단 패널)을 구성합니다.
func _build_scene_layout() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_root.add_child(vbox)

	# 1. 상단 다키스트 던전 시그니처 횃불 광원 게이지 및 퀘스트 배너 바 (높이 54px)
	var top_bar := _build_top_torch_and_quest_bar()
	vbox.add_child(top_bar)

	# 2. 중앙 2D 배틀 스테이지 (높이 410px)
	_stage_panel = Control.new()
	_stage_panel.custom_minimum_size = Vector2(1280, 410)
	_stage_panel.size_flags_vertical = SIZE_EXPAND_FILL
	_stage_panel.clip_contents = true
	vbox.add_child(_stage_panel)

	# 화면 흔들림 시 전체 레이아웃에 영향을 주지 않도록 내부 컨테이너 분리
	_stage_content = Control.new()
	_stage_content.set_anchors_preset(PRESET_FULL_RECT)
	_stage_panel.add_child(_stage_content)

	_build_stage_background(_stage_content)

	# 3. 하단 2단 고딕 다키스트 던전 컨트롤 패널 (높이 256px)
	var bottom_panel := PanelContainer.new()
	bottom_panel.custom_minimum_size = Vector2(1280, 256)
	var bp_sb := StyleBoxFlat.new()
	bp_sb.bg_color = Color("0d0b0a") # 딥 다크 고딕 바탕
	bp_sb.border_color = Color("383025") # 고딕 황동/흑철 테두리
	bp_sb.set_border_width_all(2)
	bottom_panel.add_theme_stylebox_override("panel", bp_sb)
	vbox.add_child(bottom_panel)

	var b_margin := MarginContainer.new()
	b_margin.add_theme_constant_override("margin_left", 14)
	b_margin.add_theme_constant_override("margin_right", 14)
	b_margin.add_theme_constant_override("margin_top", 10)
	b_margin.add_theme_constant_override("margin_bottom", 10)
	bottom_panel.add_child(b_margin)

	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 14)
	b_margin.add_child(bottom_hbox)

	# 하단 좌측: 영웅 정보 박스 (초상화, 스킬 4슬롯, 6대 스탯 그리드, 장비 정보)
	_hero_info_box = _build_hero_panel()
	bottom_hbox.add_child(_hero_info_box)

	# 하단 우측: 미니맵 및 전투 로그 탭 전환 박스
	var right_box := _build_right_tab_panel()
	bottom_hbox.add_child(right_box)


## 상단 횃불 광원(Torchlight) 게이지와 원정 퀘스트 배너를 생성합니다.
func _build_top_torch_and_quest_bar() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(1280, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("100e0c")
	sb.border_color = Color("3a3124")
	sb.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(hbox)

	var pad_left := Control.new()
	pad_left.custom_minimum_size = Vector2(16, 0)
	hbox.add_child(pad_left)

	# 1) 좌측 원정 퀘스트 배너
	var quest_banner := HBoxContainer.new()
	quest_banner.add_theme_constant_override("separation", 8)
	quest_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(quest_banner)

	var emblem := Label.new()
	emblem.text = "⚔"
	emblem.add_theme_font_size_override("font_size", 18)
	emblem.add_theme_color_override("font_color", Color("d4af37"))
	quest_banner.add_child(emblem)

	var q_vbox := VBoxContainer.new()
	q_vbox.add_theme_constant_override("separation", 0)
	q_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	quest_banner.add_child(q_vbox)

	var q_title := Label.new()
	q_title.text = "원정 목표: 어둠의 균열 정벌"
	q_title.add_theme_font_size_override("font_size", 13)
	q_title.add_theme_color_override("font_color", Color("f0e2b6"))
	q_vbox.add_child(q_title)

	_quest_progress_label = Label.new()
	_quest_progress_label.text = "몬스터 잔당 소탕 중"
	_quest_progress_label.add_theme_font_size_override("font_size", 10)
	_quest_progress_label.add_theme_color_override("font_color", Color("9a8d7a"))
	q_vbox.add_child(_quest_progress_label)

	# 중앙 여백
	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(spacer1)

	# 2) 중앙 다키스트 던전 시그니처 횃불 광원(Torchlight) 미터 게이지
	var torch_center := VBoxContainer.new()
	torch_center.alignment = BoxContainer.ALIGNMENT_CENTER
	torch_center.add_theme_constant_override("separation", 1)
	hbox.add_child(torch_center)

	var torch_header := HBoxContainer.new()
	torch_header.alignment = BoxContainer.ALIGNMENT_CENTER
	torch_header.add_theme_constant_override("separation", 6)
	torch_center.add_child(torch_header)

	var flame_icon := UiKit.icon_rect("res://assets/sprites/ui/icon_torch.png", 20)
	torch_header.add_child(flame_icon)

	_torch_stage_label = Label.new()
	_torch_stage_label.text = "찬란한 빛"
	_torch_stage_label.add_theme_font_size_override("font_size", 12)
	_torch_stage_label.add_theme_color_override("font_color", Color("ffd700"))
	torch_header.add_child(_torch_stage_label)

	_torch_value_label = Label.new()
	_torch_value_label.text = "(85 / 100)"
	_torch_value_label.add_theme_font_size_override("font_size", 11)
	_torch_value_label.add_theme_color_override("font_color", Color("c0b298"))
	torch_header.add_child(_torch_value_label)

	# 횃불 광원 게이지 바 (주황/골드 화염 그라데이션)
	var torch_frame := PanelContainer.new()
	torch_frame.custom_minimum_size = Vector2(280, 10)
	var tf_sb := StyleBoxFlat.new()
	tf_sb.bg_color = Color("0d0a08")
	tf_sb.border_color = Color("4a3c26")
	tf_sb.set_border_width_all(1)
	torch_frame.add_theme_stylebox_override("panel", tf_sb)
	torch_center.add_child(torch_frame)

	_torch_bar = ProgressBar.new()
	_torch_bar.show_percentage = false
	_torch_bar.max_value = 100
	_torch_bar.value = _torchlight
	_torch_bar.mouse_filter = MOUSE_FILTER_IGNORE
	var t_fill := StyleBoxFlat.new()
	t_fill.bg_color = Color("e87a15") # 타오르는 주황빛 화염
	_torch_bar.add_theme_stylebox_override("fill", t_fill)
	torch_frame.add_child(_torch_bar)

	# 우측 여백
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(spacer2)

	# 3) 우측 라운드 및 구역 표시
	_round_label = Label.new()
	_round_label.text = "제 1 라운드"
	_round_label.add_theme_font_size_override("font_size", 14)
	_round_label.add_theme_color_override("font_color", Color("d4af37"))
	hbox.add_child(_round_label)

	var pad_right := Control.new()
	pad_right.custom_minimum_size = Vector2(16, 0)
	hbox.add_child(pad_right)

	_update_torchlight_display()
	return bar


## 횃불 광원(Torchlight) 수치 및 상태 표시를 갱신합니다.
func _update_torchlight_display() -> void:
	if _torch_bar == null:
		return
	_torch_bar.value = _torchlight
	_torch_value_label.text = "(%d / 100)" % _torchlight

	var fill_sb: StyleBoxFlat = _torch_bar.get_theme_stylebox("fill").duplicate()

	if _torchlight >= 76:
		_torch_stage_label.text = "찬란한 빛"
		_torch_stage_label.add_theme_color_override("font_color", Color("ffe47a"))
		fill_sb.bg_color = Color("f59e0b") # 황금빛 주황 화염
	elif _torchlight >= 51:
		_torch_stage_label.text = "희미한 불빛"
		_torch_stage_label.add_theme_color_override("font_color", Color("e0a548"))
		fill_sb.bg_color = Color("c96816") # 주황빛
	elif _torchlight >= 26:
		_torch_stage_label.text = "어둑한 어둠"
		_torch_stage_label.add_theme_color_override("font_color", Color("b86a3d"))
		fill_sb.bg_color = Color("8c3b14") # 암적빛 화염
	else:
		_torch_stage_label.text = "칠흑의 암흑"
		_torch_stage_label.add_theme_color_override("font_color", Color("ff4444"))
		fill_sb.bg_color = Color("5e1b1b") # 검붉은 불씨

	_torch_bar.add_theme_stylebox_override("fill", fill_sb)


## 다키스트 던전 특유의 어둡고 음산한 석벽 및 원근 바닥을 그립니다.
## 다키스트 던전 1 특유의 심연 유적(Ruins & Crypts), 고딕 아치, 쇠사슬 및 촉수 실루엣 배경을 구축합니다.
func _build_stage_background(parent: Control) -> void:
	var bg_canvas := Control.new()
	bg_canvas.set_anchors_preset(PRESET_FULL_RECT)
	bg_canvas.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(bg_canvas)

	bg_canvas.draw.connect(func():
		var w := bg_canvas.size.x
		var h := bg_canvas.size.y

		# 1. 심연의 푸른빛/칠흑 석조 벽면 그라데이션
		bg_canvas.draw_rect(Rect2(0, 0, w, h), Color("0a0910"))
		for row in range(7):
			var by := row * 45.0
			var brick_col := Color(0.12, 0.14, 0.20, 0.35)
			bg_canvas.draw_line(Vector2(0, by), Vector2(w, by), brick_col, 1.5)
			var offset := (row % 2) * 60.0
			var bx := offset
			while bx < w:
				bg_canvas.draw_line(Vector2(bx, by), Vector2(bx, by + 45.0), brick_col, 1.5)
				bx += 120.0

		# 2. 다키스트 던전 2.webp 시그니처: 후면 거대한 고대 룬 아치 문양 및 촉수 실루엣
		var arch_cx := w * 0.5
		# 거대한 중앙 고딕 아치문
		var arch_poly := PackedVector2Array([
			Vector2(arch_cx - 240, 310), Vector2(arch_cx - 240, 110),
			Vector2(arch_cx - 160, 30), Vector2(arch_cx, 10),
			Vector2(arch_cx + 160, 30), Vector2(arch_cx + 240, 110),
			Vector2(arch_cx + 240, 310)
		])
		bg_canvas.draw_colored_polygon(arch_poly, Color("06050a"))
		bg_canvas.draw_polyline(arch_poly, Color("202436"), 3.0)

		# 심연에서 똬리를 틀고 올라오는 거대한 촉수 실루엣
		var tentacle_l := PackedVector2Array([
			Vector2(arch_cx - 320, 310), Vector2(arch_cx - 360, 220),
			Vector2(arch_cx - 410, 160), Vector2(arch_cx - 390, 80),
			Vector2(arch_cx - 340, 100), Vector2(arch_cx - 330, 150),
			Vector2(arch_cx - 280, 240), Vector2(arch_cx - 270, 310)
		])
		bg_canvas.draw_colored_polygon(tentacle_l, Color("0f121e"))
		bg_canvas.draw_polyline(tentacle_l, Color("242d48"), 2.0)

		var tentacle_r := PackedVector2Array([
			Vector2(arch_cx + 270, 310), Vector2(arch_cx + 290, 220),
			Vector2(arch_cx + 340, 140), Vector2(arch_cx + 390, 90),
			Vector2(arch_cx + 420, 120), Vector2(arch_cx + 360, 180),
			Vector2(arch_cx + 330, 250), Vector2(arch_cx + 340, 310)
		])
		bg_canvas.draw_colored_polygon(tentacle_r, Color("0f121e"))
		bg_canvas.draw_polyline(tentacle_r, Color("242d48"), 2.0)

		# 3. 벽면에 걸린 4개의 횃불 브래킷과 주황빛 불길
		var torch_xs := [arch_cx - 450, arch_cx - 190, arch_cx + 190, arch_cx + 450]
		for tx in torch_xs:
			# 철제 브래킷
			bg_canvas.draw_line(Vector2(tx, 140), Vector2(tx, 175), Color("2c241c"), 4.0)
			bg_canvas.draw_circle(Vector2(tx, 140), 7.0, Color("3a2e22"))
			# 횃불 화염 및 빛 번짐
			bg_canvas.draw_circle(Vector2(tx, 134), 28.0, Color(1.0, 0.45, 0.1, 0.14))
			bg_canvas.draw_circle(Vector2(tx, 134), 14.0, Color(1.0, 0.65, 0.2, 0.35))
			bg_canvas.draw_circle(Vector2(tx, 132), 6.0, Color("fff066"))

		# 4. 바닥 석판 타일 (Flagstone Floor with Perspective)
		var floor_y := 295.0
		bg_canvas.draw_rect(Rect2(0, floor_y, w, h - floor_y), Color("120f14"))
		bg_canvas.draw_line(Vector2(0, floor_y), Vector2(w, floor_y), Color("28222e"), 3.0)

		# 바닥 돌타일 원근 격자선
		for fx in range(14):
			var bx := fx * 95.0 + 15.0
			bg_canvas.draw_line(Vector2(bx, floor_y), Vector2(bx - 25.0, h), Color(0.18, 0.16, 0.22, 0.45), 1.5)
	)


## 하단 좌측 다키스트 던전 스타일 영웅 상세 패널을 생성합니다.
## (영웅 초상화, 4대 스킬 아이콘 슬롯, 6대 스탯 그리드, 무기/방어구 강화 정보)
func _build_hero_panel() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(740, 234)
	var p_sb := StyleBoxFlat.new()
	p_sb.bg_color = Color("12100d")
	p_sb.border_color = Color("3d3324")
	p_sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", p_sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	p.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# 상단 행: [영웅 초상화] + [이름/직업 & HP/스트레스 바] + [4대 스킬 아이콘 버튼 슬롯]
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	main_vbox.add_child(top_row)

	# 1. 영웅 사각 초상화 (어두운 고딕 프레임 + 실루엣)
	_hero_portrait_rect = PanelContainer.new()
	_hero_portrait_rect.custom_minimum_size = Vector2(58, 68)
	var port_sb := StyleBoxFlat.new()
	port_sb.bg_color = Color("1a1714")
	port_sb.border_color = Color("c7a13c")
	port_sb.set_border_width_all(1)
	_hero_portrait_rect.add_theme_stylebox_override("panel", port_sb)
	top_row.add_child(_hero_portrait_rect)

	var port_label := Label.new()
	port_label.name = "PortraitGlyph"
	port_label.text = "⚔"
	port_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	port_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	port_label.add_theme_font_size_override("font_size", 24)
	port_label.add_theme_color_override("font_color", Color("d4af37"))
	_hero_portrait_rect.add_child(port_label)

	# 2. 이름, 직업, 체력 및 스트레스 게이지
	var info_vbox := VBoxContainer.new()
	info_vbox.custom_minimum_size = Vector2(210, 0)
	info_vbox.add_theme_constant_override("separation", 2)
	top_row.add_child(info_vbox)

	_hero_name_label = Label.new()
	_hero_name_label.text = "대기 중..."
	_hero_name_label.add_theme_font_size_override("font_size", 16)
	_hero_name_label.add_theme_color_override("font_color", Color("ffffff"))
	info_vbox.add_child(_hero_name_label)

	_hero_job_label = Label.new()
	_hero_job_label.text = "직업 없음"
	_hero_job_label.add_theme_font_size_override("font_size", 11)
	_hero_job_label.add_theme_color_override("font_color", Color("a89a84"))
	info_vbox.add_child(_hero_job_label)

	# 체력 행
	var hp_h := HBoxContainer.new()
	hp_h.add_theme_constant_override("separation", 6)
	info_vbox.add_child(hp_h)

	var hp_ico := Label.new()
	hp_ico.text = "♥"
	hp_ico.add_theme_font_size_override("font_size", 11)
	hp_ico.add_theme_color_override("font_color", Color("ff4d4d"))
	hp_h.add_child(hp_ico)

	_hero_hp_bar = ProgressBar.new()
	_hero_hp_bar.custom_minimum_size = Vector2(90, 8)
	_hero_hp_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	_hero_hp_bar.show_percentage = false
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color("b81414")
	_hero_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_h.add_child(_hero_hp_bar)

	_hero_hp_label = Label.new()
	_hero_hp_label.text = "HP: - / -"
	_hero_hp_label.add_theme_font_size_override("font_size", 11)
	_hero_hp_label.add_theme_color_override("font_color", Color("ff6666"))
	hp_h.add_child(_hero_hp_label)

	# 스트레스 행
	var stress_h := HBoxContainer.new()
	stress_h.add_theme_constant_override("separation", 6)
	info_vbox.add_child(stress_h)

	var str_ico := Label.new()
	str_ico.text = "✦"
	str_ico.add_theme_font_size_override("font_size", 11)
	str_ico.add_theme_color_override("font_color", Color("ede8d8"))
	stress_h.add_child(str_ico)

	_hero_stress_bar = ProgressBar.new()
	_hero_stress_bar.custom_minimum_size = Vector2(90, 8)
	_hero_stress_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	_hero_stress_bar.show_percentage = false
	_hero_stress_bar.max_value = 100
	var str_fill := StyleBoxFlat.new()
	str_fill.bg_color = Color("ede8d8")
	_hero_stress_bar.add_theme_stylebox_override("fill", str_fill)
	stress_h.add_child(_hero_stress_bar)

	_hero_stress_label = Label.new()
	_hero_stress_label.text = "0 / 100"
	_hero_stress_label.add_theme_font_size_override("font_size", 11)
	_hero_stress_label.add_theme_color_override("font_color", Color("e0dcd0"))
	stress_h.add_child(_hero_stress_label)

	# 3. 4대 스킬 아이콘 슬롯 (일반 공격, 강타, 방어 태세, 집중)
	var skills_box := HBoxContainer.new()
	skills_box.add_theme_constant_override("separation", 6)
	skills_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_child(skills_box)

	_skill_buttons.clear()
	var skill_defs := [
		{"name": "일반 공격", "icon": "res://assets/sprites/ui/skill_attack.png", "desc": "기본 물리 타격 (1.0배 피해)", "color": Color("c79c38"), "fn": _on_attack_pressed},
		{"name": "강타", "icon": "res://assets/sprites/ui/skill_heavy.png", "desc": "치명타 일격 (1.4배 피해)", "color": Color("b33939"), "fn": _on_skill_pressed},
		{"name": "방어 태세", "icon": "res://assets/sprites/ui/skill_guard.png", "desc": "피해 감소 & 스트레스 10 진정", "color": Color("4a78a6"), "fn": _on_defend_pressed},
		{"name": "집중", "icon": "res://assets/sprites/ui/skill_focus.png", "desc": "정신 집중 & 체력 12 회복", "color": Color("3b9963"), "fn": _on_focus_pressed},
	]

	for i in skill_defs.size():
		var def = skill_defs[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(114, 64)
		btn.text = "%s [%d]" % [def["name"], i + 1]
		if ResourceLoader.exists(def["icon"]):
			btn.icon = load(def["icon"])
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		btn.tooltip_text = def["desc"]
		btn.add_theme_font_size_override("font_size", 11)

		var btn_sb := StyleBoxFlat.new()
		btn_sb.bg_color = Color("1e1915")
		btn_sb.border_color = def["color"]
		btn_sb.set_border_width_all(2)
		btn_sb.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", btn_sb)

		var hover_sb := btn_sb.duplicate()
		hover_sb.bg_color = Color("2d251f")
		btn.add_theme_stylebox_override("hover", hover_sb)

		btn.pressed.connect(def["fn"])
		skills_box.add_child(btn)
		_skill_buttons.append(btn)

	# 하단 구분선
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color("382e22")
	main_vbox.add_child(sep)

	# 하단 행: [ACC / CRIT / DMG / DODGE / PROT / SPD 6대 스탯 그리드] + [대장간 무기/방어구 레벨 뱃지]
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 16)
	main_vbox.add_child(bottom_row)

	# 6대 스탯 그리드 (2열 3행)
	var stat_grid := GridContainer.new()
	stat_grid.columns = 3
	stat_grid.add_theme_constant_override("h_separation", 24)
	stat_grid.add_theme_constant_override("v_separation", 4)
	bottom_row.add_child(stat_grid)

	var stat_keys := ["ACC", "CRIT", "DMG", "DODGE", "PROT", "SPD"]
	for k in stat_keys:
		var stat_item := HBoxContainer.new()
		stat_item.add_theme_constant_override("separation", 6)

		var k_lbl := Label.new()
		k_lbl.text = "%s:" % k
		k_lbl.add_theme_font_size_override("font_size", 11)
		k_lbl.add_theme_color_override("font_color", Color("9e8f7c"))
		stat_item.add_child(k_lbl)

		var v_lbl := Label.new()
		v_lbl.text = "-"
		v_lbl.add_theme_font_size_override("font_size", 11)
		v_lbl.add_theme_color_override("font_color", Color("e0d8c8"))
		stat_item.add_child(v_lbl)

		_stat_labels[k] = v_lbl
		stat_grid.add_child(stat_item)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bottom_row.add_child(spacer)

	# 대장간 강화 장비 뱃지 (무기 Lv.X, 방어구 Lv.X)
	var gear_box := HBoxContainer.new()
	gear_box.add_theme_constant_override("separation", 10)
	bottom_row.add_child(gear_box)

	var wpn_badge := PanelContainer.new()
	wpn_badge.custom_minimum_size = Vector2(85, 30)
	var wpn_sb := StyleBoxFlat.new()
	wpn_sb.bg_color = Color("1a1612")
	wpn_sb.border_color = Color("c79c38")
	wpn_sb.set_border_width_all(1)
	wpn_badge.add_theme_stylebox_override("panel", wpn_sb)
	var wpn_lbl := Label.new()
	wpn_lbl.text = "⚔ 무기 Lv.1"
	wpn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_lbl.add_theme_font_size_override("font_size", 10)
	wpn_lbl.add_theme_color_override("font_color", Color("f0e2b6"))
	wpn_badge.add_child(wpn_lbl)
	_gear_labels["weapon"] = wpn_lbl
	gear_box.add_child(wpn_badge)

	var arm_badge := PanelContainer.new()
	arm_badge.custom_minimum_size = Vector2(85, 30)
	var arm_sb := StyleBoxFlat.new()
	arm_sb.bg_color = Color("1a1612")
	arm_sb.border_color = Color("4a78a6")
	arm_sb.set_border_width_all(1)
	arm_badge.add_theme_stylebox_override("panel", arm_sb)
	var arm_lbl := Label.new()
	arm_lbl.text = "🛡 방어구 Lv.1"
	arm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arm_lbl.add_theme_font_size_override("font_size", 10)
	arm_lbl.add_theme_color_override("font_color", Color("b8d0e8"))
	arm_badge.add_child(arm_lbl)
	_gear_labels["armor"] = arm_lbl
	gear_box.add_child(arm_badge)

	return p


## 하단 우측 미니맵 & 전투 로그 탭 전환 패널을 생성합니다.
func _build_right_tab_panel() -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = SIZE_EXPAND_FILL
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
	_tab_map_btn.pressed.connect(func(): _switch_right_tab(true))
	tab_bar.add_child(_tab_map_btn)

	_tab_log_btn = Button.new()
	_tab_log_btn.text = "📜 전투 기록"
	_tab_log_btn.custom_minimum_size = Vector2(95, 26)
	_tab_log_btn.pressed.connect(func(): _switch_right_tab(false))
	tab_bar.add_child(_tab_log_btn)

	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	tab_bar.add_child(tab_spacer)

	_btn_auto_turn = UiKit.button("▶ 자동 진행", UiKit.GREEN)
	_btn_auto_turn.custom_minimum_size = Vector2(95, 26)
	_btn_auto_turn.pressed.connect(_on_auto_turn_pressed)
	tab_bar.add_child(_btn_auto_turn)

	_btn_retreat = UiKit.button("철수", UiKit.RED)
	_btn_retreat.custom_minimum_size = Vector2(65, 26)
	_btn_retreat.pressed.connect(func(): _end("retreat"))
	tab_bar.add_child(_btn_retreat)

	# 내용물 영역 (미니맵 컨테이너 vs 전투 로그 컨테이너)
	var content_area := PanelContainer.new()
	content_area.size_flags_vertical = SIZE_EXPAND_FILL
	var c_sb := StyleBoxFlat.new()
	c_sb.bg_color = Color("0a0807")
	content_area.add_theme_stylebox_override("panel", c_sb)
	vbox.add_child(content_area)

	# 1. 미니맵 컨테이너
	_minimap_container = _build_darkest_minimap()
	content_area.add_child(_minimap_container)

	# 2. 전투 로그 스크롤 컨테이너
	_log_container = Control.new()
	_log_container.set_anchors_preset(PRESET_FULL_RECT)
	_log_container.visible = false
	content_area.add_child(_log_container)

	_log_scroll = ScrollContainer.new()
	_log_scroll.set_anchors_preset(PRESET_FULL_RECT)
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_container.add_child(_log_scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_vbox)

	_switch_right_tab(true)
	_refresh_log_display()
	return p


## 우측 패널 탭(미니맵 vs 전투 로그)을 전환합니다.
func _switch_right_tab(show_map: bool) -> void:
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
	map_root.set_anchors_preset(PRESET_FULL_RECT)

	# 배경 눈금선 (그리드 도트 패턴 느낌)
	var grid_bg := ColorRect.new()
	grid_bg.set_anchors_preset(PRESET_FULL_RECT)
	grid_bg.color = Color("0a0907")
	map_root.add_child(grid_bg)

	var map_center := CenterContainer.new()
	map_center.set_anchors_preset(PRESET_FULL_RECT)
	map_root.add_child(map_center)

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	map_center.add_child(layout)

	# 방 구성: [방 1(탐험 완료: 체크)] --복도-- [방 2(현재 전투: 횃불)] --복도-- [방 3(보물/미탐험)] --복도-- [방 4(보스/미탐험)]
	# 1. 방 1 (입구/탐험 완료)
	layout.add_child(_create_room_node(false, true, "✔", Color("c79c38")))

	# 복도 1-2 (통과 완료)
	layout.add_child(_create_corridor_node(true))

	# 2. 방 2 (현재 전투 구역 - 타오르는 횃불 표시)
	layout.add_child(_create_room_node(true, false, "🔥", Color("ff7722")))

	# 복도 2-3 (미탐험)
	layout.add_child(_create_corridor_node(false))

	# 3. 방 3 (미탐험 보물방)
	layout.add_child(_create_room_node(false, false, "📦", Color("5c5142")))

	# 복도 3-4 (미탐험)
	layout.add_child(_create_corridor_node(false))

	# 4. 방 4 (미탐험 보스/심연)
	layout.add_child(_create_room_node(false, false, "☠", Color("5c5142")))

	# 미니맵 좌측 하단 구역 텍스트
	var area_lbl := Label.new()
	area_lbl.position = Vector2(10, 140)
	area_lbl.text = "현재 구역: 어둠의 균열 제 1 회랑"
	area_lbl.add_theme_font_size_override("font_size", 10)
	area_lbl.add_theme_color_override("font_color", Color("8a7b68"))
	map_root.add_child(area_lbl)

	return map_root


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
		dot.size_flags_vertical = SIZE_SHRINK_CENTER
		dot.color = Color("c79c38") if is_explored else Color("2d2720")
		corridor.add_child(dot)

	return corridor


## 아군 용병들과 적 몬스터 유닛들을 배틀 스테이지에 소환하고 배치합니다.
func _spawn_units() -> void:
	_party_units.clear()
	_monster_units.clear()

	# 1. 아군 용병 배치 (다키스트 던전 스타일: 좌측 1열 ~ 4/5열)
	var party_count := GameState.party.size()
	for i in party_count:
		var m: Mercenary = GameState.party[i]
		var unit = BattleUnitScene.new()
		_stage_content.add_child(unit)

		var slot_x: float = 460.0 - i * 115.0
		var slot_y: float = 165.0
		unit.position = Vector2(slot_x, slot_y)
		unit.base_position = unit.position
		unit.floating_text_pool = _ft_pool
		unit.sfx_pool = _sfx_pool
		unit.setup_as_mercenary(m)
		unit.clicked.connect(_on_unit_clicked)
		_party_units.append(unit)

	# 2. 적 몬스터 배치 (우측 1열 ~ 4/5열)
	var monster_count := _monsters_data.size()
	for i in monster_count:
		var mon: Dictionary = _monsters_data[i]
		var unit = BattleUnitScene.new()
		_stage_content.add_child(unit)

		var slot_x: float = 680.0 + i * 115.0
		var slot_y: float = 165.0
		unit.position = Vector2(slot_x, slot_y)
		unit.base_position = unit.position
		unit.floating_text_pool = _ft_pool
		unit.sfx_pool = _sfx_pool
		unit.setup_as_monster(mon)
		unit.clicked.connect(_on_unit_clicked)
		_monster_units.append(unit)

	_select_default_target()


## 살아있는 첫 번째 적 몬스터를 기본 타겟으로 설정합니다.
func _select_default_target() -> void:
	for mon in _monster_units:
		if not mon.is_dead:
			_set_target(mon)
			break


## 타겟 유닛을 지정하고 마커를 표시합니다.
func _set_target(target) -> void:
	for m in _monster_units:
		m.set_target_selected(false)
	_selected_target = target
	if target != null:
		target.set_target_selected(true)


## 유닛 클릭 이벤트 핸들러
func _on_unit_clicked(unit) -> void:
	if _is_busy or _finished:
		return
	if not unit.is_ally and not unit.is_dead:
		_set_target(unit)


## 새로운 전투 라운드를 시작합니다. 횃불 광원 감소를 처리합니다.
func _start_next_round() -> void:
	if _finished or not _fsm.go(BattleState.ROUND_START):
		return
	_round += 1
	_round_label.text = "제 %d 라운드" % _round
	_btn_retreat.disabled = _round < 1

	# 라운드 경과에 따른 횃불 광원 감소 (긴장감 부여)
	_torchlight = maxi(5, _torchlight - 4)
	_update_torchlight_display()

	_add_log("[제 %d 라운드] 교전이 격화됩니다. (광원 %d%%)" % [_round, _torchlight])
	_run_round_sequence()


## 라운드 내 아군 및 적군의 턴을 순차적으로 관리합니다.
func _run_round_sequence() -> void:
	if _check_battle_end():
		return

	var actor = _get_next_alive_ally()
	if actor != null:
		_fsm.go(BattleState.ALLY_TURN)
		_current_actor = actor
		actor.set_active_turn(true)
		_update_hero_panel(actor)

		if _auto_play:
			_set_controls_enabled(false)
			await get_tree().create_timer(0.2).timeout
			if _fsm.is_in(BattleState.ALLY_TURN) and _current_actor == actor:
				_execute_ally_attack(1.0)
		else:
			_set_controls_enabled(true)
	else:
		_current_actor = null
		_update_hero_panel(null)
		await _run_monsters_turn()

		if not _check_battle_end():
			_auto_play = false
			_reset_round_flags()
			_start_next_round()


## 다음 행동할 아군 유닛을 반환합니다.
func _get_next_alive_ally():
	for unit in _party_units:
		if not unit.is_dead and not unit.get_meta("acted", false):
			return unit
	return null


## 라운드 플래그 초기화
func _reset_round_flags() -> void:
	for u in _party_units:
		u.set_meta("acted", false)
	for u in _monster_units:
		u.set_meta("acted", false)


## 1번 스킬: 아군 일반 공격 실행
func _on_attack_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null:
		return
	_execute_ally_attack(1.0, false)


## 2번 스킬: 아군 강타/스킬 공격 실행 (1.4배 피해)
func _on_skill_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null:
		return
	_execute_ally_attack(1.4, true)


## 3번 스킬: 방어 태세 (스트레스 10 진정 및 방어 강화)
func _on_defend_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null or not _fsm.go(BattleState.ALLY_ACTING):
		return

	var actor = _current_actor
	actor.set_meta("acted", true)
	_set_controls_enabled(false)

	_add_log("🛡 %s 이(가) 방어 태세를 취하며 숨을 고른다. (스트레스 -10)" % actor.unit_name)
	actor.heal_stress(10)

	# 방어 자세 펄스 애니메이션
	var tween := create_tween()
	tween.tween_property(actor, "modulate", Color(1.2, 1.2, 1.5), 0.2)
	tween.tween_property(actor, "modulate", Color.WHITE, 0.2)

	await get_tree().create_timer(0.5).timeout
	actor.set_active_turn(false)
	_is_busy = false

	if _check_battle_end():
		return
	_run_round_sequence()


## 4번 스킬: 집중 (체력 12 회복 및 정신 집중)
func _on_focus_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null or not _fsm.go(BattleState.ALLY_ACTING):
		return

	var actor = _current_actor
	actor.set_meta("acted", true)
	_set_controls_enabled(false)

	var heal_amt := 12
	actor.current_hp = mini(actor.max_hp, actor.current_hp + heal_amt)
	if actor.merc_data != null:
		actor.merc_data.hp = actor.current_hp
	actor._update_view()

	_add_log("✦ %s 이(가) 집중하여 상처를 수습했다. (+%d HP)" % [actor.unit_name, heal_amt])

	# 치유 플로팅 텍스트 팝업
	var ft: FloatingText = null
	if _ft_pool != null:
		ft = _ft_pool.acquire() as FloatingText
		ft.on_finished = func(n: Node): _ft_pool.release(n)
	else:
		ft = FloatingTextScene.new()
		_stage_content.add_child(ft)
	ft.popup("+%d HP" % heal_amt, Color("2ecc71"), actor.global_position + Vector2(actor.size.x * 0.5, 0), false)

	# pixelfx 도트 치유 이펙트 (58프레임) 스폰
	var heal_path := "res://assets/sprites/vfx/heal/holy/heal/heal.png"
	if ResourceLoader.exists(heal_path):
		var h_tex = load(heal_path)
		if h_tex != null:
			var h_sp := Sprite2D.new()
			h_sp.texture = h_tex
			h_sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			h_sp.hframes = 58
			h_sp.frame = 0
			h_sp.position = Vector2(actor.size.x * 0.5, actor.size.y * 0.55)
			h_sp.scale = Vector2(1.2, 1.2)
			actor.add_child(h_sp)
			var h_tw := create_tween()
			h_tw.tween_property(h_sp, "frame", 57, 0.6)
			h_tw.tween_callback(h_sp.queue_free)

	await get_tree().create_timer(0.55).timeout
	actor.set_active_turn(false)
	_is_busy = false

	if _check_battle_end():
		return
	_run_round_sequence()


## 턴 일괄 자동 진행 버튼 핸들러
func _on_auto_turn_pressed() -> void:
	if _is_busy or _auto_play:
		return
	_auto_play = true
	_set_controls_enabled(false)
	if _current_actor != null:
		_execute_ally_attack(1.0)
	else:
		_run_round_sequence()


## 아군 공격 애니메이션 및 데미지 적용
func _execute_ally_attack(multiplier: float = 1.0, is_skill: bool = false) -> void:
	if _current_actor == null or not _fsm.go(BattleState.ALLY_ACTING):
		return

	var target = _selected_target
	if target == null or target.is_dead:
		_select_default_target()
		target = _selected_target

	if target == null:
		_is_busy = false
		_check_battle_end()
		return

	var actor = _current_actor
	actor.set_meta("acted", true)

	var eval := _dmg_pipeline.evaluate({
		"rng": GameState.rng(),
		"base_attack": int(actor.attack_power),
		"spread": 6,
		"is_ally": true,
		"party_bonus": GameState.party_attack_bonus(),
		"multiplier": multiplier,
		"is_skill": is_skill,
	})
	var final_dmg: int = int(eval.get("damage", 1))
	var is_crit: bool = eval.get("is_crit", false)

	var skill_text := "강타!" if is_skill else "공격!"
	_add_log("%s 의 %s → %s 에게 %d 피해%s" % [
		actor.unit_name, skill_text, target.unit_name, final_dmg, " (치명타!)" if is_crit else ""
	])

	# 직업별 공격 모션 및 타격 이펙트 (전사-베기, 마법사-번개, 총술사-총, 궁수-화살)
	var cat: String = String(actor.category_job)
	if cat.is_empty() and actor.merc_data != null:
		cat = actor.merc_data.category
	var atk_type: String = "slash"
	match cat:
		"마법사": atk_type = "lightning"
		"레인저", "도적": atk_type = "gun" if is_skill else "arrow"
		"성직자": atk_type = "lightning"
		_: atk_type = "slash"

	actor.play_attack_by_class(target, func():
		target.play_take_damage(final_dmg, is_crit, atk_type)
		if is_crit:
			trigger_screen_shake(7.0, 0.22)
		target.monster_data.hp = target.current_hp
		if target.current_hp <= 0:
			_add_log("☠ %s 처치!" % target.unit_name)
	, is_skill)

	await get_tree().create_timer(0.68).timeout
	actor.set_active_turn(false)

	if target.is_dead:
		_select_default_target()

	_is_busy = false

	if _check_battle_end():
		return

	_run_round_sequence()


## 적 몬스터들의 연속 턴 실행
func _run_monsters_turn() -> void:
	if not _fsm.go(BattleState.MONSTER_TURN):
		return
	_add_log("--- 몬스터들의 역습! ---")

	var alive_allies: Array = []
	for a in _party_units:
		if not a.is_dead:
			alive_allies.append(a)

	var alive_monsters: Array = []
	for m in _monster_units:
		if not m.is_dead:
			alive_monsters.append(m)

	for mon in alive_monsters:
		if _finished or mon.is_dead:
			continue

		alive_allies.clear()
		for a in _party_units:
			if not a.is_dead:
				alive_allies.append(a)

		if alive_allies.is_empty():
			break

		var rng := GameState.rng()
		var target = alive_allies[rng.randi_range(0, alive_allies.size() - 1)]
		var eval := _dmg_pipeline.evaluate({
			"rng": rng,
			"base_attack": int(mon.attack_power),
			"spread": 5,
			"is_ally": false,
			"multiplier": 1.0,
			"is_skill": false,
		})
		var dmg: int = int(eval.get("damage", 1))
		var is_crit: bool = eval.get("is_crit", false)

		mon.set_active_turn(true)
		await get_tree().create_timer(0.18).timeout

		_add_log("%s 의 맹공! → %s 에게 %d 피해%s" % [
			mon.unit_name, target.unit_name, dmg, " (치명타!)" if is_crit else ""
		])

		mon.play_melee_attack(target, func():
			target.play_take_damage(dmg, is_crit)
			# 피격 시 아군 스트레스 8 증가 (다키스트 던전 공포 메커니즘)
			target.add_stress(8)
			if is_crit:
				trigger_screen_shake(7.0, 0.22)
			if target.merc_data != null:
				target.merc_data.hp = target.current_hp
			if target.current_hp <= 0:
				_add_log("☠ %s 쓰러짐!" % target.unit_name)
		)

		await get_tree().create_timer(0.68).timeout
		mon.set_active_turn(false)
		await get_tree().create_timer(0.12).timeout

		if _check_battle_end():
			_is_busy = false
			return

	_is_busy = false


## 전투 종료 여부를 판정합니다 (승리/전멸).
func _check_battle_end() -> bool:
	if _finished:
		return true

	var alive_party_count := 0
	for u in _party_units:
		if not u.is_dead:
			alive_party_count += 1

	var alive_monster_count := 0
	for u in _monster_units:
		if not u.is_dead:
			alive_monster_count += 1

	if _quest_progress_label:
		_quest_progress_label.text = "처치: %d / %d" % [_monsters_data.size() - alive_monster_count, _monsters_data.size()]

	if alive_monster_count == 0:
		_add_log("★ 모든 몬스터를 처치했다! 던전 정복!")
		_end("clear")
		return true

	if alive_party_count == 0:
		_add_log("✝ 파티가 전멸했다...")
		_end("wipe")
		return true

	return false


## 영웅 정보 패널 UI (초상화, 이름/직업, HP, 스트레스, 6대 스탯, 대장간 장비)를 갱신합니다.
func _update_hero_panel(unit) -> void:
	if unit == null:
		_hero_name_label.text = "적의 차례"
		_hero_name_label.add_theme_color_override("font_color", Color("ff4d4d"))
		_hero_job_label.text = "몬스터 행동 중..."
		_hero_hp_label.text = "HP: -"
		_hero_stress_label.text = "스트레스: -"
		for k in _stat_labels:
			_stat_labels[k].text = "-"
		return

	_hero_name_label.text = unit.unit_name
	_hero_name_label.add_theme_color_override("font_color", Color("ffffff"))
	_hero_job_label.text = unit.category_job

	# 체력
	_hero_hp_bar.max_value = max(unit.max_hp, 1)
	_hero_hp_bar.value = unit.current_hp
	_hero_hp_label.text = "%d / %d" % [unit.current_hp, unit.max_hp]

	# 스트레스
	_hero_stress_bar.value = unit.current_stress
	_hero_stress_label.text = "%d / 100" % unit.current_stress

	# 초상화 아이콘
	var glyph: Label = _hero_portrait_rect.find_child("PortraitGlyph", true, false)
	if glyph:
		var cat: String = unit.merc_data.category if unit.merc_data != null else "전사"
		match cat:
			"마법사": glyph.text = "🔮"
			"레인저": glyph.text = "🏹"
			"성직자": glyph.text = "✝"
			_: glyph.text = "⚔"

	# 6대 스탯 갱신 (ACC, CRIT, DMG, DODGE, PROT, SPD)
	var m: Mercenary = unit.merc_data
	if m != null:
		_stat_labels["ACC"].text = "%d" % m.get_acc()
		_stat_labels["CRIT"].text = "%.1f%%" % m.get_crit()
		_stat_labels["DMG"].text = "%d-%d" % [m.get_dmg_min(), m.get_dmg_max()]
		_stat_labels["DODGE"].text = "%d" % m.get_dodge()
		_stat_labels["PROT"].text = "%d%%" % m.get_prot()
		_stat_labels["SPD"].text = "%d" % m.get_spd()

		# 대장간 무기/방어구 레벨 갱신
		_gear_labels["weapon"].text = "⚔ 무기 Lv.%d" % m.weapon_level
		_gear_labels["armor"].text = "🛡 방어구 Lv.%d" % m.armor_level
	else:
		_stat_labels["ACC"].text = "90"
		_stat_labels["CRIT"].text = "5.0%"
		_stat_labels["DMG"].text = "%d" % unit.attack_power
		_stat_labels["DODGE"].text = "10"
		_stat_labels["PROT"].text = "0%"
		_stat_labels["SPD"].text = "5"


## 스킬 커맨드 버튼 활성화/비활성화 처리
func _set_controls_enabled(enabled: bool) -> void:
	for btn in _skill_buttons:
		btn.disabled = not enabled
	_btn_auto_turn.disabled = not enabled


## 로그를 추가하고 UI에 표시합니다.
func _add_log(msg: String) -> void:
	_log.append(msg)
	_refresh_log_display()


## 로그 스크롤 창 갱신
func _refresh_log_display() -> void:
	if _log_vbox == null:
		return
	for c in _log_vbox.get_children():
		c.queue_free()

	var recent := _log.slice(maxi(0, _log.size() - 30))
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


## 크리티컬 타격 시 화면 흔들림(Screen Shake) 효과를 연출합니다.
func trigger_screen_shake(amount: float = 6.0, duration: float = 0.22) -> void:
	if not is_inside_tree() or _stage_content == null:
		return
	var sm = get_node_or_null("/root/SettingsManager")
	if sm != null and not sm.gameplay.get("screen_shake", true):
		return

	var orig_pos := Vector2.ZERO
	var tween := create_tween()
	var steps := 4
	for i in steps:
		var offset := Vector2(randf_range(-amount, amount), randf_range(-amount * 0.6, amount * 0.6))
		tween.tween_property(_stage_content, "position", orig_pos + offset, duration / float(steps * 2))
		tween.tween_property(_stage_content, "position", orig_pos, duration / float(steps * 2))


## 전투 종료 처리 및 결과 씬 전환
func _end(outcome: String) -> void:
	if _finished or not _fsm.go(BattleState.FINISHED):
		return
	_btn_retreat.disabled = true
	_set_controls_enabled(false)

	GameState.finalize_expedition(outcome, _base_gold)

	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func():
		get_tree().change_scene_to_file(GameState.SCENE_RESULT)
	)
