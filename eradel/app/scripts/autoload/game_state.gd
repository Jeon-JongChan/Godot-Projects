extends Node

## 전역 게임 상태 — 자원, 스트레스, 용병, 영지 운영, 핵심 루프를 관리한다.
## 기획서 6~16장 기반.

signal resources_changed
signal stress_changed
signal roster_changed
signal party_changed
signal game_over

const MAX_PARTY := 5
const MAX_STRESS := 100

const SCENE_TITLE := "res://scenes/flow/title.tscn"
const SCENE_ESTATE := "res://scenes/estate/estate.tscn"
const SCENE_GUILD := "res://scenes/estate/guild.tscn"
const SCENE_PREP := "res://scenes/expedition/expedition_prep.tscn"
const SCENE_DUNGEON := "res://scenes/expedition/dungeon.tscn"
const SCENE_RESULT := "res://scenes/expedition/dungeon_result.tscn"
const SCENE_BUILDING := "res://scenes/estate/building.tscn"
const SCENE_TREATMENT := "res://scenes/estate/treatment.tscn"
const SCENE_GAMEOVER := "res://scenes/flow/game_over.tscn"

const SEASONS := ["봄", "여름", "가을", "겨울"]

# ── 자원 ──
var gold: int = 300
var manastone: int = 2
## 대장간 강화용 철광석 (Iron Ore)
var iron_ore: int = 45
var max_action_points: int = 3
var day: int = 1

# [옵저버] 아래 지표는 어디서 바꾸든 세터가 범위를 보정하고 resources_changed 를 알린다.
# UI 는 시그널만 구독하면 되며, 값을 바꾼 쪽이 화면 갱신을 직접 호출할 필요가 없다.
var action_points: int = 3:
	set(v):
		action_points = maxi(0, v)
		resources_changed.emit()

# ── 영지 지표 ──
var morale: int = 50:          # 민심 0~100
	set(v):
		morale = clampi(v, 0, 100)
		resources_changed.emit()
var dungeon_activity: int = 40: # 던전 활성도 0~100
	set(v):
		dungeon_activity = clampi(v, 0, 100)
		resources_changed.emit()
var monster_tier: int = 0:      # 전멸 누적 시 몬스터 강화 단계
	set(v):
		monster_tier = maxi(0, v)
		resources_changed.emit()

# ── 스트레스 (총합 100 → 게임오버) ──
var stress_resolvable: int = 0
var stress_permanent: int = 0

# ── 용병 ──
var roster: Array[Mercenary] = []
var party: Array[Mercenary] = []
var death_log: Array[Dictionary] = []

# ── 영지 건물 (이름 -> 레벨). 불변 데이터는 BuildingDb 가 공유한다. ──
var buildings := BuildingDb.default_levels()

# ── 마지막 원정 결과 (결과 화면에서 사용) ──
var last_result: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func new_game() -> void:
	gold = 300
	manastone = 2
	max_action_points = 3
	action_points = max_action_points
	day = 1
	morale = 50
	dungeon_activity = 40
	monster_tier = 0
	stress_resolvable = 0
	stress_permanent = 0
	roster.clear()
	party.clear()
	death_log.clear()
	buildings = BuildingDb.default_levels()
	last_result = {}
	# 시작 용병 3명 지급
	for i in 3:
		roster.append(Mercenary.create_random("일반", _rng))


# ── 자원 헬퍼 ──
func can_afford(cost_gold: int, cost_mana: int = 0) -> bool:
	return gold >= cost_gold and manastone >= cost_mana


func spend(cost_gold: int, cost_mana: int = 0) -> bool:
	if not can_afford(cost_gold, cost_mana):
		return false
	gold -= cost_gold
	manastone -= cost_mana
	resources_changed.emit()
	return true


func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)
	resources_changed.emit()


func add_manastone(amount: int) -> void:
	manastone = max(0, manastone + amount)
	resources_changed.emit()


func add_iron_ore(amount: int) -> void:
	iron_ore = max(0, iron_ore + amount)
	resources_changed.emit()


func can_afford_forge(cost_gold: int, cost_ore: int, cost_mana: int) -> bool:
	return gold >= cost_gold and iron_ore >= cost_ore and manastone >= cost_mana


