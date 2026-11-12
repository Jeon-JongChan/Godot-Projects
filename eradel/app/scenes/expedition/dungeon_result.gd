## 원정 결과 정산 및 영지 귀환 화면 (dungeon_result.gd)
## 던전 탐험 종료 후 파티 생존/실종/사망 현황, 획득 전리품(골드/마나석), 영지 파문(스트레스/민심 변화)을 정산하고 영지로 복귀하는 화면.
extends Control


## 화면 진입 시 초기화: 마지막 원정 결과(GameState.last_result)를 로드하고 결과 UI 전체 렌더링
func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	var r := GameState.last_result
	if r.is_empty():
		get_tree().change_scene_to_file(GameState.SCENE_ESTATE)
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


## 원정 참가 용병들의 생존/실종/사망 현황 목록 패널 생성
func _build_party(r: Dictionary) -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("파티 현황", 11, UiKit.TEXT2))
	for m: Mercenary in r.survivors:
		v.add_child(_member_line(m, "생존", UiKit.GREEN))
	for m: Mercenary in r.missing:
		v.add_child(_member_line(m, "실종", UiKit.GOLD))
	for m: Mercenary in r.dead:
		v.add_child(_member_line(m, "사망", UiKit.RED))
	return panel


## 개별 용병 상태 표시 행 생성: 이름, 레벨/직업, 신규 패널티 목록, 생존 상태 칩
func _member_line(m: Mercenary, state: String, color: Color) -> Control:
	var p := UiKit.panel(UiKit.BG3, color.darkened(0.3), 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	info.add_child(UiKit.label(m.merc_name, 12, UiKit.TEXT))
	info.add_child(UiKit.label("%s Lv.%d" % [m.job, m.level], 10, UiKit.TEXT3))
	if state == "생존" and m.penalties.size() > 0:
		info.add_child(UiKit.label("새 패널티: " + ", ".join(m.penalties), 10, UiKit.RED))
	h.add_child(info)
	h.add_child(UiKit.chip(state, color))
	return p


## 원정 획득 전리품 및 던전 활성도 변화 패널 생성
func _build_loot(r: Dictionary) -> Control:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("획득 자원", 11, UiKit.TEXT2))
	var gold_gain: int = int(r.gold_gain)
	var mana_gain: int = int(r.mana_gain)
	v.add_child(_loot_row("금화", "+%d" % gold_gain if gold_gain > 0 else "0", UiKit.GOLD if gold_gain > 0 else UiKit.TEXT3))
	v.add_child(_loot_row("마나석", "+%d" % mana_gain if mana_gain > 0 else "0", UiKit.BLUE if mana_gain > 0 else UiKit.TEXT3))
	v.add_child(UiKit.hsep(6))
	v.add_child(UiKit.label("던전 변화", 11, UiKit.TEXT2))
	var act: int = int(r.activity_delta)
	var act_text := ("%d%%" % act) if act != 0 else "변화 없음"
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


## 원정 결과가 영지 전체에 미친 스트레스 및 민심 변화 요약 패널 생성
func _build_ripple(r: Dictionary) -> Control:
	var panel := UiKit.panel(UiKit.BG2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label("영지 파문", 11, UiKit.TEXT2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var resolvable_delta: int = int(r.resolvable_delta)
	var permanent_gain: int = int(r.permanent_gain)
	var morale_delta: int = int(r.morale_delta)
	h.add_child(UiKit.chip("해소 스트레스 %+d" % resolvable_delta, UiKit.GOLD))
	h.add_child(UiKit.chip("영구 스트레스 +%d" % permanent_gain, UiKit.RED))
	h.add_child(UiKit.chip("민심 %+d" % morale_delta, UiKit.GREEN if morale_delta >= 0 else UiKit.RED))
	v.add_child(h)
	var projected: int = clampi(GameState.total_stress() + resolvable_delta + permanent_gain, 0, 100)
	v.add_child(UiKit.label("귀환 시 영지 스트레스 예상: %d / 100" % projected, 12, UiKit.TEXT2))
	return panel


## 영지 복귀 처리: GameState.return_to_estate() 호출 후 스트레스 100 이상 시 게임오버, 미만 시 영지 씬으로 전환
func _on_return() -> void:
	GameState.return_to_estate()
	if GameState.total_stress() >= GameState.MAX_STRESS:
		get_tree().change_scene_to_file(GameState.SCENE_GAMEOVER)
	else:
		get_tree().change_scene_to_file(GameState.SCENE_ESTATE)
