class_name TreatmentPopup
extends BaseBuildingPopup
## 치료소 대형 팝업 컨텐츠. 선택 상태는 이 팝업이 직접 보유하고, 상태가 바뀌면 rebuild() 로 자기 화면만 다시 그린다.

var _selected_treatment_merc: Mercenary = null
var _selected_treatment_pen: String = ""


## 우측 본문 영역(3단 고딕 스캐폴드)을 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var injured := GameState.injured_mercs()
	if _selected_treatment_merc == null or not (_selected_treatment_merc in injured):
		_selected_treatment_merc = injured[0] if not injured.is_empty() else null
		if _selected_treatment_merc != null and not _selected_treatment_merc.penalties.is_empty():
			_selected_treatment_pen = _selected_treatment_merc.penalties[0]
		else:
			_selected_treatment_pen = ""

	var ui := UiKit.three_column_modal(vbox, "PATIENTS (%d명)" % injured.size(), "SURGERY & TREATMENT")
	var pv: VBoxContainer = ui["left"]
	var center_col: VBoxContainer = ui["center"]
	var iv: VBoxContainer = ui["right"]

	pv.add_child(UiKit.merc_roster_list(injured, {
		"empty_text": "✅ 현재 중증 외상/패널티를\n입은 용병이 없습니다.",
		"empty_color": UiKit.GREEN,
		"selected_merc": _selected_treatment_merc,
		"card_opts_fn": func(m: Mercenary, _idx: int) -> Dictionary:
			var is_sel := (m == _selected_treatment_merc)
			return {
				"selected": is_sel,
				"bg_color": Color("25181a") if is_sel else UiKit.BG3,
				"border_color": UiKit.GOLD if is_sel else UiKit.RED,
				"portrait_size": 38,
				"grade_in_title": false,
				"subtitle_mode": "penalty",
			},
		"on_click": func(cur_m: Mercenary):
			_selected_treatment_merc = cur_m
			_selected_treatment_pen = cur_m.penalties[0] if not cur_m.penalties.is_empty() else ""
			rebuild(),
	}))

	center_col.add_child(build_center_interior(320.0))

	var cv := UiKit.modal_summary_card(center_col, "🌿 수도원 요양 및 정신 정화 요법", {"title_size": 12})

	var care_row := HBoxContainer.new()
	care_row.add_theme_constant_override("separation", 10)
	care_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(care_row)

	var colors := {"pray": UiKit.BLUE, "ward": UiKit.GREEN}
	for cmd in EstateCommand.catalog("treatment"):
		var col: Color = colors.get(cmd.id, UiKit.BLUE)
		var cbox := UiKit.panel(UiKit.BG3, col, 6)
		cbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cbv := VBoxContainer.new()
		cbv.add_theme_constant_override("separation", 4)
		cbox.add_child(cbv)
		cbv.add_child(UiKit.title(cmd.title, 12, col.lightened(0.2)))
		cbv.add_child(UiKit.label(cmd.desc, 10, UiKit.TEXT2))
		var btn := UiKit.button("집행 (%s)" % cmd.cost_text(), col)
		btn.disabled = not cmd.can_execute() or (cmd.id == "pray" and GameState.stress_resolvable <= 0)
		var c_ref: EstateCommand = cmd
		btn.pressed.connect(func(): run_command(c_ref))
		cbv.add_child(btn)
		care_row.add_child(cbox)

	var succ_rate := GameState.heal_success_rate()
	var tlv := GameState.building_level("치료소")
	var base_rate: int = [50, 62, 74, 82, 90][clampi(tlv, 1, 5) - 1]
	var brand_pen := GameState.brand_heal_penalty_pp()
	var has_oath := GameState.active_curses.has("curse_faded_oath")
	iv.add_child(UiKit.label("외과 성공 확률: %d%% (치료소 Lv.%d)" % [succ_rate, tlv], 12, UiKit.GREEN if succ_rate >= 50 else UiKit.GOLD))
	if brand_pen > 0 or has_oath:
		var parts: PackedStringArray = ["기본 %d%%" % base_rate]
		if brand_pen > 0:
			parts.append("낙인 -%d%%p" % brand_pen)
		if has_oath:
			parts.append("바랜 맹세 -8%%p")
		var attr_lbl := UiKit.label("[%s%s]" % [" ".join(parts), " · 하한 10%" if succ_rate <= 10 else ""], 10, UiKit.RED.lightened(0.25))
		attr_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		iv.add_child(attr_lbl)
	iv.add_child(UiKit.progress(succ_rate, 100, UiKit.GREEN, 8))

	iv.add_child(UiKit.divider())

	var treat_cost := GameState.treat_penalty_cost()
	if _selected_treatment_merc != null and _selected_treatment_pen != "":
		iv.add_child(UiKit.title("대상: %s" % _selected_treatment_merc.merc_name, 13, UiKit.WHITE))
		iv.add_child(UiKit.label("치료 후유증: %s" % _selected_treatment_pen, 12, UiKit.RED))
		iv.add_child(UiKit.label("• 성공 시: 후유증 영구 제거\n• 실패 시: 흉터 잔존 (비용만 소모)", 11, UiKit.TEXT2))

		iv.add_child(UiKit.divider())
		var has_g := GameState.can_afford(treat_cost)
		var surcharge_txt := " [불신의 낙인 +20G]" if GameState.brand_stacks >= 3 else ""
		iv.add_child(UiKit.label("필요 비용: %d G%s (보유: %d)" % [treat_cost, surcharge_txt, GameState.gold], 12, UiKit.GOLD if has_g else UiKit.RED))

		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		iv.add_child(sp)

		var btn_cure := UiKit.gothic_button("⚕️ 외과 시술 집행 (%dG)" % treat_cost, UiKit.GOLD if has_g else UiKit.BORDER)
		btn_cure.custom_minimum_size = Vector2(0, 44)
		btn_cure.disabled = not has_g
		btn_cure.pressed.connect(func():
			var ok := GameState.treat_penalty(_selected_treatment_merc, _selected_treatment_pen, treat_cost)
			notice = "%s의 [%s] 치료 %s!" % [_selected_treatment_merc.merc_name, _selected_treatment_pen, "성공 (완치됨)" if ok else "실패 (흉터가 남음)"]
			rebuild()
		)
		iv.add_child(btn_cure)
	else:
		iv.add_child(UiKit.label("선택된 외과 수술 대상이 없습니다.\n좌측 환자 목록에서 대상을 선택하세요.", 12, UiKit.TEXT2))
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		iv.add_child(sp)
