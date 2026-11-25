class_name DungeonScene
extends Control

## 다키스트 던전 1 스타일의 2D 사이드뷰 턴제 전투 씬.
## 상단 횃불 광원(Torchlight) 미터 게이지 및 원정 퀘스트 배너,
## 2단 고딕 컨트롤 패널(영웅 초상화, 4대 스킬 슬롯, 6대 스탯 그리드, 대장간 장비 정보, 미니맵/전투로그 탭)을 제공하며
## 캐릭터별 턴 진행, 돌진 공격, 피격 넉백, 플로팅 텍스트 등의 역동적인 연출을 수행합니다.

const BattleUnitScene = preload("res://scenes/expedition/entities/battle_unit.gd")
const FloatingTextScene = preload("res://scenes/expedition/entities/floating_text.gd")

## [유한 상태 기계] 전투 진행 단계 정의
enum BattleState { ROUND_START, ALLY_TURN, ALLY_ACTING, MONSTER_TURN, FINISHED }

## 던전 1회 원정 당 돌파해야 하는 총 구역(회랑) 수
const MAX_STAGE: int = 4
## 갈림길 선택 후 목적지까지 걸어가는 연출 시간(초)
const WALK_SEC: float = 2.0

## 목적지 종류 (몬스터/보물/이벤트/상점). 마지막 단계는 보스 고정.
const DEST_TYPES: Array[String] = ["monster", "treasure", "event", "shop"]
## 갈림길 목적지 가중치 (합계 100 — 전투 중심: 몬스터 70%, 이벤트 14%, 보물 10%, 상점 6%)
const DEST_WEIGHTS: Dictionary = {"monster": 70, "event": 14, "treasure": 10, "shop": 6}
const DEST_GLYPH := {"monster": "⚔", "treasure": "💰", "event": "❗", "shop": "🏪", "boss": "☠"}
const DEST_NAME := {"monster": "몬스터", "treasure": "보물", "event": "이벤트", "shop": "상점", "boss": "심연 수호자"}

# ── 노드 및 데이터 ──
var _root: MarginContainer
var _stage_panel: Control
var _stage_content: Control
var _party_units: Array = []
var _monster_units: Array = []

var _current_stage: int = 1
var _monsters_data: Array[Dictionary] = []
var _base_gold: int = 0
var _round: int = 0
var _log: Array[String] = []
var _finished: bool = false
var _is_busy: bool = false

# 탐험 진행 상태: "map"(목적지 선택) / "walk"(이동 중) / "node"(상호작용) / "battle"(전투)
var _phase: String = "map"
var _map_overlay: Control = null
var _dest_choices: Array[String] = []
var _dest_selected: int = -1
## 갈림길에서 고른 목적지를 복도에 보여주는 월드 오브젝트(상자·포털·상인·몬스터 실루엣)
var _marker: DungeonEncounterMarker = null
## 이동 중 영웅들이 걷는 듯 위아래로 흔들리는 트윈 목록
var _walk_bobs: Array[Tween] = []
## 이동 중 미리 뽑아 둔 조우 몬스터를 전투가 그대로 쓰는지 여부(실루엣과 실제 적을 일치시킨다)
var _encounter_ready: bool = false
var _shop_panel: Control = null

# ── 횃불 광원(Torchlight) 시스템 (0 ~ 100) ──
var _torchlight: int = 85
var _dungeon_atmosphere: ColorRect = null

# ── [유한 상태 기계 / 책임 연쇄 / 오브젝트 풀] ──
var _top_bar := DungeonTopBar.new()
var _hero_panel := DungeonHeroPanel.new()
var _minimap := DungeonMinimap.new()
var _fsm: StateMachine = StateMachine.new()
var _dmg_pipeline: DamagePipeline = DamagePipeline.new()
var _ft_pool: ObjectPool = null
var _sfx_pool: ObjectPool = null

# ── 턴 진행 변수 ──
var _current_actor = null
var _selected_target = null
var _auto_play: bool = false

# ── 하단 고딕 UI 패널 참조 ──

# 6대 스탯 라벨들 (ACC, CRIT, DMG, DODGE, PROT, SPD)

# 4개 스킬 아이콘 슬롯 버튼

# 우측 패널 (미니맵 & 전투 로그 탭)


func _ready() -> void:
	UiKit.background(self, UiKit.BG)

	_root = MarginContainer.new()
	_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_root)

	# 1회랑 원정 데이터 생성 (기존 게임 로직 준수 + 다단계 회랑 확장)
	_current_stage = 1
	_monsters_data = []
	_base_gold = 120 + GameState.dungeon_activity + GameState.rng().randi_range(0, 60)
	_log.append("어둠의 균열에 진입했다. 편성 위치는 더 이상 바꿀 수 없다. 갈림길에서 목적지를 선택하라.")

	_build_scene_layout()
	_setup_fsm_and_pools()
	_spawn_units()
	_minimap.refresh(_current_stage, _finished)
	_begin_map_select()


