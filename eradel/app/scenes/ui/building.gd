extends Control

var _root: MarginContainer

const EFFECTS := {
	"대장간": "파티 공격력 +2 / 레벨",
	"마탑": "마나 관련 연구 (예정)",
	"모험가 길드": "모집 품질 향상 (예정)",
	"주점": "매일 해소 스트레스 감소",
	"영주 저택": "행동력 관련 (예정)",
	"잡화점": "상점 (예정)",
	"치료소": "패널티 완화 성공률 향상",
}


func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)
	GameState.resources_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	vbox.add_child(UiKit.top_bar("건물 관리", func(): get_tree().change_scene_to_file(GameState.SCENE_ESTATE)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	list.add_child(UiKit.label("업그레이드와 수리로 영지를 발전시키세요 (최대 Lv.5)", 12, UiKit.TEXT2))
	for building in GameState.buildings.keys():
		list.add_child(_building_card(building))


func _building_card(building: String) -> Control:
	var lv: int = GameState.buildings[building]
	var p := UiKit.panel(UiKit.BG2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.add_child(UiKit.label(building, 14, UiKit.WHITE))
	line.add_child(UiKit.chip("Lv.%d" % lv, UiKit.GREEN))
	info.add_child(line)
	info.add_child(UiKit.label(EFFECTS.get(building, ""), 11, UiKit.TEXT2))
	h.add_child(info)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	if building in ["마탑", "모험가 길드", "영주 저택", "잡화점"]:
		right.add_child(UiKit.label("미구현 (예정)", 12, UiKit.TEXT3))
		var btn := UiKit.button("업그레이드 불가", UiKit.TEXT3)
		btn.disabled = true
		right.add_child(btn)
	elif lv >= 5:
		right.add_child(UiKit.label("최대 레벨", 12, UiKit.GOLD))
	else:
		var c := GameState.upgrade_cost(building)
		var cost_text := "금화 %d" % c.gold
		if c.mana > 0:
			cost_text += " · 마나석 %d" % c.mana
		right.add_child(UiKit.label(cost_text, 11, UiKit.TEXT3))
		var btn := UiKit.button("업그레이드 (→ Lv.%d)" % (lv + 1), UiKit.GOLD)
		btn.disabled = not GameState.can_upgrade(building)
		btn.pressed.connect(func(): GameState.upgrade_building(building))
		right.add_child(btn)
	h.add_child(right)
	return p
