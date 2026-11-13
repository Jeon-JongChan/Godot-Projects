extends CanvasLayer

## F1 디버그/치트 콘솔 오토로드.
## 기능 테스트 시 자원 부족이나 상태 조건 제약을 즉시 해제할 수 있는 오버레이 창과 명령어 실행기를 제공한다.

var _root: Control
var _panel: PanelContainer
var _status_label: Label
var _log_view: RichTextLabel
var _cmd_input: LineEdit


## 콘솔 UI 트리를 구성하고 초기에는 숨김 상태로 대기한다.
func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false
	_connect_signals()
	_refresh_status()
	_append_log("[color=#c9a84c]에라델 디버그 콘솔 준비 완료.[/color] 'help' 입력 또는 상단 치트 버튼을 사용하세요.")


## GameState 자원/스트레스 변경 시 콘솔 상단 상태 표시줄을 동기화한다.
func _connect_signals() -> void:
	if not GameState.resources_changed.is_connected(_refresh_status):
		GameState.resources_changed.connect(_refresh_status)
	if not GameState.stress_changed.is_connected(_refresh_status):
		GameState.stress_changed.connect(_refresh_status)


## F1 키로 콘솔을 토글하고, 열려 있을 때 ESC 입력이 일시정지 팝업으로 전파되지 않도록 소비한다.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var kev := event as InputEventKey
	if not kev.pressed or kev.echo:
		return
	if kev.keycode == KEY_F1 or kev.physical_keycode == KEY_F1:
		toggle_console()
		get_viewport().set_input_as_handled()
		return
	if _root.visible and (kev.keycode == KEY_ESCAPE or kev.physical_keycode == KEY_ESCAPE):
		close_console()
		get_viewport().set_input_as_handled()


## 콘솔 창이 현재 화면에 열려 있는지 반환한다.
func is_open() -> bool:
	return _root != null and _root.visible


## 콘솔 창을 열고 명령어 입력란에 포커스를 둔다.
func open_console() -> void:
	if _root == null:
		return
	_root.visible = true
	_refresh_status()
	if is_instance_valid(_cmd_input) and _cmd_input.is_inside_tree():
		_cmd_input.grab_focus()


## 콘솔 창을 닫고 입력 포커스를 해제한다.
func close_console() -> void:
	if _root == null:
		return
	if is_instance_valid(_cmd_input):
		_cmd_input.release_focus()
	_root.visible = false


## 콘솔 창 열림/닫힘 상태를 전환한다.
func toggle_console() -> void:
	if is_open():
		close_console()
	else:
		open_console()


## 치트 명령어 문자열을 파싱·실행하고 결과 문자열을 반환한다.
func execute_command(cmd_line: String) -> String:
	var trimmed := cmd_line.strip_edges()
	if trimmed.is_empty():
		return ""
	var parts := trimmed.split(" ", false)
	var op := parts[0].to_lower()
	var arg := parts[1] if parts.size() > 1 else ""
	var result := ""

	match op:
		"help", "?":
			result = "명령어: gold <n> | add_gold <n> | mana <n> | add_mana <n> | ore <n> | add_ore <n> | ap <n|max> | stress <n> | heal_all | max_buildings | clear"
		"clear":
			if is_instance_valid(_log_view):
				_log_view.clear()
			return "[OK] 로그 초기화"
		"gold":
			var v := _parse_int(arg, -1)
			if v < 0:
				result = "[ERR] 사용법: gold <0 이상의 정수>"
			else:
				GameState.gold = v
				GameState.resources_changed.emit()
				result = "[OK] 금화 = %d G" % GameState.gold
		"add_gold":
			var d := _parse_int(arg, 1000)
			GameState.add_gold(d)
			result = "[OK] 금화 %+d → %d G" % [d, GameState.gold]
		"mana":
			var v := _parse_int(arg, -1)
			if v < 0:
				result = "[ERR] 사용법: mana <0 이상의 정수>"
			else:
				GameState.manastone = v
				GameState.resources_changed.emit()
				result = "[OK] 마나석 = %d" % GameState.manastone
		"add_mana":
			var d := _parse_int(arg, 10)
			GameState.add_manastone(d)
			result = "[OK] 마나석 %+d → %d" % [d, GameState.manastone]
		"ore":
			var v := _parse_int(arg, -1)
			if v < 0:
				result = "[ERR] 사용법: ore <0 이상의 정수>"
			else:
				GameState.iron_ore = v
				GameState.resources_changed.emit()
				result = "[OK] 철광석 = %d" % GameState.iron_ore
		"add_ore":
			var d := _parse_int(arg, 100)
			GameState.add_iron_ore(d)
			result = "[OK] 철광석 %+d → %d" % [d, GameState.iron_ore]
		"ap":
			if arg.to_lower() == "max" or arg.is_empty():
				GameState.action_points = GameState.max_action_points
			else:
				var v := _parse_int(arg, -1)
				if v < 0:
					result = "[ERR] 사용법: ap <정수|max>"
				else:
					GameState.action_points = v
			if result.is_empty():
				GameState.resources_changed.emit()
				result = "[OK] 행동력 = %d / %d" % [GameState.action_points, GameState.max_action_points]
		"stress":
			var v := _parse_int(arg, 0)
			GameState.stress_resolvable = clampi(v, 0, GameState.MAX_STRESS)
			if v == 0:
				GameState.stress_permanent = 0
			GameState.stress_changed.emit()
			result = "[OK] 스트레스 = %d (영구=%d)" % [GameState.total_stress(), GameState.stress_permanent]
		"heal_all":
			var count := 0
			for m in GameState.roster:
				if m.status != Mercenary.Status.DEAD and m.status != Mercenary.Status.MISSING:
					m.hp = m.max_hp
					m.stress = 0
					m.penalties.clear()
					m.status = Mercenary.Status.READY
					count += 1
			GameState.roster_changed.emit()
			GameState.party_changed.emit()
			result = "[OK] 생존 용병 %d명 체력·스트레스·패널티 완전 회복" % count
		"max_buildings":
			for def in BuildingDb.DEFS:
				var bname: String = def.get("name", "")
				if bname == "어둠의 균열":
					continue
				GameState.buildings[bname] = BuildingDb.MAX_LEVEL
				if BuildingDb.ALIASES.has(bname):
					GameState.buildings[BuildingDb.ALIASES[bname]] = BuildingDb.MAX_LEVEL
			GameState.max_action_points = 5
			GameState.action_points = maxi(GameState.action_points, GameState.max_action_points)
			GameState.resources_changed.emit()
			result = "[OK] 모든 영지 시설 Lv.%d 달성 (최대 행동력 5)" % BuildingDb.MAX_LEVEL
		_:
			result = "[ERR] 알 수 없는 명령어: '%s' ('help' 참조)" % op

	_refresh_status()
	_append_log("> %s\n  %s" % [trimmed, result])
	return result


