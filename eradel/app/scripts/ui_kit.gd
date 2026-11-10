class_name UiKit
extends RefCounted

## 기획서(UI 설계서 v0.4) 색상 팔레트와 공용 위젯 빌더.
## 모든 화면이 코드로 UI를 조립할 때 이 헬퍼를 사용한다.

const BG := Color("0e0c08")
const BG2 := Color("16130d")
const BG3 := Color("1e1a11")
const BORDER := Color("3a3020")
const BORDER2 := Color("5a4a2a")
const GOLD := Color("c9a84c")
const GOLD2 := Color("f0c85a")
const RED := Color("c04040")
const GREEN := Color("3a7a50")
const BLUE := Color("3a6a9a")
const PURPLE := Color("6a5aaa")
const TEXT := Color("e8dcc8")
const TEXT2 := Color("a09070")
const TEXT3 := Color("6a5a40")
const WHITE := Color("f5f0e8")

const AVATAR := "res://assets/avatar_default.png"
const TITLE_ART := "res://assets/eradel_title.png"


## [경량화] 동일한 조합의 StyleBox 를 한 번만 만들어 모든 위젯이 공유한다.
## 팝업을 다시 그릴 때마다 수백 개씩 새로 만들던 StyleBoxFlat 을 줄인다.
## 반환값은 공유 인스턴스이므로 절대 직접 수정하지 말 것 (필요하면 duplicate()).
static var _style_cache := {}


static func style(bg: Color, border: Color = BORDER, radius: int = 8, border_w: int = 1, pad_h: int = 12, pad_v: int = 8) -> StyleBoxFlat:
	var key := [bg, border, radius, border_w, pad_h, pad_v]
	if _style_cache.has(key):
		return _style_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	_style_cache[key] = sb
	return sb


## 캐시된 StyleBox 개수 (경량화 검증용)
static func style_cache_size() -> int:
	return _style_cache.size()


static func panel(bg: Color = BG2, border: Color = BORDER, radius: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(bg, border, radius))
	return p


static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size: int = 30, color: Color = WHITE) -> Label:
	var l := label(text, size, color)
	return l


