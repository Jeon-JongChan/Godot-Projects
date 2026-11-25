class_name DungeonPopup
extends BaseBuildingPopup
## 어둠의 균열(던전 입구) 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var ui := UiKit.three_column_modal(vbox, "EXPEDITION PARTY (%d/5)" % GameState.party.size(), "ABYSS EXPEDITION")
	var pv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	pv.add_child(UiKit.merc_roster_list(GameState.party, {
		"empty_text": "출진 파티가 비어 있습니다!\n영웅숙소에서 원정대를 편성하세요.",
		"empty_color": UiKit.RED,
		"card_opts_fn": func(m: Mercenary, _idx: int) -> Dictionary:
			return {
				"border_color": UiKit.BORDER2,
				"portrait_size": 36,
				"title_prefix": "[%s] " % Mercenary.ROW_NAMES[m.row],
				"color_name_by_grade": true,
			},
	}))

	center_col.add_child(build_center_interior(320.0))

	var rv := UiKit.modal_summary_card(center_col, "⚠ 차원 균열 침식 경보", {"title_color": UiKit.RED})
	rv.add_child(UiKit.label("• 균열 활성도: %d%%  ·  몬스터 위협 티어: +%d단계" % [GameState.dungeon_activity, GameState.monster_tier], 11, UiKit.TEXT))
	if GameState.endless_cycle > 0 or GameState.boss_sealed_count > 0:
		rv.add_child(UiKit.label("• 심연 엔드리스: +%d사이클 (몬스터 ×%.1f) · 누적 봉인 %d회" % [
			GameState.endless_cycle, GameState.endless_monster_mult(), GameState.boss_sealed_count
		], 11, UiKit.GOLD2))
	rv.add_child(UiKit.progress(GameState.dungeon_activity, 100, UiKit.RED if GameState.dungeon_activity >= 60 else UiKit.GOLD, 8))
	rv.add_child(UiKit.label("• 심연 진입 시 몬스터와의 치열한 턴제 전투가 벌어집니다. 철저한 준비 후 출진하세요.", 10, UiKit.TEXT2))

	iv.add_child(UiKit.label("편성 인원: %d / %d명" % [GameState.party.size(), GameState.MAX_PARTY], 13, UiKit.WHITE))
	var can_launch := not GameState.party.is_empty()
	if not can_launch:
		iv.add_child(UiKit.label("⚠ 최소 1명 이상의 영웅을 파티에 편성해야 출진할 수 있습니다.", 11, UiKit.RED))
	else:
		iv.add_child(UiKit.label("✅ 원정대가 출진 준비를 마쳤습니다.", 11, UiKit.GREEN))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(sp)

	# 편성 부족·배치 미확인 오출진 방지를 위해 항상 원정 준비 화면(expedition_prep)을 경유해 출진한다.
	iv.add_child(UiKit.label("※ 출진 전 편성 인원과 전열·중열·후열 배치를 원정 준비 화면에서 확인하세요.", 10, UiKit.TEXT2))

	var btn_prep := UiKit.gothic_button("⚔️ 원정 준비 화면으로 이동 ↗", UiKit.GOLD)
	btn_prep.custom_minimum_size = Vector2(0, 48)
	btn_prep.focus_mode = Control.FOCUS_ALL
	btn_prep.pressed.connect(func():
		estate.get_tree().change_scene_to_file(GameState.SCENE_PREP)
	)
	iv.add_child(btn_prep)
