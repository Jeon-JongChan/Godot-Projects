class_name BattleUnit
extends Control

## 다키스트 던전 1 스타일의 턴제 전투 유닛 시각화 및 애니메이션 컴포넌트.
## 아군(용병) 또는 적군(몬스터) 데이터를 바인딩하여 2D 사이드뷰 형태로 표시하며,
## 에셋 부족 시 절차적 도형 플레이스홀더를 렌더링하고 스프라이트 에셋이 제공되면 즉시 교체할 수 있습니다.

const FloatingTextScene = preload("res://scenes/entities/floating_text.gd")

# ── 효과음 에셋 ──
static var _sfx_normal_stream: AudioStream = null
static var _sfx_crit_stream: AudioStream = null

signal clicked(unit: BattleUnit)

# ── 유닛 데이터 ──
var is_ally: bool = true
var merc_data: Mercenary = null
var monster_data: Dictionary = {}
var unit_name: String = ""
var max_hp: int = 100
var current_hp: int = 100
var attack_power: int = 10
var category_job: String = ""

# ── 상태 변수 ──
var is_dead: bool = false
var is_active_turn: bool = false
var is_target_selected: bool = false
var base_position: Vector2 = Vector2.ZERO

# ── 시각적 노드 ──
var _visual_root: Control
var _shadow: Polygon2D
var _unit_shape: Control
var _sprite_rect: TextureRect
var _hp_bar: ProgressBar
var _hp_label: Label
var _name_label: Label
var _turn_marker: Polygon2D
var _target_marker: Polygon2D
var _idle_tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(110, 190)
	size = Vector2(110, 190)
	pivot_offset = Vector2(55, 95)
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
	attack_power = mon.get("attack", 10)
	category_job = "어둠의 권속"
	_update_view()


## 외부에서 전달받은 커스텀 텍스처(스프라이트)를 적용합니다.
## 이미지가 전달되면 도형 플레이스홀더 대신 스프라이트를 표시합니다.
func set_sprite_texture(tex: Texture2D) -> void:
	if _sprite_rect:
		_sprite_rect.texture = tex
		_sprite_rect.visible = tex != null
		if _unit_shape:
			_unit_shape.visible = tex == null


## UI 노드 트리와 도형 기반 플레이스홀더를 구성합니다.
func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	_visual_root = Control.new()
	_visual_root.set_anchors_preset(PRESET_FULL_RECT)
	_visual_root.mouse_filter = MOUSE_FILTER_PASS
	add_child(_visual_root)

	# 1. 발밑 그림자 (타원형 다크 섀도우)
	_shadow = Polygon2D.new()
	_shadow.color = Color(0, 0, 0, 0.55)
	var shadow_points := PackedVector2Array()
	var cx := 55.0
	var cy := 160.0
	for i in 16:
		var rad := i * (PI * 2.0 / 16.0)
		shadow_points.append(Vector2(cx + cos(rad) * 38.0, cy + sin(rad) * 14.0))
	_shadow.polygon = shadow_points
	_visual_root.add_child(_shadow)

	# 2. 타겟 선택 조준 마커 (적 머리 위 붉은색 역삼각형)
	_target_marker = Polygon2D.new()
	_target_marker.color = Color("ff3333")
	_target_marker.polygon = PackedVector2Array([
		Vector2(45, 5), Vector2(65, 5), Vector2(55, 18)
	])
	_target_marker.visible = false
	_visual_root.add_child(_target_marker)

	# 3. 턴 액티브 마커 (현재 턴인 캐릭터 머리 위 황금빛 다이아몬드)
	_turn_marker = Polygon2D.new()
	_turn_marker.color = UiKit.GOLD2
	_turn_marker.polygon = PackedVector2Array([
		Vector2(55, -2), Vector2(63, 6), Vector2(55, 14), Vector2(47, 6)
	])
	_turn_marker.visible = false
	_visual_root.add_child(_turn_marker)

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

	# 6. 하단 상태 표시 UI (이름, 체력바, HP 수치)
	var status_box := VBoxContainer.new()
	status_box.position = Vector2(0, 162)
	status_box.size = Vector2(110, 32)
	status_box.add_theme_constant_override("separation", 1)
	status_box.mouse_filter = MOUSE_FILTER_IGNORE
	_visual_root.add_child(status_box)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", UiKit.TEXT)
	status_box.add_child(_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(110, 7)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = MOUSE_FILTER_IGNORE
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color("1a1714")
	bg_sb.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", bg_sb)
	status_box.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 9)
	_hp_label.add_theme_color_override("font_color", UiKit.TEXT2)
	status_box.add_child(_hp_label)


