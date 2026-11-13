class_name UiKit
extends RefCounted

## 기획서(UI 설계서 v0.4) 색상 팔레트와 공용 위젯 빌더.
## 모든 화면이 코드로 UI를 조립할 때 이 헬퍼를 사용한다.

const BG := Color("0c0a09")
const BG2 := Color("15120f")
const BG3 := Color("1f1a16")
const BORDER := Color("2c251d")
const BORDER2 := Color("4a3d2e")
const GOLD := Color("c8a24a")
const GOLD2 := Color("e2c06d")
const RED := Color("b84a42")
const GREEN := Color("4a8c5c")
const BLUE := Color("4a749c")
const PURPLE := Color("7c588c")
const TEXT := Color("dfd5c3")
const TEXT2 := Color("9a8d7a")
const TEXT3 := Color("635746")
const WHITE := Color("efe9dc")

const AVATAR := "res://assets/avatar_default.png"
const TITLE_ART := "res://assets/eradel_title.png"


## [경량화] 동일한 조합의 StyleBox 를 한 번만 만들어 모든 위젯이 공유한다.
## 팝업을 다시 그릴 때마다 수백 개씩 새로 만들던 StyleBoxFlat 을 줄인다.
## 반환값은 공유 인스턴스이므로 절대 직접 수정하지 말 것 (필요하면 duplicate()).
static var _style_cache := {}
static var _pixelfx_tex_cache := {}
static var _pixelfx_meta_cache := {}
static var _atmosphere_shader: Shader = null


