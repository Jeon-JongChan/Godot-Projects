class_name BattleUnit
extends Control

## 다키스트 던전 1 스타일의 턴제 전투 유닛 시각화 및 애니메이션 컴포넌트.
## 아군(용병) 또는 적군(몬스터) 데이터를 바인딩하여 2D 사이드뷰 형태로 표시하며,
## 고딕 스타일 체력바, 10칸 분할 스트레스 핍 게이지, 머리 위 가시관 후광 및 발밑 액티브/타겟 마커를 지원합니다.

const FloatingTextScene = preload("res://scenes/expedition/entities/floating_text.gd")

# ── [경량화] 공유 효과음 에셋 & [오브젝트 풀] 데미지 텍스트/오디오 풀 참조 ──
static var _sfx_normal_stream: AudioStream = null
static var _sfx_crit_stream: AudioStream = null
static var _sprite_tex_cache: Dictionary = {}
static var _vfx_sheet_cache: Dictionary = {}
var floating_text_pool: ObjectPool = null
var sfx_pool: ObjectPool = null
var _anim_sprite: Sprite2D = null
var _anim_frame_count: int = 0
var _anim_fps: float = 24.0
var _anim_acc: float = 0.0

signal clicked(unit: BattleUnit)

# ── 유닛 기본 데이터 ──
var is_ally: bool = true
var merc_data: Mercenary = null
var monster_data: Dictionary = {}
var unit_name: String = ""
var max_hp: int = 100
var current_hp: int = 100
var current_stress: int = 0
var max_stress: int = 100
var attack_power: int = 10
var category_job: String = ""

# ── 전투 및 턴 상태 변수 ──
var is_dead: bool = false
var is_active_turn: bool = false
var is_target_selected: bool = false
var base_position: Vector2 = Vector2.ZERO

# ── 시각적 노드 참조 ──
var _visual_root: Control
var _shadow: Polygon2D
var _ground_active_aura: Node2D
var _ground_target_bracket: Node2D
var _unit_shape: Control
var _sprite_rect: TextureRect

# ── 고딕 상태 표시창 (체력바, 스트레스 핍) ──
var _status_box: VBoxContainer
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_frame: PanelContainer
var _hp_label: Label
var _stress_box: HBoxContainer
var _stress_pips: Array[Panel] = []

# ── 다키스트 던전 머리 위 후광 및 조준 마커 ──
var _head_turn_marker: Node2D
var _head_target_marker: Node2D
var _turn_halo_tween: Tween
var _target_halo_tween: Tween
var _idle_tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(110, 205)
	size = Vector2(110, 205)
	pivot_offset = Vector2(55, 100)
	mouse_filter = MOUSE_FILTER_PASS
	_build_ui()


func _ready() -> void:
	_start_idle_motion()


## 유닛을 아군(Mercenary) 데이터로 초기화합니다.
func setup_as_mercenary(m: Mercenary) -> void:
	is_ally = true
	merc_data = m
	unit_name = m.merc_name
	max_hp = m.max_hp
	current_hp = m.hp
	current_stress = m.stress
	attack_power = m.attack
	category_job = "%s · %s" % [m.category, m.job]
	_update_view()


## 유닛을 적 몬스터(Dictionary) 데이터로 초기화합니다.
func setup_as_monster(mon: Dictionary) -> void:
	is_ally = false
	monster_data = mon
	unit_name = mon.get("name", "몬스터")
	max_hp = mon.get("max_hp", 50)
	current_hp = mon.get("hp", 50)
	current_stress = 0
	attack_power = mon.get("attack", 10)
	category_job = "어둠의 권속"
	_update_view()


## 외부에서 전달받은 커스텀 텍스처(스프라이트)를 적용합니다.
func set_sprite_texture(tex: Texture2D) -> void:
	if _sprite_rect:
		_sprite_rect.texture = tex
		_sprite_rect.visible = tex != null
		if _unit_shape:
			_unit_shape.visible = tex == null


## 유닛의 UI 노드 트리와 고딕 시각 컴포넌트들을 빌드합니다.
func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	_visual_root = Control.new()
	_visual_root.set_anchors_preset(PRESET_FULL_RECT)
	_visual_root.mouse_filter = MOUSE_FILTER_PASS
	add_child(_visual_root)

	# 1. 발밑 그림자 (타원형 다크 섀도우)
	_shadow = Polygon2D.new()
	_shadow.color = Color(0, 0, 0, 0.65)
	var shadow_points := PackedVector2Array()
	var cx := 55.0
	var cy := 158.0
	for i in 16:
		var rad := i * (PI * 2.0 / 16.0)
		shadow_points.append(Vector2(cx + cos(rad) * 40.0, cy + sin(rad) * 14.0))
	_shadow.polygon = shadow_points
	_visual_root.add_child(_shadow)

	# 2. 발밑 액티브 턴 후광 링 (Ground Active Aura)
	_build_ground_active_aura()

	# 3. 발밑 타겟 선택 브래킷 (Ground Target Bracket `[   ]`)
	_build_ground_target_bracket()

	# 4. 캐릭터 그래픽 노드 (도형 플레이스홀더)
	_unit_shape = Control.new()
	_unit_shape.position = Vector2(0, 20)
	_unit_shape.size = Vector2(110, 140)
	_unit_shape.mouse_filter = MOUSE_FILTER_PASS
	_visual_root.add_child(_unit_shape)

	# 5. 스프라이트 이미지 슬롯 (추후 에셋 교체용)
	_sprite_rect = TextureRect.new()
	_sprite_rect.position = Vector2(10, 20)
	_sprite_rect.size = Vector2(90, 140)
	_sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite_rect.visible = false
	_visual_root.add_child(_sprite_rect)

	# 6. 머리 위 고딕 가시관 액티브 마커 (Iron Crown / Radiant Spike Halo)
	_build_head_turn_marker()

	# 7. 머리 위 타겟 조준 마커 (Crosshair / Reticle)
	_build_head_target_marker()

	# 8. 하단 다키스트 던전 스타일 상태창 (이름, 체력바, 스트레스 핍)
	_build_status_panel()


