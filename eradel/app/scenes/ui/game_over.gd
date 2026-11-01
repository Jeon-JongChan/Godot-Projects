extends Control


func _ready() -> void:
	UiKit.background(self, Color("0e0808"))

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var tag := UiKit.label("영지 스트레스 100 도달", 13, UiKit.RED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)

	var title := UiKit.title("영지 붕괴", 56, UiKit.RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var lore := UiKit.label("주민들은 떠났고, 왕자의 이름은 다시 잊혀졌다.", 14, UiKit.TEXT2)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lore)

	box.add_child(UiKit.hsep(16))

	var stats := UiKit.panel(UiKit.BG2)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	stats.add_child(sv)
	sv.add_child(_stat("버틴 날", "%d일차" % GameState.day))
	sv.add_child(_stat("최종 스트레스", "%d (영구 %d)" % [GameState.total_stress(), GameState.stress_permanent]))
	sv.add_child(_stat("사망 / 실종", "%d명" % GameState.death_log.size()))
	sv.add_child(_stat("최종 민심", "%d%%" % GameState.morale))
	box.add_child(stats)

	box.add_child(UiKit.hsep(16))

	var btn := UiKit.primary_button("타이틀로", UiKit.GOLD)
	btn.custom_minimum_size = Vector2(220, 44)
	btn.pressed.connect(func(): get_tree().change_scene_to_file(GameState.SCENE_TITLE))
	box.add_child(btn)


func _stat(name: String, value: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var n := UiKit.label(name, 13, UiKit.TEXT2)
	n.custom_minimum_size = Vector2(140, 0)
	h.add_child(n)
	h.add_child(UiKit.label(value, 13, UiKit.TEXT))
	return h