## 도형 플레이스홀더를 캐릭터 직업/속성에 맞게 다시 그립니다.
func _draw_placeholder() -> void:
	for c in _unit_shape.get_children():
		c.queue_free()

	var base_color: Color = UiKit.GOLD if is_ally else Color("9a3838")
	if is_ally and merc_data != null:
		base_color = JobDb.category_color(merc_data.category)

	# 1) 베이스 실린더/플랫폼 (발밑 링)
	var base_ring := Polygon2D.new()
	base_ring.color = base_color.darkened(0.6)
	base_ring.polygon = PackedVector2Array([
		Vector2(25, 135), Vector2(85, 135), Vector2(92, 142),
		Vector2(85, 149), Vector2(25, 149), Vector2(18, 142)
	])
	_unit_shape.add_child(base_ring)

	if is_ally:
		_draw_ally_silhouette(base_color)
	else:
		_draw_monster_silhouette(base_color)


## 아군 고딕 실루엣 드로잉 (망토, 갑주, 투구, 직업별 상징 무기)
func _draw_ally_silhouette(accent: Color) -> void:
	# 망토 / 어깨 실루엣
	var cloak := Polygon2D.new()
	cloak.color = Color("181512")
	cloak.polygon = PackedVector2Array([
		Vector2(35, 45), Vector2(75, 45), Vector2(88, 130), Vector2(22, 130)
	])
	_unit_shape.add_child(cloak)

	# 몸통 / 흉갑
	var armor := Polygon2D.new()
	armor.color = accent.darkened(0.35)
	armor.polygon = PackedVector2Array([
		Vector2(40, 50), Vector2(70, 50), Vector2(67, 95), Vector2(43, 95)
	])
	_unit_shape.add_child(armor)

	# 머리 / 투구 / 후드
	var head := Polygon2D.new()
	head.color = accent.lightened(0.1)
	var cat := merc_data.category if merc_data != null else "전사"
	match cat:
		"마법사":
			# 마법사 고깔 모자 & 로브
			head.polygon = PackedVector2Array([
				Vector2(55, 15), Vector2(75, 45), Vector2(35, 45)
			])
		"레인저":
			# 암살자/사냥꾼 후드
			head.polygon = PackedVector2Array([
				Vector2(55, 20), Vector2(70, 32), Vector2(68, 48), Vector2(42, 48), Vector2(40, 32)
			])
		_:
			# 전사 / 성직자 투구
			head.polygon = PackedVector2Array([
				Vector2(55, 22), Vector2(68, 30), Vector2(68, 48), Vector2(42, 48), Vector2(42, 30)
			])
	_unit_shape.add_child(head)

	# 직업별 상징 무기 실루엣
	var weapon := Polygon2D.new()
	weapon.color = UiKit.WHITE
	match cat:
		"마법사":
			# 지팡이와 빛나는 마법 오브
			weapon.polygon = PackedVector2Array([
				Vector2(80, 20), Vector2(84, 20), Vector2(84, 120), Vector2(80, 120)
			])
			var orb := Polygon2D.new()
			orb.color = UiKit.PURPLE.lightened(0.4)
			orb.polygon = PackedVector2Array([
				Vector2(82, 12), Vector2(88, 18), Vector2(82, 24), Vector2(76, 18)
			])
			_unit_shape.add_child(orb)
		"레인저":
			# 장궁 / 단검 실루엣
			weapon.polygon = PackedVector2Array([
				Vector2(24, 35), Vector2(27, 35), Vector2(18, 75), Vector2(27, 115), Vector2(24, 115), Vector2(14, 75)
			])
		"성직자":
			# 성스러운 메이스 / 십자가 방패
			weapon.polygon = PackedVector2Array([
				Vector2(75, 40), Vector2(88, 40), Vector2(88, 80), Vector2(75, 80)
			])
			var cross := Polygon2D.new()
			cross.color = UiKit.GOLD2
			cross.polygon = PackedVector2Array([
				Vector2(79, 45), Vector2(84, 45), Vector2(84, 75), Vector2(79, 75),
				Vector2(76, 52), Vector2(87, 52), Vector2(87, 57), Vector2(76, 57)
			])
			_unit_shape.add_child(cross)
		_:
			# 전사 대검 실루엣
			weapon.polygon = PackedVector2Array([
				Vector2(78, 25), Vector2(84, 25), Vector2(84, 110), Vector2(78, 110),
				Vector2(72, 85), Vector2(90, 85), Vector2(90, 90), Vector2(72, 90)
			])
	_unit_shape.add_child(weapon)


