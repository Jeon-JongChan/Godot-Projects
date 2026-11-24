class_name StorePopup
extends BaseBuildingPopup
## 잡화점 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

var _selected_store_cmd_id: String = "potion"


## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var store_cmds := EstateCommand.catalog("store")
	var sel_cmd: EstateCommand = store_cmds[0]
	for cmd in store_cmds:
		if cmd.id == _selected_store_cmd_id:
			sel_cmd = cmd
			break

	var ui := UiKit.three_column_modal(vbox, "SUPPLY CATALOG", "ITEM DETAILS")
	var cv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	for cmd in store_cmds:
		var is_sel: bool = (cmd.id == sel_cmd.id)
		var item_card := UiKit.panel(Color("231f18") if is_sel else UiKit.BG3, UiKit.GOLD if is_sel else UiKit.BORDER, 6)
		item_card.mouse_filter = Control.MOUSE_FILTER_PASS
		var ih := HBoxContainer.new()
		ih.add_theme_constant_override("separation", 8)
		item_card.add_child(ih)

		var item_v := VBoxContainer.new()
		item_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_v.add_theme_constant_override("separation", 2)
		item_v.add_child(UiKit.label(cmd.title, 12, UiKit.GOLD if is_sel else UiKit.WHITE))
		item_v.add_child(UiKit.label(cmd.cost_text(), 10, UiKit.GOLD2))
		ih.add_child(item_v)

		var cur_id: String = cmd.id
		item_card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_selected_store_cmd_id = cur_id
				rebuild()
		)
		cv.add_child(item_card)

	center_col.add_child(build_center_interior(320.0))

	var store_lv: int = GameState.building_level("잡화점")
	var discount_pct: int = (store_lv - 1) * 10
	var sv := UiKit.modal_summary_card(center_col, "⚖️ 만물상 할인 혜택 및 원정 보급 가이드")
	sv.add_child(UiKit.label("• 잡화점 Lv.%d 특권: 전 품목 %d%% 할인 적용 중!" % [store_lv, discount_pct], 11, UiKit.GREEN))
	sv.add_child(UiKit.label("• 치유 비약과 정찰 두루마리는 원정대의 체력과 던전 활성도를 즉시 관리하는 핵심 자산입니다.", 11, UiKit.TEXT2))
	sv.add_child(UiKit.label("• 고순도 마나석은 비전 연구 및 장비 인챈트에 필수적이므로 미리 비축을 권장합니다.", 10, UiKit.TEXT2))

	iv.add_child(UiKit.title(sel_cmd.title, 14, UiKit.GOLD2))
	iv.add_child(UiKit.label(sel_cmd.desc, 12, UiKit.TEXT2))

	iv.add_child(UiKit.divider())
	iv.add_child(UiKit.label("PURCHASE PRICE:", 11, UiKit.GOLD))
	iv.add_child(UiKit.label("가격: %s (잡화점 Lv.%d %d%% 할인 반영)" % [sel_cmd.cost_text(), store_lv, discount_pct], 12, UiKit.WHITE))
	iv.add_child(UiKit.label("보유 골드: %d G" % GameState.gold, 12, UiKit.GOLD))

	var can_buy := sel_cmd.can_execute()
	if not can_buy:
		iv.add_child(UiKit.label("⚠ 구매 자원이 부족합니다!", 11, UiKit.RED))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(sp)

	var btn_buy := UiKit.gothic_button("🛒 물품 구입 및 사용", UiKit.GOLD if can_buy else UiKit.BORDER)
	btn_buy.custom_minimum_size = Vector2(0, 44)
	btn_buy.disabled = not can_buy
	var c_ref: EstateCommand = sel_cmd
	btn_buy.pressed.connect(func(): run_command(c_ref))
	iv.add_child(btn_buy)
