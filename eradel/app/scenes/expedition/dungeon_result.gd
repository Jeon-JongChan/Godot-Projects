## 원정 결과 정산 및 영지 귀환 화면 (dungeon_result.gd)
## 던전 탐험 종료 후 파티 생존/실종/사망 현황, 획득 전리품(골드/마나석), 영지 파문(스트레스/민심 변화)을 정산하고 영지로 복귀하는 화면.
extends Control


## 화면 진입 시 초기화: 마지막 원정 결과(GameState.last_result)를 로드하고 결과 UI 전체 렌더링
func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	var r := GameState.last_result
	if r.is_empty():
		get_tree().change_scene_to_file.call_deferred(GameState.SCENE_ESTATE)
		return

	var outcome: String = str(r.outcome)
	var result_theme := _theme_for(outcome)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	# 상단 결과 대형 배너
	var banner := UiKit.panel(result_theme.bg, result_theme.color)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(bv)
	var label_state := UiKit.label(result_theme.label, 12, result_theme.color)
	label_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(label_state)
	var big := UiKit.title(result_theme.title, 34, result_theme.color)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(big)
	var lore := UiKit.label(result_theme.lore, 12, UiKit.TEXT2)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(lore)
	var dname := UiKit.label("어둠의 균열 던전 — %d일차" % GameState.day, 11, UiKit.TEXT3)
	dname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(dname)
	v.add_child(banner)

	# 본문 2단: 파티 생존 현황 + 획득 전리품
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(body)
	body.add_child(_build_party(r))
	body.add_child(_build_loot(r))

	# 영지 파문 (스트레스 및 민심 영향)
	v.add_child(_build_ripple(r))

	# 하단 푸터 및 영지 귀환 액션 버튼
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(sp)
	var ret := UiKit.primary_button("영지로 귀환 ↗", result_theme.color)
	ret.custom_minimum_size = Vector2(200, 46)
	ret.pressed.connect(_on_return)
	footer.add_child(ret)
	v.add_child(footer)
	UiKit.attach_gothic_atmosphere(self, 0.44, 0.16, 0.55 if outcome == "wipe" else 0.0)

	# 심층 보스 봉인 성공 시 속죄/폭군 엔딩 연출 오버레이를 표시한다.
	if not GameState.pending_ending.is_empty():
		_show_ending_overlay(GameState.pending_ending)


## 심층 보스 격파 시 속죄(ATONEMENT) vs 폭군(TYRANT) 엔딩 연출 오버레이를 표시하고 엔드리스로 연결한다.
func _show_ending_overlay(ending: Dictionary) -> void:
	var is_tyrant: bool = (str(ending.get("ending_type", "ATONEMENT")) == "TYRANT")
	var accent: Color = UiKit.RED if is_tyrant else UiKit.GOLD2

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.03, 0.86)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	dim.add_child(center)

	var card := UiKit.panel(UiKit.BG, accent, 14)
	card.custom_minimum_size = Vector2(640, 0)
	center.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	var tag := UiKit.label("어둠의 균열 심층 봉인 완료 · 제 %d대 영주" % int(ending.get("generation", 1)), 12, accent)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)

	var title_txt := "폭군의 봉인 (TYRANT ENDING)" if is_tyrant else "속죄의 봉인 (ATONEMENT ENDING)"
	var title := UiKit.title(title_txt, 28, accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var lore_txt := "수많은 원혼을 연료로 태워 어둠을 억눌렀다.\n에라델은 살아남았으나, 잿빛 돌비 아래의 원성은 결코 잠들지 않는다." if is_tyrant else "끝없는 유혹 속에서도 동료의 이름을 지켜냈다.\n봉인의 불빛이 잿빛 영지를 비추지만, 심연은 다시 고개를 들 것이다."
	var lore := UiKit.label(lore_txt, 13, UiKit.TEXT)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lore)

	v.add_child(UiKit.divider())
	var ratio_pct: float = float(ending.get("tyranny_ratio", 0.0)) * 100.0
	var stats := UiKit.label(
		"폭군 성향 비율: %.1f%%  ·  누적 정식 추모 %d회  ·  약식 안치 %d회  ·  원혼 착취 %d회  ·  현 세대 낙인 %d스택" % [
			ratio_pct, int(ending.get("total_memorialized_count", 0)),
			int(ending.get("total_pauper_buried_count", 0)), int(ending.get("total_exploited_count", 0)),
			int(ending.get("brand_stacks", 0))
		],
		11, UiKit.TEXT2
	)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(stats)

	var next_cycle: int = int(ending.get("next_endless_cycle", 1))
	var next_mult: float = 1.0 + float(next_cycle) * GameState.ENDLESS_SCALE_PER_CYCLE
	var end_note := UiKit.label("연대기를 계속하면 심연 엔드리스 +%d사이클(몬스터 ×%.1f)로 이어집니다." % [next_cycle, next_mult], 12, UiKit.GOLD)
	end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_note)

	var cbtn := CenterContainer.new()
	v.add_child(cbtn)
	var btn_cont := UiKit.primary_button("연대기 계속하기 (엔드리스 +%d)" % next_cycle, accent)
	btn_cont.custom_minimum_size = Vector2(280, 44)
	btn_cont.focus_mode = Control.FOCUS_ALL
	btn_cont.pressed.connect(func():
		GameState.continue_endless_after_seal()
		dim.queue_free()
	)
	cbtn.add_child(btn_cont)
	btn_cont.grab_focus()