static func button(text: String, accent: Color = GOLD) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_disabled_color", TEXT3)
	var normal := style(BG3, BORDER2, 6)
	var hover := style(BG3.lightened(0.06), accent, 6)
	var pressed := style(accent.darkened(0.6), accent, 6)
	var disabled := style(BG3.darkened(0.3), BORDER, 6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func primary_button(text: String, accent: Color = GREEN) -> Button:
	var b := button(text, accent)
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_stylebox_override("normal", style(accent.darkened(0.45), accent, 6))
	b.add_theme_stylebox_override("hover", style(accent.darkened(0.3), accent.lightened(0.2), 6))
	b.add_theme_stylebox_override("pressed", style(accent.darkened(0.6), accent, 6))
	return b


## 다키스트 던전 풍의 각진 흑철/황금 테두리 고딕 버튼 생성 헬퍼.
## _style_cache 기반 StyleBox 를 재사용해 대장간·결전 UI 의 일관성과 경량화를 유지한다.
static func gothic_button(text: String, accent: Color = GOLD) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", accent.lightened(0.2))
	b.add_theme_color_override("font_hover_color", WHITE)
	b.add_theme_color_override("font_pressed_color", accent.darkened(0.3))
	b.add_theme_color_override("font_disabled_color", TEXT3)
	b.add_theme_stylebox_override("normal", style(Color("120f0c"), accent.darkened(0.3), 2, 2, 16, 8))
	b.add_theme_stylebox_override("hover", style(Color("1e1712"), accent.lightened(0.3), 2, 2, 16, 8))
	b.add_theme_stylebox_override("pressed", style(Color("0a0806"), accent, 2, 2, 16, 8))
	b.add_theme_stylebox_override("disabled", style(Color("0d0c0a"), Color("2a241c"), 2, 1, 16, 8))
	b.focus_mode = Control.FOCUS_NONE
	return b


## 수평 구분선 컨트롤 생성 헬퍼 (대장간 정보 패널 등 섹션 분리용).
static func divider(color: Color = BORDER, height: int = 1) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 도트 픽셀 아트가 번지지 않도록 TEXTURE_FILTER_NEAREST 를 적용한 아이콘 TextureRect 생성 헬퍼.
static func icon_rect(path: String, px: int = 18) -> TextureRect:
	var trect := TextureRect.new()
	trect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(path):
		trect.texture = load(path)
	trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trect.custom_minimum_size = Vector2(px, px)
	trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return trect


## 도트 아이콘이 포함된 상태/자원 칩 생성 헬퍼.
static func icon_chip(icon_path: String, text: String, color: Color = GOLD, icon_px: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(color.darkened(0.55), color, 10, 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	if ResourceLoader.exists(icon_path):
		h.add_child(icon_rect(icon_path, icon_px))
	var l := label(text, 12, color.lightened(0.3))
	h.add_child(l)
	return p


static func chip(text: String, color: Color = GOLD) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(color.darkened(0.55), color, 10, 1))
	var l := label(text, 12, color.lightened(0.3))
	p.add_child(l)
	return p


static func progress(value: float, maximum: float, color: Color, height: int = 8) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = maxf(maximum, 0.0001)
	pb.value = clampf(value, 0.0, maximum)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


static func hsep(h: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func avatar(diameter: int = 36) -> TextureRect:
	var trect := TextureRect.new()
	var tex := load(AVATAR)
	if tex:
		trect.texture = tex
	trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	trect.custom_minimum_size = Vector2(diameter, diameter)
	return trect


## 자원 칩이 포함된 상단바. on_back 이 Callable 이면 뒤로 버튼을 단다.
## 사용자 피드백에 따라 일반 게임화면에서는 음량 슬라이더와 환경설정(톱니바퀴) 버튼을 노출하지 않는다.
static func top_bar(title_text: String, on_back = null, show_volume: bool = false, show_settings: bool = false) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", style(BG2, BORDER, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)
	if on_back is Callable:
		var back := button("‹ 뒤로")
		back.pressed.connect(on_back)
		h.add_child(back)
	var t := label(title_text, 16, GOLD)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var gold_val := 0
	var mana_val := 0
	var ap_val := 0
	var max_ap_val := 3
	var main_loop = Engine.get_main_loop()
	var root_node = main_loop.root if (main_loop != null and "root" in main_loop) else null
	var gs = root_node.get_node_or_null("GameState") if root_node != null else null
	if gs != null:
		gold_val = gs.gold
		mana_val = gs.manastone
		ap_val = gs.action_points
		max_ap_val = gs.max_action_points

	h.add_child(chip("금화 %d" % gold_val, GOLD))
	h.add_child(chip("마나석 %d" % mana_val, BLUE))
	h.add_child(chip("행동력 %d/%d" % [ap_val, max_ap_val], TEXT2))
	if show_volume:
		h.add_child(volume_controller())

	if show_settings:
		var setting_btn := button("⚙", GOLD)
		setting_btn.custom_minimum_size = Vector2(32, 28)
		setting_btn.pressed.connect(func():
			var scene := load("res://scenes/popups/settings_popup.tscn")
			if scene:
				var popup = scene.instantiate()
				if bar.get_tree() and bar.get_tree().current_scene:
					bar.get_tree().current_scene.add_child(popup)
		)
		h.add_child(setting_btn)

	return bar


## 실시간 마스터 오디오 볼륨을 제어하는 인게임 슬라이더 위젯.
## 스피커 아이콘 클릭 시 음소거 토글, 슬라이더 조절 시 AudioServer 마스터 버스에 즉각 반영합니다.
static func volume_controller() -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", style(BG3, BORDER2, 6, 1))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	container.add_child(hbox)

	var icon_btn := Button.new()
	icon_btn.text = "🔊"
	icon_btn.focus_mode = Control.FOCUS_NONE
	icon_btn.flat = true
	icon_btn.add_theme_font_size_override("font_size", 12)
	hbox.add_child(icon_btn)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(90, 20)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE

	var bus_idx := AudioServer.get_bus_index("Master")
	var current_vol_linear: float = 0.8
	if bus_idx >= 0:
		if AudioServer.is_bus_mute(bus_idx):
			current_vol_linear = 0.0
		else:
			current_vol_linear = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	slider.value = clampf(current_vol_linear, 0.0, 1.0)
	hbox.add_child(slider)

	var pct_label := label("%d%%" % int(slider.value * 100), 11, TEXT2)
	pct_label.custom_minimum_size = Vector2(36, 0)
	pct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(pct_label)

	var prev_vol: Array[float] = [0.8]
	if slider.value > 0.05:
		prev_vol[0] = slider.value

	var update_volume = func(val: float):
		if bus_idx >= 0:
			if val <= 0.01:
				AudioServer.set_bus_mute(bus_idx, true)
				icon_btn.text = "🔇"
			else:
				AudioServer.set_bus_mute(bus_idx, false)
				AudioServer.set_bus_volume_db(bus_idx, linear_to_db(val))
				icon_btn.text = "🔉" if val < 0.5 else "🔊"
		pct_label.text = "%d%%" % int(val * 100)

	slider.value_changed.connect(update_volume)

	# 음소거 토글 버튼 연결
	icon_btn.pressed.connect(func():
		if slider.value > 0.01:
			prev_vol[0] = slider.value
			slider.value = 0.0
		else:
			slider.value = prev_vol[0] if prev_vol[0] > 0.05 else 0.8
	)

	return container


## 화면 루트에 깔 배경(단색).
static func background(parent: Control, color: Color = BG) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg
