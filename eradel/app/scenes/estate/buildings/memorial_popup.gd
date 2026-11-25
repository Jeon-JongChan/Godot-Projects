class_name MemorialPopup
extends BaseBuildingPopup
## 위령비·기념관 대형 팝업 컨텐츠 — 3탭([유품 처리] / [헌화 의식] / [연대기]) 및 원혼 착취·추모 결단 UI를 제공한다.

## 현재 활성 탭 ("relics" | "rite" | "chronicle")
var _active_tab: String = "relics"
## [유품 처리] 탭에서 선택된 유품 ID
var _selected_relic_id: String = ""
## [연대기] 탭에서 선택된 세대 번호 (-1 = 현재 세대)
var _selected_chronicle_gen: int = -1


## 외부(상단 HUD 유품 배지 등)에서 특정 탭을 지정해 열 수 있도록 한다.
func select_tab(tab_id: String) -> void:
	if tab_id in ["relics", "rite", "chronicle"]:
		_active_tab = tab_id


## 우측 본문 영역을 3탭 구조로 채운다. BaseBuildingPopup.populate 의 건물별 구현.
func populate(vbox: VBoxContainer) -> void:
	var unres := _unresolved_relics_sorted()
	# 상단 3탭 바
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	vbox.add_child(tab_bar)

	var tabs := [
		{"id": "relics", "label": "🕯️ 유품 처리 (%d)" % unres.size(), "color": UiKit.RED if not unres.is_empty() else UiKit.GOLD},
		{"id": "rite", "label": "✝ 헌화 의식", "color": UiKit.BLUE},
		{"id": "chronicle", "label": "📜 연대기 (%d)" % GameState.soul_relics.size(), "color": UiKit.GOLD2},
	]
	for t in tabs:
		var tid: String = str(t["id"])
		var is_cur: bool = (_active_tab == tid)
		var btn := UiKit.button(str(t["label"]), t["color"] if is_cur else UiKit.BORDER)
		btn.custom_minimum_size = Vector2(180, 34)
		btn.focus_mode = Control.FOCUS_ALL
		var cur_tid: String = tid
		btn.pressed.connect(func():
			_active_tab = cur_tid
			rebuild()
		)
		tab_bar.add_child(btn)

	match _active_tab:
		"relics":
			_populate_relics_tab(vbox, unres)
		"rite":
			_populate_rite_tab(vbox)
		_:
			_populate_chronicle_tab(vbox)


## 미처리(UNRESOLVED) 유품 목록을 방치 일수 내림차순(오래된 순)으로 정렬해 반환한다.
func _unresolved_relics_sorted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rel in GameState.soul_relics:
		if str(rel.get("state", "")) == GameState.RELIC_STATE_UNRESOLVED:
			out.append(rel)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("death_day", 1)) < int(b.get("death_day", 1))
	)
	return out


