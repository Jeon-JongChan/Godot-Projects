class_name ManorPopup
extends BaseBuildingPopup
## 영주저택 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var ui := UiKit.three_column_modal(vbox, "LORD'S DECREES", "FACILITY UPGRADE (10대 시설 총람)", {"right_width": 330, "right_title_size": 14, "right_separation": 8})
	var dv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var uv: VBoxContainer = ui["right"]

	dv.add_child(UiKit.label("영주 주권 칙령 집행 (행동력 소비)", 10, UiKit.TEXT2))

	for cmd in EstateCommand.catalog("manor"):
		var cbox := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 6)
		var cbv := VBoxContainer.new()
		cbv.add_theme_constant_override("separation", 4)
		cbox.add_child(cbv)
		cbv.add_child(UiKit.title(cmd.title, 12, UiKit.GOLD2))
		cbv.add_child(UiKit.label(cmd.desc, 10, UiKit.TEXT2))
		var b := UiKit.button("집행 (%s)" % cmd.cost_text(), UiKit.GOLD)
		b.custom_minimum_size = Vector2(0, 30)
		b.disabled = not cmd.can_execute()
		var c_ref: EstateCommand = cmd
		b.pressed.connect(func(): run_command(c_ref))
		cbv.add_child(b)
		dv.add_child(cbox)

	center_col.add_child(build_center_interior(320.0))

	var sv := UiKit.modal_summary_card(center_col, "👑 영지 주권 및 발전 현황")
	sv.add_child(UiKit.label("• 영주저택 등급: Lv.%d / 5   ·   영지 민심: %d%%   ·   누적 스트레스: %d" % [
		GameState.building_level("영주저택"), GameState.morale, GameState.total_stress()
	], 11, UiKit.WHITE))
	sv.add_child(UiKit.label("💡 영지 내 모든 건물의 시설 증축은 오직 이곳 영주저택에서 총괄 인가됩니다.", 11, UiKit.GOLD2))
	sv.add_child(UiKit.label("우측의 [영지 10대 시설 증축 총람]에서 증축할 건물을 선택하여 승급을 진행하세요.", 10, UiKit.TEXT2))

	var up_scroll := ScrollContainer.new()
	up_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	uv.add_child(up_scroll)

	var up_list := VBoxContainer.new()
	up_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_list.add_theme_constant_override("separation", 6)
	up_scroll.add_child(up_list)

	for bdef in BuildingDb.DEFS:
		if bdef.id == "dungeon_gate":
			continue
		var bn: String = bdef.name
		var blv: int = GameState.building_level(bn)
		var b_card := UiKit.panel(UiKit.BG3, UiKit.BORDER, 6)
		var bh := HBoxContainer.new()
		bh.add_theme_constant_override("separation", 8)
		b_card.add_child(bh)

		bh.add_child(UiKit.label(bdef.icon, 18, UiKit.WHITE))
		var biv := VBoxContainer.new()
		biv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		biv.add_theme_constant_override("separation", 1)
		biv.add_child(UiKit.label("%s (Lv.%d)" % [bn, blv], 12, UiKit.WHITE))
		biv.add_child(UiKit.label(bdef.tag, 10, UiKit.TEXT2))
		bh.add_child(biv)

		if blv >= 5:
			bh.add_child(UiKit.chip("MAX", UiKit.GOLD))
		else:
			var c := GameState.upgrade_cost(bn)
			var can_up := GameState.can_upgrade(bn)
			var up_btn := UiKit.button("증축 (%dG)" % c.gold, UiKit.GOLD if can_up else UiKit.BORDER)
			up_btn.disabled = not can_up
			up_btn.pressed.connect(func():
				if GameState.upgrade_building(bn):
					notice = "%s 시설을 Lv.%d(으)로 증축 완료했습니다!" % [bn, blv + 1]
					estate.village.rebuild()
					var sm = estate.get_node_or_null("/root/SaveManager")
					if sm != null and sm.has_method("auto_save"):
						sm.auto_save()
					rebuild()
			)
			bh.add_child(up_btn)
		up_list.add_child(b_card)