## 발밑에 표시되는 현재 턴 황금빛 룬 후광 원형 링을 생성합니다.
func _build_ground_active_aura() -> void:
	_ground_active_aura = Node2D.new()
	_ground_active_aura.visible = false
	_ground_active_aura.position = Vector2(55, 158)
	_visual_root.add_child(_ground_active_aura)

	# 외부 룬 원형
	var outer_ring := Line2D.new()
	outer_ring.width = 2.0
	outer_ring.default_color = Color("d4af37") # 황금빛
	var ring_pts := PackedVector2Array()
	for i in 25:
		var rad := i * (PI * 2.0 / 24.0)
		ring_pts.append(Vector2(cos(rad) * 44.0, sin(rad) * 15.0))
	outer_ring.points = ring_pts
	_ground_active_aura.add_child(outer_ring)

	# 내부 은은한 글로우 채움
	var inner_fill := Polygon2D.new()
	inner_fill.color = Color(0.83, 0.68, 0.21, 0.18)
	var fill_pts := PackedVector2Array()
	for i in 16:
		var rad := i * (PI * 2.0 / 16.0)
		fill_pts.append(Vector2(cos(rad) * 40.0, sin(rad) * 13.0))
	inner_fill.polygon = fill_pts
	_ground_active_aura.add_child(inner_fill)

	# 4방향 고딕 황금 가시 눈금
	for deg: float in [0.0, 90.0, 180.0, 270.0]:
		var rad: float = deg_to_rad(deg)
		var tick := Line2D.new()
		tick.width = 2.0
		tick.default_color = Color("fff0a0")
		var p1 := Vector2(cos(rad) * 36.0, sin(rad) * 12.0)
		var p2 := Vector2(cos(rad) * 48.0, sin(rad) * 17.0)
		tick.points = PackedVector2Array([p1, p2])
		_ground_active_aura.add_child(tick)


## 다키스트 던전 특유의 발밑 타겟 괄호 브래킷 `[   ]` 마커를 생성합니다.
func _build_ground_target_bracket() -> void:
	_ground_target_bracket = Node2D.new()
	_ground_target_bracket.visible = false
	_ground_target_bracket.position = Vector2(55, 158)
	_visual_root.add_child(_ground_target_bracket)

	var bracket_color := Color("ff3333") # 타겟 붉은색

	# 좌측 괄호 `[`
	var left_bracket := Line2D.new()
	left_bracket.width = 2.5
	left_bracket.default_color = bracket_color
	left_bracket.points = PackedVector2Array([
		Vector2(-35, -8), Vector2(-46, -8), Vector2(-46, 8), Vector2(-35, 8)
	])
	_ground_target_bracket.add_child(left_bracket)

	# 우측 괄호 `]`
	var right_bracket := Line2D.new()
	right_bracket.width = 2.5
	right_bracket.default_color = bracket_color
	right_bracket.points = PackedVector2Array([
		Vector2(35, -8), Vector2(46, -8), Vector2(46, 8), Vector2(35, 8)
	])
	_ground_target_bracket.add_child(right_bracket)


## 머리 위에 위치하는 다키스트 던전 시그니처 가시관/햇살 룬 엠블럼을 생성합니다.
func _build_head_turn_marker() -> void:
	_head_turn_marker = Node2D.new()
	_head_turn_marker.position = Vector2(55, 12)
	_head_turn_marker.visible = false
	_visual_root.add_child(_head_turn_marker)

	# 1) 중앙 철제 링
	var ring := Line2D.new()
	ring.width = 2.2
	ring.default_color = Color("f5cf47") # 밝은 황금색
	var ring_pts := PackedVector2Array()
	for i in 17:
		var rad := i * (PI * 2.0 / 16.0)
		ring_pts.append(Vector2(cos(rad) * 11.0, sin(rad) * 11.0))
	ring.points = ring_pts
	_head_turn_marker.add_child(ring)

	# 2) 7방향 방사형 고딕 가시 스파이크 (Darkest Dungeon Iron Crown 형태)
	var angles: Array[float] = [-135.0, -90.0, -45.0, 0.0, 45.0, 90.0, 135.0, 180.0]
	for a in angles:
		var rad := deg_to_rad(a)
		var spike := Line2D.new()
		spike.width = 2.0
		spike.default_color = Color("fff5a6")
		var p1 := Vector2(cos(rad) * 11.0, sin(rad) * 11.0)
		var p2 := Vector2(cos(rad) * 18.0, sin(rad) * 18.0)
		spike.points = PackedVector2Array([p1, p2])
		_head_turn_marker.add_child(spike)

	# 3) 중앙 고딕 다이아몬드 코어
	var core := Polygon2D.new()
	core.color = Color("ffea75")
	core.polygon = PackedVector2Array([
		Vector2(0, -5), Vector2(4, 0), Vector2(0, 5), Vector2(-4, 0)
	])
	_head_turn_marker.add_child(core)


## 머리 위에 위치하는 타겟 조준용 고딕 크로스헤어 마커를 생성합니다.
func _build_head_target_marker() -> void:
	_head_target_marker = Node2D.new()
	_head_target_marker.position = Vector2(55, 12)
	_head_target_marker.visible = false
	_visual_root.add_child(_head_target_marker)

	# 날카로운 붉은색 역삼각형 및 크로스헤어
	var tri := Polygon2D.new()
	tri.color = Color("ff2e2e")
	tri.polygon = PackedVector2Array([
		Vector2(-9, -8), Vector2(9, -8), Vector2(0, 6)
	])
	_head_target_marker.add_child(tri)

	# 크로스 십자 가시선
	var cross_v := Line2D.new()
	cross_v.width = 1.8
	cross_v.default_color = Color("ffffff")
	cross_v.points = PackedVector2Array([Vector2(0, -14), Vector2(0, 10)])
	_head_target_marker.add_child(cross_v)

	var cross_h := Line2D.new()
	cross_h.width = 1.8
	cross_h.default_color = Color("ffffff")
	cross_h.points = PackedVector2Array([Vector2(-12, -4), Vector2(12, -4)])
	_head_target_marker.add_child(cross_h)