## [유품 처리] 탭: 좌측 미처리 목록 + 우측 3종 결단 카드(정식 추모 / 균열 억제 / 원정 축복) + 하단 분리 약식 안치(0G).
func _populate_relics_tab(vbox: VBoxContainer, unres: Array[Dictionary]) -> void:
	# 선택 유품 유효성 보정
	var selected: Dictionary = {}
	for rel in unres:
		if str(rel.get("id", "")) == _selected_relic_id:
			selected = rel
			break
	if selected.is_empty() and not unres.is_empty():
		selected = unres[0]
		_selected_relic_id = str(selected.get("id", ""))
	elif unres.is_empty():
		_selected_relic_id = ""

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	# ── 좌측: 미처리 유품 리스트 ──
	var left_panel := UiKit.panel(UiKit.BG3, UiKit.BORDER, 10)
	left_panel.custom_minimum_size = Vector2(360, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left_panel.add_child(lv)
	lv.add_child(UiKit.title("미처리 유품 (%d건)" % unres.size(), 14, UiKit.GOLD2))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)

	var list_v := VBoxContainer.new()
	list_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_v.add_theme_constant_override("separation", 6)
	scroll.add_child(list_v)

	if unres.is_empty():
		list_v.add_child(UiKit.label("미처리 유품이 없습니다.\n전사한 용병의 유품이 이곳에 안치됩니다.", 12, UiKit.TEXT2))
	else:
		for rel in unres:
			var rid: String = str(rel.get("id", ""))
			var is_sel: bool = (rid == _selected_relic_id)
			var d_day: int = int(rel.get("death_day", 1))
			var age_days: int = maxi(0, GameState.day - d_day)
			var badge_txt := "오늘 안치 (방치 유예)" if age_days <= 0 else "방치 %d일차 (귀환 시 스트레스 +2)" % age_days
			var btn_item := UiKit.button(
				"✝ [%s] %s (%s Lv.%d)\n%s" % [str(rel.get("grade", "일반")), str(rel.get("merc_name", "")), str(rel.get("job", "")), int(rel.get("level", 1)), badge_txt],
				UiKit.GOLD if is_sel else UiKit.BORDER
			)
			btn_item.custom_minimum_size = Vector2(0, 52)
			btn_item.focus_mode = Control.FOCUS_ALL
			var cur_rid: String = rid
			btn_item.pressed.connect(func():
				_selected_relic_id = cur_rid
				rebuild()
			)
			list_v.add_child(btn_item)

	# ── 우측: 선택된 유품 상세 & 결단 영역 ──
	var right_panel := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 12)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_panel)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right_panel.add_child(rv)

	if selected.is_empty():
		rv.add_child(UiKit.title("결단 대기 중인 유품 없음", 15, UiKit.TEXT2))
		rv.add_child(UiKit.label("모든 전사자의 유품이 처리되었습니다. [헌화 의식] 또는 [연대기] 탭을 확인하세요.", 12, UiKit.TEXT3))
		return

	var r_id: String = str(selected.get("id", ""))
	var r_name: String = str(selected.get("merc_name", ""))
	var r_job: String = str(selected.get("job", ""))
	var r_grade: String = str(selected.get("grade", "일반"))
	var r_lv: int = int(selected.get("level", 1))
	var g_mult: float = GameState.grade_mult(r_grade)
	var exp_stress: int = GameState.exploit_permanent_stress_for(r_lv)
	var sup_amt: int = GameState.exploit_suppress_amount_for(r_lv, r_grade)
	var buff_vals: Dictionary = GameState.exploit_buff_values_for(r_lv, r_grade)
	var restore_vals: Dictionary = GameState.memorial_restore_values(false)

	rv.add_child(UiKit.title("✝ [%s] %s · %s Lv.%d (등급 배율 ×%.1f)" % [r_grade, r_name, r_job, r_lv, g_mult], 16, UiKit.GOLD2))
	if GameState.brand_stacks >= 6:
		rv.add_child(UiKit.label("⚠ [타락한 영주 (낙인 %d스택)] 정식 추모 및 영지 회복 커맨드 회복량 -50%" % GameState.brand_stacks, 11, UiKit.RED))

	# ── 주요 카드 3종 고정 배치 ──
	var cards_h := HBoxContainer.new()
	cards_h.add_theme_constant_override("separation", 10)
	cards_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(cards_h)

	# 카드 1: 정식 추모 (25G)
	var can_formal := GameState.gold >= GameState.MEMORIAL_COST_GOLD
	var c1 := UiKit.panel(UiKit.BG3, UiKit.BLUE if can_formal else UiKit.BORDER, 8)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c1v := VBoxContainer.new()
	c1v.add_theme_constant_override("separation", 6)
	c1.add_child(c1v)
	c1v.add_child(UiKit.title("🕯️ 정식 추모 (25G)", 13, UiKit.BLUE.lightened(0.3)))
	var c1_desc := "• 민심 +%d%% · 해소 스트레스 -%d\n• 속죄 연대기 정식 기록 (+1)" % [int(restore_vals["morale"]), int(restore_vals["stress"])]
	if GameState.morale == 100 and GameState.stress_resolvable == 0:
		c1_desc += "\n• 평온 상태 — 안식을 기리며 연대기에 기록합니다."
	c1v.add_child(UiKit.label(c1_desc, 11, UiKit.TEXT2))
	var btn_formal := UiKit.gothic_button("정식 추모 (25G)", UiKit.BLUE if can_formal else UiKit.BORDER)
	btn_formal.custom_minimum_size = Vector2(0, 38)
	btn_formal.focus_mode = Control.FOCUS_ALL
	btn_formal.disabled = not can_formal
	btn_formal.pressed.connect(func():
		if GameState.memorialize_relic(r_id, false):
			estate.play_soul_feedback(false)
			notice = "%s의 유품을 정식 추모했습니다. (민심 +%d, 스트레스 -%d)" % [r_name, int(restore_vals["morale"]), int(restore_vals["stress"])]
			rebuild()
	)
	c1v.add_child(btn_formal)
	if not can_formal:
		c1v.add_child(UiKit.label("골드 부족 (25G 필요)", 10, UiKit.RED))
	cards_h.add_child(c1)

	# 카드 2: 착취 — 균열 억제
	var can_sup := (GameState.dungeon_activity > 0 or GameState.monster_tier > 0)
	var c2 := UiKit.panel(UiKit.BG3, UiKit.RED if can_sup else UiKit.BORDER, 8)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c2v := VBoxContainer.new()
	c2v.add_theme_constant_override("separation", 6)
	c2.add_child(c2v)
	c2v.add_child(UiKit.title("🔥 착취: 균열 억제 (0G)", 13, UiKit.RED.lightened(0.2)))
	c2v.add_child(UiKit.label("• 균열 활성도 -%d%% · 몬스터 티어 -1\n• 대가: 영구 스트레스 +%d · 낙인 +1" % [sup_amt, exp_stress], 11, UiKit.TEXT2))
	var btn_sup := UiKit.gothic_button("균열 억제 착취", UiKit.RED if can_sup else UiKit.BORDER)
	btn_sup.custom_minimum_size = Vector2(0, 38)
	btn_sup.focus_mode = Control.FOCUS_ALL
	btn_sup.disabled = not can_sup
	btn_sup.pressed.connect(func():
		_confirm_exploit(selected, GameState.RELIC_STATE_EXPLOITED_SUPPRESS, "균열 -%d%% · 몬스터 티어 -1" % sup_amt)
	)
	c2v.add_child(btn_sup)
	if not can_sup:
		c2v.add_child(UiKit.label("균열 0% · 티어 0 (억제 불필요)", 10, UiKit.TEXT3))
	cards_h.add_child(c2)

	# 카드 3: 착취 — 원정 축복
	var buff_active := bool(GameState.active_exploit_buff.get("active", false))
	var can_buff := not buff_active
	var c3 := UiKit.panel(UiKit.BG3, UiKit.RED if can_buff else UiKit.BORDER, 8)
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c3v := VBoxContainer.new()
	c3v.add_theme_constant_override("separation", 6)
	c3.add_child(c3v)
	c3v.add_child(UiKit.title("⚔️ 착취: 원정 축복 (0G)", 13, UiKit.RED.lightened(0.2)))
	c3v.add_child(UiKit.label("• 다음 1회 원정 ATK +%d · CRIT +%.1f%%\n• 대가: 영구 스트레스 +%d · 낙인 +1" % [int(buff_vals["atk"]), float(buff_vals["crit"]), exp_stress], 11, UiKit.TEXT2))
	var btn_buff := UiKit.gothic_button("원정 축복 착취", UiKit.RED if can_buff else UiKit.BORDER)
	btn_buff.custom_minimum_size = Vector2(0, 38)
	btn_buff.focus_mode = Control.FOCUS_ALL
	btn_buff.disabled = not can_buff
	btn_buff.pressed.connect(func():
		_confirm_exploit(selected, GameState.RELIC_STATE_EXPLOITED_BUFF, "다음 1회 원정 ATK +%d · CRIT +%.1f%%" % [int(buff_vals["atk"]), float(buff_vals["crit"])])
	)
	c3v.add_child(btn_buff)
	if not can_buff:
		c3v.add_child(UiKit.label("이미 원정 축복 활성 중", 10, UiKit.TEXT3))
	cards_h.add_child(c3)

	# ── 하단 별도 분리된 보조 액션: 약식 안치 (0G, PAUPER_BURIED) ──
	rv.add_child(UiKit.divider())
	var pauper_row := HBoxContainer.new()
	pauper_row.add_theme_constant_override("separation", 10)
	rv.add_child(pauper_row)
	var p_lbl := UiKit.label("보조 처분: 장례비 없이 약식 안치 시 민심 -2 · 스트레스 회복 0 · 속죄 연대기 미반영", 11, UiKit.TEXT3)
	p_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pauper_row.add_child(p_lbl)
	var btn_pauper := UiKit.button("약식 안치 (0G)", UiKit.BORDER2)
	btn_pauper.custom_minimum_size = Vector2(140, 32)
	btn_pauper.focus_mode = Control.FOCUS_ALL
	btn_pauper.pressed.connect(func():
		var p_body := "대상: [%s] %s (%s Lv.%d)\n• 민심 -2 (예상: %d%% → %d%%)\n• 스트레스 회복 0 · 속죄 연대기 미반영 · 되돌릴 수 없음" % [
			r_grade, r_name, r_job, r_lv, GameState.morale, maxi(0, GameState.morale - GameState.PAUPER_MORALE_LOSS)
		]
		estate.open_confirm_modal("약식 안치 확인 (0G)", p_body, "약식 안치 확정", UiKit.GOLD, func():
			if GameState.memorialize_relic(r_id, true):
				notice = "%s의 유품을 약식 안치했습니다. (민심 -2)" % r_name
				rebuild()
		)
	)
	pauper_row.add_child(btn_pauper)