## [유한 상태 기계 & 오브젝트 풀] 전투 상태 전이 표와 데미지 텍스트/효과음 풀을 초기화합니다.
func _setup_fsm_and_pools() -> void:
	_fsm.add(BattleState.ROUND_START, func(): _is_busy = false, Callable(), [BattleState.ROUND_START, BattleState.ALLY_TURN, BattleState.MONSTER_TURN, BattleState.FINISHED])
	_fsm.add(BattleState.ALLY_TURN, func(): _is_busy = false, Callable(), [BattleState.ROUND_START, BattleState.ALLY_ACTING, BattleState.MONSTER_TURN, BattleState.FINISHED])
	_fsm.add(BattleState.ALLY_ACTING, func(): _is_busy = true; _set_controls_enabled(false), Callable(), [BattleState.ROUND_START, BattleState.ALLY_TURN, BattleState.MONSTER_TURN, BattleState.FINISHED])
	_fsm.add(BattleState.MONSTER_TURN, func(): _is_busy = true; _set_controls_enabled(false), Callable(), [BattleState.ROUND_START, BattleState.FINISHED])
	_fsm.add(BattleState.FINISHED, func(): _finished = true; _is_busy = false; _set_controls_enabled(false), Callable(), [BattleState.FINISHED])

	_ft_pool = ObjectPool.new(func(): return FloatingTextScene.new(), _stage_content, 6)
	_sfx_pool = ObjectPool.new(func():
		var p := AudioStreamPlayer.new()
		p.finished.connect(func(): _sfx_pool.release(p))
		return p, self, 4)


## 전체 화면 레이아웃 (상단 다키스트 횃불 및 퀘스트 배너, 중앙 배틀 스테이지, 하단 고딕 2단 패널)을 구성합니다.
func _build_scene_layout() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_root.add_child(vbox)

	# 1. 상단 다키스트 던전 시그니처 횃불 광원 게이지 및 퀘스트 배너 바 (높이 54px)
	var top_bar := _top_bar.build()
	vbox.add_child(top_bar)

	# 2. 중앙 2D 배틀 스테이지 (높이 410px)
	_stage_panel = Control.new()
	_stage_panel.custom_minimum_size = Vector2(1280, 410)
	_stage_panel.size_flags_vertical = SIZE_EXPAND_FILL
	_stage_panel.clip_contents = true
	vbox.add_child(_stage_panel)

	# 화면 흔들림 시 전체 레이아웃에 영향을 주지 않도록 내부 컨테이너 분리
	_stage_content = Control.new()
	_stage_content.set_anchors_preset(PRESET_FULL_RECT)
	_stage_panel.add_child(_stage_content)

	_build_stage_background(_stage_content)
	_dungeon_atmosphere = UiKit.attach_gothic_atmosphere(_stage_panel, 0.44, 0.18, 0.0)
	_top_bar.set_atmosphere(_dungeon_atmosphere)
	_top_bar.update_torchlight(_torchlight)

	# 3. 하단 2단 고딕 다키스트 던전 컨트롤 패널 (높이 256px)
	var bottom_panel := PanelContainer.new()
	bottom_panel.custom_minimum_size = Vector2(1280, 256)
	var bp_sb := StyleBoxFlat.new()
	bp_sb.bg_color = Color("0d0b0a") # 딥 다크 고딕 바탕
	bp_sb.border_color = Color("383025") # 고딕 황동/흑철 테두리
	bp_sb.set_border_width_all(2)
	bottom_panel.add_theme_stylebox_override("panel", bp_sb)
	vbox.add_child(bottom_panel)

	var b_margin := MarginContainer.new()
	b_margin.add_theme_constant_override("margin_left", 14)
	b_margin.add_theme_constant_override("margin_right", 14)
	b_margin.add_theme_constant_override("margin_top", 10)
	b_margin.add_theme_constant_override("margin_bottom", 10)
	bottom_panel.add_child(b_margin)

	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 14)
	b_margin.add_child(bottom_hbox)

	# 하단 좌측: 영웅 정보 박스 (초상화, 스킬 4슬롯, 6대 스탯 그리드, 장비 정보)
	_hero_panel.attack_pressed.connect(_on_attack_pressed)
	_hero_panel.skill_pressed.connect(_on_skill_pressed)
	_hero_panel.defend_pressed.connect(_on_defend_pressed)
	_hero_panel.focus_pressed.connect(_on_focus_pressed)
	bottom_hbox.add_child(_hero_panel.build())

	# 하단 우측: 미니맵 및 전투 로그 탭 전환 박스
	_minimap.auto_turn_pressed.connect(_on_auto_turn_pressed)
	_minimap.retreat_pressed.connect(func(): _end("retreat"))
	var right_box := _minimap.build(MAX_STAGE, _log)
	bottom_hbox.add_child(right_box)