## 하단 다키스트 던전 스타일 상태창 (이름, 체력바, 스트레스 핍)을 구축합니다.
func _build_status_panel() -> void:
	_status_box = VBoxContainer.new()
	_status_box.position = Vector2(0, 166)
	_status_box.size = Vector2(110, 36)
	_status_box.add_theme_constant_override("separation", 2)
	_status_box.mouse_filter = MOUSE_FILTER_IGNORE
	_visual_root.add_child(_status_box)

	# 1. 캐릭터 이름 라벨
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", UiKit.TEXT)
	_status_box.add_child(_name_label)

	# 2. 다키스트 던전 스타일 체력바 (다크 철제 외곽 프레임 + 핏빛 그라데이션)
	_hp_frame = PanelContainer.new()
	_hp_frame.custom_minimum_size = Vector2(106, 9)
	_hp_frame.size_flags_horizontal = SIZE_SHRINK_CENTER
	_hp_frame.mouse_filter = MOUSE_FILTER_IGNORE

	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color("0d0b09") # 암흑 바탕
	frame_sb.border_color = Color("383025") # 고딕 흑철/황동 테두리
	frame_sb.set_border_width_all(1)
	frame_sb.set_corner_radius_all(1)
	_hp_frame.add_theme_stylebox_override("panel", frame_sb)
	_status_box.add_child(_hp_frame)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(104, 7)
	_hp_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = SIZE_EXPAND_FILL
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = MOUSE_FILTER_IGNORE

	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color("150909") # 핏빛 음영 배경
	_hp_bar.add_theme_stylebox_override("background", hp_bg)
	_hp_frame.add_child(_hp_bar)

	# 체력바 위/아래 HP 수치 라벨
	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 8)
	_hp_label.add_theme_color_override("font_color", Color("cccccc"))
	_status_box.add_child(_hp_label)

	# 3. 10칸 분할 스트레스 핍 (Stress Pips 게이지: 아군 전용)
	_stress_box = HBoxContainer.new()
	_stress_box.custom_minimum_size = Vector2(106, 6)
	_stress_box.size_flags_horizontal = SIZE_SHRINK_CENTER
	_stress_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_stress_box.add_theme_constant_override("separation", 2)
	_stress_box.mouse_filter = MOUSE_FILTER_IGNORE
	_status_box.add_child(_stress_box)

	_stress_pips.clear()
	for i in 10:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(8, 5)
		pip.mouse_filter = MOUSE_FILTER_IGNORE
		_stress_box.add_child(pip)
		_stress_pips.append(pip)


## 10칸 분할 스트레스 핍의 시각 상태를 갱신합니다. (10스트레스 당 1칸)
func _update_stress_pips() -> void:
	if not is_ally:
		_stress_box.visible = false
		return

	_stress_box.visible = true
	var filled_pips := int(clamp(current_stress / 10, 0, 10))

	for i in 10:
		var pip: Panel = _stress_pips[i]
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(1)

		if i < filled_pips:
			# 채워진 핍: 백색/크림 골드 (스트레스 수치에 따라 80이상 경고 주황, 100 붉은색)
			if current_stress >= 100:
				sb.bg_color = Color("ff2b2b") # 붕괴/고통 적색광
				sb.border_color = Color("ffffff")
			elif current_stress >= 70:
				sb.bg_color = Color("f5a623") # 경고 주황빛
				sb.border_color = Color("ffd280")
			else:
				sb.bg_color = Color("ede8d8") # 정통 다키스트 던전 백색/크림 핍
				sb.border_color = Color("ffffff")
		else:
			# 빈 핍: 어두운 고딕 프레임
			sb.bg_color = Color("141210")
			sb.border_color = Color("2c2620")

		pip.add_theme_stylebox_override("panel", sb)


## 현재 체력, 스트레스, 상태에 맞춰 UI를 갱신합니다.
func _update_view() -> void:
	_name_label.text = unit_name
	_hp_label.text = "%d / %d" % [current_hp, max_hp]
	_hp_bar.max_value = max(max_hp, 1)
	_hp_bar.value = clamp(current_hp, 0, max_hp)

	# 다키스트 던전 스타일 체력바 그라데이션 채움 스타일 적용
	var hp_ratio := float(current_hp) / float(max(max_hp, 1))
	var fill_sb := StyleBoxFlat.new()
	fill_sb.set_corner_radius_all(1)

	if is_ally:
		# 아군: 핏빛 레드 ~ 에메랄드/골드
		if hp_ratio > 0.6:
			fill_sb.bg_color = Color("2e914d") # 안정적 녹색
		elif hp_ratio > 0.25:
			fill_sb.bg_color = Color("c78b24") # 주의 황금색
		else:
			fill_sb.bg_color = Color("b81414") # 빈사/죽음의 문턱 적색
	else:
		# 적군: 짙은 크림슨 레드
		fill_sb.bg_color = Color("a81818")

	_hp_bar.add_theme_stylebox_override("fill", fill_sb)

	# 스트레스 핍 갱신 (아군 전용)
	_update_stress_pips()

	if current_hp <= 0 and not is_dead:
		_on_death()

	_draw_placeholder()


## 아군 유닛의 스트레스를 증가시키고 시각 효과를 연출합니다.
func add_stress(amount: int) -> void:
	if not is_ally or is_dead:
		return
	current_stress = clamp(current_stress + amount, 0, max_stress)
	if merc_data != null:
		merc_data.stress = current_stress
	_update_stress_pips()

	# 스트레스 플로팅 텍스트 팝업 (검은색/보라색 텍스트)
	var ft: FloatingText = null
	if floating_text_pool != null:
		ft = floating_text_pool.acquire() as FloatingText
		ft.on_finished = func(n: Node): floating_text_pool.release(n)
	else:
		ft = FloatingTextScene.new()
		get_parent().add_child(ft)
	ft.popup("+%d 스트레스" % amount, Color("d154ec"), global_position + Vector2(size.x * 0.5, 0), false)