## 돌이킬 수 없는 원혼 착취 확인 모달(임계·치명 경고 + Before→After 표 + 기본 포커스 [취소])을 표시한다.
func _confirm_exploit(rel: Dictionary, mode: String, gain_summary: String) -> void:
	var r_id: String = str(rel.get("id", ""))
	var r_name: String = str(rel.get("merc_name", ""))
	var r_grade: String = str(rel.get("grade", "일반"))
	var r_lv: int = int(rel.get("level", 1))
	var stress_gain: int = GameState.exploit_permanent_stress_for(r_lv)
	var next_perm: int = clampi(GameState.stress_permanent + stress_gain, 0, GameState.MAX_STRESS)
	var next_total: int = clampi(GameState.stress_resolvable + next_perm, 0, GameState.MAX_STRESS)
	var next_stacks: int = GameState.brand_stacks + 1
	var dm: float = GameState.difficulty_mult()
	var next_rec_pen: float = minf(GameState.CAP_RECRUIT_PEN, float(next_stacks) * 5.0 * dm)
	var next_heal_pen: int = mini(GameState.CAP_HEAL_PEN, int(round(float(next_stacks) * 3.0 * dm)))
	var next_mloss: int = mini(GameState.CAP_MORALE_PEN, int(ceil(float(next_stacks) * 0.5 * dm)))
	var tlv: int = GameState.building_level("치료소")
	var base_heal: int = [50, 62, 74, 82, 90][clampi(tlv, 1, 5) - 1]
	var curse_pen: int = 8 if GameState.active_curses.has("curse_faded_oath") else 0
	var next_heal_rate: int = maxi(GameState.MIN_HEAL_RATE, base_heal - next_heal_pen - curse_pen)

	var body := "대상: %s (%s Lv.%d) → %s\n" % [r_name, r_grade, r_lv, gain_summary]
	if next_total >= GameState.MAX_STRESS:
		body += "\n⚠ 경고: 현 영주가 즉시 몰락하며 세대가 교체됩니다 (착취 효과 미발동)!\n"
	if next_stacks == 3:
		body += "\n⚠ 불신의 낙인 활성: 치료비 +20G, 부상 용병 유기 시 민심 -8\n"
	elif next_stacks == 6:
		body += "\n⚠ 타락한 영주 활성: 정식 추모·영지 회복 커맨드 회복량 -50%\n"
	if next_stacks in [1, 4, 7]:
		var prev_c := 0 if next_stacks == 1 else (1 if next_stacks == 4 else 2)
		body += "⚠ 차기 세대 계승 저주 임계 도달: %d개 → %d개\n" % [prev_c, prev_c + 1]

	body += "\n[Before → After]\n"
	body += "• 영구 스트레스: %d → %d (총 %d/100)\n" % [GameState.stress_permanent, next_perm, next_total]
	body += "• 모집비 할증: +%.0f%% → +%.0f%%\n" % [GameState.brand_recruit_penalty_pct(), next_rec_pen]
	body += "• 치료 성공률: %d%% → %d%%\n" % [GameState.heal_success_rate(), next_heal_rate]
	body += "• 일일 민심 하락: -%d → -%d" % [GameState.brand_daily_morale_loss(), next_mloss]
	if mode == GameState.RELIC_STATE_EXPLOITED_BUFF:
		body += "\n\n※ 원정 축복은 다음 1회 원정 종료 시 철수·전멸 여부와 무관하게 소모됩니다."

	estate.open_confirm_modal("🔥 원혼 착취 확인 (되돌릴 수 없음)", body, "원혼 착취 확정", UiKit.RED, func():
		if GameState.exploit_relic(r_id, mode):
			estate.play_soul_feedback(true)
			# 총 스트레스 100 이상 치명적 몰락 시 후속 rebuild()를 생략해 estate._on_game_over() 전환을 보호한다.
			if GameState.total_stress() >= GameState.MAX_STRESS or not GameState.pending_succession_summary.is_empty():
				return
			notice = "%s의 원혼을 착취했습니다. (%s · 낙인 %d스택)" % [r_name, gain_summary, GameState.brand_stacks]
			rebuild()
	)


