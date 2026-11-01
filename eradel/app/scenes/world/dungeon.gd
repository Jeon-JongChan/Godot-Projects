class_name DungeonScene
extends Control

## 다키스트 던전 1 스타일의 2D 사이드뷰 턴제 전투 씬.
## 좌측 아군 파티와 우측 적 몬스터들이 대치하며,
## 캐릭터별 턴 진행, 돌진 공격, 피격 넉백, 플로팅 텍스트 등의 역동적인 연출을 제공합니다.

const BattleUnitScene = preload("res://scenes/entities/battle_unit.gd")

# ── 노드 및 데이터 ──
var _root: MarginContainer
var _stage_panel: Control
var _stage_content: Control
var _party_units: Array = []
var _monster_units: Array = []

var _monsters_data: Array[Dictionary] = []
var _base_gold: int = 0
var _round: int = 0
var _log: Array[String] = []
var _finished: bool = false
var _is_busy: bool = false

# ── 턴 진행 변수 ──
var _current_actor = null
var _selected_target = null
var _auto_play: bool = false

# ── 하단 UI 참조 ──
var _hero_info_box: Control
var _cmd_box: Control
var _log_vbox: VBoxContainer
var _log_scroll: ScrollContainer
var _round_label: Label
var _btn_attack: Button
var _btn_skill: Button
var _btn_auto_turn: Button
var _btn_retreat: Button


func _ready() -> void:
	UiKit.background(self, UiKit.BG)

	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)

	# 원정 데이터 생성 (기존 게임 로직 준수)
	_monsters_data = GameState.generate_monsters()
	_base_gold = 120 + GameState.dungeon_activity + GameState.rng().randi_range(0, 60)
	_log.append("어둠의 균열에 들어섰다. 몬스터 %d마리가 모습을 드러낸다." % _monsters_data.size())

	_build_scene_layout()
	_spawn_units()
	_start_next_round()


## 전체 화면 레이아웃 (상단 바, 중앙 고딕 배틀 스테이지, 하단 커맨드 바)을 구성합니다.
func _build_scene_layout() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_root.add_child(vbox)

	# 1. 상단 타이틀 바
	var top_bar := UiKit.top_bar("던전 탐사 — 어둠의 균열")
	vbox.add_child(top_bar)

	# 2. 중앙 2D 배틀 스테이지 (높이 420px)
	_stage_panel = Control.new()
	_stage_panel.custom_minimum_size = Vector2(1280, 420)
	_stage_panel.size_flags_vertical = SIZE_EXPAND_FILL
	_stage_panel.clip_contents = true
	vbox.add_child(_stage_panel)

	# 화면 흔들림 시 VBox 레이아웃에 영향을 주지 않도록 내부 컨테이너 분리
	_stage_content = Control.new()
	_stage_content.set_anchors_preset(PRESET_FULL_RECT)
	_stage_panel.add_child(_stage_content)

	_build_stage_background(_stage_content)

	# 3. 하단 컨트롤 & 커맨드 패널 (높이 250px)
	var bottom_panel := PanelContainer.new()
	bottom_panel.custom_minimum_size = Vector2(1280, 240)
	bottom_panel.add_theme_stylebox_override("panel", UiKit.style(UiKit.BG2, UiKit.BORDER2, 0, 2))
	vbox.add_child(bottom_panel)

	var b_margin := MarginContainer.new()
	b_margin.add_theme_constant_override("margin_left", 20)
	b_margin.add_theme_constant_override("margin_right", 20)
	b_margin.add_theme_constant_override("margin_top", 12)
	b_margin.add_theme_constant_override("margin_bottom", 12)
	bottom_panel.add_child(b_margin)

	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 16)
	b_margin.add_child(bottom_hbox)

	# 하단 좌측: 현재 행동 영웅 카드
	_hero_info_box = _build_hero_panel()
	bottom_hbox.add_child(_hero_info_box)

	# 하단 중앙: 커맨드 버튼군
	_cmd_box = _build_action_commands()
	bottom_hbox.add_child(_cmd_box)

	# 하단 우측: 전투 로그 및 철수
	var log_panel := _build_log_panel()
	bottom_hbox.add_child(log_panel)


