extends Node

## 영지 2.5D 마을 월드(EstateWorld), 역할별 씬 폴더 구조, 7대 게임 디자인 패턴 통합 검증 러너

var _obs_gold_count: int = 0
var _obs_res_count: int = 0

func _ready() -> void:
	print("\n[TEST] ── Eradel 역할별 씬 구조 & 7대 게임 디자인 패턴 통합 테스트 시작 ──")

	# 0. 역할별 세분화 폴더 씬 로드 검증 (flow / estate / expedition / popups)
	var role_scenes := [
		"res://scenes/flow/title.tscn",
		"res://scenes/flow/game_over.tscn",
		"res://scenes/estate/estate.tscn",
		"res://scenes/estate/guild.tscn",
		"res://scenes/estate/building.tscn",
		"res://scenes/estate/treatment.tscn",
		"res://scenes/expedition/expedition_prep.tscn",
		"res://scenes/expedition/dungeon.tscn",
		"res://scenes/expedition/dungeon_result.tscn",
		"res://scenes/popups/pause_popup.tscn",
		"res://scenes/popups/settings_popup.tscn",
		"res://scenes/popups/save_load_popup.tscn",
	]
	for path in role_scenes:
		var packed := load(path)
		assert(packed != null, "씬 로드 실패: " + path)
	print("  [OK] 0. 역할별 폴더(flow/estate/expedition/popups) 12개 씬 로드 확인 완료")

	# 1. [유한 상태 기계 (FSM)] StateMachine 전이 가드 및 시그널 검증
	var fsm := StateMachine.new(0)
	fsm.add(0, [1])
	fsm.add(1, [2])
	fsm.add(2, [0])
	assert(fsm.can_go(1) and not fsm.can_go(2), "FSM 전이 가드 오류")
	assert(fsm.go(1) and fsm.is_in(1), "FSM 정상 전이 실패")
	assert(not fsm.go(0), "FSM 비허용 전이 차단 실패")
	print("  [OK] 2. 유한 상태 기계(StateMachine) 전이 규칙 검증 완료")

	# 2. [오브젝트 풀 (Object Pool)] ObjectPool 대여/반납 재사용 검증
	var pool_host := Node2D.new()
	add_child(pool_host)
	var ft_script := load("res://scenes/expedition/entities/floating_text.gd")
	var pool := ObjectPool.new(pool_host, func() -> Node: return ft_script.new(), 2)
	assert(pool.created_count() == 2 and pool.free_count() == 2, "풀 사전 생성 수량 불일치")
	var item_a := pool.acquire()
	var item_b := pool.acquire()
	assert(pool.free_count() == 0, "풀 대여 후 여유 수량 불일치")
	pool.release(item_a)
	var item_c := pool.acquire()
	assert(item_c == item_a and pool.created_count() == 2, "풀 반납 노드 재사용 실패")
	pool.release(item_b)
	pool.release(item_c)
	pool_host.queue_free()
	print("  [OK] 3. 오브젝트 풀(ObjectPool) 사전 워밍업 및 재사용 검증 완료")

	# 3. [경량화 패턴 (Flyweight)] BuildingDb 불변 데이터 & UiKit StyleBoxFlat 캐시 검증
	assert(BuildingDb.DEFS.size() == 11, "BuildingDb 11개 정의 불일치")
	var s1 := UiKit.style(Color.BLACK, Color.WHITE, 6, 1, 8, 6)
	var s2 := UiKit.style(Color.BLACK, Color.WHITE, 6, 1, 8, 6)
	assert(s1 == s2 and UiKit.style_cache_size() > 0, "UiKit 스타일 경량화 캐시 공유 실패")
	print("  [OK] 4. 경량화 패턴(BuildingDb & UiKit StyleCache=%d) 공유 검증 완료" % UiKit.style_cache_size())

	# 4. [커맨드 패턴 (Command)] EstateCommand 자격 검사 및 실행 검증
	var gs := get_node("/root/GameState")
	gs.new_game()
	var sanctum_cmds := EstateCommand.catalog("sanctum")
	assert(sanctum_cmds.size() >= 2, "성소 커맨드 카탈로그 누락")
	var bless_cmd: EstateCommand = sanctum_cmds[0]
	var prev_morale: int = gs.morale
	assert(bless_cmd.can_execute(gs), "성소 축복 커맨드 실행 가능 조건 실패")
	assert(bless_cmd.execute(gs), "성소 축복 커맨드 실행 실패")
	assert(gs.morale > prev_morale, "성소 축복 커맨드 사기 증가 미반영")
	print("  [OK] 5. 커맨드 패턴(EstateCommand) 캡슐화 실행 검증 완료")

	# 5. [옵저버 패턴 (Observer)] GameState 리소스 프로퍼티 변경 시그널 검증
	_obs_gold_count = 0
	_obs_res_count = 0
	var on_gold := func(_g: int) -> void: _obs_gold_count += 1
	var on_res := func() -> void: _obs_res_count += 1
	gs.gold_changed.connect(on_gold)
	gs.resources_changed.connect(on_res)
	gs.add_gold(50)
	gs.morale = clampi(gs.morale - 5, 0, 100)
	gs.action_points = gs.action_points - 1
	assert(_obs_gold_count >= 1 and _obs_res_count >= 2, "GameState 옵저버 시그널 발행 누락")
	gs.gold_changed.disconnect(on_gold)
	gs.resources_changed.disconnect(on_res)
	print("  [OK] 6. 옵저버 패턴(GameState 시그널 자동 발행) 검증 완료")

	# 6. [책임 연쇄 (Chain of Responsibility)] DamagePipeline 핸들러 체인 검증
	var pipe := DamagePipeline.create_default()
	var ctx_normal := pipe.evaluate({"atk": 20, "def": 5, "blacksmith_lv": 2, "skill_mult": 1.0, "crit_chance": 0.0})
	var ctx_crit := pipe.evaluate({"atk": 20, "def": 5, "blacksmith_lv": 2, "skill_mult": 1.5, "force_crit": true})
	assert(int(ctx_normal.get("damage", 0)) > 15, "기본+대장간 데미지 파이프라인 계산 오류")
	assert(bool(ctx_crit.get("is_crit", false)) and int(ctx_crit.get("damage", 0)) > int(ctx_normal.get("damage", 0)), "스킬+치명타 데미지 체인 계산 오류")
	print("  [OK] 7. 책임 연쇄(DamagePipeline 4단계 핸들러 체인) 검증 완료")

	# 7. [업데이트 메서드 (Update Method)] & 영지 2.5D 월드 + 11개 대형 팝업 + ESC 체인 검증
	var estate_scene := load("res://scenes/estate/estate.tscn")
	var estate_inst = estate_scene.instantiate()
	add_child(estate_inst)
	assert(estate_inst._terrain_canvas != null, "지형 캔버스 누락")
	assert(estate_inst._building_defs.size() == 11, "건물 정의 11개 불일치")
	assert(estate_inst._buildings_layer.get_child_count() == 11, "생성된 2.5D 건물 노드 11개 불일치")

	# 중앙 집중형 업데이트 메서드 호출 검증
	estate_inst._process(0.16)
	assert(estate_inst._terrain_canvas.time_acc > 0.0, "Update Method(update_tick) 지형 시간 누적 미동작")
	print("  [OK] 1. 업데이트 메서드(EstateWorld -> update_tick 중앙 틱 구동) 검증 완료")

	# 11개 건물 대형 팝업창(1060x600) 오픈 및 ESC 책임 연쇄 닫기 검증
	for def in estate_inst._building_defs:
		estate_inst._open_large_building_popup(def)
		assert(estate_inst._active_modal != null, "%s 대형 팝업 오픈 실패" % def.name)
		assert(estate_inst._interior_canvas != null, "%s 내부 일러스트 캔버스 누락" % def.name)
		estate_inst._process(0.1)
		assert(estate_inst._interior_canvas.time_acc > 0.0, "%s 내부 일러스트 update_tick 미동작" % def.name)
		# ESC 책임 연쇄 훅(try_handle_cancel)으로 닫기 검증
		var handled: bool = estate_inst.try_handle_cancel()
		assert(handled and estate_inst._active_modal == null, "%s try_handle_cancel 팝업 닫기 실패" % def.name)
	print("  [OK] 11개 2.5D 건물 대형 팝업창 & ESC 책임 연쇄 닫기 전수 검증 완료")

	estate_inst.queue_free()
	print("[TEST] ── 역할별 씬 폴더 구조 & 7대 게임 디자인 패턴 통합 테스트 통과! (ALL PASS) ✅ ──\n")
	get_tree().quit(0)
