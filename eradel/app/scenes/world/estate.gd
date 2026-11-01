extends Control

var _root: MarginContainer


func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)

	GameState.resources_changed.connect(_rebuild)
	GameState.stress_changed.connect(_rebuild)
	GameState.party_changed.connect(_rebuild)
	GameState.roster_changed.connect(_rebuild)
	GameState.game_over.connect(_on_game_over)
	_rebuild()


func _on_game_over() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_GAMEOVER)


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_root.add_child(vbox)

	# 상단바
	var bar := UiKit.top_bar("영지 관리   %d일차 — %s" % [GameState.day, GameState.season()])
	vbox.add_child(bar)

	# 본문 3단
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(body)
	vbox.add_child(margin)

	body.add_child(_build_left())
	body.add_child(_build_center())
	body.add_child(_build_right())


func _build_left() -> Control:
	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(260, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	v.add_child(UiKit.label("영지 현황", 11, UiKit.TEXT2))
	v.add_child(_stat_row("민심", "%d%%" % GameState.morale, GameState.morale, 100, UiKit.GOLD))
	var act_color := UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GREEN
	v.add_child(_stat_row("던전 활성도", "%d%%" % GameState.dungeon_activity, GameState.dungeon_activity, 100, act_color))
	if GameState.monster_tier > 0:
		v.add_child(UiKit.label("몬스터 강화 +%d 단계" % GameState.monster_tier, 11, UiKit.RED))

	v.add_child(UiKit.hsep(10))
	v.add_child(UiKit.label("이동", 11, UiKit.TEXT2))

	var b_build := UiKit.button("건물 관리")
	b_build.pressed.connect(func(): get_tree().change_scene_to_file(GameState.SCENE_BUILDING))
	v.add_child(b_build)

	var b_guild := UiKit.button("모험가 길드")
	b_guild.pressed.connect(func(): get_tree().change_scene_to_file(GameState.SCENE_GUILD))
	v.add_child(b_guild)

	var b_treat := UiKit.button("치료소")
	b_treat.pressed.connect(func(): get_tree().change_scene_to_file(GameState.SCENE_TREATMENT))
	v.add_child(b_treat)

	return panel


func _stat_row(name: String, value: String, cur: float, maxv: float, color: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var h := HBoxContainer.new()
	var n := UiKit.label(name, 12, UiKit.TEXT)
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(UiKit.label(value, 12, color))
	v.add_child(h)
	v.add_child(UiKit.progress(cur, maxv, color, 6))
	return v


func _build_center() -> Control:
	var panel := UiKit.panel(UiKit.BG2)
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	# 영지 지도
	v.add_child(UiKit.label("영지 지도", 11, UiKit.TEXT2))
	var map := UiKit.panel(UiKit.BG3, UiKit.BORDER)
	var map_v := VBoxContainer.new()
	map.add_child(map_v)
	map_v.add_child(UiKit.label("왕도 ─ 영지 ─ 차원문 ─ 바다", 14, UiKit.TEXT))
	map_v.add_child(UiKit.label("제국의 끝자락, 방치된 변경 영지 (추후 시각적 지도 구현 예정)", 12, UiKit.TEXT3))
	v.add_child(map)

	# 경보
	if GameState.dungeon_activity >= 60:
		var alert := UiKit.panel(Color("2a1a1a"), UiKit.RED)
		var av := VBoxContainer.new()
		alert.add_child(av)
		av.add_child(UiKit.label("⚠ 던전 경보", 13, UiKit.RED))
		av.add_child(UiKit.label("활성도가 높습니다. 몬스터가 점차 강해집니다.", 12, UiKit.TEXT2))
		v.add_child(alert)

	v.add_child(UiKit.hsep(4))

	# 스트레스
	v.add_child(UiKit.label("영지 스트레스", 11, UiKit.TEXT2))
	var stress_panel := UiKit.panel(UiKit.BG3)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	stress_panel.add_child(sv)
	var sh := HBoxContainer.new()
	var stage := UiKit.label("상태: %s" % GameState.stress_stage(), 13, GameState.stress_color())
	stage.size_flags_horizontal = SIZE_EXPAND_FILL
	sh.add_child(stage)
	sh.add_child(UiKit.label("%d / 100" % GameState.total_stress(), 13, UiKit.TEXT))
	sv.add_child(sh)
	sv.add_child(UiKit.progress(GameState.total_stress(), 100, GameState.stress_color(), 10))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(UiKit.chip("해소가능 %d" % GameState.stress_resolvable, UiKit.GOLD))
	tags.add_child(UiKit.chip("영구 %d" % GameState.stress_permanent, UiKit.RED))
	sv.add_child(tags)
	v.add_child(stress_panel)

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(spacer)

	return panel


func _build_right() -> Control:
	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(260, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	v.add_child(UiKit.label("원정 파티 (%d/%d)" % [GameState.party.size(), GameState.MAX_PARTY], 11, UiKit.TEXT2))

	for i in GameState.MAX_PARTY:
		if i < GameState.party.size():
			v.add_child(_member_row(GameState.party[i]))
		else:
			var empty := UiKit.panel(UiKit.BG3, UiKit.BORDER, 6)
			var el := UiKit.label("슬롯 비어있음", 11, UiKit.TEXT3)
			empty.add_child(el)
			v.add_child(empty)

	v.add_child(UiKit.hsep(8))
	var go := UiKit.primary_button("던전 원정 준비 ↗", UiKit.GREEN)
	go.custom_minimum_size = Vector2(0, 40)
	go.pressed.connect(func(): get_tree().change_scene_to_file(GameState.SCENE_PREP))
	v.add_child(go)

	return panel


func _member_row(m: Mercenary) -> Control:
	var p := UiKit.panel(UiKit.BG3, UiKit.BORDER, 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var av := UiKit.avatar(28)
	h.add_child(av)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	info.add_child(UiKit.label(m.merc_name, 12, UiKit.TEXT))
	info.add_child(UiKit.label("%s Lv.%d" % [m.job, m.level], 10, JobDb.category_color(m.category)))
	info.add_child(UiKit.progress(m.hp, m.max_hp, UiKit.GREEN, 4))
	h.add_child(info)
	return p
