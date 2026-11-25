## 세대 교체 결산 화면 (game_over.gd — SUCCESSION_SUMMARY)
## 영주 총 스트레스 100 도달 시 원자적 세대 교체 결과를 표시하고 차기 세대(제 N+1대) 영지로 복귀한다.
extends Control

const FALL_CAUSE_LABELS: Dictionary = {
	"EXPLOIT": "원혼 착취 과부하",
	"EXPEDITION_RETURN": "원정 귀환 정산",
	"REST_SETTLEMENT": "비상 휴식 정산",
	"ESTATE_COMMAND": "영지 통치 압박",
	"OTHER": "영주 스트레스 100 도달",
}

var _btn_next_gen: Button = null


## PauseManager ESC 체인에서 호출: 결산 화면에서는 일시정지 팝업 침투를 차단한다.
func try_handle_cancel() -> bool:
	return true


## 화면 진입 시 pending_succession_summary 전용 데이터로 결산 화면을 구성한다.
func _ready() -> void:
	var summary: Dictionary = GameState.pending_succession_summary
	if summary.is_empty():
		get_tree().change_scene_to_file.call_deferred(GameState.SCENE_ESTATE)
		return

	UiKit.background(self, Color("0e0808"))
	UiKit.attach_gothic_atmosphere(self, 0.50, 0.22, 0.45)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	root_v.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(root_v)

	var fallen_gen: int = int(summary.get("fallen_generation", 1))
	var next_gen: int = int(summary.get("next_generation", fallen_gen + 1))
	var days_survived: int = int(summary.get("days_survived", 1))
	var cause_key: String = str(summary.get("fall_cause", "OTHER"))
	var cause_text: String = str(FALL_CAUSE_LABELS.get(cause_key, "영주 스트레스 100 도달"))
	var mem_cnt: int = int(summary.get("memorialized_count", 0))
	var pauper_cnt: int = int(summary.get("pauper_buried_count", 0))
	var exp_cnt: int = int(summary.get("exploited_count", 0))
	var expired_cnt: int = int(summary.get("expired_count", 0))
	var peak_stress: int = int(summary.get("peak_permanent_stress", 0))
	var brand_stacks: int = int(summary.get("brand_stacks", 0))
	var max_b_lv: int = int(summary.get("max_building_level", 1))
	var fallen_mercs: int = int(summary.get("total_fallen_mercs", 0))

	# 1. 상단 타이틀
	var tag := UiKit.label("영주 스트레스 100 도달 · %s" % cause_text, 12, UiKit.RED.lightened(0.2))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_v.add_child(tag)

	var title := UiKit.title("제 %d대 영주 몰락 — 에라델의 계승" % fallen_gen, 34, UiKit.GOLD2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_v.add_child(title)

	# 2. 전대 통치 요약
	var summary_line := "통치 %d일  ·  정식 추모 %d회  ·  원혼 착취 %d회  ·  최고 영구 스트레스 %d" % [
		days_survived, mem_cnt, exp_cnt, peak_stress
	]
	if pauper_cnt > 0 or expired_cnt > 0:
		summary_line += "  ·  약식 안치 %d회  ·  미처리 마감 %d건" % [pauper_cnt, expired_cnt]
	var sum_lbl := UiKit.label(summary_line, 13, UiKit.TEXT)
	sum_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_v.add_child(sum_lbl)

	# 3. 유실 vs 보존 2열 대비 블록
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 14)
	root_v.add_child(diff_row)

	var lost_panel := UiKit.panel(Color("1a0e0e"), UiKit.RED.darkened(0.2), 10)
	lost_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lost_panel.add_child(lv)
	lv.add_child(UiKit.title("유실 (초기화)", 14, UiKit.RED.lightened(0.2)))
	lv.add_child(UiKit.label("• 골드·마나석·철광석 및 일차(1일차) 초기화\n• 건물 강화(최고 Lv.%d → Lv.1) · 용병단(전사 %d명) · 장비 초기화\n• 현재 엔드리스 사이클 0으로 초기화" % [max_b_lv, fallen_mercs], 11, UiKit.TEXT2))
	diff_row.add_child(lost_panel)

	var keep_panel := UiKit.panel(Color("101812"), UiKit.GREEN.darkened(0.2), 10)
	keep_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var kv := VBoxContainer.new()
	kv.add_theme_constant_override("separation", 4)
	keep_panel.add_child(kv)
	kv.add_child(UiKit.title("보존 (영구 계승)", 14, UiKit.GREEN.lightened(0.2)))
	kv.add_child(UiKit.label("• 세대 계승: 제 %d대 영주 즉위\n• 기념관 연대기(총 %d세대 기록) 및 누적 도덕 성향\n• 심층 보스 봉인 %d회 · 최고 엔드리스 사이클 %d" % [
		next_gen, GameState.chronicle_entries.size(), GameState.boss_sealed_count, GameState.max_endless_cycle
	], 11, UiKit.TEXT2))
	diff_row.add_child(keep_panel)

	# 4. 계승 저주 카드 영역
	var kept_curses: Array = summary.get("kept_curses", [])
	var new_curses: Array = summary.get("newly_drawn_curses", [])
	var curse_box := UiKit.panel(UiKit.BG2, UiKit.BORDER2, 12)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	curse_box.add_child(cv)
	cv.add_child(UiKit.title("차기 세대 계승 저주 (%d개)" % (kept_curses.size() + new_curses.size()), 15, UiKit.GOLD2))

	if kept_curses.is_empty() and new_curses.is_empty():
		var clean_panel := UiKit.panel(Color("121e16"), UiKit.GREEN, 8)
		clean_panel.add_child(UiKit.label("✨ 계승된 저주 없음 — 전대 영주의 통치가 원혼을 더럽히지 않았습니다.", 13, UiKit.GREEN.lightened(0.2)))
		cv.add_child(clean_panel)
	else:
		var cards_h := HBoxContainer.new()
		cards_h.add_theme_constant_override("separation", 10)
		cv.add_child(cards_h)
		for cid in kept_curses:
			var reason := "[전대 잔존 · 조기 몰락]" if bool(summary.get("is_early_fall", false)) else "[전대 잔존 · 점진 정화]"
			cards_h.add_child(_build_curse_card(str(cid), reason, UiKit.GOLD))
		for cid in new_curses:
			cards_h.add_child(_build_curse_card(str(cid), "[신규 계승 · 착취 %d스택]" % brand_stacks, UiKit.RED))
	root_v.add_child(curse_box)

	# 5. 하단 안내 & 액션 버튼 (0.5s 입력 잠금 후 자동 포커스)
	var save_note := UiKit.label("차기 세대 기록이 자동 저장되었습니다.", 11, UiKit.TEXT3)
	save_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_v.add_child(save_note)

	var btn_box := VBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 8)
	root_v.add_child(btn_box)

	var center_btn := CenterContainer.new()
	btn_box.add_child(center_btn)
	_btn_next_gen = UiKit.primary_button("제 %d대 영지 시작" % next_gen, UiKit.GOLD)
	_btn_next_gen.custom_minimum_size = Vector2(280, 46)
	_btn_next_gen.focus_mode = Control.FOCUS_ALL
	_btn_next_gen.disabled = true
	_btn_next_gen.pressed.connect(_on_start_next_generation)
	center_btn.add_child(_btn_next_gen)

	var center_title := CenterContainer.new()
	btn_box.add_child(center_title)
	var btn_title := UiKit.button("타이틀로 (저장 완료)", UiKit.BORDER)
	btn_title.custom_minimum_size = Vector2(180, 32)
	btn_title.focus_mode = Control.FOCUS_ALL
	btn_title.pressed.connect(func():
		GameState.consume_succession_summary()
		get_tree().change_scene_to_file(GameState.SCENE_TITLE)
	)
	center_title.add_child(btn_title)

	# 연타 스킵 방지를 위해 0.5초 후 주 버튼을 활성화하고 포커스를 부여한다.
	_unlock_primary_button_after_delay()


