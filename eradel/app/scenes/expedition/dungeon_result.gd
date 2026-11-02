extends Control


func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	var r := GameState.last_result
	if r.is_empty():
		get_tree().change_scene_to_file(GameState.SCENE_ESTATE)
		return

	var outcome: String = str(r.outcome)
	var result_theme := _theme_for(outcome)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	# 배너
	var banner := UiKit.panel(result_theme.bg, result_theme.color)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(bv)
	var label_state := UiKit.label(result_theme.label, 12, result_theme.color)
	label_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(label_state)
	var big := UiKit.title(result_theme.title, 34, result_theme.color)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(big)
	var lore := UiKit.label(result_theme.lore, 12, UiKit.TEXT2)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(lore)
	var dname := UiKit.label("어둠의 균열 던전 — %d일차" % GameState.day, 11, UiKit.TEXT3)
	dname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(dname)
	v.add_child(banner)

	# 본문 2단
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(body)
	body.add_child(_build_party(r))
	body.add_child(_build_loot(r))

	# 영지 파문
	v.add_child(_build_ripple(r))

	# 하단 버튼
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(sp)
	var ret := UiKit.primary_button("영지로 귀환 ↗", result_theme.color)
	ret.custom_minimum_size = Vector2(200, 46)
	ret.pressed.connect(_on_return)
	footer.add_child(ret)
	v.add_child(footer)


func _theme_for(outcome: String) -> Dictionary:
	match outcome:
		"clear":
			return {"label": "던전 클리어", "title": "귀환", "color": UiKit.GREEN,
				"bg": Color("0d1f12"), "lore": "\"살아 돌아온 자만이 다음을 이야기할 수 있다.\""}
		"retreat":
			return {"label": "철수", "title": "후퇴", "color": UiKit.GOLD,
				"bg": Color("1a100a"), "lore": "\"후퇴의 대가는 언제나 타인이 치른다.\""}
		_:
			return {"label": "전멸", "title": "몰살", "color": UiKit.RED,
				"bg": Color("1a0808"), "lore": "\"영지는 그들을 기다렸다. 그러나 아무도 돌아오지 않았다.\""}


func _build_party(r: Dictionary) -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("파티 현황", 11, UiKit.TEXT2))
	for m: Mercenary in r.survivors:
		v.add_child(_member_line(m, "생존", UiKit.GREEN))
	for m: Mercenary in r.missing:
		v.add_child(_member_line(m, "실종", UiKit.GOLD))
	for m: Mercenary in r.dead:
		v.add_child(_member_line(m, "사망", UiKit.RED))
	return panel


func _member_line(m: Mercenary, state: String, color: Color) -> Control:
	var p := UiKit.panel(UiKit.BG3, color.darkened(0.3), 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	info.add_child(UiKit.label(m.merc_name, 12, UiKit.TEXT))
	info.add_child(UiKit.label("%s Lv.%d" % [m.job, m.level], 10, UiKit.TEXT3))
	if state == "생존" and m.penalties.size() > 0:
		info.add_child(UiKit.label("새 패널티: " + ", ".join(m.penalties), 10, UiKit.RED))
	h.add_child(info)
	h.add_child(UiKit.chip(state, color))
	return p


func _build_loot(r: Dictionary) -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("획득 자원", 11, UiKit.TEXT2))
	var gold_gain: int = int(r.gold_gain)
	var mana_gain: int = int(r.mana_gain)
	v.add_child(_loot_row("금화", "+%d" % gold_gain if gold_gain > 0 else "0", UiKit.GOLD if gold_gain > 0 else UiKit.TEXT3))
	v.add_child(_loot_row("마나석", "+%d" % mana_gain if mana_gain > 0 else "0", UiKit.BLUE if mana_gain > 0 else UiKit.TEXT3))
	v.add_child(UiKit.hsep(6))
	v.add_child(UiKit.label("던전 변화", 11, UiKit.TEXT2))
	var act: int = int(r.activity_delta)
	var act_text := ("%d%%" % act) if act != 0 else "변화 없음"
	v.add_child(_loot_row("활성도", act_text, UiKit.GREEN if act < 0 else UiKit.RED))
	return panel


func _loot_row(name: String, value: String, color: Color) -> Control:
	var h := HBoxContainer.new()
	var n := UiKit.label(name, 12, UiKit.TEXT)
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(UiKit.label(value, 12, color))
	return h


func _build_ripple(r: Dictionary) -> Control:
	var panel := UiKit.panel(UiKit.BG2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("영지 파문", 11, UiKit.TEXT2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var resolvable_delta: int = int(r.resolvable_delta)
	var permanent_gain: int = int(r.permanent_gain)
	var morale_delta: int = int(r.morale_delta)
	h.add_child(UiKit.chip("해소 스트레스 %+d" % resolvable_delta, UiKit.GOLD))
	h.add_child(UiKit.chip("영구 스트레스 +%d" % permanent_gain, UiKit.RED))
	h.add_child(UiKit.chip("민심 %+d" % morale_delta, UiKit.GREEN if morale_delta >= 0 else UiKit.RED))
	v.add_child(h)
	var projected: int = clampi(GameState.total_stress() + resolvable_delta + permanent_gain, 0, 100)
	v.add_child(UiKit.label("귀환 시 영지 스트레스 예상: %d / 100" % projected, 12, UiKit.TEXT2))
	return panel


func _on_return() -> void:
	GameState.return_to_estate()
	if GameState.total_stress() >= GameState.MAX_STRESS:
		get_tree().change_scene_to_file(GameState.SCENE_GAMEOVER)
	else:
		get_tree().change_scene_to_file(GameState.SCENE_ESTATE)