## 콘솔 오버레이 UI(반투명 배경, 빠른 치트 버튼, 로그 창, 명령어 입력창)를 생성한다.
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ConsoleRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.03, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = UiKit.panel(Color("110f0b"), UiKit.GOLD, 12)
	_panel.custom_minimum_size = Vector2(760, 480)
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	# 상단 헤더
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title_lbl := UiKit.title("⚙ 디버그 · 테스트 치트 콘솔 (F1)", 20, UiKit.GOLD2)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn := UiKit.button("닫기 (F1 / ESC)", UiKit.RED)
	close_btn.pressed.connect(close_console)
	header.add_child(close_btn)

	# 현재 자원 상태 요약 바
	_status_label = UiKit.label("", 13, UiKit.TEXT2)
	vbox.add_child(_status_label)

	vbox.add_child(UiKit.divider())

	# 원클릭 빠른 치트 버튼 묶음
	var cheat_lbl := UiKit.label("빠른 치트 (테스트용 즉시 지급)", 13, UiKit.GOLD)
	vbox.add_child(cheat_lbl)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	var quick_cheats := [
		{"label": "+1,000 금화", "cmd": "add_gold 1000"},
		{"label": "+10,000 금화", "cmd": "add_gold 10000"},
		{"label": "+20 마나석", "cmd": "add_mana 20"},
		{"label": "+200 철광석", "cmd": "add_ore 200"},
		{"label": "행동력 MAX", "cmd": "ap max"},
		{"label": "영웅 전원 회복", "cmd": "heal_all"},
		{"label": "스트레스 0", "cmd": "stress 0"},
		{"label": "모든 건물 Lv.5", "cmd": "max_buildings"},
	]
	for item in quick_cheats:
		var btn := UiKit.button(item["label"], UiKit.GOLD)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cmd_str: String = item["cmd"]
		btn.pressed.connect(func(): execute_command(cmd_str))
		grid.add_child(btn)

	# 콘솔 출력 로그
	var log_frame := UiKit.panel(Color("090806"), UiKit.BORDER2, 8)
	log_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(log_frame)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.selection_enabled = true
	_log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.add_theme_font_size_override("normal_font_size", 13)
	log_frame.add_child(_log_view)

	# 명령어 입력 행
	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 8)
	vbox.add_child(cmd_row)

	_cmd_input = LineEdit.new()
	_cmd_input.placeholder_text = "명령어 입력 (예: gold 5000, mana 25, ore 300, ap 5, heal_all, help)"
	_cmd_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cmd_input.add_theme_stylebox_override("normal", UiKit.style(UiKit.BG3, UiKit.BORDER2, 6))
	_cmd_input.add_theme_color_override("font_color", UiKit.WHITE)
	_cmd_input.text_submitted.connect(_on_submit_command)
	cmd_row.add_child(_cmd_input)

	var run_btn := UiKit.primary_button("실행", UiKit.GREEN)
	run_btn.pressed.connect(func(): _on_submit_command(_cmd_input.text))
	cmd_row.add_child(run_btn)


## 입력창에서 엔터/실행 버튼 누름 시 명령을 실행하고 입력창을 비운다.
func _on_submit_command(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	execute_command(text)
	if is_instance_valid(_cmd_input):
		_cmd_input.text = ""
		_cmd_input.grab_focus()


## 상단 요약 바에 현재 금화/마나석/철광석/행동력/스트레스를 갱신한다.
func _refresh_status() -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = "현재 상태 | 금화: %dG   마나석: %d   철광석: %d   행동력: %d/%d   스트레스: %d/%d   일차: %d일" % [
		GameState.gold,
		GameState.manastone,
		GameState.iron_ore,
		GameState.action_points,
		GameState.max_action_points,
		GameState.total_stress(),
		GameState.MAX_STRESS,
		GameState.day,
	]


## 콘솔 로그 영역에 타임스탬프 없이 줄 단위로 텍스트를 추가한다.
func _append_log(line: String) -> void:
	if is_instance_valid(_log_view):
		_log_view.append_text(line + "\n")


## 문자열 인자를 정수로 변환하며, 유효하지 않으면 fallback 값을 반환한다.
func _parse_int(raw: String, fallback: int) -> int:
	if raw.is_valid_int():
		return raw.to_int()
	return fallback