## 탐험 결과 상태(clear, retreat, wipe)에 따른 배너 색상, 타이틀, 로어 문구 테마 반환
func _theme_for(outcome: String) -> Dictionary:
	match outcome:
		"clear":
			return {"label": "던전 클리어", "title": "귀환", "color": UiKit.GREEN,
				"bg": Color("0d1f12"), "lore": "\"살아 돌아온 자만이 다음을 이야기할 수 있다.\""}
		"retreat":
			return {"label": "철수", "title": "후퇴", "color": UiKit.GOLD,
				"bg": Color("1a100a"), "lore": "\"후퇴의 대가는 언제나 타인이 치른다.\""}
		_:
			return {"label": "전멸", "title": "몰살", "color": UiKit.RED,
				"bg": Color("1a0808"), "lore": "\"영지는 그들을 기다렸다. 그러나 아무도 돌아오지 않았다.\""}


## 원정 참가 용병들의 생존/실종/사망 현황 목록 패널 생성 (클리어 시에도 던전 도중 전사자 결과를 명확히 구분 표시)
func _build_party(r: Dictionary) -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var survivors: Array = r.get("survivors", [])
	var missing: Array = r.get("missing", [])
	var dead: Array = r.get("dead", [])

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title_lbl := UiKit.label("파티 현황", 12, UiKit.TEXT2)
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title_lbl)
	head.add_child(UiKit.chip("생존 %d" % survivors.size(), UiKit.GREEN))
	if not dead.is_empty():
		head.add_child(UiKit.chip("전사 %d" % dead.size(), UiKit.RED))
	if not missing.is_empty():
		head.add_child(UiKit.chip("실종 %d" % missing.size(), UiKit.GOLD))
	v.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)

	# 던전 도중 전사한 캐릭터를 최상단 붉은 강조 섹션으로 우선 표시한다.
	if not dead.is_empty():
		var dead_box := UiKit.panel(Color("220d0f"), UiKit.RED, 8)
		var dv := VBoxContainer.new()
		dv.add_theme_constant_override("separation", 4)
		dead_box.add_child(dv)
		var dead_names: PackedStringArray = []
		for dm: Mercenary in dead:
			dead_names.append("%s(%s Lv.%d)" % [dm.merc_name, dm.job, dm.level])
		dv.add_child(UiKit.label("☠ 던전 도중 전사 (%d명) — %s" % [dead.size(), ", ".join(dead_names)], 12, UiKit.RED.lightened(0.25)))
		for m: Mercenary in dead:
			dv.add_child(_member_line(m, "전사 (유품 생성)", UiKit.RED))
		list.add_child(dead_box)
	else:
		list.add_child(UiKit.label("✦ 전사자 없음 — 원정 중 사망한 용병이 없습니다.", 11, UiKit.GREEN))

	if not missing.is_empty():
		list.add_child(UiKit.label("실종 (%d명)" % missing.size(), 11, UiKit.GOLD))
		for m: Mercenary in missing:
			list.add_child(_member_line(m, "실종", UiKit.GOLD))

	if not survivors.is_empty():
		list.add_child(UiKit.label("생존 귀환 (%d명)" % survivors.size(), 11, UiKit.GREEN))
		for m: Mercenary in survivors:
			list.add_child(_member_line(m, "생존", UiKit.GREEN))
	return panel


## 개별 용병 상태 표시 행 생성: UiKit.merc_card 공용 위젯으로 통합
func _member_line(m: Mercenary, state: String, color: Color) -> Control:
	return UiKit.merc_card(m, {
		"bg_color": UiKit.BG3,
		"border_color": color.darkened(0.3),
		"portrait_size": 32,
		"grade_in_title": false,
		"subtitle_mode": "job_only",
		"subtitle_color": UiKit.TEXT3,
		"show_penalties": (state == "생존"),
		"penalty_prefix": "새 패널티: ",
		"right_chip_text": state,
		"right_chip_color": color,
	})