func spend_forge(cost_gold: int, cost_ore: int, cost_mana: int) -> bool:
	if not can_afford_forge(cost_gold, cost_ore, cost_mana):
		return false
	gold -= cost_gold
	iron_ore -= cost_ore
	manastone -= cost_mana
	resources_changed.emit()
	return true


func season() -> String:
	return SEASONS[((day - 1) / 7) % SEASONS.size()]


# ── 스트레스 ──
func total_stress() -> int:
	return clampi(stress_resolvable + stress_permanent, 0, MAX_STRESS)


func add_resolvable_stress(amount: int) -> void:
	stress_resolvable = max(0, stress_resolvable + amount)
	stress_changed.emit()
	_check_game_over()


func add_permanent_stress(amount: int) -> void:
	stress_permanent = max(0, stress_permanent + amount)
	stress_changed.emit()
	_check_game_over()


func stress_stage() -> String:
	var s := total_stress()
	if s >= 100: return "게임 오버"
	if s >= 91: return "붕괴 직전"
	if s >= 71: return "임계"
	if s >= 51: return "동요"
	if s >= 31: return "불안"
	return "안정"


func stress_color() -> Color:
	var s := total_stress()
	if s >= 71: return UiKit.RED
	if s >= 31: return UiKit.GOLD
	return UiKit.GREEN


func _check_game_over() -> void:
	if total_stress() >= MAX_STRESS:
		game_over.emit()


# ── 용병 모집 ──
func recruit(grade: String) -> Mercenary:
	var cost: int = JobDb.RECRUIT_COST.get(grade, 50)
	if action_points <= 0:
		return null
	if not spend(cost):
		return null
	action_points -= 1
	var m := Mercenary.create_random(grade, _rng)
	roster.append(m)
	resources_changed.emit()
	roster_changed.emit()
	return m


# ── 파티 편성 ──
func available_mercs() -> Array[Mercenary]:
	var out: Array[Mercenary] = []
	for m in roster:
		if m.is_available():
			out.append(m)
	return out


func add_to_party(m: Mercenary) -> bool:
	if party.size() >= MAX_PARTY or party.has(m) or not m.is_available():
		return false
	party.append(m)
	party_changed.emit()
	return true


func remove_from_party(m: Mercenary) -> void:
	party.erase(m)
	party_changed.emit()


func party_attack_bonus() -> int:
	return (buildings.get("대장간", 1) - 1) * 2


# ── 치료소 ──
func heal_success_rate() -> int:
	var lv: int = buildings.get("치료소", 1)
	# Lv.1~5 에 따른 치료 성공률: 50%, 62%, 74%, 82%, 90%
	return [50, 62, 74, 82, 90][clampi(lv, 1, 5) - 1]


func injured_mercs() -> Array[Mercenary]:
	var out: Array[Mercenary] = []
	for m in roster:
		if m.penalties.size() > 0 and m.status == Mercenary.Status.READY:
			out.append(m)
	return out


## 패널티 1건 완화 시도. 성공 시 제거, 실패 시 유지. 비용은 항상 소모.
func treat_penalty(m: Mercenary, penalty: String, cost: int) -> bool:
	if not m.penalties.has(penalty):
		return false
	if not spend(cost):
		return false
	var roll := _rng.randi_range(1, 100)
	var ok := roll <= heal_success_rate()
	if ok:
		m.penalties.erase(penalty)
	roster_changed.emit()
	return ok


# ── 건물 ──
func upgrade_cost(building: String) -> Dictionary:
	var lv: int = buildings.get(building, 1)
	return {"gold": lv * 150, "mana": maxi(0, lv - 1)}


func can_upgrade(building: String) -> bool:
	var lv: int = buildings.get(building, 1)
	if lv >= 5:
		return false
	var c := upgrade_cost(building)
	return can_afford(c.gold, c.mana)


func upgrade_building(building: String) -> bool:
	if not can_upgrade(building):
		return false
	var c := upgrade_cost(building)
	if not spend(c.gold, c.mana):
		return false
	var next_lv: int = buildings.get(building, 1) + 1
	buildings[building] = next_lv
	# 구버전 명칭과 상호 동기화 (별칭 표는 BuildingDb 가 소유)
	if BuildingDb.ALIASES.has(building):
		buildings[BuildingDb.ALIASES[building]] = next_lv
	if building == "영주저택" or building == "영주 저택":
		max_action_points = 3 + int((next_lv - 1) / 2)
	resources_changed.emit()
	return true