## 아군 유닛의 스트레스를 회복시키고 시각 효과를 연출합니다.
func heal_stress(amount: int) -> void:
	if not is_ally or is_dead:
		return
	current_stress = clamp(current_stress - amount, 0, max_stress)
	if merc_data != null:
		merc_data.stress = current_stress
	_update_stress_pips()

	# 스트레스 해소 플로팅 텍스트 팝업 (하늘색/청록색 텍스트)
	var ft: FloatingText = null
	if floating_text_pool != null:
		ft = floating_text_pool.acquire() as FloatingText
		ft.on_finished = func(n: Node): floating_text_pool.release(n)
	else:
		ft = FloatingTextScene.new()
		get_parent().add_child(ft)
	ft.popup("-%d 스트레스" % amount, Color("4cd9c0"), global_position + Vector2(size.x * 0.5, 0), false)


## 타겟 선택 여부를 전환하며 발밑 브래킷 및 머리 위 조준 마커를 제어합니다.
func set_target_selected(selected: bool) -> void:
	is_target_selected = selected
	_head_target_marker.visible = selected
	_ground_target_bracket.visible = selected

	if _target_halo_tween and _target_halo_tween.is_valid():
		_target_halo_tween.kill()

	if selected:
		modulate = Color(1.2, 1.08, 1.08)
		# 조준 마커 펄스 애니메이션
		_target_halo_tween = create_tween().set_loops()
		_target_halo_tween.tween_property(_head_target_marker, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_SINE)
		_target_halo_tween.tween_property(_head_target_marker, "scale", Vector2(0.95, 0.95), 0.35).set_trans(Tween.TRANS_SINE)
	else:
		_head_target_marker.scale = Vector2(1.0, 1.0)
		modulate = Color.WHITE if not is_dead else Color(0.4, 0.4, 0.4, 0.5)


## 현재 턴 활성화 상태(한 발 전진, 머리 위 가시관 후광, 발밑 황금 룬 링)를 제어합니다.
func set_active_turn(active: bool) -> void:
	is_active_turn = active
	_head_turn_marker.visible = active
	_ground_active_aura.visible = active

	if _turn_halo_tween and _turn_halo_tween.is_valid():
		_turn_halo_tween.kill()

	if active:
		# 가시관 상하 부유 및 맥동 애니메이션
		_turn_halo_tween = create_tween().set_loops()
		_turn_halo_tween.tween_property(_head_turn_marker, "position:y", 6.0, 0.5).set_trans(Tween.TRANS_SINE)
		_turn_halo_tween.tween_property(_head_turn_marker, "position:y", 12.0, 0.5).set_trans(Tween.TRANS_SINE)
	else:
		_head_turn_marker.position.y = 12.0

	var target_x: float = base_position.x + (24.0 if is_ally else -24.0)
	var final_x: float = target_x if active else base_position.x

	if is_inside_tree():
		var tween := create_tween()
		tween.tween_property(self, "position:x", final_x, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		position.x = final_x


## 유닛의 대기 호흡 모션 (상하 펄스)을 시작합니다.
func _start_idle_motion() -> void:
	if not is_inside_tree() or is_dead:
		return
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_visual_root, "scale", Vector2(1.0, 0.97), 1.2).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(_visual_root, "scale", Vector2(1.0, 1.0), 1.2).set_trans(Tween.TRANS_SINE)


## 아군/적군 도트 스프라이트(TextureRect/Sprite2D)를 우선 적용하고, 없을 경우 고딕 실루엣으로 폴백한다.
func _draw_placeholder() -> void:
	for c in _unit_shape.get_children():
		c.queue_free()
	_anim_sprite = null
	_anim_frame_count = 0

	var base_color: Color = UiKit.GOLD if is_ally else Color("9a3838")
	if is_ally and merc_data != null:
		base_color = JobDb.category_color(merc_data.category)

	# 1) 베이스 플랫폼 (발밑 그림자 타원)
	var base_ring := Polygon2D.new()
	base_ring.color = Color(0, 0, 0, 0.45)
	base_ring.polygon = PackedVector2Array([
		Vector2(25, 138), Vector2(85, 138), Vector2(92, 145),
		Vector2(85, 151), Vector2(25, 151), Vector2(18, 145)
	])
	_unit_shape.add_child(base_ring)

	if is_ally:
		var cat := merc_data.category if merc_data != null else "전사"
		var p := str(JobDb.visual_spec(cat).get("hero_sprite", ""))
		var tex := UiKit.get_cached_texture(p)
		if tex != null:
			_attach_crisp_sprite(tex, false)
			return
		_draw_ally_silhouette(base_color)
	else:
		# 고해상도 다키스트 던전 풍 4종 몬스터 정적 도트 스프라이트 배분
		var mob_keys := ["mob_skeleton", "mob_cultist", "mob_eldritch", "mob_wraith"]
		var mob_key: String = mob_keys[absi(unit_name.hash()) % mob_keys.size()]
		var m_tex := _get_cached_tex("res://assets/sprites/characters/%s.png" % mob_key)
		if m_tex != null:
			_attach_crisp_sprite(m_tex, false)
			return
		_draw_monster_silhouette(base_color)


func _get_cached_tex(path: String) -> Texture2D:
	if _sprite_tex_cache.has(path):
		return _sprite_tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_sprite_tex_cache[path] = tex
	return tex


func _attach_crisp_sprite(tex: Texture2D, flip_h: bool = false) -> void:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.flip_h = flip_h
	# 유닛 표준 발 위치 (55, 146) 정렬 및 적정 높이(128px) 스케일
	var target_h := 130.0
	var sc := target_h / maxf(1.0, float(tex.get_height()))
	sp.scale = Vector2(sc, sc)
	sp.position = Vector2(55.0, 146.0 - float(tex.get_height()) * sc * 0.5)
	_unit_shape.add_child(sp)


func _attach_animated_sheet(tex: Texture2D, frame_cnt: int, flip_h: bool = false, scale_mult: float = 1.0) -> void:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.hframes = frame_cnt
	sp.frame = 0
	sp.flip_h = flip_h
	var fh := float(tex.get_height())
	var sc := (105.0 * scale_mult) / maxf(1.0, fh)
	sp.scale = Vector2(sc, sc)
	sp.position = Vector2(55.0, 146.0 - fh * sc * 0.5)
	_unit_shape.add_child(sp)
	_anim_sprite = sp
	_anim_frame_count = frame_cnt
	set_process(true)


