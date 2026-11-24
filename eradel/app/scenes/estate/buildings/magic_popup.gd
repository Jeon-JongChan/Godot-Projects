class_name MagicPopup
extends BaseBuildingPopup
## 마법 연구소 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

var _selected_magic_cmd_id: String = "suppress"


## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var mg_cmds := EstateCommand.catalog("magic")
	var sel_cmd: EstateCommand = mg_cmds[0]
	for cmd in mg_cmds:
		if cmd.id == _selected_magic_cmd_id:
			sel_cmd = cmd
			break

	var ui := UiKit.three_column_modal(vbox, "ARCANE RESEARCH", "RESEARCH DETAILS")
	var rv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	for cmd in mg_cmds:
		var is_sel: bool = (cmd.id == sel_cmd.id)
		var ccard := UiKit.panel(Color("221a28") if is_sel else UiKit.BG3, UiKit.PURPLE if is_sel else UiKit.BORDER, 6)
		ccard.mouse_filter = Control.MOUSE_FILTER_PASS
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 8)
		ccard.add_child(ch)

		var civ := VBoxContainer.new()
		civ.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		civ.add_theme_constant_override("separation", 2)
		civ.add_child(UiKit.label(cmd.title, 12, UiKit.PURPLE.lightened(0.3) if is_sel else UiKit.WHITE))
		civ.add_child(UiKit.label(cmd.cost_text(), 10, UiKit.GOLD2))
		ch.add_child(civ)

		var cur_id: String = cmd.id
		ccard.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_selected_magic_cmd_id = cur_id
				rebuild()
		)
		rv.add_child(ccard)

	center_col.add_child(build_center_interior(320.0))

	var sv := UiKit.modal_summary_card(center_col, "🔮 차원 균열 제어 및 마나 연구실 (Lv.%d)" % GameState.building_level("마법사학회"))
	sv.add_child(UiKit.label("• 현재 던전 균열 활성도: %d%%  (몬스터 강화 +%d단계)" % [GameState.dungeon_activity, GameState.monster_tier], 11, UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GOLD))
	sv.add_child(UiKit.progress(GameState.dungeon_activity, 100, UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.PURPLE, 8))
	sv.add_child(UiKit.label("• 현재 비축 마나석: %d개  (마나 결정을 통해 장비 인챈트 및 고대 봉인 해제 가능)" % GameState.manastone, 11, UiKit.BLUE.lightened(0.3)))

	iv.add_child(UiKit.title(sel_cmd.title, 14, UiKit.PURPLE.lightened(0.35)))
	iv.add_child(UiKit.label(sel_cmd.desc, 12, UiKit.TEXT2))

	iv.add_child(UiKit.divider())
	iv.add_child(UiKit.label("RESEARCH COST:", 11, UiKit.GOLD))
	iv.add_child(UiKit.label("소모 자원: %s" % sel_cmd.cost_text(), 12, UiKit.WHITE))
	iv.add_child(UiKit.label("보유 골드: %d G  |  보유 마나석: %d개" % [GameState.gold, GameState.manastone], 11, UiKit.TEXT2))

	var can_exec := sel_cmd.can_execute()
	if not can_exec:
		iv.add_child(UiKit.label("⚠ 연구에 필요한 자원이 부족합니다!", 11, UiKit.RED))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(sp)

	var btn_exec := UiKit.gothic_button("🔮 비전 연구 및 연성 집행", UiKit.PURPLE if can_exec else UiKit.BORDER)
	btn_exec.custom_minimum_size = Vector2(0, 44)
	btn_exec.disabled = not can_exec
	var c_ref: EstateCommand = sel_cmd
	btn_exec.pressed.connect(func(): run_command(c_ref))
	iv.add_child(btn_exec)