## 3×3 (전열 3 · 중열 3 · 후열 3 = 9칸) 전투 필드 진형 좌표 상수 (석조 바닥 원근 배치)
const ALLY_GRID_COL_X: Array[float] = [440.0, 300.0, 160.0] # [FRONT=0, MID=1, BACK=2]
const ENEMY_GRID_COL_X: Array[float] = [740.0, 880.0, 1020.0] # [적 전열=0, 적 중열=1, 적 후열=2]
const GRID_SLOT_Y: Array[float] = [132.0, 178.0, 224.0] # 석조 바닥 상 / 중 / 하 3단


## 다키스트 던전 특유의 어둡고 음산한 석조 회랑 및 원근 바닥을 그립니다.
func _build_stage_background(parent: Control) -> void:
	var bg_canvas := DungeonCombatBackgroundCanvas.new()
	bg_canvas.set_anchors_preset(PRESET_FULL_RECT)
	bg_canvas.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(bg_canvas)


## 아군 용병들과 적 몬스터 유닛들을 3×3 (전열3·중열3·후열3 = 9칸) 진형 좌표에 배치합니다.
func _spawn_units() -> void:
	_party_units.clear()
	_monster_units.clear()

	# 1. 아군 용병 배치 (각 용병의 row: 전열/중열/후열 × 바닥 상/중/하 3슬롯)
	var row_counts := [0, 0, 0]
	for m in GameState.party:
		var r_idx: int = clampi(m.row, Mercenary.Row.FRONT, Mercenary.Row.BACK)
		var slot_idx: int = mini(row_counts[r_idx], 2)
		row_counts[r_idx] += 1

		var unit = BattleUnitScene.new()
		_stage_content.add_child(unit)

		# 뒤쪽(상단)에서 앞쪽(하단)으로 미세 원근 오프셋을 주어 겹침 없이 바닥에 배치
		var slot_x: float = ALLY_GRID_COL_X[r_idx] + float(slot_idx - 1) * 14.0
		var slot_y: float = GRID_SLOT_Y[slot_idx]
		unit.position = Vector2(slot_x, slot_y)
		unit.base_position = unit.position
		unit.scale = Vector2(0.84, 0.84)
		unit.z_index = slot_idx
		unit.floating_text_pool = _ft_pool
		unit.sfx_pool = _sfx_pool
		unit.setup_as_mercenary(m)
		unit.clicked.connect(_on_unit_clicked)
		_party_units.append(unit)

	# 2. 적 몬스터 배치 (현재 회랑)
	_spawn_stage_monsters()


## 현재 회랑 데이터(_monsters_data)를 바탕으로 적 몬스터 유닛을 우측 3×3 (9칸) 진형에 소환합니다.
func _spawn_stage_monsters() -> void:
	for old_mon in _monster_units:
		if is_instance_valid(old_mon):
			if old_mon.get_parent() == _stage_content:
				_stage_content.remove_child(old_mon)
			old_mon.queue_free()
	_monster_units.clear()

	var monster_count := _monsters_data.size()
	var layout_slots: Array[Vector2i] = []
	match monster_count:
		1:
			layout_slots = [Vector2i(0, 1)]
		2:
			layout_slots = [Vector2i(0, 1), Vector2i(1, 1)]
		3:
			layout_slots = [Vector2i(0, 0), Vector2i(0, 2), Vector2i(1, 1)]
		_:
			for idx in range(monster_count):
				layout_slots.append(Vector2i(int(idx / 3) % 3, idx % 3))

	for i in monster_count:
		var mon: Dictionary = _monsters_data[i]
		var unit = BattleUnitScene.new()
		_stage_content.add_child(unit)

		var cell: Vector2i = layout_slots[i]
		var slot_x: float = ENEMY_GRID_COL_X[clampi(cell.x, 0, 2)] - float(cell.y - 1) * 14.0
		var slot_y: float = GRID_SLOT_Y[clampi(cell.y, 0, 2)]
		unit.position = Vector2(slot_x, slot_y)
		unit.base_position = unit.position
		unit.scale = Vector2(0.84, 0.84)
		unit.z_index = cell.y
		unit.floating_text_pool = _ft_pool
		unit.sfx_pool = _sfx_pool
		unit.setup_as_monster(mon)
		unit.clicked.connect(_on_unit_clicked)
		_monster_units.append(unit)

	_select_default_target()
	_top_bar.set_quest_text("구역: %d/%d · 처치: 0 / %d" % [_current_stage, MAX_STAGE, _monsters_data.size()])


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
	if _finished:
		return
	if unit.is_ally and _phase != "battle":
		_hero_panel.update_hero(unit)
		return
	if _is_busy:
		return
	if not unit.is_ally and not unit.is_dead:
		_set_target(unit)


## 새로운 전투 라운드를 시작합니다. 횃불 광원 감소를 처리합니다.
func _start_next_round() -> void:
	if _finished or not _fsm.go(BattleState.ROUND_START):
		return
	_round += 1
	_top_bar.set_round_text("제 %d 구역 · %d 라운드" % [_current_stage, _round])
	_minimap.set_retreat_disabled(_round < 1)

	# 라운드 경과에 따른 횃불 광원 감소 (긴장감 부여)
	_torchlight = maxi(5, _torchlight - 4)
	_top_bar.update_torchlight(_torchlight)

	_add_log("[제 %d 라운드] 교전이 격화됩니다. (광원 %d%%)" % [_round, _torchlight])
	_run_round_sequence()