# ── 원정 / 전투 결과 처리 ──
func generate_monsters() -> Array[Dictionary]:
	var count := _rng.randi_range(3, 5)
	var monsters: Array[Dictionary] = []
	var tier_mult := 1.0 + monster_tier * 0.25
	var act_mult := 1.0 + dungeon_activity / 100.0
	for i in count:
		var hp := int(_rng.randi_range(40, 70) * tier_mult * act_mult)
		var atk := int(_rng.randi_range(8, 16) * tier_mult * act_mult)
		monsters.append({
			"name": "균열 몬스터 %d" % (i + 1),
			"hp": hp, "max_hp": hp, "attack": atk,
		})
	return monsters


func rng() -> RandomNumberGenerator:
	return _rng


## 던전 씬이 전투를 끝낸 뒤 호출. outcome: "clear"/"retreat"/"wipe"
## 사망/실종 처리, 전리품·스트레스·지표 계산 후 last_result 에 저장.
func finalize_expedition(outcome: String, base_gold: int) -> void:
	var dead: Array[Mercenary] = []
	var missing: Array[Mercenary] = []
	var survivors: Array[Mercenary] = []

	for m in party:
		if m.hp <= 0:
			if outcome == "retreat":
				# 철수 시 쓰러진 동료는 실종 → 즉시 판정(20% 귀환)
				if _rng.randi_range(1, 100) <= 20:
					m.hp = max(1, int(m.max_hp * 0.15))
					m.status = Mercenary.Status.READY
					_maybe_add_penalty(m, true)
					survivors.append(m)
				else:
					missing.append(m)
			else:
				dead.append(m)
		else:
			m.status = Mercenary.Status.READY
			if outcome != "wipe":
				_maybe_add_penalty(m, m.hp < m.max_hp * 0.4)
			survivors.append(m)

	if outcome == "wipe":
		dead = party.duplicate()
		survivors.clear()

	# 사망 처리
	var permanent_gain := 0
	for m in dead:
		m.status = Mercenary.Status.DEAD
		permanent_gain += m.permanent_stress_value()
		death_log.append({"name": m.merc_name, "job": m.job, "level": m.level, "day": day})
	for m in missing:
		m.status = Mercenary.Status.MISSING
		death_log.append({"name": m.merc_name, "job": m.job, "level": m.level, "day": day, "missing": true})

	# 전리품
	var gold_gain := 0
	var mana_gain := 0
	match outcome:
		"clear":
			gold_gain = base_gold
			mana_gain = _rng.randi_range(1, 3)
		"retreat":
			gold_gain = int(base_gold * 0.3)
		"wipe":
			gold_gain = 0

	# 스트레스
	var resolvable_delta := 0
	match outcome:
		"clear": resolvable_delta = -8
		"retreat": resolvable_delta = 5
		"wipe": resolvable_delta = 10
	if outcome == "wipe":
		permanent_gain += 20

	# 영지 지표
	var morale_delta := 0
	var activity_delta := 0
	match outcome:
		"clear":
			morale_delta = 5
			activity_delta = -30
		"retreat":
			morale_delta = -5
			activity_delta = 0
		"wipe":
			morale_delta = -15
			activity_delta = 10
			monster_tier += 1

	last_result = {
		"outcome": outcome,
		"survivors": survivors,
		"dead": dead,
		"missing": missing,
		"gold_gain": gold_gain,
		"mana_gain": mana_gain,
		"resolvable_delta": resolvable_delta,
		"permanent_gain": permanent_gain,
		"morale_delta": morale_delta,
		"activity_delta": activity_delta,
	}


func _maybe_add_penalty(m: Mercenary, likely: bool) -> void:
	var chance := 60 if likely else 20
	if _rng.randi_range(1, 100) <= chance:
		var p := JobDb.random_penalty(_rng)
		if not m.penalties.has(p):
			m.penalties.append(p)