## [헌화 의식] 탭: 기존 50G 영령 추모 헌화 의식(EstateCommand) UI를 제공한다.
func _populate_rite_tab(vbox: VBoxContainer) -> void:
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


## [연대기] 탭: 마스터-디테일(좌측 현재/역대 세대 목록 + 우측 선택 세대의 계승 저주·개별 유품 상세 열람).
func _populate_chronicle_tab(vbox: VBoxContainer) -> void:
	var header := UiKit.label(
		"에라델 연대기 · 제 %d대 통치 중 · 누적 정식 추모 %d · 약식 %d · 착취 %d · 보스 봉인 %d회 · 최고 심연 +%d" % [
			GameState.generation_number, GameState.total_memorialized_count, GameState.total_pauper_buried_count,
			GameState.total_exploited_count, GameState.boss_sealed_count, GameState.max_endless_cycle
		],
		12, UiKit.GOLD2
	)
	vbox.add_child(header)

	if GameState.soul_relics.is_empty() and GameState.chronicle_entries.is_empty():
		vbox.add_child(UiKit.label("아직 에라델의 잿빛 돌비에 새겨진 이름이 없습니다.", 12, UiKit.TEXT3))
		return

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	# 좌측: 현재 세대 + 역대 세대 목록 (최신순)
	var left_p := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
	left_p.custom_minimum_size = Vector2(320, 0)
	left_p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_p)
	var lscroll := ScrollContainer.new()
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_p.add_child(lscroll)
	var llist := VBoxContainer.new()
	llist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	llist.add_theme_constant_override("separation", 6)
	lscroll.add_child(llist)

	var cur_btn := UiKit.button("👑 현재 제 %d대 (%d일차 · 유품 %d)" % [GameState.generation_number, GameState.day, GameState.soul_relics.size()], UiKit.GOLD if _selected_chronicle_gen == -1 else UiKit.BORDER)
	cur_btn.custom_minimum_size = Vector2(0, 38)
	cur_btn.focus_mode = Control.FOCUS_ALL
	cur_btn.pressed.connect(func():
		_selected_chronicle_gen = -1
		rebuild()
	)
	llist.add_child(cur_btn)

	for i in range(GameState.chronicle_entries.size() - 1, -1, -1):
		var ce: Dictionary = GameState.chronicle_entries[i]
		var gnum: int = int(ce.get("generation", 1))
		var out_str: String = str(ce.get("outcome", "FALLEN"))
		var tag := "✦속죄봉인" if out_str == "SEALED_ATONEMENT" else ("🔥폭군봉인" if out_str == "SEALED_TYRANT" else "✝몰락")
		var btn := UiKit.button("제 %d대 [%s · %d일]" % [gnum, tag, int(ce.get("days_survived", 1))], UiKit.GOLD if _selected_chronicle_gen == gnum else UiKit.BORDER)
		btn.custom_minimum_size = Vector2(0, 36)
		btn.focus_mode = Control.FOCUS_ALL
		var cap_g: int = gnum
		btn.pressed.connect(func():
			_selected_chronicle_gen = cap_g
			rebuild()
		)
		llist.add_child(btn)

	# 우측: 선택한 세대의 상세 기록
	var right_p := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 10)
	right_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_p)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right_p.add_child(rv)

	var records: Array = []
	var curses_list: Array = []
	if _selected_chronicle_gen == -1:
		rv.add_child(UiKit.title("현재 제 %d대 실시간 기록 (최고 영구 스트레스 %d)" % [GameState.generation_number, GameState.peak_permanent_stress], 14, UiKit.GOLD2))
		records = GameState.soul_relics
		curses_list = GameState.active_curses
	else:
		var chosen: Dictionary = {}
		for ce in GameState.chronicle_entries:
			if int(ce.get("generation", -1)) == _selected_chronicle_gen:
				chosen = ce
				break
		if chosen.is_empty():
			rv.add_child(UiKit.label("선택한 세대 기록을 찾을 수 없습니다.", 12, UiKit.TEXT3))
			return
		rv.add_child(UiKit.title("제 %d대 (%s · 통치 %d일 · 최고 영구 스트레스 %d)" % [
			int(chosen.get("generation", 1)), str(chosen.get("outcome", "FALLEN")),
			int(chosen.get("days_survived", 1)), int(chosen.get("peak_permanent_stress", 0))
		], 14, UiKit.GOLD2))
		rv.add_child(UiKit.label("정식 추모 %d회 · 약식 안치 %d회 · 원혼 착취 %d회 · 미처리 마감 %d건" % [
			int(chosen.get("memorialized_count", 0)), int(chosen.get("pauper_buried_count", 0)),
			int(chosen.get("exploited_count", 0)), int(chosen.get("expired_count", 0))
		], 11, UiKit.TEXT2))
		records = chosen.get("relic_records", [])
		curses_list = chosen.get("inherited_curses", [])

	if not curses_list.is_empty():
		var cnames: PackedStringArray = []
		for cid in curses_list:
			var info: Dictionary = GameState.CURSE_INFO.get(str(cid), {"name": str(cid)})
			cnames.append(str(info["name"]))
		rv.add_child(UiKit.label("짊어진 계승 저주: %s" % ", ".join(cnames), 11, UiKit.RED.lightened(0.2)))

	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(rscroll)
	var rlist := VBoxContainer.new()
	rlist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rlist.add_theme_constant_override("separation", 5)
	rscroll.add_child(rlist)

	if records.is_empty():
		var empty_msg := "10세대 이전 압축 기록 — 집계 수치만 보존되어 있습니다." if _selected_chronicle_gen != -1 else "현 세대에 기록된 유품이 없습니다."
		rlist.add_child(UiKit.label(empty_msg, 11, UiKit.TEXT3))
		return

	var state_labels := {
		GameState.RELIC_STATE_UNRESOLVED: "미처리",
		GameState.RELIC_STATE_MEMORIALIZED: "정식 추모 (안치됨)",
		GameState.RELIC_STATE_PAUPER_BURIED: "약식 안치 (0G)",
		GameState.RELIC_STATE_EXPLOITED_SUPPRESS: "착취 — 균열 억제",
		GameState.RELIC_STATE_EXPLOITED_BUFF: "착취 — 원정 축복",
		GameState.RELIC_STATE_EXPIRED: "세대 교체 마감",
	}
	for rel in records:
		var st: String = str(rel.get("state", ""))
		var col := UiKit.RED if st.begins_with("EXPLOITED") else (UiKit.BLUE.lightened(0.25) if st == GameState.RELIC_STATE_MEMORIALIZED else UiKit.TEXT2)
		var row := UiKit.panel(UiKit.BG3, col.darkened(0.3), 6)
		row.add_child(UiKit.label("✝ [%s] %s (%s Lv.%d · %d일차 전사) — %s" % [
			str(rel.get("grade", "일반")), str(rel.get("merc_name", "")), str(rel.get("job", "")),
			int(rel.get("level", 1)), int(rel.get("death_day", 1)), str(state_labels.get(st, st))
		], 11, col))
		rlist.add_child(row)