func _process(delta: float) -> void:
	if _anim_sprite != null and is_instance_valid(_anim_sprite) and _anim_frame_count > 0:
		_anim_acc += delta * _anim_fps
		_anim_sprite.frame = int(_anim_acc) % _anim_frame_count


## 아군 고딕 실루엣 드로잉 (다키스트 던전 1 스타일: 짙은 블랙 섀도우, 가려진 눈, 고대비 잉크 펜화)
func _draw_ally_silhouette(accent: Color) -> void:
	var cat := merc_data.category if merc_data != null else "전사"

	# 1. 망토 / 코트 (휘날리는 짙은 고딕 실루엣)
	var cloak := Polygon2D.new()
	cloak.color = Color("141116")
	cloak.polygon = PackedVector2Array([
		Vector2(32, 42), Vector2(78, 42), Vector2(88, 132), Vector2(65, 126), Vector2(20, 132)
	])
	_unit_shape.add_child(cloak)

	# 망토 주름 라인
	var cloak_line := Line2D.new()
	cloak_line.width = 2.0
	cloak_line.default_color = Color("08060a")
	cloak_line.points = PackedVector2Array([Vector2(36, 50), Vector2(28, 120)])
	_unit_shape.add_child(cloak_line)

	# 2. 갑옷 / 흉갑 및 가죽 서콧
	var armor := Polygon2D.new()
	armor.color = Color("2e2a34") if cat == "전사" else Color("221820")
	armor.polygon = PackedVector2Array([
		Vector2(36, 46), Vector2(74, 46), Vector2(70, 96), Vector2(40, 96)
	])
	_unit_shape.add_child(armor)

	# 견갑 (어깨 아머)
	for side: float in [-1.0, 1.0]:
		var pauldron := Polygon2D.new()
		pauldron.color = Color("44404e")
		var px: float = 55.0 + side * 22.0
		pauldron.polygon = PackedVector2Array([
			Vector2(px - 10, 42), Vector2(px + 10, 42), Vector2(px + 8, 62), Vector2(px - 8, 62)
		])
		_unit_shape.add_child(pauldron)

	# 3. 직업별 다키스트 던전 시그니처 페이스 & 헤드기어 (눈이 섀도우에 완전히 가려짐!)
	match cat:
		"전사":
			# 성전사: 풀페이스 철제 헬름, 검은색 T자형 바이저 슬릿
			var helm := Polygon2D.new()
			helm.color = Color("4a505e")
			helm.polygon = PackedVector2Array([
				Vector2(42, 18), Vector2(68, 18), Vector2(70, 44), Vector2(55, 52), Vector2(40, 44)
			])
			_unit_shape.add_child(helm)
			# T자 슬릿 섀도우
			var slit := Line2D.new()
			slit.width = 3.5
			slit.default_color = Color("060608")
			slit.points = PackedVector2Array([Vector2(46, 32), Vector2(64, 32)])
			_unit_shape.add_child(slit)
			var slit_v := Line2D.new()
			slit_v.width = 3.5
			slit_v.default_color = Color("060608")
			slit_v.points = PackedVector2Array([Vector2(55, 32), Vector2(55, 48)])
			_unit_shape.add_child(slit_v)

		"마법사", "성직자":
			# 사제/마법사: 깊은 로브 후드, 챙 그늘에 가려진 칠흑의 얼굴, 금빛 십자가
			var hood := Polygon2D.new()
			hood.color = Color("28182a")
			hood.polygon = PackedVector2Array([
				Vector2(55, 10), Vector2(74, 46), Vector2(36, 46)
			])
			_unit_shape.add_child(hood)
			# 후드 내부 칠흑 섀도우
			var shadow_face := Polygon2D.new()
			shadow_face.color = Color("08050a")
			shadow_face.polygon = PackedVector2Array([
				Vector2(55, 20), Vector2(68, 44), Vector2(42, 44)
			])
			_unit_shape.add_child(shadow_face)

		"레인저", "도적":
			# 도굴꾼/현상금 사냥꾼: 챙 넓은 모자, 복면, 날카로운 실루엣
			var hat := Polygon2D.new()
			hat.color = Color("221814")
			hat.polygon = PackedVector2Array([
				Vector2(30, 26), Vector2(80, 22), Vector2(68, 12), Vector2(42, 14)
			])
			_unit_shape.add_child(hat)
			var mask := Polygon2D.new()
			mask.color = Color("14100c")
			mask.polygon = PackedVector2Array([
				Vector2(44, 32), Vector2(66, 32), Vector2(55, 48)
			])
			_unit_shape.add_child(mask)

		_:
			var head_default := Polygon2D.new()
			head_default.color = Color("38323a")
			head_default.polygon = PackedVector2Array([
				Vector2(44, 20), Vector2(66, 20), Vector2(68, 46), Vector2(42, 46)
			])
			_unit_shape.add_child(head_default)

	# 4. 직업별 다키스트 던전 상징 무기 드로잉 (은빛 날, 피 묻은 엣지, 묵직한 메이스)
	match cat:
		"전사":
			# 거대한 흑철 그레이트소드 (양손 대검)
			var sword_blade := Polygon2D.new()
			sword_blade.color = Color("c8d0da")
			sword_blade.polygon = PackedVector2Array([
				Vector2(78, 14), Vector2(86, 14), Vector2(84, 115), Vector2(80, 115)
			])
			_unit_shape.add_child(sword_blade)
			# 칼날 중앙 핏빛/하이라이트 엣지
			var sword_line := Line2D.new()
			sword_line.width = 1.5
			sword_line.default_color = Color("ffffff")
			sword_line.points = PackedVector2Array([Vector2(82, 14), Vector2(82, 115)])
			_unit_shape.add_child(sword_line)
			# 코등이
			var cross := Line2D.new()
			cross.width = 4.5
			cross.default_color = Color("d4af37")
			cross.points = PackedVector2Array([Vector2(72, 86), Vector2(92, 86)])
			_unit_shape.add_child(cross)

		"마법사":
			# 비전 지팡이와 이글거리는 룬 구체
			var staff := Line2D.new()
			staff.width = 4.0
			staff.default_color = Color("3c2418")
			staff.points = PackedVector2Array([Vector2(82, 18), Vector2(82, 125)])
			_unit_shape.add_child(staff)
			var rune_orb := Polygon2D.new()
			rune_orb.color = Color("b844ff")
			rune_orb.polygon = PackedVector2Array([
				Vector2(82, 10), Vector2(89, 17), Vector2(82, 24), Vector2(75, 17)
			])
			_unit_shape.add_child(rune_orb)

		"성직자":
			# 성스러운 철제 플랜지 메이스 (Mace)
			var mace_handle := Line2D.new()
			mace_handle.width = 3.5
			mace_handle.default_color = Color("443022")
			mace_handle.points = PackedVector2Array([Vector2(80, 40), Vector2(80, 110)])
			_unit_shape.add_child(mace_handle)
			var mace_head := Polygon2D.new()
			mace_head.color = Color("8c94a4")
			mace_head.polygon = PackedVector2Array([
				Vector2(74, 30), Vector2(86, 30), Vector2(88, 52), Vector2(72, 52)
			])
			_unit_shape.add_child(mace_head)

		"레인저", "도적":
			# 도굴용 피켈 곡괭이 / 쇠뇌 활
			var bow := Line2D.new()
			bow.width = 3.0
			bow.default_color = Color("5c3c24")
			bow.points = PackedVector2Array([
				Vector2(26, 30), Vector2(16, 75), Vector2(26, 120)
			])
			_unit_shape.add_child(bow)