## 적 몬스터 어두운 괴수 실루엣 드로잉 (다키스트 던전 특유의 날카로운 암흑 크리처)
func _draw_monster_silhouette(accent: Color) -> void:
	# 괴물 몸체
	var body := Polygon2D.new()
	body.color = Color("1e1215")
	body.polygon = PackedVector2Array([
		Vector2(55, 30), Vector2(85, 60), Vector2(80, 130), Vector2(30, 130), Vector2(25, 60)
	])
	_unit_shape.add_child(body)

	# 붉은 코어/흉부
	var core := Polygon2D.new()
	core.color = accent
	core.polygon = PackedVector2Array([
		Vector2(55, 55), Vector2(70, 75), Vector2(55, 95), Vector2(40, 75)
	])
	_unit_shape.add_child(core)

	# 날카로운 뿔 / 송곳니
	var horns := Polygon2D.new()
	horns.color = Color("401515")
	horns.polygon = PackedVector2Array([
		Vector2(40, 40), Vector2(25, 15), Vector2(35, 35),
		Vector2(70, 40), Vector2(85, 15), Vector2(75, 35)
	])
	_unit_shape.add_child(horns)

	# 번뜩이는 붉은 눈빛
	var eye_l := Polygon2D.new()
	eye_l.color = Color("ff2222")
	eye_l.polygon = PackedVector2Array([Vector2(45, 45), Vector2(50, 47), Vector2(46, 50)])
	_unit_shape.add_child(eye_l)

	var eye_r := Polygon2D.new()
	eye_r.color = Color("ff2222")
	eye_r.polygon = PackedVector2Array([Vector2(65, 45), Vector2(60, 47), Vector2(64, 50)])
	_unit_shape.add_child(eye_r)


## 현재 체력과 상태에 맞춰 UI를 갱신합니다.
func _update_view() -> void:
	_name_label.text = unit_name
	_hp_label.text = "%d / %d" % [current_hp, max_hp]
	_hp_bar.max_value = max(max_hp, 1)
	_hp_bar.value = clamp(current_hp, 0, max_hp)

	# HP 비율에 따른 체력바 색상 스타일
	var fill_sb := StyleBoxFlat.new()
	fill_sb.set_corner_radius_all(3)
	var hp_ratio := float(current_hp) / float(max(max_hp, 1))
	if hp_ratio > 0.5:
		fill_sb.bg_color = UiKit.GREEN if is_ally else Color("9a3838")
	elif hp_ratio > 0.2:
		fill_sb.bg_color = UiKit.GOLD
	else:
		fill_sb.bg_color = UiKit.RED
	_hp_bar.add_theme_stylebox_override("fill", fill_sb)

	if current_hp <= 0 and not is_dead:
		_on_death()

	_draw_placeholder()


## 타겟 선택 여부를 전환합니다.
func set_target_selected(selected: bool) -> void:
	is_target_selected = selected
	_target_marker.visible = selected
	if selected:
		modulate = Color(1.2, 1.1, 1.1)
	else:
		modulate = Color(1.0, 1.0, 1.0) if not is_dead else Color(0.4, 0.4, 0.4, 0.5)


## 현재 턴 활성화 상태(한 발 전진 및 마커)를 제어합니다.
func set_active_turn(active: bool) -> void:
	is_active_turn = active
	if _turn_marker:
		_turn_marker.visible = active
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


