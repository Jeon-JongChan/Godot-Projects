## 모험가 길드 / 용병 모집소 화면 (guild.gd)
## 일반/정예/특수 등급의 신규 용병을 봉인서로 모집하고, 보유 로스터 관리 및 사망/실종 기록을 열람하는 서브 씬.
extends Control

var _root: MarginContainer
var _last_recruited: Mercenary = null


## 화면 진입 시 초기화: 고딕 배경 구성 및 자원/로스터 변경 시그널 연결
func _ready() -> void:
	UiKit.background(self, UiKit.BG)
	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)
	GameState.resources_changed.connect(_rebuild)
	GameState.roster_changed.connect(_rebuild)
	_rebuild()


## UI 재구성: 상단바, 등급별 용병 모집 카드, 최근 모집 용병 알림, 생존 로스터 목록 및 사망/실종 기록 렌더링
func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	vbox.add_child(UiKit.top_bar("모험가 길드", func(): get_tree().change_scene_to_file(GameState.SCENE_ESTATE)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	content.add_child(UiKit.label("\"봉인서를 뜯는 순간, 운명이 결정된다\"", 13, UiKit.TEXT2))

	# 등급별 모집 버튼 행 (일반, 정예, 특수)
	var recruit_row := HBoxContainer.new()
	recruit_row.add_theme_constant_override("separation", 10)
	for grade in ["일반", "정예", "특수"]:
		recruit_row.add_child(_recruit_card(grade))
	content.add_child(recruit_row)

	# 최근 모집 결과 알림 배너
	if _last_recruited:
		var note := UiKit.panel(Color("1a2a1e"), UiKit.GREEN)
		var nv := VBoxContainer.new()
		note.add_child(nv)
		nv.add_child(UiKit.label("새 용병 합류!", 11, UiKit.GREEN))
		nv.add_child(_merc_card(_last_recruited, false))
		content.add_child(note)

	# 생존 용병 명단 스크롤 뷰
	content.add_child(UiKit.label("용병 명단 (%d명)" % GameState.roster.size(), 11, UiKit.TEXT2))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var alive := GameState.roster.filter(func(m): return m.status != Mercenary.Status.DEAD and m.status != Mercenary.Status.MISSING)
	if alive.is_empty():
		grid.add_child(UiKit.label("아직 용병이 없습니다. 모집하세요.", 12, UiKit.TEXT3))
	for m in alive:
		grid.add_child(_merc_card(m, true))

	# 과거 사망 및 실종 영웅 기록
	if GameState.death_log.size() > 0:
		content.add_child(UiKit.label("사망 / 실종 기록 (%d)" % GameState.death_log.size(), 11, UiKit.RED))
		var recent := GameState.death_log.slice(maxi(0, GameState.death_log.size() - 3))
		for rec in recent:
			var txt := "%s — %s Lv.%d (%d일차%s)" % [rec.name, rec.job, rec.level, rec.day, " · 실종" if rec.get("missing", false) else " · 전사"]
			content.add_child(UiKit.label(txt, 11, UiKit.TEXT3))


## 등급별 용병 모집 카드 UI 생성: 등급명, 소모 금화, 모집 실행 버튼
func _recruit_card(grade: String) -> Control:
	var cost: int = JobDb.RECRUIT_COST[grade]
	var color := JobDb.grade_color(grade)
	var p := UiKit.panel(UiKit.BG3, color)
	p.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := UiKit.label("%s 모집" % grade, 14, color.lightened(0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var c := UiKit.label("금화 %d" % cost, 12, UiKit.TEXT2)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var btn := UiKit.button("모집", color)
	btn.disabled = not GameState.can_afford(cost) or GameState.action_points <= 0
	btn.pressed.connect(func(): _on_recruit(grade))
	v.add_child(btn)
	return p


## 용병 모집 실행: GameState.recruit() 호출하여 신규 용병 생성 및 행동력/금화 차감
func _on_recruit(grade: String) -> void:
	var m := GameState.recruit(grade)
	if m:
		_last_recruited = m
	# rebuild 은 roster_changed 시그널로 자동 호출됨


## 단일 용병 정보 카드 UI 생성: UiKit.merc_card 공용 위젯으로 통합
func _merc_card(m: Mercenary, show_status: bool) -> Control:
	var can_fire := show_status and m.status == Mercenary.Status.READY
	return UiKit.merc_card(m, {
		"bg_color": UiKit.BG2,
		"border_color": UiKit.BORDER,
		"portrait_size": 32,
		"grade_in_title": false,
		"grade_chip": true,
		"title_size": 13,
		"subtitle_mode": "full",
		"subtitle_color": JobDb.category_color(m.category),
		"show_penalties": true,
		"right_chip_text": m.status_text() if show_status else "",
		"action_text": "해고" if can_fire else "",
		"action_color": UiKit.RED,
		"on_action": func(target: Mercenary):
			GameState.roster.erase(target)
			GameState.roster_changed.emit(),
	})