## 저주 카드 1장을 생성한다.
func _build_curse_card(curse_id: String, badge_text: String, badge_color: Color) -> Control:
	var info: Dictionary = GameState.CURSE_INFO.get(curse_id, {"name": curse_id, "icon": "☠", "desc": ""})
	var p := UiKit.panel(UiKit.BG3, badge_color.darkened(0.2), 8)
	p.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(UiKit.title("%s %s" % [str(info["icon"]), str(info["name"])], 13, UiKit.WHITE))
	v.add_child(UiKit.label(badge_text, 10, badge_color.lightened(0.2)))
	var d := UiKit.label(str(info["desc"]), 11, UiKit.TEXT2)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return p


## 0.5초 입력 잠금 해제 후 [제 N+1대 영지 시작] 버튼에 포커스를 부여한다.
func _unlock_primary_button_after_delay() -> void:
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree() or not is_instance_valid(_btn_next_gen):
		return
	_btn_next_gen.disabled = false
	_btn_next_gen.grab_focus()


## [제 N+1대 영지 시작] 클릭 시 결산 요약을 소비·저장하고 영지 씬으로 복귀한다.
func _on_start_next_generation() -> void:
	GameState.consume_succession_summary()
	get_tree().change_scene_to_file(GameState.SCENE_ESTATE)