## 다키스트 던전 특유의 어둡고 음산한 석벽 및 원근 바닥을 그립니다.
func _build_stage_background(parent: Control) -> void:
	# 어두운 비네팅 배경
	var bg_gradient := ColorRect.new()
	bg_gradient.set_anchors_preset(PRESET_FULL_RECT)
	bg_gradient.color = Color("0d0b09")
	parent.add_child(bg_gradient)

	# 뒷벽 석조 기둥들 (도형으로 분위기 연출)
	for i in range(7):
		var pillar := ColorRect.new()
		pillar.position = Vector2(60 + i * 180, 0)
		pillar.size = Vector2(28, 320)
		pillar.color = Color("15120e")
		parent.add_child(pillar)

	# 바닥 원근 라인 (어두운 지면)
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2(0, 310)
	floor_rect.size = Vector2(1280, 110)
	floor_rect.color = Color("14100b")
	parent.add_child(floor_rect)

	var floor_line := ColorRect.new()
	floor_line.position = Vector2(0, 308)
	floor_line.size = Vector2(1280, 3)
	floor_line.color = Color("2a2016")
	parent.add_child(floor_line)

	# 중앙 대치 구분선 효과 (미세한 어둠의 기운)
	var center_glow := Polygon2D.new()
	center_glow.color = Color(0.3, 0.05, 0.05, 0.12)
	center_glow.polygon = PackedVector2Array([
		Vector2(640, 20), Vector2(670, 310), Vector2(610, 310)
	])
	parent.add_child(center_glow)


## 하단 영웅 정보 패널을 생성합니다.
func _build_hero_panel() -> Control:
	var p := UiKit.panel(UiKit.BG3, UiKit.GOLD, 8)
	p.custom_minimum_size = Vector2(280, 210)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)

	var header := Label.new()
	header.text = "현재 차례인 용병"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", UiKit.GOLD)
	v.add_child(header)

	var name_lbl := Label.new()
	name_lbl.name = "HeroName"
	name_lbl.text = "대기 중..."
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", UiKit.WHITE)
	v.add_child(name_lbl)

	var job_lbl := Label.new()
	job_lbl.name = "HeroJob"
	job_lbl.text = "-"
	job_lbl.add_theme_font_size_override("font_size", 12)
	job_lbl.add_theme_color_override("font_color", UiKit.TEXT2)
	v.add_child(job_lbl)

	var hp_lbl := Label.new()
	hp_lbl.name = "HeroHp"
	hp_lbl.text = "HP: - / -"
	hp_lbl.add_theme_font_size_override("font_size", 13)
	hp_lbl.add_theme_color_override("font_color", UiKit.GREEN)
	v.add_child(hp_lbl)

	var atk_lbl := Label.new()
	atk_lbl.name = "HeroAtk"
	atk_lbl.text = "공격력: -"
	atk_lbl.add_theme_font_size_override("font_size", 12)
	atk_lbl.add_theme_color_override("font_color", UiKit.TEXT)
	v.add_child(atk_lbl)

	return p


## 하단 액션 커맨드 버튼 패널을 생성합니다.
func _build_action_commands() -> Control:
	var p := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
	p.custom_minimum_size = Vector2(340, 210)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)

	_round_label = Label.new()
	_round_label.text = "라운드 1 준비"
	_round_label.add_theme_font_size_override("font_size", 13)
	_round_label.add_theme_color_override("font_color", UiKit.GOLD2)
	v.add_child(_round_label)

	_btn_attack = UiKit.primary_button("⚔ 일반 공격", UiKit.GOLD)
	_btn_attack.custom_minimum_size = Vector2(0, 42)
	_btn_attack.pressed.connect(_on_attack_pressed)
	v.add_child(_btn_attack)

	_btn_skill = UiKit.button("⚡ 강력한 일격 (강타)", UiKit.PURPLE)
	_btn_skill.custom_minimum_size = Vector2(0, 40)
	_btn_skill.pressed.connect(_on_skill_pressed)
	v.add_child(_btn_skill)

	_btn_auto_turn = UiKit.primary_button("▶ 다음 턴 진행 (일괄)", UiKit.GREEN)
	_btn_auto_turn.custom_minimum_size = Vector2(0, 42)
	_btn_auto_turn.pressed.connect(_on_auto_turn_pressed)
	v.add_child(_btn_auto_turn)

	return p