## 적 몬스터 실루엣 드로잉 (다키스트 던전 스타일: 해골, 촉수 괴수, 깊은 블랙 섀도우)
func _draw_monster_silhouette(accent: Color) -> void:
	# 1. 흉측한 괴수 몸통 실루엣
	var body := Polygon2D.new()
	body.color = Color("181014")
	body.polygon = PackedVector2Array([
		Vector2(55, 24), Vector2(88, 55), Vector2(84, 132), Vector2(26, 132), Vector2(22, 55)
	])
	_unit_shape.add_child(body)

	# 2. 늑골/해골 뼈마디 음영
	for row in range(4):
		var rib := Line2D.new()
		rib.width = 2.5
		rib.default_color = Color("382e36")
		var ry := 65.0 + row * 14.0
		rib.points = PackedVector2Array([Vector2(42, ry), Vector2(55, ry - 3), Vector2(68, ry)])
		_unit_shape.add_child(rib)

	# 3. 뒤틀린 가시 뿔 및 촉수
	var horns := Polygon2D.new()
	horns.color = Color("3a121a")
	horns.polygon = PackedVector2Array([
		Vector2(38, 35), Vector2(16, 8), Vector2(30, 30),
		Vector2(72, 35), Vector2(94, 8), Vector2(80, 30)
	])
	_unit_shape.add_child(horns)

	# 4. 안광이 없는 텅 빈 핏빛 눈빛 (기괴한 붉은 광채)
	var eye_l := Polygon2D.new()
	eye_l.color = Color("ff1828")
	eye_l.polygon = PackedVector2Array([Vector2(44, 42), Vector2(49, 44), Vector2(45, 48)])
	_unit_shape.add_child(eye_l)

	var eye_r := Polygon2D.new()
	eye_r.color = Color("ff1828")
	eye_r.polygon = PackedVector2Array([Vector2(66, 42), Vector2(61, 44), Vector2(65, 48)])
	_unit_shape.add_child(eye_r)

	# 5. 괴수의 핏빛 발톱/부러진 칼
	var claw := Line2D.new()
	claw.width = 3.0
	claw.default_color = Color("721820")
	claw.points = PackedVector2Array([Vector2(20, 85), Vector2(10, 115), Vector2(14, 125)])
	_unit_shape.add_child(claw)


## 1. 전사: 근접 돌진 대검 베기 애니메이션을 재생합니다.
func play_melee_attack(target_unit: BattleUnit, on_impact: Callable = Callable()) -> void:
	var start_pos := position
	var dir := 1.0 if is_ally else -1.0
	var rush_target := target_unit.position - Vector2(dir * 70.0, 0)

	var tween := create_tween()
	tween.tween_property(self, "position:x", start_pos.x - dir * 16.0, 0.12).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position", rush_target, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if on_impact.is_valid():
		tween.tween_callback(on_impact)
	tween.tween_interval(0.12)
	tween.tween_property(self, "position", start_pos, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 2. 마법사: 비전 마력 영창 및 하늘에서 내리꽂히는 번개(Lightning) 공격을 재생합니다.
func play_mage_attack(target_unit: BattleUnit, on_impact: Callable = Callable()) -> void:
	var start_pos := position
	var tween := create_tween()
	# 공중 부유 및 신비로운 보랏빛/청백색 마력 오라 펄스
	modulate = Color(1.6, 1.2, 2.2)
	tween.tween_property(self, "position:y", start_pos.y - 20.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.18, 1.18), 0.18)
	tween.tween_callback(func():
		modulate = Color(2.0, 2.0, 2.5) # 섬광 방출
		if on_impact.is_valid():
			on_impact.call()
	)
	tween.tween_interval(0.18)
	tween.tween_property(self, "position:y", start_pos.y, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.25)
	tween.parallel().tween_property(self, "modulate", Color.WHITE, 0.25)


## 3. 총술사: 화약 권총/소총 사격 반동 킥백 및 머즐 플래시(Gun Shot)를 재생합니다.
func play_gun_attack(target_unit: BattleUnit, on_impact: Callable = Callable()) -> void:
	var start_pos := position
	var dir := 1.0 if is_ally else -1.0
	var tween := create_tween()
	# 총구 조준 살짝 숙임
	tween.tween_property(self, "position:x", start_pos.x + dir * 6.0, 0.1)
	tween.tween_callback(func():
		# 총구 위치 머즐 플래시 pixelfx 스폰
		_spawn_muzzle_flash()
		if on_impact.is_valid():
			on_impact.call()
	)
	# 강렬한 반동 킥백 (뒤로 밀림)
	tween.tween_property(self, "position:x", start_pos.x - dir * 18.0, 0.08).set_trans(Tween.TRANS_EXPO)
	tween.tween_interval(0.14)
	tween.tween_property(self, "position:x", start_pos.x, 0.22).set_trans(Tween.TRANS_SINE)


