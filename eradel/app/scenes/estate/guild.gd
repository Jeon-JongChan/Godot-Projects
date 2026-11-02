extends Control

var _root: MarginContainer
var _last_recruited: Mercenary = null


func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)
	GameState.resources_changed.connect(_rebuild)
	GameState.roster_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	vbox.add_child(UiKit.top_bar("모험가 길드", func(): get_tree().change_scene_to_file(GameState.SCENE_ESTATE)))

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

	content.add_child(UiKit.label("\"봉인서를 뜯는 순간, 운명이 결정된다\"", 13, UiKit.TEXT2))

	# 모집 버튼
	var recruit_row := HBoxContainer.new()
	recruit_row.add_theme_constant_override("separation", 10)
	for grade in ["일반", "정예", "특수"]:
		recruit_row.add_child(_recruit_card(grade))
	content.add_child(recruit_row)

	# 최근 모집 결과
	if _last_recruited:
		var note := UiKit.panel(Color("1a2a1e"), UiKit.GREEN)
		var nv := VBoxContainer.new()
		note.add_child(nv)
		nv.add_child(UiKit.label("새 용병 합류!", 11, UiKit.GREEN))
		nv.add_child(_merc_card(_last_recruited, false))
		content.add_child(note)

	# 명단
	content.add_child(UiKit.label("용병 명단 (%d명)" % GameState.roster.size(), 11, UiKit.TEXT2))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var alive := GameState.roster.filter(func(m): return m.status != Mercenary.Status.DEAD and m.status != Mercenary.Status.MISSING)
	if alive.is_empty():
		grid.add_child(UiKit.label("아직 용병이 없습니다. 모집하세요.", 12, UiKit.TEXT3))
	for m in alive:
		grid.add_child(_merc_card(m, true))

	# 사망 기록
	if GameState.death_log.size() > 0:
		content.add_child(UiKit.label("사망 / 실종 기록 (%d)" % GameState.death_log.size(), 11, UiKit.RED))
		var recent := GameState.death_log.slice(maxi(0, GameState.death_log.size() - 3))
		for rec in recent:
			var txt := "%s — %s Lv.%d (%d일차%s)" % [rec.name, rec.job, rec.level, rec.day, " · 실종" if rec.get("missing", false) else " · 전사"]
			content.add_child(UiKit.label(txt, 11, UiKit.TEXT3))


func _recruit_card(grade: String) -> Control:
	var cost: int = JobDb.RECRUIT_COST[grade]
	var color := JobDb.grade_color(grade)
	var p := UiKit.panel(UiKit.BG3, color)
	p.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := UiKit.label("%s 모집" % grade, 14, color.lightened(0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var c := UiKit.label("금화 %d" % cost, 12, UiKit.TEXT2)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var btn := UiKit.button("모집", color)
	btn.disabled = not GameState.can_afford(cost) or GameState.action_points <= 0
	btn.pressed.connect(func(): _on_recruit(grade))
	v.add_child(btn)
	return p


func _on_recruit(grade: String) -> void:
	var m := GameState.recruit(grade)
	if m:
		_last_recruited = m
	# rebuild 은 roster_changed 시그널로 자동 호출됨


func _merc_card(m: Mercenary, show_status: bool) -> Control:
	var p := UiKit.panel(UiKit.BG2, UiKit.BORDER, 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(UiKit.avatar(32))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.add_child(UiKit.label(m.merc_name, 13, UiKit.TEXT))
	line.add_child(UiKit.chip(m.grade, JobDb.grade_color(m.grade)))
	info.add_child(line)
	info.add_child(UiKit.label("%s · %s Lv.%d" % [m.category, m.job, m.level], 11, JobDb.category_color(m.category)))
	var stats := UiKit.label("HP %d / 공격 %d" % [m.max_hp, m.attack], 10, UiKit.TEXT3)
	info.add_child(stats)
	if m.penalties.size() > 0:
		info.add_child(UiKit.label("패널티: " + ", ".join(m.penalties), 10, UiKit.RED))
	h.add_child(info)
	if show_status:
		var right_box := VBoxContainer.new()
		right_box.add_theme_constant_override("separation", 2)
		right_box.alignment = BoxContainer.ALIGNMENT_CENTER
		right_box.add_child(UiKit.chip(m.status_text(), UiKit.TEXT2))
		if m.status == Mercenary.Status.READY:
			var fire_btn := UiKit.button("해고", UiKit.RED)
			fire_btn.pressed.connect(func():
				GameState.roster.erase(m)
				GameState.roster_changed.emit()
			)
			right_box.add_child(fire_btn)
		h.add_child(right_box)
	return p
