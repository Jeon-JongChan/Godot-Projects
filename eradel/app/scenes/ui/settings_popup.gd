class_name SettingsPopup
extends Control

## 환경설정 팝업 — 게임플레이, 비디오, 오디오, 조작키 4개 탭을 제공하는 독립 컴포넌트.
## 기획서 5장 및 그림 3, 4, 5, 6 스케치 기반.

signal closed

enum Tab { GAMEPLAY, VIDEO, AUDIO, CONTROLS }

var _current_tab: Tab = Tab.GAMEPLAY
var _tab_buttons: Array[Button] = []
var _tab_panels: Array[Control] = []

# 키 바인딩 변경 대기 상태
var _rebinding_action: String = ""
var _rebind_modal: Control = null

var _sm: Node:
	get:
		var node = get_node_or_null("/root/SettingsManager")
		if node != null:
			return node
		var ml = Engine.get_main_loop()
		if ml != null and "root" in ml and ml.root != null:
			return ml.root.get_node_or_null("SettingsManager")
		return null


func _ready() -> void:
	# 어두운 딤 배경
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	# 메인 패널
	var panel := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 12)
	panel.custom_minimum_size = Vector2(680, 520)
	center.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(main_vbox)

	# 헤더 (타이틀 + 닫기)
	var header := HBoxContainer.new()
	var title_lbl := UiKit.title("환경설정 (SETTINGS)", 20, UiKit.GOLD)
	header.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := UiKit.button("✕", UiKit.RED)
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(close_popup)
	header.add_child(close_btn)
	main_vbox.add_child(header)

	# 4개 탭 버튼 바
	var tabs_bar := HBoxContainer.new()
	tabs_bar.add_theme_constant_override("separation", 6)
	main_vbox.add_child(tabs_bar)

	var tab_names := ["Gameplay", "Video", "Audio", "Controls"]
	for i in tab_names.size():
		var btn := UiKit.button(tab_names[i])
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		var t_idx := i
		btn.pressed.connect(func(): _switch_tab(t_idx as Tab))
		tabs_bar.add_child(btn)
		_tab_buttons.append(btn)

	main_vbox.add_child(UiKit.hsep(4))

	# 탭 콘텐츠 컨테이너
	var content_area := PanelContainer.new()
	content_area.size_flags_vertical = SIZE_EXPAND_FILL
	content_area.add_theme_stylebox_override("panel", UiKit.style(UiKit.BG3, UiKit.BORDER, 8))
	main_vbox.add_child(content_area)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	content_area.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_left", 16)
	scroll_margin.add_theme_constant_override("margin_right", 16)
	scroll_margin.add_theme_constant_override("margin_top", 12)
	scroll_margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(scroll_margin)

	var tabs_holder := VBoxContainer.new()
	tabs_holder.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_margin.add_child(tabs_holder)

	# 4개 탭 화면 구축
	_tab_panels.append(_build_gameplay_tab())
	_tab_panels.append(_build_video_tab())
	_tab_panels.append(_build_audio_tab())
	_tab_panels.append(_build_controls_tab())

	for p in _tab_panels:
		tabs_holder.add_child(p)

	_switch_tab(Tab.GAMEPLAY)


