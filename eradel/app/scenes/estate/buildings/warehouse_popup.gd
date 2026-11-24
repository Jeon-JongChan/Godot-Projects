class_name WarehousePopup
extends BaseBuildingPopup
## 창고 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var ui := UiKit.three_column_modal(vbox, "ESTATE RESERVES", "STRATEGIC DECISION", {"right_separation": 8})
	var rv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var av: VBoxContainer = ui["right"]

	var assets_data := [
		{"name": "황실 금화", "val": "%d G" % GameState.gold, "icon": "🪙", "col": UiKit.GOLD},
		{"name": "비전 마나석", "val": "%d 개" % GameState.manastone, "icon": "💎", "col": UiKit.BLUE},
		{"name": "제련 철광석", "val": "%d 개" % GameState.iron_ore, "icon": "⛏️", "col": Color("a0b2c6")},
		{"name": "고용 용병단", "val": "%d 명" % GameState.roster.size(), "icon": "🛡️", "col": UiKit.WHITE},
	]

	for ad in assets_data:
		var acard := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 6)
		var ah := HBoxContainer.new()
		ah.add_theme_constant_override("separation", 8)
		acard.add_child(ah)
		ah.add_child(UiKit.label(ad.icon, 18, ad.col))
		var aiv := VBoxContainer.new()
		aiv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		aiv.add_theme_constant_override("separation", 1)
		aiv.add_child(UiKit.label(ad.name, 11, UiKit.TEXT2))
		aiv.add_child(UiKit.title(ad.val, 13, ad.col))
		ah.add_child(aiv)
		rv.add_child(acard)

	center_col.add_child(build_center_interior(320.0))

	var dv := UiKit.modal_summary_card(center_col, "📊 영지 물류 및 위기 지표 (창고 Lv.%d)" % GameState.building_level("창고"))
	dv.add_child(UiKit.label("• 영지 민심 (%d / 100)" % GameState.morale, 11, UiKit.GOLD))
	dv.add_child(UiKit.progress(GameState.morale, 100, UiKit.GOLD, 8))
	dv.add_child(UiKit.label("• 영지 스트레스 (%d / 100 — 상태: %s)" % [GameState.total_stress(), GameState.stress_stage()], 11, GameState.stress_color()))
	dv.add_child(UiKit.progress(GameState.total_stress(), 100, GameState.stress_color(), 8))

	for cmd in EstateCommand.catalog("warehouse"):
		var ccard := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
		var ccv := VBoxContainer.new()
		ccv.add_theme_constant_override("separation", 4)
		ccard.add_child(ccv)
		ccv.add_child(UiKit.title(cmd.title, 13, UiKit.GOLD2))
		ccv.add_child(UiKit.label(cmd.desc, 10, UiKit.TEXT2))
		var b := UiKit.gothic_button("집행 (%s)" % cmd.cost_text(), UiKit.GOLD if cmd.can_execute() else UiKit.BORDER)
		b.custom_minimum_size = Vector2(0, 36)
		b.disabled = not cmd.can_execute()
		var c_ref: EstateCommand = cmd
		b.pressed.connect(func(): run_command(c_ref))
		ccv.add_child(b)
		av.add_child(ccard)