## 결과 화면 "영지로 귀환" 시 호출 — 실제 반영 + 날짜 진행 + 게임오버 판정.
func return_to_estate() -> void:
	var r := last_result
	if r.is_empty():
		return
	# 매일 영지 기본 수입 (소프트락 방지)
	add_gold(r.gold_gain + 50)
	add_manastone(r.mana_gain)
	morale = clampi(morale + r.morale_delta, 0, 100)
	dungeon_activity = clampi(dungeon_activity + r.activity_delta, 0, 100)
	add_resolvable_stress(r.resolvable_delta)
	add_permanent_stress(r.permanent_gain)

	# 파티에서 죽거나 실종된 인원 제외, 생존자 복귀
	party.clear()
	party_changed.emit()
	roster_changed.emit()

	# 대기 인원 휴식 자동 회복 및 실종자 귀환 (5% 확률)
	for m in roster:
		if m.status == Mercenary.Status.READY and m.hp > 0:
			m.hp = mini(m.max_hp, m.hp + int(m.max_hp * 0.3))
		elif m.status == Mercenary.Status.MISSING:
			if _rng.randi_range(1, 100) <= 5:
				m.status = Mercenary.Status.READY
				m.hp = max(1, int(m.max_hp * 0.1))

	# 다음 날
	day += 1
	action_points = max_action_points
	# 주점 효과: 매일 해소 스트레스 소폭 감소
	var pub: int = int(buildings.get("주점", 1)) - 1
	if pub > 0:
		stress_resolvable = max(0, stress_resolvable - pub)
		stress_changed.emit()
	resources_changed.emit()

	last_result = {}
	_check_game_over()


## 게임 상태 전체를 저장용 딕셔너리로 직렬화한다.
func to_dict() -> Dictionary:
	var roster_data: Array[Dictionary] = []
	for m in roster:
		roster_data.append(m.to_dict())

	# party에 속한 용병의 roster 인덱스 목록 기록
	var party_indices: Array[int] = []
	for p_merc in party:
		var idx := roster.find(p_merc)
		if idx != -1:
			party_indices.append(idx)

	return {
		"gold": gold,
		"manastone": manastone,
		"iron_ore": iron_ore,
		"action_points": action_points,
		"max_action_points": max_action_points,
		"day": day,
		"morale": morale,
		"dungeon_activity": dungeon_activity,
		"monster_tier": monster_tier,
		"stress_resolvable": stress_resolvable,
		"stress_permanent": stress_permanent,
		"buildings": buildings.duplicate(),
		"death_log": death_log.duplicate(true),
		"roster": roster_data,
		"party_indices": party_indices,
	}


## 저장된 딕셔너리 데이터로부터 게임 상태를 복원한다.
func from_dict(data: Dictionary) -> void:
	gold = int(data.get("gold", 300))
	manastone = int(data.get("manastone", 2))
	iron_ore = int(data.get("iron_ore", 45))
	action_points = int(data.get("action_points", 3))
	max_action_points = int(data.get("max_action_points", 3))
	day = int(data.get("day", 1))
	morale = int(data.get("morale", 50))
	dungeon_activity = int(data.get("dungeon_activity", 40))
	monster_tier = int(data.get("monster_tier", 0))
	stress_resolvable = int(data.get("stress_resolvable", 0))
	stress_permanent = int(data.get("stress_permanent", 0))

	buildings = BuildingDb.default_levels()
	var b_data: Dictionary = data.get("buildings", {})
	for k in b_data:
		buildings[k] = int(b_data[k])

	death_log.clear()
	var d_data: Array = data.get("death_log", [])
	for d in d_data:
		if d is Dictionary:
			death_log.append(d.duplicate(true))

	roster.clear()
	var r_data: Array = data.get("roster", [])
	for m_dict in r_data:
		if m_dict is Dictionary:
			roster.append(Mercenary.from_dict(m_dict))

	party.clear()
	var p_indices: Array = data.get("party_indices", [])
	for idx in p_indices:
		var i := int(idx)
		if i >= 0 and i < roster.size():
			party.append(roster[i])

	last_result = {}

	# 변경 시그널 일괄 방출
	resources_changed.emit()
	stress_changed.emit()
	roster_changed.emit()
	party_changed.emit()