## 공통 고딕 StyleBoxFlat 을 캐시에서 재사용하며, 테두리가 있는 위젯에는 입체감 있는 드롭 섀도우를 부여한다.
static func style(bg: Color, border: Color = BORDER, radius: int = 8, border_w: int = 1, pad_h: int = 12, pad_v: int = 8) -> StyleBoxFlat:
	var key := [bg, border, radius, border_w, pad_h, pad_v]
	if _style_cache.has(key):
		return _style_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	if border_w >= 1:
		# 평면 패널·버튼에 미세한 그림자 깊이를 추가해 상용 UI 마감 확보
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
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
	_attach_button_juice(b)
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
	b.add_theme_stylebox_override("normal", style(Color("14110e"), BORDER2, 2, 2, 16, 8))
	b.add_theme_stylebox_override("hover", style(Color("221c16"), accent.lightened(0.25), 2, 2, 16, 8))
	b.add_theme_stylebox_override("pressed", style(Color("0b0907"), accent, 2, 2, 16, 8))
	b.add_theme_stylebox_override("disabled", style(Color("0d0c0a"), BORDER, 2, 1, 16, 8))
	b.focus_mode = Control.FOCUS_NONE
	_attach_button_juice(b)
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
	p.add_theme_stylebox_override("panel", style(BG2, BORDER2, 8, 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	if ResourceLoader.exists(icon_path):
		h.add_child(icon_rect(icon_path, icon_px))
	var l := label(text, 12, color.lerp(TEXT, 0.35))
	h.add_child(l)
	return p


## 고딕 통일 톤의 상태/자원 칩 생성 헬퍼.
static func chip(text: String, color: Color = GOLD) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(BG2, BORDER2, 8, 1))
	var l := label(text, 12, color.lerp(TEXT, 0.35))
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


## 컨테이너 레이아웃 충돌 없이 호버·클릭 타격감을 주는 버튼 self_modulate 마이크로 애니메이션을 연결한다.
static func _attach_button_juice(b: Button) -> void:
	b.mouse_entered.connect(func():
		if not is_instance_valid(b) or not b.is_inside_tree() or b.disabled:
			return
		var tw := b.create_tween()
		tw.tween_property(b, "self_modulate", Color(1.14, 1.10, 1.02), 0.10)
	)
	b.mouse_exited.connect(func():
		if not is_instance_valid(b) or not b.is_inside_tree():
			return
		var tw := b.create_tween()
		tw.tween_property(b, "self_modulate", Color.WHITE, 0.12)
	)
	b.button_down.connect(func():
		if not is_instance_valid(b) or not b.is_inside_tree() or b.disabled:
			return
		var tw := b.create_tween()
		tw.tween_property(b, "self_modulate", Color(0.86, 0.82, 0.76), 0.05)
	)
	b.button_up.connect(func():
		if not is_instance_valid(b) or not b.is_inside_tree():
			return
		var target := Color(1.14, 1.10, 1.02) if b.is_hovered() and not b.disabled else Color.WHITE
		var tw := b.create_tween()
		tw.tween_property(b, "self_modulate", target, 0.10)
	)


## 마우스 입력을 가로채지 않는(MOUSE_FILTER_IGNORE) 고딕 비네팅·횃불 온기 포스트프로세싱 오버레이를 생성해 부착한다.
static func attach_gothic_atmosphere(host: Node, intensity: float = 0.42, warmth: float = 0.14, danger: float = 0.0) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = "GothicAtmosphereOverlay"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.TRANSPARENT

	if _atmosphere_shader == null and ResourceLoader.exists("res://assets/shaders/gothic_atmosphere.gdshader"):
		_atmosphere_shader = load("res://assets/shaders/gothic_atmosphere.gdshader")
	if _atmosphere_shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = _atmosphere_shader
		mat.set_shader_parameter("vignette_intensity", intensity)
		mat.set_shader_parameter("torch_warmth", warmth)
		mat.set_shader_parameter("danger_pulse", danger)
		rect.material = mat

	if host != null:
		host.add_child(rect)
	return rect


## 텍스처를 공용 캐시에서 로드해 반환한다.
static func get_cached_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _pixelfx_tex_cache.has(path):
		return _pixelfx_tex_cache[path]
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_pixelfx_tex_cache[path] = tex
		return tex
	return null


## pixelfx JSON 메타데이터(프레임 수, 열 개수, FPS, 프레임 크기)를 읽어 캐싱해 둔다.
static func _load_pixelfx_sheet_meta(sheet_path: String) -> Dictionary:
	if _pixelfx_meta_cache.has(sheet_path):
		return _pixelfx_meta_cache[sheet_path]
	var fallback := {"frames": 1, "columns": 1, "fps": 24.0, "frame_w": 0, "frame_h": 0}
	var json_path := "%s.json" % sheet_path.get_basename()
	if not FileAccess.file_exists(json_path):
		_pixelfx_meta_cache[sheet_path] = fallback
		return fallback
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		_pixelfx_meta_cache[sheet_path] = fallback
		return fallback
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_pixelfx_meta_cache[sheet_path] = fallback
		return fallback
	var pdict: Dictionary = parsed
	var pfx: Dictionary = pdict.get("meta", {}).get("pixelfx", {})
	var frames_arr = pdict.get("frames", [])
	var frames: int = maxi(1, int(pfx.get("frames", frames_arr.size() if frames_arr is Array else 1)))
	var columns: int = maxi(1, int(pfx.get("columns", frames)))
	var fps: float = maxf(1.0, float(pfx.get("fps", 24.0)))
	var frame_w: int = 0
	var frame_h: int = 0
	var fsize = pfx.get("frameSize", null)
	if fsize is Array and fsize.size() >= 2:
		frame_w = int(fsize[0])
		frame_h = int(fsize[1])
	elif frames_arr is Array and frames_arr.size() > 0 and frames_arr[0] is Dictionary:
		var fr: Dictionary = frames_arr[0].get("frame", {})
		frame_w = int(fr.get("w", 0))
		frame_h = int(fr.get("h", 0))
	var out := {"frames": frames, "columns": columns, "fps": fps, "frame_w": frame_w, "frame_h": frame_h}
	_pixelfx_meta_cache[sheet_path] = out
	return out


## pixelfx 시트 경로의 JSON 메타데이터를 기반으로 현재 anim_time 에 해당하는 소스 Rect2 를 계산한다.
static func pixelfx_frame_rect_from_sheet(sheet_path: String, anim_time: float, frame_offset: int = 0) -> Rect2:
	var meta := _load_pixelfx_sheet_meta(sheet_path)
	var total_frames: int = maxi(1, int(meta.get("frames", 1)))
	var cols: int = maxi(1, int(meta.get("columns", 1)))
	var rows: int = maxi(1, int(ceil(float(total_frames) / float(cols))))
	var fps: float = float(meta.get("fps", 24.0))
	var fw: int = int(meta.get("frame_w", 0))
	var fh: int = int(meta.get("frame_h", 0))
	if fw <= 0 or fh <= 0:
		var tex := get_cached_texture(sheet_path)
		if tex != null:
			fw = maxi(1, int(tex.get_width() / cols))
			fh = maxi(1, int(tex.get_height() / rows))
	var idx := (int(maxf(0.0, anim_time) * fps) + frame_offset) % total_frames
	if idx < 0:
		idx += total_frames
	var col := idx % cols
	var row := int(idx / cols)
	return Rect2(col * fw, row * fh, fw, fh)


## CanvasItem 위에 pixelfx 스프라이트 시트 루프 프레임을 단일 JSON 규격으로 그린다.
static func draw_pixelfx_frame(canvas: CanvasItem, sheet_path: String, dst_rect: Rect2, anim_time: float, frame_offset: int = 0, modulate: Color = Color.WHITE) -> void:
	if canvas == null:
		return
	var tex := get_cached_texture(sheet_path)
	if tex == null:
		return
	var src_rect := pixelfx_frame_rect_from_sheet(sheet_path, anim_time, frame_offset)
	if src_rect.size.x <= 0 or src_rect.size.y <= 0:
		return
	canvas.draw_texture_rect_region(tex, dst_rect, src_rect, modulate)


## pixelfx 다중 행/열 스프라이트 시트를 JSON 메타데이터 기반으로 재생한 뒤 자동 해제하는 원샷 Sprite2D 를 스폰한다.
static func spawn_pixelfx_oneshot(parent: Node, sheet_path: String, local_pos: Vector2, scale_vec: Vector2 = Vector2.ONE, tint: Color = Color.WHITE) -> Sprite2D:
	if parent == null:
		return null
	var tex := get_cached_texture(sheet_path)
	if tex == null:
		return null

	var meta := _load_pixelfx_sheet_meta(sheet_path)
	var total_frames: int = int(meta.get("frames", 1))
	var cols: int = int(meta.get("columns", 1))
	var rows: int = maxi(1, int(ceil(float(total_frames) / float(cols))))
	var fps: float = float(meta.get("fps", 24.0))

	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.hframes = cols
	sp.vframes = rows
	sp.frame = 0
	sp.position = local_pos
	sp.scale = scale_vec
	sp.modulate = tint
	parent.add_child(sp)

	if total_frames > 1 and parent.is_inside_tree():
		var dur := maxf(0.18, float(total_frames) / fps)
		var tw := sp.create_tween()
		tw.tween_property(sp, "frame", total_frames - 1, dur)
		tw.tween_callback(sp.queue_free)
	return sp


## 공용 용병 카드 위젯을 생성한다 (초상화, 등급/직업/HP/패널티/개인 스트레스 핍/클릭·액션 버튼 통합).
static func merc_card(m: Mercenary, opts: Dictionary = {}) -> PanelContainer:
	var is_sel: bool = bool(opts.get("selected", false))
	var sel_border: Color = opts.get("selected_border", GOLD)
	var border_col: Color = opts.get("border_color", sel_border if is_sel else BORDER)
	var bg_col: Color = opts.get("bg_color", Color("2a2016") if is_sel else BG3)
	var radius: int = int(opts.get("radius", 6))

	var p := PanelContainer.new()
	if opts.has("pad_h") or opts.has("pad_v"):
		p.add_theme_stylebox_override("panel", style(bg_col, border_col, radius, 1, int(opts.get("pad_h", 8)), int(opts.get("pad_v", 6))))
	else:
		p.add_theme_stylebox_override("panel", style(bg_col, border_col, radius))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(opts.get("separation", 8)))
	p.add_child(h)

	var p_size: int = int(opts.get("portrait_size", 38))
	if bool(opts.get("show_portrait", true)) and p_size > 0 and m != null:
		# VillageVisuals 순환 참조 방지를 위해 런타임 로드하여 HeroPortraitCanvas 인스턴스 생성
		var vv_script: Variant = ResourceLoader.load("res://scripts/village_visuals.gd")
		if vv_script != null and vv_script.get("HeroPortraitCanvas") != null:
			var port: Control = vv_script.HeroPortraitCanvas.new()
			port.set("category", m.category)
			port.set("grade", m.grade)
			port.set("hero_name", m.merc_name)
			port.custom_minimum_size = Vector2(p_size, p_size)
			port.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(port)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)

	if m != null:
		var prefix: String = str(opts.get("title_prefix", ""))
		var subtitle_mode: String = str(opts.get("subtitle_mode", "full"))
		var grade_col: Color = JobDb.grade_color(m.grade)
		var name_col: Color = GOLD if is_sel else opts.get("name_color", grade_col if bool(opts.get("color_name_by_grade", false)) else WHITE)

		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 6)
		var name_text: String = "%s[%s] %s" % [prefix, m.grade, m.merc_name] if bool(opts.get("grade_in_title", true)) else "%s%s" % [prefix, m.merc_name]
		var name_lbl := label(name_text, int(opts.get("title_size", 12)), name_col)
		if subtitle_mode == "gear_stress":
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(name_lbl)
		if bool(opts.get("grade_chip", false)):
			title_row.add_child(chip(m.grade, grade_col))
		if subtitle_mode == "gear_stress":
			title_row.add_child(label("Lv.%d" % m.level, 10, GOLD2))
		info.add_child(title_row)

		match subtitle_mode:
			"job_level":
				info.add_child(label("[%s] %s Lv.%d" % [m.grade, m.job, m.level], 10, opts.get("subtitle_color", TEXT2)))
			"level_job":
				info.add_child(label("LVL %d %s" % [m.level, m.job], 10, opts.get("subtitle_color", TEXT2)))
			"job_only":
				info.add_child(label("%s Lv.%d" % [m.job, m.level], 10, opts.get("subtitle_color", TEXT2)))
			"penalty":
				var pen_txt: String = m.penalties[0] if not m.penalties.is_empty() else "없음"
				info.add_child(label("후유증: %s" % pen_txt, 10, RED))
			"gear_stress":
				info.add_child(label("%s | ⚔+%d 🛡+%d" % [m.job, m.weapon_level, m.armor_level], 9, TEXT2))
				# 용병 개별 스트레스(m.stress)를 10칸 핍 바로 시각화 (영지 전체 스트레스와 분리)
				var pips_h := HBoxContainer.new()
				pips_h.name = "StressPips"
				pips_h.add_theme_constant_override("separation", 2)
				var filled_pips: int = clampi(int(round(float(m.stress) / 10.0)), 0, 10)
				for p_idx in range(10):
					var pip := ColorRect.new()
					pip.custom_minimum_size = Vector2(10, 4)
					pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
					pip.color = Color("e03838") if p_idx < filled_pips else Color("2a201a")
					pips_h.add_child(pip)
				info.add_child(pips_h)
			_:
				info.add_child(label("%s Lv.%d · HP %d/%d · 공격력 %d" % [m.job, m.level, m.hp, m.max_hp, m.attack], 10, opts.get("subtitle_color", TEXT2)))

		if bool(opts.get("show_hp_bar", false)):
			info.add_child(progress(m.hp, m.max_hp, opts.get("hp_color", GREEN), 4))

		if bool(opts.get("show_penalties", false)) and m.penalties.size() > 0:
			var pen_prefix: String = str(opts.get("penalty_prefix", "패널티: "))
			info.add_child(label(pen_prefix + ", ".join(m.penalties), 10, RED))

	var chip_txt: String = str(opts.get("right_chip_text", ""))
	var act_txt: String = str(opts.get("action_text", ""))
	if chip_txt != "" or act_txt != "":
		var right_box := VBoxContainer.new()
		right_box.alignment = BoxContainer.ALIGNMENT_CENTER
		right_box.add_theme_constant_override("separation", 3)
		if chip_txt != "":
			right_box.add_child(chip(chip_txt, opts.get("right_chip_color", TEXT2)))
		if act_txt != "":
			var btn := button(act_txt, opts.get("action_color", GOLD))
			btn.custom_minimum_size = opts.get("action_min_size", Vector2(44, 28))
			btn.disabled = bool(opts.get("action_disabled", false))
			var on_act: Callable = opts.get("on_action", Callable())
			if on_act.is_valid():
				var cur_m := m
				btn.pressed.connect(func():
					if on_act.get_argument_count() >= 1:
						on_act.call(cur_m)
					else:
						on_act.call()
				)
			right_box.add_child(btn)
		h.add_child(right_box)

	var on_click: Callable = opts.get("on_click", Callable())
	if on_click.is_valid():
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var cur_m2 := m
		p.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				if on_click.get_argument_count() >= 1:
					on_click.call(cur_m2)
				else:
					on_click.call()
		)
	return p


