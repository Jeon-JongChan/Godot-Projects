extends Control

var _root: MarginContainer


func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)
	GameState.party_changed.connect(_rebuild)
	GameState.roster_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	vbox.add_child(UiKit.top_bar("던전 원정 준비", func(): get_tree().change_scene_to_file(GameState.SCENE_ESTATE)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	# 목표 던전
	var dungeon_panel := UiKit.panel(UiKit.BG2)
	var dv := VBoxContainer.new()
	dungeon_panel.add_child(dv)
	dv.add_child(UiKit.label("목표 던전 — 어둠의 균열", 14, UiKit.WHITE))
	dv.add_child(UiKit.label("\"한번 들어간 자는 같은 모습으로 돌아오지 않는다\"", 11, UiKit.TEXT3))
	var act_color := UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GOLD
	dv.add_child(UiKit.label("활성도 %d%% — 예상 난이도 %s" % [GameState.dungeon_activity, _difficulty_text()], 12, act_color))
	content.add_child(dungeon_panel)

	# 본문 좌우
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(body)

	body.add_child(_build_party())
	body.add_child(_build_available())

	# 하단
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	var hint := UiKit.label(_footer_hint(), 12, UiKit.TEXT2)
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(hint)
	var enter := UiKit.primary_button("던전 입장 ↗", UiKit.GREEN)
	enter.custom_minimum_size = Vector2(160, 44)
	enter.disabled = GameState.party.is_empty()
	enter.pressed.connect(_on_enter)
	footer.add_child(enter)
	content.add_child(footer)


func _difficulty_text() -> String:
	var a := GameState.dungeon_activity + GameState.monster_tier * 15
	if a >= 80: return "상"
	if a >= 50: return "중상"
	if a >= 30: return "중"
	return "하"


func _footer_hint() -> String:
	if GameState.party.is_empty():
		return "⚠ 최소 1명의 용병을 파티에 편성하세요."
	return "파티 %d명 편성됨. 입장하면 그 날의 원정이 시작됩니다." % GameState.party.size()


func _build_party() -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UiKit.label("파티 구성 (%d/%d)" % [GameState.party.size(), GameState.MAX_PARTY], 11, UiKit.TEXT2))
	if GameState.party.is_empty():
		v.add_child(UiKit.label("비어있음 — 오른쪽에서 용병을 추가하세요.", 12, UiKit.TEXT3))
	for m in GameState.party:
		v.add_child(_slot(m, true))
	return panel


func _build_available() -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UiKit.label("대기 용병", 11, UiKit.TEXT2))
	var avail := GameState.available_mercs()
	if avail.is_empty():
		v.add_child(UiKit.label("대기 중인 용병이 없습니다.", 12, UiKit.TEXT3))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for m in avail:
		list.add_child(_slot(m, false))
	return panel


func _slot(m: Mercenary, in_party: bool) -> Control:
	var p := UiKit.panel(UiKit.BG3, UiKit.BORDER, 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(UiKit.avatar(30))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	info.add_child(UiKit.label(m.merc_name, 12, UiKit.TEXT))
	info.add_child(UiKit.label("%s Lv.%d" % [m.job, m.level], 10, JobDb.category_color(m.category)))
	if m.penalties.size() > 0:
		info.add_child(UiKit.label("패널티 " + str(m.penalties.size()), 10, UiKit.RED))
	h.add_child(info)
	if in_party:
		var rm := UiKit.button("빼기", UiKit.RED)
		rm.pressed.connect(func(): GameState.remove_from_party(m))
		h.add_child(rm)
	else:
		var add := UiKit.button("추가", UiKit.GREEN)
		add.disabled = GameState.party.size() >= GameState.MAX_PARTY
		add.pressed.connect(func(): GameState.add_to_party(m))
		h.add_child(add)
	return p


func _on_enter() -> void:
	for m in GameState.party:
		m.status = Mercenary.Status.ON_EXPEDITION
	get_tree().change_scene_to_file(GameState.SCENE_DUNGEON)