## 하단 전투 로그 및 철수 패널을 생성합니다.
func _build_log_panel() -> Control:
	var p := UiKit.panel(UiKit.BG3, UiKit.BORDER, 8)
	p.size_flags_horizontal = SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)

	var top_h := HBoxContainer.new()
	var log_title := UiKit.label("전투 상황 기록", 12, UiKit.TEXT2)
	log_title.size_flags_horizontal = SIZE_EXPAND_FILL
	top_h.add_child(log_title)

	_btn_retreat = UiKit.button("철수", UiKit.RED)
	_btn_retreat.custom_minimum_size = Vector2(90, 30)
	_btn_retreat.pressed.connect(func(): _end("retreat"))
	top_h.add_child(_btn_retreat)
	v.add_child(top_h)

	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_log_scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_vbox)

	_refresh_log_display()
	return p


## 아군 용병들과 적 몬스터 유닛들을 배틀 스테이지에 소환하고 배치합니다.
func _spawn_units() -> void:
	_party_units.clear()
	_monster_units.clear()

	# 1. 아군 용병 배치 (다키스트 던전 스타일: 좌측 1열 ~ 4/5열)
	# 전위가 오른쪽(중앙 근처), 후위가 왼쪽
	var party_count := GameState.party.size()
	for i in party_count:
		var m: Mercenary = GameState.party[i]
		var unit = BattleUnitScene.new()
		_stage_content.add_child(unit)

		# 위치 계산: 중앙(640)으로부터 좌측으로 정렬
		var slot_x: float = 460.0 - i * 115.0
		var slot_y: float = 175.0
		unit.position = Vector2(slot_x, slot_y)
		unit.base_position = unit.position
		unit.setup_as_mercenary(m)
		unit.clicked.connect(_on_unit_clicked)
		_party_units.append(unit)

	# 2. 적 몬스터 배치 (우측 1열 ~ 4/5열)
	# 전위가 왼쪽(중앙 근처), 후위가 오른쪽
	var monster_count := _monsters_data.size()
	for i in monster_count:
		var mon: Dictionary = _monsters_data[i]
		var unit = BattleUnitScene.new()
		_stage_content.add_child(unit)

		var slot_x: float = 680.0 + i * 115.0
		var slot_y: float = 175.0
		unit.position = Vector2(slot_x, slot_y)
		unit.base_position = unit.position
		unit.setup_as_monster(mon)
		unit.clicked.connect(_on_unit_clicked)
		_monster_units.append(unit)

	# 기본 타겟을 첫 번째 살아있는 몬스터로 지정
	_select_default_target()


## 살아있는 첫 번째 적 몬스터를 기본 타겟으로 설정합니다.
func _select_default_target() -> void:
	for mon in _monster_units:
		if not mon.is_dead:
			_set_target(mon)
			break


## 타겟 유닛을 지정하고 마커를 표시합니다.
func _set_target(target) -> void:
	for m in _monster_units:
		m.set_target_selected(false)
	_selected_target = target
	if target != null:
		target.set_target_selected(true)


## 유닛 클릭 이벤트 핸들러
func _on_unit_clicked(unit) -> void:
	if _is_busy or _finished:
		return
	if not unit.is_ally and not unit.is_dead:
		_set_target(unit)


## 새로운 전투 라운드를 시작합니다.
func _start_next_round() -> void:
	if _finished:
		return
	_round += 1
	_round_label.text = "제 %d 라운드" % _round
	_btn_retreat.disabled = _round < 1
	_add_log("[라운드 %d] 교전이 이어집니다." % _round)

	_run_round_sequence()


## 라운드 내 아군 및 적군의 턴을 순차적으로 관리합니다.
func _run_round_sequence() -> void:
	if _check_battle_end():
		return

	# 살아있는 아군들 중 아직 행동하지 않은 유닛을 찾음
	var actor = _get_next_alive_ally()
	if actor != null:
		_current_actor = actor
		actor.set_active_turn(true)
		_update_hero_panel(actor)

		# 만약 일괄 자동 진행 중이라면 버튼을 비활성화한 채 자동 공격 수행 (연타 방지)
		if _auto_play:
			_set_controls_enabled(false)
			await get_tree().create_timer(0.2).timeout
			if not _is_busy and _current_actor == actor:
				_execute_ally_attack(1.0)
		else:
			_set_controls_enabled(true)
	else:
		# 모든 아군 행동 완료 -> 적 몬스터들의 턴 진행
		_current_actor = null
		_set_controls_enabled(false)
		_update_hero_panel(null)
		await _run_monsters_turn()

		# 라운드 종료 후 다음 라운드로
		if not _check_battle_end():
			_auto_play = false
			_reset_round_flags()
			_start_next_round()