## 4. 궁수: 석궁/활 시위 당김 및 화살(Arrow) 고속 사격을 재생합니다.
func play_arrow_attack(target_unit: BattleUnit, on_impact: Callable = Callable()) -> void:
	var start_pos := position
	var dir := 1.0 if is_ally else -1.0
	var tween := create_tween()
	# 시위 당김 예비동작 (호흡 멈춤)
	tween.tween_property(self, "scale", Vector2(0.92, 1.06), 0.16)
	tween.tween_callback(func():
		_spawn_flying_arrow(target_unit, on_impact)
	)
	# 시위 튕김 반동
	tween.tween_property(self, "scale", Vector2(1.08, 0.94), 0.08)
	tween.tween_property(self, "scale", Vector2.ONE, 0.18)


## 총구 머즐플래시 pixelfx 이펙트 스폰
func _spawn_muzzle_flash() -> void:
	if not is_inside_tree():
		return
	var pos := Vector2(85, 95) if is_ally else Vector2(25, 95)
	var sp := UiKit.spawn_pixelfx_oneshot(self, "res://assets/sprites/vfx/muzzle_pistol/projectiles/muzzle-pistol/muzzle-pistol.png", pos, Vector2(1.3, 1.3))
	if sp != null:
		sp.flip_h = not is_ally


## 날아가는 화살 pixelfx 투사체 스폰
func _spawn_flying_arrow(target_unit: BattleUnit, on_impact: Callable) -> void:
	if not is_inside_tree() or target_unit == null or not target_unit.is_inside_tree():
		if on_impact.is_valid(): on_impact.call()
		return
	var a_tex := _get_cached_tex("res://assets/sprites/vfx/arrow/projectiles/arrow/arrow.png")
	var p_start := global_position + Vector2(75 if is_ally else 35, 95)
	var p_end := target_unit.global_position + Vector2(target_unit.size.x * 0.5, 95)
	if a_tex != null:
		var sp := Sprite2D.new()
		sp.texture = a_tex
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.hframes = 18
		sp.frame = 0
		sp.global_position = p_start
		sp.flip_h = not is_ally
		sp.scale = Vector2(1.2, 1.2)
		get_tree().root.add_child(sp)
		var tw := sp.create_tween()
		tw.tween_property(sp, "global_position", p_end, 0.16).set_trans(Tween.TRANS_LINEAR)
		tw.parallel().tween_property(sp, "frame", 17, 0.16)
		tw.tween_callback(func():
			sp.queue_free()
			if on_impact.is_valid(): on_impact.call()
		)
	else:
		if on_impact.is_valid(): on_impact.call()


## 직업군 및 카테고리에 맞는 전용 공격 모션 자동 라우팅
func play_attack_by_class(target_unit: BattleUnit, on_impact: Callable = Callable(), is_skill: bool = false) -> void:
	if not is_ally:
		play_melee_attack(target_unit, on_impact)
		return
	var cat := merc_data.category if merc_data != null else "전사"
	match cat:
		"마법사":
			play_mage_attack(target_unit, on_impact)
		"레인저", "도적":
			# 스킬 공격이거나 총술사 계열이면 총 사격, 일반 사격이면 화살 사격
			if is_skill:
				play_gun_attack(target_unit, on_impact)
			else:
				play_arrow_attack(target_unit, on_impact)
		"성직자":
			play_mage_attack(target_unit, on_impact)
		_:
			play_melee_attack(target_unit, on_impact)


## 원거리/마법 공격 애니메이션을 재생합니다. (하위 호환)
func play_ranged_attack(target_unit: BattleUnit, on_impact: Callable = Callable()) -> void:
	play_attack_by_class(target_unit, on_impact, true)


## 피격 애니메이션(다키스트 던전 1 스타일: 직업별 번개/총/화살/베기 이펙트, 혈흔 파티클, 넉백, CRIT 플래시)을 재생합니다.
func play_take_damage(dmg: int, is_crit: bool = false, atk_type: String = "slash") -> void:
	current_hp = max(0, current_hp - dmg)
	_update_view()

	_play_hit_sound(is_crit)
	_spawn_hit_effect(is_crit, atk_type)

	var ft: FloatingText = null
	if floating_text_pool != null:
		ft = floating_text_pool.acquire() as FloatingText
		ft.on_finished = func(n: Node): floating_text_pool.release(n)
	else:
		ft = FloatingTextScene.new()
		get_parent().add_child(ft)
	var txt := "-%d" % dmg
	if is_crit:
		txt = "CRIT!  -%d" % dmg
	var col := Color("ff2b2b") if not is_crit else Color("ff0033")
	ft.popup(txt, col, global_position + Vector2(size.x * 0.5, 10), is_crit)

	var dir := -1.0 if is_ally else 1.0
	var original_x := position.x
	var knockback_dist: float = (38.0 if is_crit else 18.0) * dir
	var hit_tween := create_tween()

	modulate = Color("ff2222") if is_crit else Color("ff7777")
	hit_tween.tween_property(self, "position:x", original_x + knockback_dist, 0.06)
	hit_tween.tween_property(self, "position:x", original_x - knockback_dist * 0.5, 0.06)
	if is_crit:
		hit_tween.tween_property(self, "position:x", original_x + knockback_dist * 0.25, 0.05)
	hit_tween.tween_property(self, "position:x", original_x, 0.09)
	hit_tween.tween_property(self, "modulate", Color.WHITE if not is_dead else Color(0.3, 0.3, 0.3, 0.45), 0.15)


