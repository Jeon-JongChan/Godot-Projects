extends Control

var _root: MarginContainer
var _last_msg: String = ""


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
	vbox.add_child(UiKit.top_bar("치료소", func(): get_tree().change_scene_to_file(GameState.SCENE_ESTATE)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	content.add_child(UiKit.label("\"상처는 낫지만, 흉터는 남는다\"  ·  성공률 %d%% (치료소 Lv.%d)" % [GameState.heal_success_rate(), GameState.buildings["치료소"]], 12, UiKit.TEXT2))
	if _last_msg != "":
		content.add_child(UiKit.label(_last_msg, 12, UiKit.GOLD))

	var injured := GameState.injured_mercs()
	if injured.is_empty():
		content.add_child(UiKit.label("치료가 필요한 용병이 없습니다.", 13, UiKit.TEXT3))
		return

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for m in injured:
		list.add_child(_merc_card(m))


func _merc_card(m: Mercenary) -> Control:
	var p := UiKit.panel(UiKit.BG2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.avatar(28))
	head.add_child(UiKit.label("%s — %s Lv.%d" % [m.merc_name, m.job, m.level], 13, UiKit.TEXT))
	v.add_child(head)
	for penalty in m.penalties.duplicate():
		v.add_child(_penalty_row(m, penalty))
	return p


func _penalty_row(m: Mercenary, penalty: String) -> Control:
	var cost := 80
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var p := UiKit.panel(UiKit.BG3, UiKit.RED.darkened(0.3), 6)
	p.add_child(h)
	var name := UiKit.label(penalty, 12, UiKit.TEXT)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(name)
	h.add_child(UiKit.label("금화 %d" % cost, 11, UiKit.TEXT3))
	var btn := UiKit.button("치료", UiKit.BLUE)
	btn.disabled = not GameState.can_afford(cost)
	btn.pressed.connect(func(): _on_treat(m, penalty, cost))
	h.add_child(btn)
	return p


func _on_treat(m: Mercenary, penalty: String, cost: int) -> void:
	var ok := GameState.treat_penalty(m, penalty, cost)
	_last_msg = "%s 의 '%s' 치료 %s" % [m.merc_name, penalty, "성공 — 완화됨" if ok else "실패 (흉터가 남았다)"]
	# rebuild 은 roster_changed 시그널로 자동 호출