func _unhandled_input(event: InputEvent) -> void:
	if _rebinding_action != "":
		# 키 바인딩 대기 중인 경우
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				_cancel_rebind()
			else:
				_apply_rebind(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close_popup()
		get_viewport().set_input_as_handled()


## 탭 전환 처리
func _switch_tab(tab: Tab) -> void:
	_current_tab = tab
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		if i == tab:
			btn.add_theme_stylebox_override("normal", UiKit.style(UiKit.GOLD.darkened(0.5), UiKit.GOLD, 6))
			btn.add_theme_color_override("font_color", UiKit.WHITE)
		else:
			btn.add_theme_stylebox_override("normal", UiKit.style(UiKit.BG, UiKit.BORDER, 6))
			btn.add_theme_color_override("font_color", UiKit.TEXT3)

	for i in _tab_panels.size():
		_tab_panels[i].visible = (i == tab)


# ── 1. Gameplay 탭 ──
func _build_gameplay_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	# ST-G1: 전투 배속 (라디오 그룹)
	vbox.add_child(_create_radio_row("전투 배속", [
		{"label": "×1", "value": 1},
		{"label": "×2", "value": 2},
		{"label": "×4", "value": 4},
	], _sm.gameplay.get("battle_speed", 1) if _sm != null else 1, func(val):
		if _sm != null:
			_sm.gameplay["battle_speed"] = val
			_sm.save_settings()
			_sm.apply_gameplay()
	))

	# ST-G2: 텍스트 출력 속도 (순서 변경: 피드백 반영 2번째 위치)
	vbox.add_child(_create_radio_row("텍스트 출력 속도", [
		{"label": "×1", "value": 1},
		{"label": "×2", "value": 2},
		{"label": "×4", "value": 4},
	], _sm.gameplay.get("text_speed", 1) if _sm != null else 1, func(val):
		if _sm != null:
			_sm.gameplay["text_speed"] = val
			_sm.save_settings()
			_sm.apply_gameplay()
	))

	# ST-G3: 설명 툴팁 활성화 (순서 변경: 피드백 반영 3번째 위치)
	vbox.add_child(_create_checkbox_row("설명 툴팁 활성화", _sm.gameplay.get("show_tooltips", true) if _sm != null else true, func(checked):
		if _sm != null:
			_sm.gameplay["show_tooltips"] = checked
			_sm.save_settings()
			_sm.apply_gameplay()
	))

	# ST-G4: 체력/자원 항시 표시
	vbox.add_child(_create_checkbox_row("체력 / 자원 수치 항시 표시", _sm.gameplay.get("always_show_hp", true) if _sm != null else true, func(checked):
		if _sm != null:
			_sm.gameplay["always_show_hp"] = checked
			_sm.save_settings()
			_sm.apply_gameplay()
	))

	# ST-G5: 화면 흔들림 효과
	var shake_row = _create_checkbox_row("화면 흔들림 연출 (카메라 셰이크)", _sm.gameplay.get("screen_shake", true) if _sm != null else true, func(checked):
		if _sm != null:
			_sm.gameplay["screen_shake"] = checked
			_sm.save_settings()
			_sm.apply_gameplay()
	)
	var shake_cb: CheckBox = shake_row.get_meta("checkbox")
	vbox.add_child(shake_row)

	# ST-G6: 광과민성 보호
	vbox.add_child(_create_checkbox_row("광과민성 보호 (섬광 완화 및 화면 흔들림 강제 끔)", _sm.gameplay.get("photosensitivity", false) if _sm != null else false, func(checked):
		if _sm != null:
			_sm.gameplay["photosensitivity"] = checked
			_sm.save_settings()
			_sm.apply_gameplay()
		if checked and shake_cb != null:
			shake_cb.button_pressed = false
	))

	return vbox


# ── 2. Video 탭 ──
func _build_video_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	# ST-V1: 화면 모드 (라디오)
	vbox.add_child(_create_radio_row("화면 모드", [
		{"label": "전체화면", "value": 0},
		{"label": "창모드", "value": 1},
		{"label": "전체 창모드", "value": 2},
	], _sm.video.get("window_mode", 1) if _sm != null else 1, func(val):
		if _sm != null:
			_sm.video["window_mode"] = val
			_sm.save_settings()
			_sm.apply_video()
	))

	# ST-V2: 해상도 (드롭다운) — 현재 유저 모니터 최대 해상도 이하만 필터링 노출
	var all_res_options := [
		Vector2i(960, 540),
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
	]
	var screen_size := DisplayServer.screen_get_size()
	var res_options: Array[String] = []
	for opt in all_res_options:
		if opt.x <= screen_size.x and opt.y <= screen_size.y:
			res_options.append("%d×%d" % [opt.x, opt.y])

	if res_options.is_empty():
		res_options.append("1280×720")

	var cur_w: int = _sm.video.get("resolution_w", 1280) if _sm != null else 1280
	var cur_h: int = _sm.video.get("resolution_h", 720) if _sm != null else 720
	var cur_res_str := "%d×%d" % [cur_w, cur_h]
	var res_idx := res_options.find(cur_res_str)
	if res_idx == -1:
		res_idx = 0

	vbox.add_child(_create_dropdown_row("해상도", res_options, res_idx, func(selected_idx):
		if _sm != null:
			var parts: PackedStringArray = str(res_options[selected_idx]).split("×")
			_sm.video["resolution_w"] = int(parts[0])
			_sm.video["resolution_h"] = int(parts[1])
			_sm.save_settings()
			_sm.apply_video()
	))

	# ST-V3: 최대 프레임 제한 (드롭다운)
	var fps_labels := ["30 FPS", "60 FPS", "120 FPS", "144 FPS", "제한 없음"]
	var fps_values := [30, 60, 120, 144, 0]
	var cur_fps: int = _sm.video.get("max_fps", 60) if _sm != null else 60
	var fps_idx := fps_values.find(cur_fps)
	if fps_idx == -1:
		fps_idx = 1

	vbox.add_child(_create_dropdown_row("최대 프레임 제한", fps_labels, fps_idx, func(selected_idx):
		if _sm != null:
			_sm.video["max_fps"] = fps_values[selected_idx]
			_sm.save_settings()
			_sm.apply_video()
	))

	# ST-V4: 그래픽 종합 품질
	var sub_quality_radios: Array[Node] = []
	vbox.add_child(_create_radio_row("그래픽 종합 품질", [
		{"label": "상", "value": "high"},
		{"label": "중", "value": "medium"},
		{"label": "하", "value": "low"},
	], _sm.video.get("graphic_quality", "medium") if _sm != null else "medium", func(val):
		if _sm != null:
			_sm.video["graphic_quality"] = val
			_sm.video["texture_quality"] = val
			_sm.video["shadow_quality"] = val
			_sm.video["antialiasing"] = val
			_sm.save_settings()
			_sm.apply_video()
		for r_row in sub_quality_radios:
			if r_row.has_method("select_value"):
				r_row.select_value(val)
	))

	# ST-V5, V6, V7 세부 품질
	var tex_row = _create_radio_row("텍스처 품질", [
		{"label": "상", "value": "high"}, {"label": "중", "value": "medium"}, {"label": "하", "value": "low"}
	], _sm.video.get("texture_quality", "medium") if _sm != null else "medium", func(v):
		if _sm != null:
			_sm.video["texture_quality"] = v
			_sm.save_settings()
	)
	sub_quality_radios.append(tex_row)
	vbox.add_child(tex_row)

	var shd_row = _create_radio_row("그림자 품질", [
		{"label": "상", "value": "high"}, {"label": "중", "value": "medium"}, {"label": "하", "value": "low"}
	], _sm.video.get("shadow_quality", "medium") if _sm != null else "medium", func(v):
		if _sm != null:
			_sm.video["shadow_quality"] = v
			_sm.save_settings()
	)
	sub_quality_radios.append(shd_row)
	vbox.add_child(shd_row)

	var aa_row = _create_radio_row("안티 앨리어싱", [
		{"label": "상", "value": "high"}, {"label": "중", "value": "medium"}, {"label": "하", "value": "low"}
	], _sm.video.get("antialiasing", "medium") if _sm != null else "medium", func(v):
		if _sm != null:
			_sm.video["antialiasing"] = v
			_sm.save_settings()
	)
	sub_quality_radios.append(aa_row)
	vbox.add_child(aa_row)

	# ST-V8: 화면 밝기 슬라이더
	vbox.add_child(_create_slider_row("화면 밝기 보정", _sm.video.get("brightness", 50) if _sm != null else 50, 0, 100, func(val):
		if _sm != null:
			_sm.video["brightness"] = int(val)
			_sm.save_settings()
	))

	return vbox


# ── 3. Audio 탭 ──
func _build_audio_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	# ST-A1: 마스터 음량
	vbox.add_child(_create_slider_row("마스터 음량", _sm.audio.get("master_volume", 80) if _sm != null else 80, 0, 100, func(val):
		if _sm != null:
			_sm.audio["master_volume"] = int(val)
			_sm.save_settings()
			_sm.apply_audio()
	))

	# ST-A2: 배경음량
	vbox.add_child(_create_slider_row("배경음량 (BGM)", _sm.audio.get("bgm_volume", 70) if _sm != null else 70, 0, 100, func(val):
		if _sm != null:
			_sm.audio["bgm_volume"] = int(val)
			_sm.save_settings()
			_sm.apply_audio()
	))

	# ST-A3: 효과음량
	vbox.add_child(_create_slider_row("효과음량 (SFX)", _sm.audio.get("sfx_volume", 80) if _sm != null else 80, 0, 100, func(val):
		if _sm != null:
			_sm.audio["sfx_volume"] = int(val)
			_sm.save_settings()
			_sm.apply_audio()
	))

	# ST-A4: 인터페이스 음량
	vbox.add_child(_create_slider_row("인터페이스 음량 (UI)", _sm.audio.get("ui_volume", 80) if _sm != null else 80, 0, 100, func(val):
		if _sm != null:
			_sm.audio["ui_volume"] = int(val)
			_sm.save_settings()
			_sm.apply_audio()
	))

	# ST-A5: 오디오 출력 장치
	var dev_list := ["기본 장치"]
	var godot_devs = AudioServer.get_output_device_list()
	for d in godot_devs:
		if not dev_list.has(d):
			dev_list.append(d)

	var cur_dev: String = _sm.audio.get("output_device", "기본 장치") if _sm != null else "기본 장치"
	var dev_idx := dev_list.find(cur_dev)
	if dev_idx == -1:
		dev_idx = 0

	vbox.add_child(_create_dropdown_row("오디오 출력 장치", dev_list, dev_idx, func(selected_idx):
		if _sm != null:
			_sm.audio["output_device"] = dev_list[selected_idx]
			_sm.save_settings()
			_sm.apply_audio()
	))

	# ST-A6: 백그라운드 음소거
	vbox.add_child(_create_checkbox_row("백그라운드 음소거 (창 포커스 해제 시 소리 끔)", _sm.audio.get("mute_in_background", true) if _sm != null else true, func(checked):
		if _sm != null:
			_sm.audio["mute_in_background"] = checked
			_sm.save_settings()
	))

	# ST-A7: 자막 활성화
	vbox.add_child(_create_checkbox_row("대사 및 내레이션 자막 활성화", _sm.audio.get("subtitles", true) if _sm != null else true, func(checked):
		if _sm != null:
			_sm.audio["subtitles"] = checked
			_sm.save_settings()
	))

	return vbox


# ── 4. Controls 탭 ──
var _key_buttons: Dictionary = {}

func _build_controls_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var guide := UiKit.label("버튼을 클릭한 뒤 원하는 키를 누르면 변경됩니다. (ESC: 취소)", 12, UiKit.TEXT2)
	vbox.add_child(guide)

	var action_labels := {
		"inventory": "인벤토리 열기",
		"map": "던전/영지 지도",
		"menu": "일시정지 / 메뉴",
		"end_turn": "턴 종료 / 행동 완료",
	}

	_key_buttons.clear()
	for act in ["inventory", "map", "menu", "end_turn"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var lbl := UiKit.label(action_labels.get(act, act), 14, UiKit.TEXT)
		lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(lbl)

		var cur_key: int = int(_sm.controls.get(act, KEY_NONE)) if _sm != null else KEY_NONE
		var key_label: String = _sm.get_key_label(cur_key) if _sm != null else OS.get_keycode_string(cur_key as Key)
		var key_btn := UiKit.button(key_label, UiKit.GOLD)
		key_btn.custom_minimum_size = Vector2(140, 36)
		var this_act: String = str(act)
		key_btn.pressed.connect(func(): _start_rebind(this_act))
		row.add_child(key_btn)
		_key_buttons[act] = key_btn

		vbox.add_child(row)

	vbox.add_child(UiKit.hsep(12))

	# 기본값 복원 버튼
	var reset_btn := UiKit.button("기본값으로 되돌리기", UiKit.TEXT2)
	reset_btn.custom_minimum_size = Vector2(160, 38)
	reset_btn.pressed.connect(_on_reset_controls)
	vbox.add_child(reset_btn)

	return vbox


## 키 리바인딩 시작
func _start_rebind(action_name: String) -> void:
	_rebinding_action = action_name
	if _rebind_modal != null:
		_rebind_modal.queue_free()

	_rebind_modal = ColorRect.new()
	_rebind_modal.color = Color(0, 0, 0, 0.7)
	_rebind_modal.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_rebind_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	_rebind_modal.add_child(center)

	var box := UiKit.panel(UiKit.BG, UiKit.GOLD, 10)
	box.custom_minimum_size = Vector2(340, 140)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	box.add_child(vbox)

	var t := UiKit.title("새로운 키를 입력하세요", 16, UiKit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)

	var sub := UiKit.label("동작: " + action_name + " (ESC 누르면 취소)", 13, UiKit.TEXT2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)


## 키 리바인딩 적용
func _apply_rebind(new_key: int) -> void:
	var act := _rebinding_action
	_rebinding_action = ""
	if _rebind_modal != null:
		_rebind_modal.queue_free()
		_rebind_modal = null

	if _sm != null:
		# 기존에 같은 키를 사용하는 다른 액션이 있는지 확인하고 교환(Swap)
		for other_act in _sm.controls:
			if other_act != act and _sm.controls[other_act] == new_key:
				var prev_key = _sm.controls[act]
				_sm.controls[other_act] = prev_key
				if _key_buttons.has(other_act):
					_key_buttons[other_act].text = _sm.get_key_label(prev_key)
				break

		_sm.controls[act] = new_key
		if _key_buttons.has(act):
			_key_buttons[act].text = _sm.get_key_label(new_key)

		_sm.apply_controls()
		_sm.save_settings()


func _cancel_rebind() -> void:
	_rebinding_action = ""
	if _rebind_modal != null:
		_rebind_modal.queue_free()
		_rebind_modal = null


func _on_reset_controls() -> void:
	if _sm != null:
		_sm.reset_controls_to_default()
		for act in _key_buttons:
			var k: int = int(_sm.controls.get(act, KEY_NONE))
			_key_buttons[act].text = _sm.get_key_label(k)


# ── 공통 UI 컨트롤 헬퍼 ──

var _cached_unchecked_icon: ImageTexture = null
var _cached_checked_icon: ImageTexture = null


## 체크되지 않았을 때도 또렷한 빈 사각 박스 아이콘을 생성한다.
func _get_unchecked_icon() -> ImageTexture:
	if _cached_unchecked_icon != null:
		return _cached_unchecked_icon
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.1, 0.08, 1.0))
	var border_color := Color(0.5, 0.45, 0.35, 1.0)
	for x in range(18):
		img.set_pixel(x, 0, border_color)
		img.set_pixel(x, 17, border_color)
	for y in range(18):
		img.set_pixel(0, y, border_color)
		img.set_pixel(17, y, border_color)
	_cached_unchecked_icon = ImageTexture.create_from_image(img)
	return _cached_unchecked_icon