## 근접 돌진 공격 애니메이션을 재생합니다. 타격 시점에 hit 콜백을 호출합니다.
func play_melee_attack(target_unit: BattleUnit, on_impact: Callable = Callable()) -> void:
	var start_pos := position
	var dir := 1.0 if is_ally else -1.0
	# 타겟 바로 앞까지 돌진
	var rush_target := target_unit.position - Vector2(dir * 70.0, 0)

	var tween := create_tween()
	# 1. 기 모으기 (살짝 뒤로 물러섬)
	tween.tween_property(self, "position:x", start_pos.x - dir * 16.0, 0.12).set_trans(Tween.TRANS_QUAD)
	# 2. 돌진 타격
	tween.tween_property(self, "position", rush_target, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	# 3. 타격 임팩트 콜백
	if on_impact.is_valid():
		tween.tween_callback(on_impact)
	# 4. 타격 후 경직
	tween.tween_interval(0.12)
	# 5. 복귀
	tween.tween_property(self, "position", start_pos, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 원거리/마법 공격 애니메이션을 재생합니다.
func play_ranged_attack(target_unit: BattleUnit, on_impact: Callable = Callable()) -> void:
	var start_pos := position
	var tween := create_tween()
	# 스케일 펄스 및 위로 들림
	tween.tween_property(self, "position:y", start_pos.y - 15.0, 0.2).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.15)
	if on_impact.is_valid():
		tween.tween_callback(on_impact)
	tween.tween_interval(0.1)
	tween.tween_property(self, "position:y", start_pos.y, 0.2)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)


## 피격 애니메이션(넉백, 붉은 플래시, 흔들림, 데미지 텍스트 팝업, 타격음)을 재생합니다.
func play_take_damage(dmg: int, is_crit: bool = false) -> void:
	current_hp = max(0, current_hp - dmg)
	_update_view()

	# 1. 타격 효과음 재생
	_play_hit_sound(is_crit)

	# 2. 플로팅 텍스트 팝업 (크리티컬 시 대형 강조 배너 및 폰트)
	var ft = FloatingTextScene.new()
	get_parent().add_child(ft)
	var txt := "-%d" % dmg
	var col := Color("ff3b30") if not is_crit else Color("ff4400")
	ft.popup(txt, col, global_position + Vector2(size.x * 0.5, 10), is_crit)

	# 3. 넉백 및 흔들림 (크리티컬 시 더 큰 진폭과 진동)
	var dir := -1.0 if is_ally else 1.0
	var original_x := position.x
	var knockback_dist: float = (30.0 if is_crit else 16.0) * dir
	var hit_tween := create_tween()

	# 붉은 플래시 (크리티컬 시 더 밝고 강렬함)
	modulate = Color("ff3333") if is_crit else Color("ff7777")
	hit_tween.tween_property(self, "position:x", original_x + knockback_dist, 0.07)
	hit_tween.tween_property(self, "position:x", original_x - knockback_dist * 0.5, 0.07)
	if is_crit:
		hit_tween.tween_property(self, "position:x", original_x + knockback_dist * 0.25, 0.05)
	hit_tween.tween_property(self, "position:x", original_x, 0.09)
	hit_tween.tween_property(self, "modulate", Color.WHITE if not is_dead else Color(0.3, 0.3, 0.3, 0.45), 0.15)


## 타격 효과음을 재생합니다. (크리티컬 / 일반)
func _play_hit_sound(is_crit: bool) -> void:
	if not is_inside_tree():
		return

	# 오디오 스트림 지연 로드 (첫 호출 시 로드)
	if _sfx_normal_stream == null and ResourceLoader.exists("res://assets/audio/hit_normal.wav"):
		_sfx_normal_stream = load("res://assets/audio/hit_normal.wav")
	if _sfx_crit_stream == null and ResourceLoader.exists("res://assets/audio/hit_crit.wav"):
		_sfx_crit_stream = load("res://assets/audio/hit_crit.wav")

	var stream: AudioStream = _sfx_crit_stream if is_crit else _sfx_normal_stream
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
	# 자연스러운 타격 질감을 위해 미세한 피치 변동 적용
	player.pitch_scale = randf_range(0.96, 1.04) if not is_crit else randf_range(0.98, 1.02)
	player.volume_db = 2.0 if is_crit else 0.0
	get_tree().root.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## 사망 시 연출을 실행합니다.
func _on_death() -> void:
	is_dead = true
	if _target_marker:
		_target_marker.visible = false
	if _turn_marker:
		_turn_marker.visible = false
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()

	if is_inside_tree():
		var death_tween := create_tween().set_parallel(true)
		death_tween.tween_property(self, "rotation_degrees", -25.0 if is_ally else 25.0, 0.35)
		death_tween.tween_property(self, "modulate", Color(0.3, 0.3, 0.3, 0.45), 0.35)
	else:
		rotation_degrees = -25.0 if is_ally else 25.0
		modulate = Color(0.3, 0.3, 0.3, 0.45)


## 마우스 클릭 시 시그널 전달
func _gui_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
