class_name LodgePopup
extends BaseBuildingPopup
## 영웅숙소 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var ui := UiKit.three_column_modal(vbox, "원정 파티 (%d / %d)" % [GameState.party.size(), GameState.MAX_PARTY], "STANDBY ROSTER", {"right_separation": 8})
	var pv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var rv: VBoxContainer = ui["right"]

	# 던전 입장 전 화면과 동일한 진형 규칙(열당 3명)을 숙소에서도 미리 보여주는 열별 인원 요약
	var row_parts: PackedStringArray = []
	for r in Mercenary.ROW_NAMES.size():
		row_parts.append("%s %d/%d" % [Mercenary.ROW_NAMES[r], GameState.party_row_count(r), Mercenary.ROW_SLOTS])
	pv.add_child(UiKit.label("진형: " + "  ·  ".join(row_parts), 11, UiKit.GOLD2))

	pv.add_child(UiKit.merc_roster_list(GameState.party, {
		"empty_text": "원정 파티가 비어 있습니다.\n우측 대기 로스터에서 영웅을 편성하세요.",
		"card_opts_fn": func(m: Mercenary, idx: int) -> Dictionary:
			return {
				"border_color": UiKit.BORDER2,
				"portrait_size": 36,
				"title_prefix": "[%s] " % Mercenary.ROW_NAMES[m.row],
				"color_name_by_grade": true,
				"action_text": "제외",
				"action_color": UiKit.RED,
				"action_min_size": Vector2(44, 28),
				"on_action": func(target: Mercenary):
					GameState.remove_from_party(target)
					rebuild(),
			},
	}))

	center_col.add_child(build_center_interior(320.0))

	var feast_cmd: EstateCommand = EstateCommand.catalog("lodge")[0]
	var fv := UiKit.modal_summary_card(center_col, "🍲 숙소 연회 및 안식", {"separation": 8})
	fv.add_child(UiKit.label("• 대기 중인 모든 영웅의 체력을 100% 완치하고 휴식을 취합니다.", 11, UiKit.TEXT2))
	fv.add_child(UiKit.label("• 비용: %s" % feast_cmd.cost_text(), 11, UiKit.GOLD2))

	var btn_feast := UiKit.gothic_button("🍲 숙소 특식 배급 및 전원 완치", UiKit.GREEN)
	btn_feast.custom_minimum_size = Vector2(0, 38)
	btn_feast.disabled = not feast_cmd.can_execute() or GameState.roster.is_empty()
	btn_feast.pressed.connect(func(): run_command(feast_cmd))
	fv.add_child(btn_feast)

	var available_mercs := GameState.available_mercs()
	rv.add_child(UiKit.merc_roster_list(available_mercs, {
		"empty_text": "대기 중인 다른 영웅이 없습니다.",
		# 용병은 자신의 열에만 편성 가능하므로 열 이름을 표시하고, 해당 열이 가득 차면 버튼을 비활성화한다
		"card_opts_fn": func(m: Mercenary, _idx: int) -> Dictionary:
			var row_full := GameState.party_row_count(m.row) >= Mercenary.ROW_SLOTS
			return {
				"portrait_size": 38,
				"color_name_by_grade": true,
				"title_prefix": "[%s] " % Mercenary.ROW_NAMES[m.row],
				"action_text": "열 가득" if row_full else "편성",
				"action_color": UiKit.GOLD,
				"action_disabled": GameState.party.size() >= GameState.MAX_PARTY or row_full,
				"action_min_size": Vector2(50, 32),
				"on_action": func(target: Mercenary):
					GameState.add_to_party(target)
					rebuild(),
			},
	}))