## 라운드 내 아군 및 적군의 턴을 순차적으로 관리합니다.
func _run_round_sequence() -> void:
	if _check_battle_end():
		return

	var actor = _get_next_alive_ally()
	if actor != null:
		_fsm.go(BattleState.ALLY_TURN)
		_current_actor = actor
		actor.set_active_turn(true)
		_hero_panel.update_hero(actor)

		if _auto_play:
			_set_controls_enabled(false)
			await get_tree().create_timer(0.2).timeout
			if _fsm.is_in(BattleState.ALLY_TURN) and _current_actor == actor:
				_execute_ally_attack(1.0)
		else:
			_set_controls_enabled(true)
	else:
		_current_actor = null
		_hero_panel.update_hero(null)
		await _run_monsters_turn()

		if not _check_battle_end():
			_auto_play = false
			_reset_round_flags()
			_start_next_round()


## 다음 행동할 아군 유닛을 속도(SPD) 우선순위에 따라 반환합니다.
func _get_next_alive_ally():
	var best = null
	var best_spd := -999
	for unit in _party_units:
		if not unit.is_dead and not unit.get_meta("acted", false):
			var spd: int = unit.merc_data.get_spd() if unit.merc_data != null else 0
			if best == null or spd > best_spd:
				best = unit
				best_spd = spd
	return best


## 라운드 플래그 초기화
func _reset_round_flags() -> void:
	for u in _party_units:
		u.set_meta("acted", false)
	for u in _monster_units:
		u.set_meta("acted", false)


## 1번 스킬: 아군 일반 공격 실행
func _on_attack_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null:
		return
	_execute_ally_attack(1.0, false)


## 2번 스킬: 아군 강타/스킬 공격 실행 (1.4배 피해)
func _on_skill_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null:
		return
	_execute_ally_attack(1.4, true)


## 3번 스킬: 방어 태세 (스트레스 10 진정 및 방어 강화)
func _on_defend_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null or not _fsm.go(BattleState.ALLY_ACTING):
		return

	var actor = _current_actor
	actor.set_meta("acted", true)
	_set_controls_enabled(false)

	_add_log("🛡 %s 이(가) 방어 태세를 취하며 숨을 고른다. (스트레스 -10)" % actor.unit_name)
	actor.heal_stress(10)
	actor.play_defend_effect()

	# 방어 자세 펄스 애니메이션
	var tween := create_tween()
	tween.tween_property(actor, "modulate", Color(1.2, 1.2, 1.5), 0.2)
	tween.tween_property(actor, "modulate", Color.WHITE, 0.2)

	await get_tree().create_timer(0.5).timeout
	actor.set_active_turn(false)
	_is_busy = false

	if _check_battle_end():
		return
	_run_round_sequence()


## 4번 스킬: 집중 (체력 12 회복 및 정신 집중)
func _on_focus_pressed() -> void:
	if _is_busy or _auto_play or _current_actor == null or not _fsm.go(BattleState.ALLY_ACTING):
		return

	var actor = _current_actor
	actor.set_meta("acted", true)
	_set_controls_enabled(false)

	var heal_amt := 12
	actor.current_hp = mini(actor.max_hp, actor.current_hp + heal_amt)
	if actor.merc_data != null:
		actor.merc_data.hp = actor.current_hp
	actor._update_view()

	_add_log("✦ %s 이(가) 집중하여 상처를 수습했다. (+%d HP)" % [actor.unit_name, heal_amt])

	# 치유 플로팅 텍스트 팝업
	var ft: FloatingText = null
	if _ft_pool != null:
		ft = _ft_pool.acquire() as FloatingText
		ft.on_finished = func(n: Node): _ft_pool.release(n)
	else:
		ft = FloatingTextScene.new()
		_stage_content.add_child(ft)
	ft.popup("+%d HP" % heal_amt, Color("2ecc71"), actor.global_position + Vector2(actor.size.x * 0.5, 0), false)

	# 절제된 치유 펄스 연출 (어색한 pixelfx 시트 대신 영웅 본체 에메랄드 글로우 적용)
	var heal_tw := create_tween()
	heal_tw.tween_property(actor, "modulate", Color(0.85, 1.28, 0.92), 0.22)
	heal_tw.tween_property(actor, "modulate", Color.WHITE, 0.28)

	await get_tree().create_timer(0.55).timeout
	actor.set_active_turn(false)
	_is_busy = false

	if _check_battle_end():
		return
	_run_round_sequence()


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
	if _current_actor == null or not _fsm.go(BattleState.ALLY_ACTING):
		return

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

	var eval := _dmg_pipeline.resolve_attack(
		actor.merc_data,
		null,
		int(actor.attack_power),
		multiplier,
		is_skill,
		GameState.party_attack_bonus(),
		GameState.rng(),
		GameState.party_crit_bonus()
	)
	var final_dmg: int = int(eval.get("damage", 1))
	var is_crit: bool = eval.get("is_crit", false)

	var skill_text := "강타!" if is_skill else "공격!"
	_add_log("%s 의 %s → %s 에게 %d 피해%s" % [
		actor.unit_name, skill_text, target.unit_name, final_dmg, " (치명타!)" if is_crit else ""
	])

	# 직업별 공격 모션 및 타격 이펙트 타입을 JobDb 단일 카탈로그에서 조회
	var cat: String = String(actor.category_job)
	if cat.is_empty() and actor.merc_data != null:
		cat = actor.merc_data.category
	var atk_type: String = JobDb.attack_type_for(cat, is_skill)

	actor.play_attack_by_class(target, func():
		target.play_take_damage(final_dmg, is_crit, atk_type)
		if is_crit:
			trigger_screen_shake(7.0, 0.22)
		target.monster_data.hp = target.current_hp
		if target.current_hp <= 0:
			_add_log("☠ %s 처치!" % target.unit_name)
	, is_skill)

	await get_tree().create_timer(0.68).timeout
	actor.set_active_turn(false)

	if target.is_dead:
		_select_default_target()

	_is_busy = false

	if _check_battle_end():
		return

	_run_round_sequence()