## 공용 용병 로스터 스크롤 리스트를 생성한다 (단일 열 VBox 또는 다중 열 Grid 지원).
static func merc_roster_list(mercs: Array, opts: Dictionary = {}) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var cols: int = maxi(1, int(opts.get("columns", 1)))
	var list_box: Control
	if cols > 1:
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", int(opts.get("separation", 8)))
		grid.add_theme_constant_override("v_separation", int(opts.get("separation", 8)))
		list_box = grid
	else:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", int(opts.get("separation", 6)))
		list_box = vb
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	if mercs.is_empty():
		var empty_txt: String = str(opts.get("empty_text", ""))
		if empty_txt != "":
			list_box.add_child(label(empty_txt, 11, opts.get("empty_color", TEXT2)))
		return scroll

	var base_card_opts: Dictionary = opts.get("card_opts", {})
	var card_opts_fn: Callable = opts.get("card_opts_fn", Callable())
	var sel_merc = opts.get("selected_merc", null)
	for i in range(mercs.size()):
		var m: Mercenary = mercs[i]
		var c_opts: Dictionary = base_card_opts.duplicate()
		if card_opts_fn.is_valid():
			var dyn = card_opts_fn.call(m, i)
			if dyn is Dictionary:
				c_opts.merge(dyn, true)
		if sel_merc != null and not c_opts.has("selected"):
			c_opts["selected"] = (m == sel_merc)
		if opts.has("on_click") and not c_opts.has("on_click"):
			c_opts["on_click"] = opts["on_click"]
		list_box.add_child(merc_card(m, c_opts))

	return scroll


