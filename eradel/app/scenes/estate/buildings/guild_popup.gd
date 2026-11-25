class_name GuildPopup
extends BaseBuildingPopup
## 용병모집소 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

var _selected_guild_grade: String = "일반"


## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var ui := UiKit.three_column_modal(vbox, "영지 용병단 (%d명)" % GameState.roster.size(), "RECRUITMENT SEAL")
	var rv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	rv.add_child(UiKit.merc_roster_list(GameState.roster, {
		"empty_text": "현재 고용된 용병이 없습니다.\n우측 봉인서로 모험가를 영입하세요.",
		"card_opts_fn": func(m: Mercenary, _idx: int) -> Dictionary:
			var can_fire := (m.status == Mercenary.Status.READY)
			return {
				"bg_color": Color("141116"),
				"grade_in_title": false,
				"subtitle_mode": "job_level",
				"show_hp_bar": true,
				"action_text": "해고" if can_fire else "",
				"action_color": UiKit.RED,
				"action_min_size": Vector2(44, 28),
				"on_action": func(target: Mercenary):
					var has_pen := target.penalties.size() > 0
					var m_loss := (8 if GameState.brand_stacks >= 3 else 3) if has_pen else 0
					var warn_body := "대상: [%s] %s (%s Lv.%d)\n" % [target.grade, target.merc_name, target.job, target.level]
					if has_pen:
						if GameState.brand_stacks >= 3:
							warn_body += "부상 용병 유기: 민심 -8 (기본 -3 + 불신의 낙인 -5)\n예상 민심: %d%% → %d%%" % [GameState.morale, maxi(0, GameState.morale - m_loss)]
						else:
							warn_body += "부상 용병 유기: 민심 -3\n예상 민심: %d%% → %d%%" % [GameState.morale, maxi(0, GameState.morale - m_loss)]
					else:
						warn_body += "건강한 용병 해고: 민심 변동 없음"
					estate.open_confirm_modal("용병 해고 확인", warn_body, "해고 확정", UiKit.RED, func():
						if GameState.dismiss_merc(target):
							notice = "[%s] %s 용병을 해고했습니다.%s" % [target.grade, target.merc_name, " (부상 유기: 민심 -%d)" % m_loss if m_loss > 0 else ""]
							rebuild()
					),
			},
	}))

	center_col.add_child(build_center_interior(320.0))

	var sv := UiKit.modal_summary_card(center_col, "📜 영입 봉인서 선택 (클릭하여 영입 조건 확인)", {"title_size": 12})

	var seals_h := HBoxContainer.new()
	seals_h.add_theme_constant_override("separation", 10)
	seals_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(seals_h)

	var grade_info := [
		{"grade": "일반", "desc": "기본 전투원\n전사·레인저·마법사·성직자", "icon": "🛡️"},
		{"grade": "정예", "desc": "베테랑 모험가\n높은 초기 전투력과 생존력", "icon": "⚔️"},
		{"grade": "특수", "desc": "희귀 전설 전력\n압도적 고유 능력치 보유", "icon": "👑"},
	]

	for info in grade_info:
		var gr: String = info.grade
		var is_sel: bool = (_selected_guild_grade == gr)
		var col: Color = JobDb.grade_color(gr)
		var border_col: Color = UiKit.GOLD if is_sel else UiKit.BORDER
		var bg_col: Color = Color("2a2016") if is_sel else UiKit.BG3

		var scard := UiKit.panel(bg_col, border_col, 8)
		scard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scard.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scard.mouse_filter = Control.MOUSE_FILTER_PASS

		var scv := VBoxContainer.new()
		scv.alignment = BoxContainer.ALIGNMENT_CENTER
		scv.add_theme_constant_override("separation", 4)
		scard.add_child(scv)

		scv.add_child(UiKit.label(info.icon, 20, col))
		scv.add_child(UiKit.title("%s 봉인서" % gr, 13, col.lightened(0.2)))
		scv.add_child(UiKit.label("%dG · ⚡1" % GameState.recruit_cost(gr), 11, UiKit.GOLD2 if is_sel else UiKit.TEXT2))

		var cur_gr: String = gr
		scard.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_selected_guild_grade = cur_gr
				rebuild()
		)
		seals_h.add_child(scard)

	var sel_info: Dictionary = grade_info[0]
	for gi in grade_info:
		if gi.grade == _selected_guild_grade:
			sel_info = gi
			break

	var sel_col: Color = JobDb.grade_color(_selected_guild_grade)
	var base_cost: int = int(JobDb.RECRUIT_COST.get(_selected_guild_grade, 50))
	var sel_cost: int = GameState.recruit_cost(_selected_guild_grade)
	var bonus_hp: int = GameState.guild_recruit_hp_bonus()
	var guild_lv: int = GameState.building_level("용병모집소")

	iv.add_child(UiKit.title("%s %s 용병 봉인서" % [sel_info.icon, _selected_guild_grade], 15, sel_col.lightened(0.25)))
	iv.add_child(UiKit.label(sel_info.desc, 12, UiKit.TEXT2))

	iv.add_child(UiKit.divider())
	iv.add_child(UiKit.label("FACILITY BONUS:", 11, UiKit.GOLD))
	iv.add_child(UiKit.label("• 용병모집소 Lv.%d 특권:\n  신규 합류 용병 체력 +%d 보너스" % [guild_lv, bonus_hp], 12, UiKit.GREEN))
	if GameState.active_curses.has("curse_ashen_blood"):
		iv.add_child(UiKit.label("• [잿빛 혈흔] 신규 모집 최대 HP -10%", 11, UiKit.RED.lightened(0.2)))

	iv.add_child(UiKit.divider())
	iv.add_child(UiKit.label("REQUIRED RESOURCES:", 11, UiKit.GOLD))

	var has_gold := GameState.can_afford(sel_cost)
	var has_ap := (GameState.action_points >= 1)
	var can_recruit := has_gold and has_ap

	var g_txt := "GOLD: %d G (보유: %d)" % [sel_cost, GameState.gold]
	if not has_gold:
		g_txt += " [골드 부족!]"
	iv.add_child(UiKit.label(g_txt, 12, UiKit.GOLD if has_gold else UiKit.RED))
	var brand_pct := GameState.brand_recruit_penalty_pct()
	var morale_pct := GameState.morale_cost_mod_pct()
	if brand_pct != 0.0 or morale_pct != 0.0:
		var cost_parts: PackedStringArray = ["기본 %dG" % base_cost]
		if brand_pct > 0.0:
			cost_parts.append("낙인 +%.0f%%" % brand_pct)
		if morale_pct < 0.0:
			cost_parts.append("민심 고양 %.0f%%" % morale_pct)
		elif morale_pct > 0.0:
			cost_parts.append("민심 붕괴 +%.0f%%" % morale_pct)
		var attr_c := UiKit.label("산출: %s" % " · ".join(cost_parts), 10, UiKit.TEXT2)
		attr_c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		iv.add_child(attr_c)

	var ap_txt := "ACTION POINT: 1 AP (보유: %d)" % GameState.action_points
	if not has_ap:
		ap_txt += " [행동력 부족!]"
	iv.add_child(UiKit.label(ap_txt, 12, UiKit.GREEN if has_ap else UiKit.RED))

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(sp)

	var btn_recruit := UiKit.gothic_button("📜 봉인 해제 및 영입", sel_col if can_recruit else UiKit.BORDER)
	btn_recruit.custom_minimum_size = Vector2(0, 44)
	btn_recruit.disabled = not can_recruit
	btn_recruit.pressed.connect(func():
		var m := GameState.recruit(_selected_guild_grade)
		if m != null:
			notice = "[%s] %s (%s Lv.%d, HP %d, 공격력 %d) 용병이 합류했습니다!" % [m.grade, m.merc_name, m.job, m.level, m.max_hp, m.attack]
			estate.village.rebuild()
			rebuild()
	)
	iv.add_child(btn_recruit)