## 체크되었을 때 골드 테두리와 체크마크가 채워진 아이콘을 생성한다.
func _get_checked_icon() -> ImageTexture:
	if _cached_checked_icon != null:
		return _cached_checked_icon
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.1, 0.08, 1.0))
	var border_color := UiKit.GOLD
	for x in range(18):
		img.set_pixel(x, 0, border_color)
		img.set_pixel(x, 17, border_color)
	for y in range(18):
		img.set_pixel(0, y, border_color)
		img.set_pixel(17, y, border_color)

	# 체크마크 (V자) 그리기
	var check_pixels := [
		Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11), Vector2i(7, 12),
		Vector2i(8, 11), Vector2i(9, 10), Vector2i(10, 9), Vector2i(11, 8),
		Vector2i(12, 7), Vector2i(13, 6),
		Vector2i(4, 10), Vector2i(5, 11), Vector2i(6, 12), Vector2i(7, 13),
		Vector2i(8, 12), Vector2i(9, 11), Vector2i(10, 10), Vector2i(11, 9),
		Vector2i(12, 8), Vector2i(13, 7)
	]
	for p in check_pixels:
		img.set_pixel(p.x, p.y, UiKit.GOLD)
	_cached_checked_icon = ImageTexture.create_from_image(img)
	return _cached_checked_icon


