## 하단 좌측 영웅 정보 패널(초상화·HP/스트레스·스킬 버튼·스탯·장비)을 소유하는 UI 헬퍼.
## 스킬 버튼 입력은 시그널로 던전 씬의 기존 핸들러에 전달됩니다.
class_name DungeonHeroPanel
extends RefCounted

signal attack_pressed
signal skill_pressed
signal defend_pressed
signal focus_pressed

var _hero_portrait_rect: PanelContainer
var _hero_name_label: Label
var _hero_job_label: Label
var _hero_hp_bar: ProgressBar
var _hero_hp_label: Label
var _hero_stress_bar: ProgressBar
var _hero_stress_label: Label
var _stat_labels: Dictionary = {}
var _gear_labels: Dictionary = {}
var _skill_buttons: Array[Button] = []


## 스킬 커맨드 버튼 전체의 활성/비활성을 일괄 설정합니다.
func set_skills_enabled(enabled: bool) -> void:
	for btn in _skill_buttons:
		btn.disabled = not enabled


## 하단 좌측 다키스트 던전 스타일 영웅 상세 패널을 생성합니다.
## (영웅 초상화, 4대 스킬 아이콘 슬롯, 6대 스탯 그리드, 무기/방어구 강화 정보)
func build() -> Control:
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

	# 1. 영웅 사각 초상화 (어두운 고딕 프레임 + 실제 도트 초상화 텍스처)
	_hero_portrait_rect = PanelContainer.new()
	_hero_portrait_rect.custom_minimum_size = Vector2(64, 68)
	var port_sb := StyleBoxFlat.new()
	port_sb.bg_color = Color("15120f")
	port_sb.border_color = UiKit.BORDER2
	port_sb.set_border_width_all(1)
	_hero_portrait_rect.add_theme_stylebox_override("panel", port_sb)
	top_row.add_child(_hero_portrait_rect)

	var port_tex := TextureRect.new()
	port_tex.name = "PortraitTex"
	port_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	port_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	port_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	port_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	port_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_portrait_rect.add_child(port_tex)

	var port_label := Label.new()
	port_label.name = "PortraitGlyph"
	port_label.text = "⚔"
	port_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	port_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	port_label.add_theme_font_size_override("font_size", 24)
	port_label.add_theme_color_override("font_color", UiKit.GOLD)
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
	_hero_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	_hero_stress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		{"name": "일반 공격", "icon": "res://assets/sprites/ui/skill_attack.png", "desc": "기본 물리 타격 (1.0배 피해)", "color": Color("c79c38"), "fn": func(): attack_pressed.emit()},
		{"name": "강타", "icon": "res://assets/sprites/ui/skill_heavy.png", "desc": "치명타 일격 (1.4배 피해)", "color": Color("b33939"), "fn": func(): skill_pressed.emit()},
		{"name": "방어 태세", "icon": "res://assets/sprites/ui/skill_guard.png", "desc": "피해 감소 & 스트레스 10 진정", "color": Color("4a78a6"), "fn": func(): defend_pressed.emit()},
		{"name": "집중", "icon": "res://assets/sprites/ui/skill_focus.png", "desc": "정신 집중 & 체력 12 회복", "color": Color("3b9963"), "fn": func(): focus_pressed.emit()},
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
		btn_sb.bg_color = Color("1a1612")
		btn_sb.border_color = Color("4c3f30")
		btn_sb.set_border_width_all(1)
		btn_sb.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", btn_sb)

		var hover_sb := btn_sb.duplicate()
		hover_sb.bg_color = Color("28211a")
		hover_sb.border_color = UiKit.GOLD
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
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer)

	# 대장간 강화 장비 뱃지 (무기 Lv.X, 방어구 Lv.X)
	var gear_box := HBoxContainer.new()
	gear_box.add_theme_constant_override("separation", 10)
	bottom_row.add_child(gear_box)

	var wpn_badge := PanelContainer.new()
	wpn_badge.custom_minimum_size = Vector2(85, 30)
	var wpn_sb := StyleBoxFlat.new()
	wpn_sb.bg_color = Color("181410")
	wpn_sb.border_color = Color("4c3f30")
	wpn_sb.set_border_width_all(1)
	wpn_badge.add_theme_stylebox_override("panel", wpn_sb)
	var wpn_lbl := Label.new()
	wpn_lbl.text = "⚔ 무기 Lv.1"
	wpn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_lbl.add_theme_font_size_override("font_size", 10)
	wpn_lbl.add_theme_color_override("font_color", UiKit.TEXT)
	wpn_badge.add_child(wpn_lbl)
	_gear_labels["weapon"] = wpn_lbl
	gear_box.add_child(wpn_badge)

	var arm_badge := PanelContainer.new()
	arm_badge.custom_minimum_size = Vector2(85, 30)
	var arm_sb := StyleBoxFlat.new()
	arm_sb.bg_color = Color("181410")
	arm_sb.border_color = Color("4c3f30")
	arm_sb.set_border_width_all(1)
	arm_badge.add_theme_stylebox_override("panel", arm_sb)
	var arm_lbl := Label.new()
	arm_lbl.text = "🛡 방어구 Lv.1"
	arm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arm_lbl.add_theme_font_size_override("font_size", 10)
	arm_lbl.add_theme_color_override("font_color", UiKit.TEXT)
	arm_badge.add_child(arm_lbl)
	_gear_labels["armor"] = arm_lbl
	gear_box.add_child(arm_badge)

	return p


## 영웅 정보 패널 UI (초상화, 이름/직업, HP, 스트레스, 6대 스탯, 대장간 장비)를 갱신합니다.
func update_hero(unit) -> void:
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

	# 초상화 도트 텍스처 및 폴백 글리프 갱신 (JobDb & UiKit 공용 캐시)
	var cat: String = unit.merc_data.category if unit.merc_data != null else "전사"
	var vs := JobDb.visual_spec(cat)
	var ptex: TextureRect = _hero_portrait_rect.find_child("PortraitTex", true, false)
	var glyph: Label = _hero_portrait_rect.find_child("PortraitGlyph", true, false)
	var loaded_tex: Texture2D = UiKit.get_cached_texture(str(vs.get("portrait", "")))
	if ptex:
		ptex.texture = loaded_tex
		ptex.visible = (loaded_tex != null)
	if glyph:
		glyph.visible = (loaded_tex == null)
		glyph.text = str(vs.get("glyph", "⚔"))

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