## 다키스트 던전 시그니처: 공격 타입(베기/번개/총/화살/강타/신성)에 맞는 pixelfx 도트 애니메이션 시트를 재생합니다.
func _spawn_hit_effect(is_crit: bool, atk_type: String = "slash") -> void:
	var effect_holder := Node2D.new()
	effect_holder.position = Vector2(size.x * 0.5, size.y * 0.45)
	add_child(effect_holder)

	var sheet_path := ""
	var anim_dur := 0.38
	var sp_scale := Vector2(1.2, 1.2)
	var sp_mod := Color.WHITE

	match atk_type:
		"lightning", "magic", "holy":
			# 마법사/성직자 시전 타격: lightning-strike 또는 zap-hit
			sheet_path = "res://assets/sprites/vfx/lightning_strike/lightning/lightning-strike/lightning-strike.png" if is_crit else "res://assets/sprites/vfx/lightning_zap/lightning/zap-hit/zap-hit.png"
			anim_dur = 0.55 if is_crit else 0.32
			sp_scale = Vector2(1.1, 1.1)
			sp_mod = Color("ffe6a8") if atk_type == "holy" else Color("cce8ff")
			effect_holder.position.y = size.y * 0.38
		"gun":
			# 총술사 총: bullet-impact
			sheet_path = "res://assets/sprites/vfx/bullet_impact/impacts/bullet-impact/bullet-impact.png"
			anim_dur = 0.30
			sp_scale = Vector2(1.3, 1.3)
			sp_mod = Color("ffe088")
		"arrow", "ranged":
			# 궁수 화살: 관통 타격
			sheet_path = "res://assets/sprites/vfx/sword_slash/melee/sword-slash/sword-slash.png"
			anim_dur = 0.25
			sp_mod = Color("70e8a0")
		_:
			# 전사 베기/강타: double-slash / sword-slash
			var heavy := is_crit or atk_type == "crush"
			sheet_path = "res://assets/sprites/vfx/double_slash/melee/double-slash/double-slash.png" if heavy else "res://assets/sprites/vfx/sword_slash/melee/sword-slash/sword-slash.png"
			anim_dur = 0.42
			sp_mod = Color(1.0, 0.85, 0.35) if heavy else Color(1.0, 0.3, 0.3)

	if sheet_path != "":
		UiKit.spawn_pixelfx_oneshot(effect_holder, sheet_path, Vector2.ZERO, sp_scale, sp_mod)

	var slash_line := Line2D.new()
	slash_line.width = 6.0 if is_crit else 3.5
	slash_line.default_color = Color("e8b848") if is_crit else Color("c83434")
	slash_line.points = PackedVector2Array([Vector2(-32, -42), Vector2(32, 42)])
	effect_holder.add_child(slash_line)
	if is_crit:
		var cross_line := Line2D.new()
		cross_line.width = 4.0
		cross_line.default_color = Color("f0d890")
		cross_line.points = PackedVector2Array([Vector2(30, -36), Vector2(-30, 36)])
		effect_holder.add_child(cross_line)

	# 혈흔 파편
	for i in range(12 if is_crit else 6):
		var drop := Polygon2D.new()
		drop.color = Color("ff1122") if (i % 2 == 0) else Color("b80818")
		var ang := randf_range(-PI, PI)
		var spd := randf_range(20.0, 60.0)
		var target_offset := Vector2(cos(ang), sin(ang)) * spd
		drop.polygon = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)])
		effect_holder.add_child(drop)
		if is_inside_tree():
			var tw := create_tween()
			tw.tween_property(drop, "position", target_offset, 0.22).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(drop, "modulate:a", 0.0, 0.22)

	if is_inside_tree():
		var cleanup_tw := create_tween()
		cleanup_tw.tween_interval(anim_dur)
		cleanup_tw.tween_property(effect_holder, "modulate:a", 0.0, 0.10)
		cleanup_tw.tween_callback(effect_holder.queue_free)


## 하위 호환
func _spawn_hit_slash_effect(is_crit: bool) -> void:
	_spawn_hit_effect(is_crit, "slash")


## 타격 효과음을 재생합니다. (크리티컬 / 일반)
func _play_hit_sound(is_crit: bool) -> void:
	if not is_inside_tree():
		return

	if _sfx_normal_stream == null and ResourceLoader.exists("res://assets/audio/hit_normal.wav"):
		_sfx_normal_stream = load("res://assets/audio/hit_normal.wav")
	if _sfx_crit_stream == null and ResourceLoader.exists("res://assets/audio/hit_crit.wav"):
		_sfx_crit_stream = load("res://assets/audio/hit_crit.wav")

	var stream: AudioStream = _sfx_crit_stream if is_crit else _sfx_normal_stream
	if stream == null:
		return

	var player: AudioStreamPlayer = null
	if sfx_pool != null:
		player = sfx_pool.acquire() as AudioStreamPlayer
	else:
		player = AudioStreamPlayer.new()
		get_tree().root.add_child(player)
	player.stream = stream
	player.pitch_scale = randf_range(0.96, 1.04) if not is_crit else randf_range(0.98, 1.02)
	player.volume_db = 2.0 if is_crit else 0.0
	player.play()
	if sfx_pool == null and not player.finished.is_connected(player.queue_free):
		player.finished.connect(player.queue_free)


## 유닛 사망 시 연출을 실행합니다.
func _on_death() -> void:
	is_dead = true
	if _head_target_marker:
		_head_target_marker.visible = false
	if _head_turn_marker:
		_head_turn_marker.visible = false
	if _ground_active_aura:
		_ground_active_aura.visible = false
	if _ground_target_bracket:
		_ground_target_bracket.visible = false
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()

	if is_inside_tree():
		var death_tween := create_tween().set_parallel(true)
		death_tween.tween_property(self, "rotation_degrees", -25.0 if is_ally else 25.0, 0.35)
		death_tween.tween_property(self, "modulate", Color(0.3, 0.3, 0.3, 0.45), 0.35)
	else:
		rotation_degrees = -25.0 if is_ally else 25.0
		modulate = Color(0.3, 0.3, 0.3, 0.45)


## 방어 태세 시 절제된 금속성 스틸/골드 펄스 연출을 재생한다.
func play_defend_effect() -> void:
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.15, 1.2, 1.35), 0.14)
	tw.tween_property(self, "position:x", base_position.x - 6.0, 0.10)
	tw.tween_property(self, "position:x", base_position.x, 0.14)
	tw.parallel().tween_property(self, "modulate", Color.WHITE, 0.18)


## 마우스 클릭 시 시그널 전달
func _gui_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
