class_name BlacksmithPopup
extends BaseBuildingPopup
## 대장간 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

var _selected_forge_merc: Mercenary = null
var _selected_forge_slot: String = "weapon"


## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	# 대기 중인 유효 용병 목록 확인
	var available_mercs: Array[Mercenary] = []
	for m in GameState.roster:
		if m.status == Mercenary.Status.READY:
			available_mercs.append(m)

	# 기본 선택 용병 유효성 검사
	if _selected_forge_merc == null or not (_selected_forge_merc in available_mercs):
		_selected_forge_merc = available_mercs[0] if not available_mercs.is_empty() else null

	var target_m: Mercenary = _selected_forge_merc

	# ─────────────────────────────────────────────────────────
	# [상단 헤더]: < BACK TO TOWN  |  [골드] GOLD   [루비] RUBIES   [철광석] ORE
	# ─────────────────────────────────────────────────────────
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 16)
	top_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(top_h)

	var btn_back := UiKit.gothic_button("◀  BACK TO TOWN", UiKit.GOLD)
	btn_back.custom_minimum_size = Vector2(170, 36)
	btn_back.pressed.connect(func():
		estate._zoom_out_and_return()
	)
	top_h.add_child(btn_back)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(top_spacer)

	# 실시간 자원 HUD (도트 아이콘 적용)
	var res_card := UiKit.panel(Color("161214"), UiKit.BORDER2, 6)
	var res_h := HBoxContainer.new()
	res_h.add_theme_constant_override("separation", 14)
	res_card.add_child(res_h)

	var g_box := HBoxContainer.new()
	g_box.add_theme_constant_override("separation", 5)
	g_box.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_gold.png", 18))
	g_box.add_child(UiKit.label("%d GOLD" % GameState.gold, 13, UiKit.GOLD))
	res_h.add_child(g_box)

	var r_box := HBoxContainer.new()
	r_box.add_theme_constant_override("separation", 5)
	r_box.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ruby.png", 18))
	r_box.add_child(UiKit.label("%d RUBIES" % GameState.manastone, 13, Color("ff3b56")))
	res_h.add_child(r_box)

	var o_box := HBoxContainer.new()
	o_box.add_theme_constant_override("separation", 5)
	o_box.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ore.png", 18))
	o_box.add_child(UiKit.label("%d ORE" % GameState.iron_ore, 13, Color("a0b2c6")))
	res_h.add_child(o_box)
	top_h.add_child(res_card)

	# ─────────────────────────────────────────────────────────
	# [메인 본문]: 3단 고딕 스캐폴드 + 좌측 영웅 로스터 + 중앙 대장간/장비 + 우측 UPGRADE INFO
	# ─────────────────────────────────────────────────────────
	var ui := UiKit.three_column_modal(vbox, "HERO ROSTER (%d)" % available_mercs.size(), "UPGRADE INFO", {
		"left_width": 250,
		"right_width": 290,
		"col_separation": 14,
		"center_separation": 8,
	})
	var r_cv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	r_cv.add_child(UiKit.merc_roster_list(available_mercs, {
		"empty_text": "대기 중인 영웅이 없습니다.",
		"selected_merc": _selected_forge_merc,
		"card_opts_fn": func(m: Mercenary, _idx: int) -> Dictionary:
			var is_sel := (m == _selected_forge_merc)
			return {
				"selected": is_sel,
				"selected_border": Color("f6d355"),
				"bg_color": Color("2a2016") if is_sel else Color("141116"),
				"portrait_size": 44,
				"grade_in_title": false,
				"subtitle_mode": "level_job",
				"show_hp_bar": true,
			},
		"on_click": func(cur_m: Mercenary):
			if _selected_forge_merc != cur_m:
				_selected_forge_merc = cur_m
				_selected_forge_slot = "weapon" # 캐릭터 변경 시 강화부위 기본값 초기화
			rebuild(),
	}))

	# 2-A. 드워프 모루/화덕 캔버스 (상단 약 340px)
	var forge_holder := Control.new()
	forge_holder.custom_minimum_size = Vector2(0, 340)
	forge_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_col.add_child(forge_holder)

	var forge_interior := VillageVisuals.BlacksmithInteriorCanvas.new()
	forge_interior.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_holder.add_child(forge_interior)
	estate._active_blacksmith_canvas = forge_interior

	# 2-B. 중앙 하단 4칸 장비 슬롯 (WEAPON, ARMOR, HELMET, ACCESSORY)
	var eq_card := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 8)
	eq_card.custom_minimum_size = Vector2(0, 110)
	center_col.add_child(eq_card)

	var eq_h := HBoxContainer.new()
	eq_h.alignment = BoxContainer.ALIGNMENT_CENTER
	eq_h.add_theme_constant_override("separation", 24)
	eq_card.add_child(eq_h)

	var slots_data := [
		{"id": "weapon", "label": "WEAPON", "level": target_m.weapon_level if target_m else 1},
		{"id": "armor", "label": "ARMOR", "level": target_m.armor_level if target_m else 1},
		{"id": "helmet", "label": "HELMET", "level": target_m.helmet_level if target_m else 1},
		{"id": "accessory", "label": "ACCESSORY", "level": target_m.ring_level if target_m else 1}
	]

	for s_info in slots_data:
		var sid: String = s_info.id
		var is_s_sel: bool = (_selected_forge_slot == sid or (_selected_forge_slot == "ring" and sid == "accessory"))
		var s_box := VBoxContainer.new()
		s_box.alignment = BoxContainer.ALIGNMENT_CENTER
		s_box.custom_minimum_size = Vector2(76, 94)
		s_box.add_theme_constant_override("separation", 4)
		s_box.mouse_filter = Control.MOUSE_FILTER_STOP
		s_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# 상단 슬롯 레이블
		var top_lbl := UiKit.label(s_info.label, 10, UiKit.GOLD if is_s_sel else UiKit.TEXT2)
		top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s_box.add_child(top_lbl)

		# 아이콘 캔버스 (내부 마우스 이벤트 무시 -> 부모 슬롯 카드가 이미지 영역 클릭을 직접 수신)
		var icon_cv := VillageVisuals.EquipmentIconCanvas.new()
		icon_cv.slot_type = sid
		icon_cv.item_level = int(s_info.level)
		icon_cv.is_selected = is_s_sel
		icon_cv.custom_minimum_size = Vector2(58, 58)
		icon_cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s_box.add_child(icon_cv)

		# 하단 레벨 레이블
		var lv_lbl := UiKit.label("+%d강" % int(s_info.level), 11, UiKit.GOLD2 if is_s_sel else UiKit.WHITE)
		lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s_box.add_child(lv_lbl)

		# 이미지 포함 슬롯 전체 영역 클릭 시 장비 슬롯 전환
		var clicked_sid: String = sid
		s_box.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_selected_forge_slot = clicked_sid
				rebuild()
		)
		eq_h.add_child(s_box)

	if target_m != null:
		var spec := EstateCommand.forge_slot_spec(target_m, _selected_forge_slot)
		var cur_slot_lv: int = int(spec["cur_lv"])
		var next_slot_lv: int = int(spec["next_lv"])
		var slot_kr_name: String = str(spec["slot_name"])
		iv.add_child(UiKit.label("대상: %s (+%d → +%d강)" % [slot_kr_name, cur_slot_lv, next_slot_lv], 13, UiKit.WHITE))

		var success_rate: int = int(spec["success_rate"])
		iv.add_child(UiKit.label("SUCCESS RATE: %d%%" % success_rate, 12, UiKit.GREEN))
		iv.add_child(UiKit.progress(success_rate, 100, UiKit.GREEN, 8))

		iv.add_child(UiKit.divider())
		iv.add_child(UiKit.label("REQUIRED MATERIALS:", 11, UiKit.GOLD))

		var req_ore: int = int(spec["req_ore"])
		var req_mana: int = int(spec["req_mana"])
		var req_gold: int = int(spec["req_gold"])
		var has_ore: bool = bool(spec["has_ore"])
		var has_mana: bool = bool(spec["has_mana"])
		var has_gold: bool = bool(spec["has_gold"])
		var can_forge: bool = bool(spec["can_forge"])

		# 1. 철광석 행 (도트 아이콘 + 부족 시 빨간색 글씨)
		var ore_c := UiKit.WHITE if has_ore else UiKit.RED
		var ore_txt := "IRON ORE  x%d  (보유: %d)" % [req_ore, GameState.iron_ore]
		if not has_ore:
			ore_txt += " [부족!]"
		var ore_row := HBoxContainer.new()
		ore_row.add_theme_constant_override("separation", 6)
		ore_row.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ore.png", 16))
		ore_row.add_child(UiKit.label(ore_txt, 12, ore_c))
		iv.add_child(ore_row)

		# 2. 마나석 행 (부족 시 빨간색 글씨)
		if req_mana > 0:
			var mana_c := UiKit.WHITE if has_mana else UiKit.RED
			var mana_txt := "MAGIC DUST  x%d  (보유: %d)" % [req_mana, GameState.manastone]
			if not has_mana:
				mana_txt += " [부족!]"
			var mana_row := HBoxContainer.new()
			mana_row.add_theme_constant_override("separation", 6)
			mana_row.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_ruby.png", 16))
			mana_row.add_child(UiKit.label(mana_txt, 12, mana_c))
			iv.add_child(mana_row)

		# 3. 골드 행 (부족 시 빨간색 글씨)
		var gold_c := UiKit.GOLD2 if has_gold else UiKit.RED
		var gold_txt := "%d GOLD  (보유: %d)" % [req_gold, GameState.gold]
		if not has_gold:
			gold_txt += " [부족!]"
		var gold_row := HBoxContainer.new()
		gold_row.add_theme_constant_override("separation", 6)
		gold_row.add_child(UiKit.icon_rect("res://assets/sprites/ui/icon_gold.png", 16))
		gold_row.add_child(UiKit.label(gold_txt, 12, gold_c))
		iv.add_child(gold_row)

		var iv_spacer := Control.new()
		iv_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		iv.add_child(iv_spacer)

		# 대형 황금 [ FORGE UPGRADE ] 버튼
		var btn_forge := UiKit.gothic_button("⚒️  FORGE UPGRADE", UiKit.GOLD)
		btn_forge.custom_minimum_size = Vector2(0, 52)
		btn_forge.disabled = not can_forge

		btn_forge.pressed.connect(func():
			if not can_forge:
				return
			if not GameState.spend_forge(req_gold, req_ore, req_mana):
				return

			btn_forge.disabled = true
			forge_interior.current_state = VillageVisuals.BlacksmithInteriorCanvas.DwarfState.HAMMERING

			var is_success := (GameState.rng().randi_range(1, 100) <= success_rate)

			# 4번의 모루질과 화면 전체 플래시 빛 연출 (타격 간격 0.35초)
			var tw := estate.create_tween()
			for strike in range(4):
				tw.tween_callback(func():
					forge_interior.trigger_hammer_strike()
				)
				tw.tween_interval(0.35)

			# 4회 타격 종료 후 결과 연출 및 데이터 반영
			tw.chain().tween_callback(func():
				if is_success:
					var forged := EstateCommand.apply_forge_stat_bonus(target_m, _selected_forge_slot)
					forge_interior.current_state = VillageVisuals.BlacksmithInteriorCanvas.DwarfState.SUCCESS
					notice = "✨ 강화 성공! [%s]의 %s가 +%d강이 되었습니다!" % [target_m.merc_name, str(forged.get("slot_name", slot_kr_name)), int(forged.get("new_lv", cur_slot_lv + 1))]
				else:
					forge_interior.current_state = VillageVisuals.BlacksmithInteriorCanvas.DwarfState.FAIL
					notice = "💨 강화 실패... 아쉽게도 이번 제련은 성공하지 못했습니다."

				GameState.roster_changed.emit()

				# 기획서 규칙: 강화 버튼 클릭 시 자동 저장
				var sm = estate.get_node_or_null("/root/SaveManager")
				if sm != null and sm.has_method("auto_save"):
					sm.auto_save()

				# 1.5초 후 대장간 팝업 UI 상태 갱신
				var reset_tw := estate.create_tween()
				reset_tw.tween_interval(1.5)
				reset_tw.tween_callback(func():
					rebuild()
				)
			)
		)
		iv.add_child(btn_forge)
	else:
		iv.add_child(UiKit.label("좌측 목록에서 강화를 진행할 영웅을 먼저 선택해 주세요.", 12, UiKit.TEXT2))
