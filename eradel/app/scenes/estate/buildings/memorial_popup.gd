class_name MemorialPopup
extends BaseBuildingPopup
## 위령비 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var honor_cmd: EstateCommand = EstateCommand.catalog("memorial")[0]
	var ui := UiKit.three_column_modal(vbox, "FALLEN HEROES (%d위)" % GameState.death_log.size(), "MEMORIAL RITE")
	var rv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if GameState.death_log.is_empty():
		list.add_child(UiKit.label("✨ 희생된 영웅이 없습니다.\n모든 원정대가 무사 귀환했습니다.", 11, UiKit.GREEN))
	else:
		for rec in GameState.death_log:
			var row := UiKit.panel(UiKit.BG3, UiKit.RED, 6)
			var rh := HBoxContainer.new()
			row.add_child(rh)
			var state_str := "실종" if rec.get("missing", false) else "전사"
			rh.add_child(UiKit.label("✝ %s (%s Lv.%d · %s)" % [
				rec.get("name", "무명 용병"), rec.get("job", "전사"), int(rec.get("level", 1)), state_str
			], 11, UiKit.TEXT))
			list.add_child(row)

	center_col.add_child(build_center_interior(320.0))

	var mv := UiKit.modal_summary_card(center_col, "🏛️ 전사자 위령비와 안식의 묘비")
	mv.add_child(UiKit.label("• 던전의 심연에서 스러져간 동료들의 넋을 기리고 추모하는 장소입니다.", 11, UiKit.TEXT2))
	mv.add_child(UiKit.label("• 위령비에 헌화하면 영지민의 슬픔을 달래어 스트레스가 정화됩니다.", 11, UiKit.BLUE.lightened(0.3)))

	iv.add_child(UiKit.title(honor_cmd.title, 14, UiKit.BLUE.lightened(0.3)))
	iv.add_child(UiKit.label(honor_cmd.desc, 12, UiKit.TEXT2))

	iv.add_child(UiKit.divider())
	iv.add_child(UiKit.label("소모 비용: %s" % honor_cmd.cost_text(), 12, UiKit.WHITE))
	iv.add_child(UiKit.label("보유 골드: %d G" % GameState.gold, 12, UiKit.GOLD))

	var can_honor := honor_cmd.can_execute()
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(sp)

	var btn_honor := UiKit.gothic_button("✝ 헌화 의식 거행", UiKit.BLUE if can_honor else UiKit.BORDER)
	btn_honor.custom_minimum_size = Vector2(0, 44)
	btn_honor.disabled = not can_honor
	btn_honor.pressed.connect(func(): run_command(honor_cmd))
	iv.add_child(btn_honor)