## 다음 행동할 아군 유닛을 반환합니다.
func _get_next_alive_ally():
	for unit in _party_units:
		if not unit.is_dead and not unit.get_meta("acted", false):
			return unit
	return null


## 라운드 플래그 초기화
func _reset_round_flags() -> void:
	for u in _party_units:
		u.set_meta("acted", false)
	for u in _monster_units:
		u.set_meta("acted", false)


## 아군 일반 공격 실행
func _on_attack_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null:
		return
	_execute_ally_attack(1.0)


## 아군 강타/스킬 공격 실행 (1.4배 피해)
func _on_skill_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null:
		return
	_execute_ally_attack(1.4, true)


## 턴 일괄 자동 진행 버튼 핸들러
func _on_auto_turn_pressed() -> void:
	if _is_busy or _auto_play:
		return
	_auto_play = true
	_set_controls_enabled(false)
	if _current_actor != null:
		_execute_ally_attack(1.0)
	else:
		_run_round_sequence()


## 아군 공격 애니메이션 및 데미지 적용
func _execute_ally_attack(multiplier: float = 1.0, is_skill: bool = false) -> void:
	if _current_actor == null or _is_busy:
		return
	_is_busy = true
	_set_controls_enabled(false)

	var target = _selected_target
	if target == null or target.is_dead:
		_select_default_target()
		target = _selected_target

	if target == null:
		_is_busy = false
		_check_battle_end()
		return

	var actor = _current_actor
	actor.set_meta("acted", true)

	var rng := GameState.rng()
	var bonus := GameState.party_attack_bonus()
	var base_dmg: int = int(actor.attack_power) + bonus + rng.randi_range(0, 6)
	var final_dmg: int = int(base_dmg * multiplier)
	var is_crit: bool = rng.randi_range(1, 100) <= (30 if is_skill else 12)
	if is_crit:
		final_dmg = int(final_dmg * 1.5)

	# 돌진 공격 연출
	var skill_text := "강타!" if is_skill else "공격!"
	_add_log("%s 의 %s → %s 에게 %d 피해%s" % [
		actor.unit_name, skill_text, target.unit_name, final_dmg, " (치명타!)" if is_crit else ""
	])

	actor.play_melee_attack(target, func():
		target.play_take_damage(final_dmg, is_crit)
		if is_crit:
			trigger_screen_shake(7.0, 0.22)
		# 몬스터 데이터 동기화
		target.monster_data.hp = target.current_hp
		if target.current_hp <= 0:
			_add_log("☠ %s 처치!" % target.unit_name)
	)

	# 애니메이션 완료 대기 (약 0.65초)
	await get_tree().create_timer(0.68).timeout
	actor.set_active_turn(false)

	if target.is_dead:
		_select_default_target()

	_is_busy = false

	if _check_battle_end():
		return

	# 다음 아군 턴으로 진행
	_run_round_sequence()


## 적 몬스터들의 연속 턴 실행
func _run_monsters_turn() -> void:
	_is_busy = true
	_add_log("--- 몬스터들의 역습! ---")

	var alive_allies: Array = []
	for a in _party_units:
		if not a.is_dead:
			alive_allies.append(a)

	var alive_monsters: Array = []
	for m in _monster_units:
		if not m.is_dead:
			alive_monsters.append(m)

	for mon in alive_monsters:
		if _finished or mon.is_dead:
			continue

		# 타겟 살아있는 아군 재확인
		alive_allies.clear()
		for a in _party_units:
			if not a.is_dead:
				alive_allies.append(a)

		if alive_allies.is_empty():
			break

		var rng := GameState.rng()
		var target = alive_allies[rng.randi_range(0, alive_allies.size() - 1)]
		var dmg: int = mon.attack_power + rng.randi_range(0, 5)
		var is_crit := rng.randi_range(1, 100) <= 10
		if is_crit:
			dmg = int(dmg * 1.4)

		mon.set_active_turn(true)
		await get_tree().create_timer(0.18).timeout

		_add_log("%s 의 맹공! → %s 에게 %d 피해%s" % [
			mon.unit_name, target.unit_name, dmg, " (치명타!)" if is_crit else ""
		])

		mon.play_melee_attack(target, func():
			target.play_take_damage(dmg, is_crit)
			if is_crit:
				trigger_screen_shake(7.0, 0.22)
			if target.merc_data != null:
				target.merc_data.hp = target.current_hp
			if target.current_hp <= 0:
				_add_log("☠ %s 쓰러짐!" % target.unit_name)
		)

		await get_tree().create_timer(0.68).timeout
		mon.set_active_turn(false)
		await get_tree().create_timer(0.12).timeout

		if _check_battle_end():
			_is_busy = false
			return

	_is_busy = false


