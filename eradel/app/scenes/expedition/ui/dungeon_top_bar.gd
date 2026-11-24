## 던전 상단 횃불 광원 게이지·퀘스트 배너·라운드 표시 바를 소유하는 UI 헬퍼 (표시 전용).
class_name DungeonTopBar
extends RefCounted

var _torchlight: int = 85
var _torch_bar: ProgressBar
var _torch_value_label: Label
var _torch_stage_label: Label
var _quest_progress_label: Label
var _round_label: Label
var _dungeon_atmosphere: ColorRect = null


## 횃불 수치에 맞춰 분위기(비네트) 셰이더를 갱신할 대상 노드를 지정합니다.
func set_atmosphere(atmosphere: ColorRect) -> void:
	_dungeon_atmosphere = atmosphere


## 횃불 수치를 저장하고 게이지/라벨/분위기를 다시 그립니다.
func update_torchlight(value: int) -> void:
	_torchlight = value
	_update_torchlight_display()


## 우측 라운드/구역 라벨 텍스트를 설정합니다.
func set_round_text(text: String) -> void:
	if _round_label != null:
		_round_label.text = text


## 좌측 퀘스트 진행 라벨 텍스트를 설정합니다.
func set_quest_text(text: String) -> void:
	if _quest_progress_label != null:
		_quest_progress_label.text = text


## 상단 횃불 광원(Torchlight) 게이지와 원정 퀘스트 배너를 생성합니다.
func build() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(1280, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("100e0c")
	sb.border_color = Color("3a3124")
	sb.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_torch_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t_fill := StyleBoxFlat.new()
	t_fill.bg_color = Color("e87a15") # 타오르는 주황빛 화염
	_torch_bar.add_theme_stylebox_override("fill", t_fill)
	torch_frame.add_child(_torch_bar)

	# 우측 여백
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	if is_instance_valid(_dungeon_atmosphere) and _dungeon_atmosphere.material is ShaderMaterial:
		var mat := _dungeon_atmosphere.material as ShaderMaterial
		var dark_ratio := 1.0 - clampf(float(_torchlight) / 100.0, 0.0, 1.0)
		mat.set_shader_parameter("vignette_intensity", 0.34 + dark_ratio * 0.44)
		mat.set_shader_parameter("torch_warmth", clampf(float(_torchlight) / 100.0 * 0.24, 0.02, 0.24))
		mat.set_shader_parameter("danger_pulse", clampf((40.0 - float(_torchlight)) / 40.0, 0.0, 0.85))