## 적 몬스터들의 연속 턴 실행
func _run_monsters_turn() -> void:
	if not _fsm.go(BattleState.MONSTER_TURN):
		return
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

		alive_allies.clear()
		for a in _party_units:
			if not a.is_dead:
				alive_allies.append(a)

		if alive_allies.is_empty():
			break

		var rng := GameState.rng()
		var target = alive_allies[rng.randi_range(0, alive_allies.size() - 1)]
		var eval := _dmg_pipeline.resolve_attack(
			null,
			target.merc_data,
			int(mon.attack_power),
			1.0,
			false,
			0,
			rng
		)
		var dmg: int = int(eval.get("damage", 1))
		var is_crit: bool = eval.get("is_crit", false)

		mon.set_active_turn(true)
		await get_tree().create_timer(0.18).timeout

		_add_log("%s 의 맹공! → %s 에게 %d 피해%s" % [
			mon.unit_name, target.unit_name, dmg, " (치명타!)" if is_crit else ""
		])

		mon.play_melee_attack(target, func():
			target.play_take_damage(dmg, is_crit)
			# 피격 시 아군 스트레스 8 증가 (다키스트 던전 공포 메커니즘)
			target.add_stress(8)
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

	_top_bar.set_quest_text("구역: %d/%d · 처치: %d / %d" % [_current_stage, MAX_STAGE, _monsters_data.size() - alive_monster_count, _monsters_data.size()])

	if alive_monster_count == 0:
		if _current_stage < MAX_STAGE:
			advance_stage_now()
			return true
		_add_log("★ 어둠의 균열 전 구역(%d/%d) 정복 완료!" % [MAX_STAGE, MAX_STAGE])
		_end("clear")
		return true

	if alive_party_count == 0:
		_add_log("✝ 파티가 전멸했다...")
		_end("wipe")
		return true

	return false


## 미니맵의 지정 구역(1~3회랑)에 맞는 몬스터 무리 생성을 GameState 도메인 규칙에 위임합니다.
func _generate_stage_monsters(stage: int) -> Array[Dictionary]:
	return GameState.generate_stage_monsters(stage, MAX_STAGE)


## 현재 회랑 처치 후 다음 회랑으로 전진하고 미니맵 및 다음 적군 웨이브를 갱신합니다.
func advance_stage_now() -> void:
	_current_stage += 1
	_auto_play = false
	_is_busy = false
	_base_gold += 60 * _current_stage

	# 다음 구역 이동 시 생존 아군 짧은 숨고르기 (HP 15% 회복, 스트레스 6 진정)
	for unit in _party_units:
		if is_instance_valid(unit) and not unit.is_dead:
			var rec := maxi(4, int(round(float(unit.max_hp) * 0.15)))
			unit.current_hp = mini(unit.max_hp, unit.current_hp + rec)
			if unit.merc_data != null:
				unit.merc_data.hp = unit.current_hp
			unit.heal_stress(6)
			unit.set_active_turn(false)
			unit._update_view()

	_minimap.refresh(_current_stage, _finished)
	_minimap.switch_right_tab(true)
	_reset_round_flags()
	_add_log("▶ 다음 갈림길(%d/%d)로 전진! (보상 +%dG, 파티 정비 완료)" % [_current_stage, MAX_STAGE, 60 * _current_stage])
	_begin_map_select()


## 스킬 커맨드 버튼 활성화/비활성화 처리
func _set_controls_enabled(enabled: bool) -> void:
	_hero_panel.set_skills_enabled(enabled)
	_minimap.set_auto_disabled(not enabled)


## 로그를 추가하고 UI에 표시합니다.
func _add_log(msg: String) -> void:
	_log.append(msg)
	_minimap.refresh_log()


## 크리티컬 타격 시 화면 흔들림(Screen Shake) 효과를 연출합니다.
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


# ───────────────────────── 탐험 단계: 갈림길 선택 · 이동 · 목적지 상호작용 ─────────────────────────

## 현재 단계의 갈림길(항상 3갈래, 마지막은 보스)을 생성하고 목적지 선택 지도를 표시한다.
func _begin_map_select() -> void:
	if _finished:
		return
	_phase = "map"
	_dest_selected = -1
	_dest_choices.clear()
	if _current_stage >= MAX_STAGE:
		_dest_choices.append("boss")
	else:
		var rng := GameState.rng()
		for i in 3:
			_dest_choices.append(_roll_dest_type(rng))
		# 갈림길 3개 모두 비전투로만 채워지는 현상을 방지하기 위해 최소 1개는 몬스터를 보장한다.
		if not _dest_choices.has("monster"):
			_dest_choices[rng.randi_range(0, 2)] = "monster"
	_minimap.set_retreat_disabled(false)
	_set_controls_enabled(false)
	_top_bar.set_round_text("제 %d 구역 · 갈림길" % _current_stage)
	_top_bar.set_quest_text("구역: %d/%d · 목적지 선택" % [_current_stage, MAX_STAGE])
	for u in _party_units:
		if is_instance_valid(u) and not u.is_dead:
			_hero_panel.update_hero(u)
			break
	_build_map_overlay()


## DEST_WEIGHTS 가중치(몬스터 70 / 이벤트 14 / 보물 10 / 상점 6)에 따라 갈림길 목적지 1개를 추첨한다.
func _roll_dest_type(rng: RandomNumberGenerator) -> String:
	var roll: int = rng.randi_range(1, 100)
	var acc: int = 0
	for key: String in ["monster", "event", "treasure", "shop"]:
		acc += int(DEST_WEIGHTS.get(key, 0))
		if roll <= acc:
			return key
	return "monster"


## 지도 오버레이: 좌측 깃발(현재 위치)에서 3갈래 길이 뻗고 목적지는 선택 전까지 '?'로 가려진다.
func _build_map_overlay() -> void:
	if _map_overlay != null and is_instance_valid(_map_overlay):
		_map_overlay.queue_free()
	_map_overlay = Control.new()
	_map_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_stage_content.add_child(_map_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.02, 0.02, 0.88)
	_map_overlay.add_child(dim)

	var title := UiKit.label("갈림길 — 가고 싶은 길을 선택하세요 (%d / %d)" % [_current_stage, MAX_STAGE], 14, Color("c8a24a"))
	title.position = Vector2(24, 14)
	_map_overlay.add_child(title)

	var flag_pos := Vector2(150, 205)
	var flag := UiKit.label("⚑", 44, Color("ffd700"))
	flag.position = flag_pos + Vector2(-20, -30)
	_map_overlay.add_child(flag)

	var n := _dest_choices.size()
	var ys: Array = [205.0] if n == 1 else [70.0, 205.0, 340.0]
	for i in n:
		var node_pos := Vector2(560, ys[i])
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color("5c5142") if _dest_selected != -1 and _dest_selected != i else Color("c8a24a")
		var mid := Vector2((flag_pos.x + node_pos.x) * 0.5, (flag_pos.y + node_pos.y) * 0.5 + (0 if n == 1 else (-20 if i == 0 else (20 if i == 2 else 0))))
		for k in 13:
			var s := float(k) / 12.0
			line.add_point(flag_pos.lerp(mid, s).lerp(mid.lerp(node_pos - Vector2(55, 0), s), s))
		_map_overlay.add_child(line)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 90)
		btn.size = Vector2(110, 90)
		btn.position = node_pos - Vector2(55, 45)
		btn.add_theme_font_size_override("font_size", 30)
		var type: String = _dest_choices[i]
		var revealed := (_dest_selected == i) or type == "boss"
		var greyed := _dest_selected != -1 and _dest_selected != i
		btn.text = ("%s\n%s" % [DEST_GLYPH[type], DEST_NAME[type]]) if revealed else "?"
		if revealed:
			btn.add_theme_font_size_override("font_size", 22)
		# 한 번 길을 선택하면 선택하지 않은 길은 회색 처리 및 클릭 비활성화(엿보기 방지)
		btn.disabled = greyed
		if greyed or _dest_selected != -1:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.modulate = Color(1, 1, 1, 0.35) if greyed else Color.WHITE
		btn.pressed.connect(_on_dest_selected.bind(i))
		_map_overlay.add_child(btn)

		# 선택한 ? 박스가 뒤집히며 열리는 애니메이션 + 깃발이 선택한 통로를 따라 이동한 뒤 자동 출발
		if _dest_selected == i:
			btn.pivot_offset = btn.size * 0.5
			btn.scale = Vector2(0.08, 1.15)
			btn.modulate = Color(1.45, 1.3, 0.85, 1.0)
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.14).set_delay(0.22)
			tw.tween_property(btn, "modulate", Color.WHITE, 0.35)
			tw.tween_property(flag, "position", node_pos + Vector2(-95, -30), 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			tw.chain().tween_callback(_on_depart_pressed)


## 갈림길 선택: 별도 출발 버튼 없이 ? 박스를 클릭하면 즉시 다른 길이 잠기고 박스 오픈 애니메이션과 함께 자동 출발한다.
func _on_dest_selected(index: int) -> void:
	if _phase != "map" or _finished or _dest_selected != -1:
		return
	_dest_selected = index if _dest_choices[index] != "boss" else 0
	_build_map_overlay()


## 출발 확정: 지도를 닫고 선택한 목적지를 향해 이동을 시작한다.
func _on_depart_pressed() -> void:
	if _phase != "map" or _finished:
		return
	var idx := maxi(_dest_selected, 0)
	_start_walk(_dest_choices[idx])


## 이동 연출: 대표 캐릭터(전열 선두)가 우측으로 이동하고 목적지 오브젝트가 점점 가까워진다.
func _start_walk(type: String) -> void:
	_phase = "walk"
	_minimap.set_retreat_disabled(true)
	if _map_overlay != null and is_instance_valid(_map_overlay):
		_map_overlay.queue_free()
		_map_overlay = null
	_torchlight = maxi(5, _torchlight - 6)
	_top_bar.update_torchlight(_torchlight)
	_add_log("%s 방향으로 통로를 따라 이동한다..." % DEST_NAME[type])

	# 몬스터/보스는 이동 중에 적을 미리 정해 두어, 복도 끝 실루엣이 실제로 만나는 적과 같게 한다
	var mob_tex: Texture2D = null
	if type == "monster" or type == "boss":
		_monsters_data = _generate_stage_monsters(_current_stage)
		_encounter_ready = true
		var first_name: String = str(_monsters_data[0].get("name", "")) if not _monsters_data.is_empty() else ""
		mob_tex = UiKit.get_cached_texture(BattleUnitScene.mob_sprite_path(first_name))

	_clear_marker()
	_marker = DungeonEncounterMarker.new()
	_marker.setup(type, mob_tex)
	_stage_content.add_child(_marker)
	_stage_content.move_child(_marker, 1)  # 배경 바로 위, 유닛 아래
	_marker.approach(WALK_SEC)

	var tw := create_tween().set_parallel(true)
	for i in _party_units.size():
		var u = _party_units[i]
		if is_instance_valid(u):
			var dx := 110.0 if i == 0 else 40.0
			tw.tween_property(u, "position:x", u.base_position.x + dx, WALK_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_start_walk_bob()
	await tw.finished
	if _finished:
		return
	_arrive(type)


## 목적지 도착: 종류에 따라 전투 / 보물 / 이벤트 / 상점 처리로 분기한다.
func _arrive(type: String) -> void:
	_phase = "node"
	_stop_walk_bob()
	var back := create_tween().set_parallel(true)
	for u in _party_units:
		if is_instance_valid(u):
			back.tween_property(u, "position", u.base_position, 0.3)
	match type:
		"monster", "boss":
			_clear_marker(0.18)
			_start_battle()
		"treasure":
			var gold := GameState.rng().randi_range(40, 90) + 20 * _current_stage
			_base_gold += gold
			_add_log("★ 보물 상자를 발견했다! +%dG" % gold)
			_finish_node_after(_marker.play_arrival() + 0.5 if _marker != null else 1.2)
		"event":
			if _marker != null:
				_marker.play_arrival()
			_run_event()
			_finish_node_after(1.6)
		"shop":
			_open_shop()


## 마커를 서서히 지운다.
func _clear_marker(fade_sec: float = 0.3) -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.dismiss(fade_sec)
	_marker = null


## 이동 중 영웅들이 발걸음에 맞춰 위아래로 살짝 흔들리게 한다(유닛마다 박자가 조금씩 다르다).
func _start_walk_bob() -> void:
	_stop_walk_bob()
	for i in _party_units.size():
		var u = _party_units[i]
		if not is_instance_valid(u):
			continue
		var step := 0.13 + 0.012 * i
		var bt := create_tween().set_loops()
		bt.tween_property(u, "position:y", u.base_position.y - 4.0, step).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		bt.tween_property(u, "position:y", u.base_position.y, step).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_walk_bobs.append(bt)


## 걸음 흔들림을 멈추고 유닛을 원래 높이로 되돌린다.
func _stop_walk_bob() -> void:
	for bt in _walk_bobs:
		if bt != null and bt.is_valid():
			bt.kill()
	_walk_bobs.clear()
	for u in _party_units:
		if is_instance_valid(u):
			u.position.y = u.base_position.y


## 몬스터/보스 목적지 전투 개시: 기존 턴제 전투 로직 재사용.
func _start_battle() -> void:
	_phase = "battle"
	_round = 0
	if not _encounter_ready:
		_monsters_data = _generate_stage_monsters(_current_stage)
	_encounter_ready = false
	_spawn_stage_monsters()
	# 어둠 속 실루엣이 걷히며 적이 모습을 드러내는 느낌으로 서서히 나타난다
	for mu in _monster_units:
		if is_instance_valid(mu):
			mu.modulate.a = 0.0
			create_tween().tween_property(mu, "modulate:a", 1.0, 0.25)
	_reset_round_flags()
	_add_log("몬스터 %d마리와 조우했다!" % _monsters_data.size())
	_start_next_round()


## 비전투 목적지 처리 후 잠시 뒤 다음 갈림길로 진행한다.
func _finish_node_after(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
	if _finished:
		return
	_clear_marker()
	_advance_after_node()


## 비전투 노드 완료: 전투 승리 후와 동일하게 단계 전진(회복 포함) 처리.
func _advance_after_node() -> void:
	advance_stage_now()


## 무작위 이벤트: 60% 샘물(HP 회복·스트레스 완화) / 40% 함정(피해·스트레스).
func _run_event() -> void:
	if GameState.rng().randi_range(1, 100) <= 60:
		_heal_party(0.2)
		for u in _party_units:
			if is_instance_valid(u) and not u.is_dead:
				u.heal_stress(8)
		_add_log("✦ 맑은 샘물을 발견했다. 파티 HP +20%, 스트레스 완화.")
	else:
		for u in _party_units:
			if is_instance_valid(u) and not u.is_dead:
				var dmg := maxi(2, int(round(float(u.max_hp) * 0.08)))
				u.current_hp = maxi(1, u.current_hp - dmg)
				if u.merc_data != null:
					u.merc_data.hp = u.current_hp
				u.add_stress(8)
				u._update_view()
		_add_log("☠ 숨겨진 함정이 발동했다! 파티 피해 및 스트레스 +8.")


## 생존 파티원 HP를 최대 체력 비율만큼 회복한다.
func _heal_party(ratio: float) -> void:
	for u in _party_units:
		if is_instance_valid(u) and not u.is_dead:
			u.current_hp = mini(u.max_hp, u.current_hp + maxi(1, int(round(float(u.max_hp) * ratio))))
			if u.merc_data != null:
				u.merc_data.hp = u.current_hp
			u._update_view()


## 상점: 원정 중 획득한 골드로 치료/성수를 구매하고 '나가기'로 다음 갈림길로 진행한다.
func _open_shop() -> void:
	if _shop_panel != null and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
	_shop_panel = UiKit.panel(Color(0.07, 0.06, 0.05, 0.94), UiKit.GOLD, 12)
	_shop_panel.position = Vector2(905, 24)
	_shop_panel.custom_minimum_size = Vector2(340, 0)
	_stage_content.add_child(_shop_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_shop_panel.add_child(v)
	var gold_lbl := UiKit.label("떠돌이 상인 — 보유 %dG" % _base_gold, 14, Color("ffd700"))
	v.add_child(gold_lbl)
	var offers := [
		{"name": "붕대 세트 (파티 HP +25%)", "cost": 40, "kind": "heal"},
		{"name": "성수 (파티 스트레스 -12)", "cost": 30, "kind": "holy"},
	]
	for o in offers:
		var b := UiKit.button("%s — %dG" % [o["name"], o["cost"]], UiKit.GOLD)
		b.disabled = _base_gold < int(o["cost"])
		b.pressed.connect(_shop_buy.bind(str(o["kind"]), int(o["cost"]), str(o["name"])))
		v.add_child(b)
	var leave := UiKit.primary_button("나가기 ▶", UiKit.GREEN)
	leave.pressed.connect(func():
		_shop_panel.queue_free()
		_shop_panel = null
		_clear_marker()
		_advance_after_node())
	v.add_child(leave)


## 상점 구매 처리: 골드를 차감하고 효과(heal/holy)를 적용한 뒤 상점 UI를 갱신한다.
func _shop_buy(kind: String, cost: int, item_name: String) -> void:
	if _base_gold < cost:
		return
	_base_gold -= cost
	if kind == "heal":
		_heal_party(0.25)
	else:
		for u in _party_units:
			if is_instance_valid(u) and not u.is_dead:
				u.heal_stress(12)
	_add_log("🛡 %s 구매 (-%dG)" % [item_name, cost])
	_open_shop()


## 전투 종료 처리 및 결과 씬 전환
func _end(outcome: String) -> void:
	if _finished or not _fsm.go(BattleState.FINISHED):
		return
	_minimap.refresh(_current_stage, _finished)
	_minimap.set_retreat_disabled(true)
	_set_controls_enabled(false)

	# 최종 결과 정산 직전에 모든 파티 유닛의 생존/사망 HP를 merc_data에 확실히 동기화한다.
	for u in _party_units:
		if is_instance_valid(u) and u.merc_data != null:
			u.merc_data.hp = 0 if u.is_dead else maxi(0, u.current_hp)

	GameState.finalize_expedition(outcome, _base_gold)

	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func():
		get_tree().change_scene_to_file(GameState.SCENE_RESULT)
	)