## 전투 종료 여부를 판정합니다 (승리/전멸).
func _check_battle_end() -> bool:
	if _finished:
		return true

	var alive_party_count := 0
	for u in _party_units:
		if not u.is_dead:
			alive_party_count += 1

	var alive_monster_count := 0
	for u in _monster_units:
		if not u.is_dead:
			alive_monster_count += 1

	if alive_monster_count == 0:
		_add_log("★ 모든 몬스터를 처치했다! 던전 정복!")
		_end("clear")
		return true

	if alive_party_count == 0:
		_add_log("✝ 파티가 전멸했다...")
		_end("wipe")
		return true

	return false


## 영웅 정보 패널 UI를 갱신합니다.
func _update_hero_panel(unit) -> void:
	var name_lbl: Label = _hero_info_box.find_child("HeroName", true, false)
	var job_lbl: Label = _hero_info_box.find_child("HeroJob", true, false)
	var hp_lbl: Label = _hero_info_box.find_child("HeroHp", true, false)
	var atk_lbl: Label = _hero_info_box.find_child("HeroAtk", true, false)

	if unit == null:
		name_lbl.text = "적의 차례"
		name_lbl.add_theme_color_override("font_color", UiKit.RED)
		job_lbl.text = "몬스터 행동 중..."
		hp_lbl.text = "-"
		atk_lbl.text = "-"
	else:
		name_lbl.text = unit.unit_name
		name_lbl.add_theme_color_override("font_color", UiKit.WHITE)
		job_lbl.text = unit.category_job
		hp_lbl.text = "HP: %d / %d" % [unit.current_hp, unit.max_hp]
		atk_lbl.text = "공격력: %d (+%d)" % [unit.attack_power, GameState.party_attack_bonus()]


## 버튼 활성화/비활성화 처리
func _set_controls_enabled(enabled: bool) -> void:
	_btn_attack.disabled = not enabled
	_btn_skill.disabled = not enabled
	_btn_auto_turn.disabled = not enabled


## 로그를 추가하고 UI에 표시합니다.
func _add_log(msg: String) -> void:
	_log.append(msg)
	_refresh_log_display()


## 로그 스크롤 창 갱신
func _refresh_log_display() -> void:
	if _log_vbox == null:
		return
	for c in _log_vbox.get_children():
		c.queue_free()

	var recent := _log.slice(maxi(0, _log.size() - 25))
	for line in recent:
		var col := UiKit.TEXT2
		if line.begins_with("★"): col = UiKit.GOLD2
		elif line.begins_with("☠") or line.begins_with("✝"): col = UiKit.RED
		elif line.begins_with("[라운드"): col = UiKit.GOLD
		elif line.begins_with("---"): col = Color("f08080")
		_log_vbox.add_child(UiKit.label(line, 11, col))

	# 최신 로그로 스크롤
	if _log_scroll:
		_log_scroll.call_deferred("set_v_scroll", 99999)


## 크리티컬 타격 시 화면 흔들림(Screen Shake) 효과를 연출합니다.
## VBox 전체 레이아웃이나 상단 타이틀 바에 영향을 주지 않도록 내부 _stage_content만 흔듭니다.
func trigger_screen_shake(amount: float = 6.0, duration: float = 0.22) -> void:
	if not is_inside_tree() or _stage_content == null:
		return
	var sm = get_node_or_null("/root/SettingsManager")
	if sm != null and not sm.gameplay.get("screen_shake", true):
		return

	var orig_pos := Vector2.ZERO
	var tween := create_tween()
	var steps := 4
	for i in steps:
		var offset := Vector2(randf_range(-amount, amount), randf_range(-amount * 0.6, amount * 0.6))
		tween.tween_property(_stage_content, "position", orig_pos + offset, duration / float(steps * 2))
		tween.tween_property(_stage_content, "position", orig_pos, duration / float(steps * 2))


## 전투 종료 처리 및 결과 씬 전환
func _end(outcome: String) -> void:
	if _finished:
		return
	_finished = true
	_set_controls_enabled(false)
	_btn_retreat.disabled = true

	# 기존 게임 상태 정산 함수 호출
	GameState.finalize_expedition(outcome, _base_gold)

	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func():
		get_tree().change_scene_to_file(GameState.SCENE_RESULT)
	)