## 라벨은 좌측(폰트 13px 통일), 체크박스는 우측에 배치하며 미체크 시에도 빈 사각 박스가 보이는 체크 행
func _create_checkbox_row(title_text: String, initial_val: bool, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var lbl := UiKit.label(title_text, 13, UiKit.TEXT)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var cb := CheckBox.new()
	cb.focus_mode = FOCUS_NONE
	cb.button_pressed = initial_val
	cb.add_theme_icon_override("unchecked", _get_unchecked_icon())
	cb.add_theme_icon_override("checked", _get_checked_icon())
	cb.toggled.connect(on_changed)
	row.add_child(cb)

	row.set_meta("checkbox", cb)
	return row


func _create_slider_row(label_text: String, initial_val: float, min_val: float, max_val: float, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var lbl := UiKit.label(label_text, 14, UiKit.TEXT)
	lbl.custom_minimum_size = Vector2(160, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 1.0
	slider.value = initial_val
	slider.focus_mode = FOCUS_NONE
	row.add_child(slider)

	var val_lbl := UiKit.label("%d" % int(initial_val), 13, UiKit.GOLD)
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v):
		val_lbl.text = "%d" % int(v)
		on_changed.call(v)
	)

	return row


func _create_dropdown_row(label_text: String, options: Array, selected_idx: int, on_selected: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var lbl := UiKit.label(label_text, 14, UiKit.TEXT)
	lbl.custom_minimum_size = Vector2(160, 0)
	row.add_child(lbl)

	var opt_btn := OptionButton.new()
	opt_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	opt_btn.custom_minimum_size = Vector2(0, 34)
	opt_btn.focus_mode = FOCUS_NONE
	for i in options.size():
		opt_btn.add_item(str(options[i]), i)
	opt_btn.selected = selected_idx
	opt_btn.item_selected.connect(on_selected)
	row.add_child(opt_btn)

	return row


func _create_radio_row(label_text: String, items: Array, current_val, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lbl := UiKit.label(label_text, 14, UiKit.TEXT)
	lbl.custom_minimum_size = Vector2(160, 0)
	row.add_child(lbl)

	var btns_box := HBoxContainer.new()
	btns_box.add_theme_constant_override("separation", 6)
	row.add_child(btns_box)

	var radio_buttons: Array[Button] = []
	var update_visuals = func(selected_v):
		for idx in items.size():
			var it: Dictionary = items[idx]
			var b: Button = radio_buttons[idx]
			if it["value"] == selected_v:
				b.add_theme_stylebox_override("normal", UiKit.style(UiKit.GOLD.darkened(0.5), UiKit.GOLD, 4))
				b.add_theme_color_override("font_color", UiKit.WHITE)
			else:
				b.add_theme_stylebox_override("normal", UiKit.style(UiKit.BG, UiKit.BORDER, 4))
				b.add_theme_color_override("font_color", UiKit.TEXT3)

	for item in items:
		var btn := UiKit.button(str(item["label"]))
		btn.custom_minimum_size = Vector2(60, 32)
		var val = item["value"]
		btn.pressed.connect(func():
			update_visuals.call(val)
			on_changed.call(val)
		)
		btns_box.add_child(btn)
		radio_buttons.append(btn)

	update_visuals.call(current_val)

	# 외부에서 값 변경 시 호출 가능한 헬퍼 메서드 추가
	row.set_meta("select_value", update_visuals)
	return row


## 팝업 닫기
func close_popup() -> void:
	closed.emit()
	queue_free()