## 3단 고딕 대형 건물 모달 스캐폴드(좌측 로스터/카탈로그 · 중앙 전경/요약 · 우측 상세/액션)를 조립해 슬롯 딕셔너리를 반환한다.
static func three_column_modal(parent: Control, left_title: String, right_title: String, opts: Dictionary = {}) -> Dictionary:
	var main_h := HBoxContainer.new()
	main_h.add_theme_constant_override("separation", int(opts.get("col_separation", 12)))
	main_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if parent != null:
		parent.add_child(main_h)

	# [1. 좌측 컬럼]
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(int(opts.get("left_width", 260)), 0)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	main_h.add_child(left_col)

	var left_card := panel(opts.get("left_bg", BG3), opts.get("left_border", BORDER), 8)
	left_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_v := VBoxContainer.new()
	left_v.add_theme_constant_override("separation", 8)
	left_card.add_child(left_v)
	if left_title != "":
		left_v.add_child(title(left_title, int(opts.get("left_title_size", 13)), opts.get("left_title_color", GOLD)))
	left_col.add_child(left_card)

	# [2. 중앙 컬럼]
	var center_col := VBoxContainer.new()
	center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_col.add_theme_constant_override("separation", int(opts.get("center_separation", 10)))
	main_h.add_child(center_col)

	# [3. 우측 컬럼]
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(int(opts.get("right_width", 300)), 0)
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 8)
	main_h.add_child(right_col)

	var right_panel := panel(opts.get("right_bg", BG2), opts.get("right_border", BORDER2), 10)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", int(opts.get("right_separation", 10)))
	right_panel.add_child(right_v)
	if right_title != "":
		right_v.add_child(title(right_title, int(opts.get("right_title_size", 15)), opts.get("right_title_color", GOLD)))
		if bool(opts.get("right_divider", true)):
			right_v.add_child(divider())
	right_col.add_child(right_panel)

	return {
		"root": main_h,
		"left": left_v,
		"left_card": left_card,
		"left_col": left_col,
		"center": center_col,
		"right": right_v,
		"right_panel": right_panel,
		"right_col": right_col,
	}


## 모달 중앙 하단 등에 배치하는 공용 고딕 요약 카드 컨테이너를 생성한다.
static func modal_summary_card(parent: Control, title_text: String, opts: Dictionary = {}) -> VBoxContainer:
	var card := panel(opts.get("bg", BG2), opts.get("border", BORDER2), 8)
	var min_h: int = int(opts.get("min_height", 140))
	if min_h > 0:
		card.custom_minimum_size = Vector2(0, min_h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(opts.get("separation", 6)))
	card.add_child(v)
	if title_text != "":
		v.add_child(title(title_text, int(opts.get("title_size", 13)), opts.get("title_color", GOLD)))
	if parent != null:
		parent.add_child(card)
	return v