## 원정 획득 전리품 및 던전 활성도 변화 패널 생성
func _build_loot(r: Dictionary) -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("획득 자원", 11, UiKit.TEXT2))
	var gold_gain: int = int(r.gold_gain)
	var eff_gold: int = maxi(0, int(round(float(gold_gain) * 0.85))) if GameState.active_curses.has("curse_hollow_coffers") else gold_gain
	var gold_txt := ("+%d" % eff_gold if eff_gold > 0 else "0") + (" [빈 금고 -15%]" if GameState.active_curses.has("curse_hollow_coffers") and gold_gain > 0 else "")
	var mana_gain: int = int(r.mana_gain)
	v.add_child(_loot_row("금화", gold_txt, UiKit.GOLD if eff_gold > 0 else UiKit.TEXT3))
	v.add_child(_loot_row("마나석", "+%d" % mana_gain if mana_gain > 0 else "0", UiKit.BLUE if mana_gain > 0 else UiKit.TEXT3))
	v.add_child(UiKit.hsep(6))
	v.add_child(UiKit.label("던전 변화", 11, UiKit.TEXT2))
	var act: int = int(r.activity_delta)
	var act_text := (("%d%%" % act) if act != 0 else "변화 없음") + (" [속삭이는 균열]" if GameState.active_curses.has("curse_whispering_rift") and str(r.get("outcome", "")) == "clear" else "")
	v.add_child(_loot_row("활성도", act_text, UiKit.GREEN if act < 0 else UiKit.RED))
	return panel


## 단일 전리품 항목 라벨 및 수치 행 생성 헬퍼
func _loot_row(name: String, value: String, color: Color) -> Control:
	var h := HBoxContainer.new()
	var n := UiKit.label(name, 12, UiKit.TEXT)
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(UiKit.label(value, 12, color))
	return h


## 원정 결과가 영지 전체에 미친 스트레스 및 민심 변화 요약 패널 생성 (preview_return_settlement 공용 프리뷰 사용)
func _build_ripple(r: Dictionary) -> Control:
	var prev := GameState.preview_return_settlement(r, false)
	var panel := UiKit.panel(UiKit.BG2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("영지 파문 및 일일 정산 예상", 11, UiKit.TEXT2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var resolvable_delta: int = int(prev["resolvable_delta"])
	var permanent_gain: int = int(prev["permanent_gain"])
	var morale_delta: int = int(prev["morale_delta"])
	h.add_child(UiKit.chip("원정 해소 %+d" % resolvable_delta, UiKit.GOLD))
	h.add_child(UiKit.chip("영구 스트레스 +%d" % permanent_gain, UiKit.RED))
	h.add_child(UiKit.chip("원정 민심 %+d" % morale_delta, UiKit.GREEN if morale_delta >= 0 else UiKit.RED))
	if int(prev["unresolved_stress"]) > 0:
		h.add_child(UiKit.chip("유품 방치 +%d" % int(prev["unresolved_stress"]), UiKit.RED))
	if int(prev["brand_morale_loss"]) > 0:
		h.add_child(UiKit.chip("낙인 민심 -%d" % int(prev["brand_morale_loss"]), UiKit.RED))
	if int(prev["morale_stress"]) > 0:
		h.add_child(UiKit.chip("민심 동요 +%d" % int(prev["morale_stress"]), UiKit.RED))
	if int(prev["pub_relief"]) > 0:
		h.add_child(UiKit.chip("주점 완화 -%d" % int(prev["pub_relief"]), UiKit.GREEN))
	v.add_child(h)

	var new_relics: int = int(prev["new_relics_count"])
	var relic_note := ("  ·  신규 유품 %d건 생성 (당일 방치 유예)" % new_relics) if new_relics > 0 else ""
	var projected: int = int(prev["final_total_stress"])
	var proj_col := UiKit.RED if bool(prev["will_fall"]) else UiKit.TEXT2
	v.add_child(UiKit.label("귀환 시 영지 총 스트레스 예상: %d / 100 · 예상 민심: %d%%%s" % [projected, int(prev["final_morale"]), relic_note], 12, proj_col))
	return panel


## 영지 복귀 처리: GameState.return_to_estate() 호출 후 세대 교체 요약 생성(또는 스트레스 100) 시 결산 화면, 아니면 영지로 전환
func _on_return() -> void:
	GameState.return_to_estate()
	if not GameState.pending_succession_summary.is_empty() or GameState.total_stress() >= GameState.MAX_STRESS:
		get_tree().change_scene_to_file(GameState.SCENE_GAMEOVER)
	else:
		get_tree().change_scene_to_file(GameState.SCENE_ESTATE)
