class_name TrainingPopup
extends BaseBuildingPopup
## 훈련소 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

var _selected_training_merc: Mercenary = null


## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var ready_mercs: Array[Mercenary] = []
	for m in GameState.roster:
		if m.status == Mercenary.Status.READY:
			ready_mercs.append(m)

	if _selected_training_merc == null or not (_selected_training_merc in ready_mercs):
		_selected_training_merc = ready_mercs[0] if not ready_mercs.is_empty() else null

	var target_m: Mercenary = _selected_training_merc
	var tr_lv: int = GameState.building_level("훈련장")
	var tg := EstateCommand.training_gains(tr_lv)
	var hp_gain: int = int(tg["hp"])
	var atk_gain: int = int(tg["atk"])

	var ui := UiKit.three_column_modal(vbox, "TRAINEE ROSTER", "TACTICAL DRILL")
	var rv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	rv.add_child(UiKit.merc_roster_list(ready_mercs, {
		"empty_text": "훈련 가능한 대기 영웅이 없습니다.",
		"selected_merc": target_m,
		"card_opts_fn": func(m: Mercenary, _idx: int) -> Dictionary:
			var is_sel := (m == target_m)
			return {
				"selected": is_sel,
				"bg_color": Color("221e16") if is_sel else UiKit.BG3,
				"portrait_size": 38,
				"grade_in_title": false,
				"subtitle_mode": "job_only",
			},
		"on_click": func(cur_m: Mercenary):
			_selected_training_merc = cur_m
			rebuild(),
	}))

	center_col.add_child(build_center_interior(320.0))

	var regv := UiKit.modal_summary_card(center_col, "🎯 전술 연병장 수련 성과 지표 (Lv.%d)" % tr_lv)
	regv.add_child(UiKit.label("• 실전 모의 훈련 1회당: 레벨 +1 상승, 최대 체력 +%d, 공격력 +%d 성장!" % [hp_gain, atk_gain], 11, UiKit.GREEN))
	regv.add_child(UiKit.label("• 영웅의 기본 전투 기량을 높여 고난도 던전의 강력한 몬스터를 제압할 수 있습니다.", 11, UiKit.TEXT2))

	if target_m != null:
		var train_cmd := EstateCommand.for_merc("train", target_m)
		iv.add_child(UiKit.title("수련 대상: %s (%s)" % [target_m.merc_name, target_m.job], 14, UiKit.WHITE))
		iv.add_child(UiKit.label("현재 레벨: Lv.%d  →  수련 후: Lv.%d" % [target_m.level, target_m.level + 1], 12, UiKit.GOLD2))
		iv.add_child(UiKit.label("체력 성장: %d  →  %d (+%d)" % [target_m.max_hp, target_m.max_hp + hp_gain, hp_gain], 11, UiKit.TEXT2))
		iv.add_child(UiKit.label("공격력: %d  →  %d (+%d)" % [target_m.attack, target_m.attack + atk_gain, atk_gain], 11, UiKit.TEXT2))

		iv.add_child(UiKit.divider())
		iv.add_child(UiKit.label("REQUIRED RESOURCES:", 11, UiKit.GOLD))
		iv.add_child(UiKit.label("소모 비용: %s" % train_cmd.cost_text(), 12, UiKit.WHITE))

		var can_train := train_cmd.can_execute()
		if not can_train:
			iv.add_child(UiKit.label("⚠ 훈련 비용 또는 행동력이 부족합니다!", 11, UiKit.RED))

		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		iv.add_child(sp)

		var btn_train := UiKit.gothic_button("🎯 실전 모의 훈련 개시", UiKit.GREEN if can_train else UiKit.BORDER)
		btn_train.custom_minimum_size = Vector2(0, 44)
		btn_train.disabled = not can_train
		btn_train.pressed.connect(func(): run_command(train_cmd))
		iv.add_child(btn_train)
	else:
		iv.add_child(UiKit.label("훈련할 대상을 선택하세요.", 12, UiKit.TEXT2))
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		iv.add_child(sp)
