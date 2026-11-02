extends Control

var _root: MarginContainer

const EFFECTS := {
	"용병모집소": "모집 용병 초기 최대 체력 +5 / 레벨",
	"영웅숙소": "원정 귀환 시 일일 스트레스 자연 감소",
	"치료소": "부상 및 패널티 완화 성공률 향상",
	"영주저택": "최대 행동력 및 통치 결단 효율 증가",
	"잡화점": "원정 보급품 구매 가격 할인",
	"창고": "마나석 교역 환율 및 전리품 가치 증가",
	"대장간": "파티 전체 공격력 +2 / 레벨",
	"훈련장": "용병 특훈 성장 효율 증가",
	"마법사학회": "차원 균열 억제 및 마나 연구 효율 증가",
	"기념관": "영령 추모 시 민심 및 스트레스 완화 증가",
	"마탑": "마나 관련 연구 효율 증가",
	"모험가 길드": "모집 용병 품질 향상",
	"주점": "매일 해소 스트레스 감소",
	"영주 저택": "최대 행동력 및 통치 효율 증가",
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
	if lv >= 5:
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
