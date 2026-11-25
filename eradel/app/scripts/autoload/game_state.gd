extends Node

## 전역 게임 상태 — 자원, 스트레스, 용병, 영지 운영, 핵심 루프를 관리한다.
## 기획서 6~16장 기반.

signal resources_changed
signal stress_changed
signal roster_changed
signal party_changed
signal relics_changed
signal game_over

const MAX_PARTY := 5
const MAX_STRESS := 100
const TREAT_PENALTY_COST := 80
const TREAT_BRAND_SURCHARGE := 20
const MEMORIAL_COST_GOLD := 25
const PAUPER_MORALE_LOSS := 2
const DAILY_BASE_INCOME := 50

const RELIC_STATE_UNRESOLVED := "UNRESOLVED"
const RELIC_STATE_MEMORIALIZED := "MEMORIALIZED"
const RELIC_STATE_PAUPER_BURIED := "PAUPER_BURIED"
const RELIC_STATE_EXPLOITED_SUPPRESS := "EXPLOITED_SUPPRESS"
const RELIC_STATE_EXPLOITED_BUFF := "EXPLOITED_BUFF"
const RELIC_STATE_EXPIRED := "EXPIRED_ON_SUCCESSION"

const DIFFICULTY_MULTS: Dictionary = {
	"normal": 1.0,
	"hard": 1.5,
	"nightmare": 2.0,
}
const GRADE_MULTS: Dictionary = {
	"일반": 0.7,
	"정예": 1.0,
	"특수": 1.3,
}

const CAP_RECRUIT_PEN := 100.0
const CAP_HEAL_PEN := 45
const MIN_HEAL_RATE := 10
const CAP_MORALE_PEN := 10
const CAP_UNRESOLVED_STRESS := 10
const DAILY_STRESS_PER_RELIC := 2

const CURSE_POOL: Array[String] = [
	"curse_hollow_coffers",
	"curse_ashen_blood",
	"curse_whispering_rift",
	"curse_heavy_crown",
	"curse_faded_oath",
]
const CURSE_INFO: Dictionary = {
	"curse_hollow_coffers": {
		"name": "빈 금고의 망령",
		"icon": "🪙",
		"desc": "원정 전리품 골드 -15% (일일 기본 수입·비상 구제 50G는 면제)",
	},
	"curse_ashen_blood": {
		"name": "잿빛 혈흔",
		"icon": "🩸",
		"desc": "신규 모집 용병 최대 HP -10% (세대 시작 기본 3명 제외)",
	},
	"curse_whispering_rift": {
		"name": "속삭이는 균열",
		"icon": "🌀",
		"desc": "원정 클리어 시 균열 활성도 억제량 축소 (-30% → -20%)",
	},
	"curse_heavy_crown": {
		"name": "무거운 왕관",
		"icon": "👑",
		"desc": "세대 시작 영구 스트레스 +10 (몰락까지 여유 90)",
	},
	"curse_faded_oath": {
		"name": "바랜 맹세",
		"icon": "🕯️",
		"desc": "치료소 성공률 -8%p (최종 하한 10%)",
	},
}
const STACKS_PER_CURSE := 3
const MAX_INHERITED_CURSES := 3
const CLEANSING_BURN_MIN_DAYS := 5
const CLEANSING_BURN_MIN_CLEARS := 2
const MAX_DETAILED_CHRONICLE_GENS := 10
const TYRANNY_THRESHOLD := 0.40
const ENDLESS_SCALE_PER_CYCLE := 0.20
const BOSS_UNLOCK_MAX_ACTIVITY := 30
const BOSS_UNLOCK_MIN_DAY := 10

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

## 배치 정산·초기화·복원 중 중간 시그널 발행 및 조기 게임오버 판정을 억제하는 가드 플래그
var _suppress_signals: bool = false

# [옵저버] 아래 지표는 어디서 바꾸든 세터가 범위를 보정하고 resources_changed 를 알린다.
# UI 는 시그널만 구독하면 되며, 값을 바꾼 쪽이 화면 갱신을 직접 호출할 필요가 없다.
var action_points: int = 3:
	set(v):
		action_points = maxi(0, v)
		if not _suppress_signals:
			resources_changed.emit()

# ── 영지 지표 ──
var morale: int = 50:          # 민심 0~100
	set(v):
		morale = clampi(v, 0, 100)
		if not _suppress_signals:
			resources_changed.emit()
var dungeon_activity: int = 40: # 던전 활성도 0~100
	set(v):
		dungeon_activity = clampi(v, 0, 100)
		if not _suppress_signals:
			resources_changed.emit()
var monster_tier: int = 0:      # 전멸 누적 시 몬스터 강화 단계
	set(v):
		monster_tier = maxi(0, v)
		if not _suppress_signals:
			resources_changed.emit()

# ── 스트레스 (총합 100 → 게임오버) ──
var stress_resolvable: int = 0
var stress_permanent: int = 0
## 현 세대 최고 영구 스트레스 (연대기 기록용)
var peak_permanent_stress: int = 0

# ── 원혼/유품 착취 & 세대 영속 데이터 ──
## 현 세대 전사 용병 유품 목록 (각 항목은 id, merc_name, job, grade, level, death_day, state, resolved_day 보유)
var soul_relics: Array[Dictionary] = []
## 세대 내 1-based 유품 일련번호
var relic_seq: int = 0
## 현 세대 누적 원혼 착취 낙인 스택
var brand_stacks: int = 0
## 다음 1회 원정 파티 전투 버프 상태 (항상 4-키 팩토리 구조 유지)
var active_exploit_buff: Dictionary = {
	"active": false,
	"atk": 0,
	"crit": 0.0,
	"source_relic_id": "",
}
## 난이도 ("normal" / "hard" / "nightmare")
var difficulty_level: String = "normal"
## 전 세대 누적 원혼 착취 횟수
var total_exploited_count: int = 0
## 전 세대 누적 정식 추모(25G, MEMORIALIZED) 횟수
var total_memorialized_count: int = 0
## 전 세대 누적 약식 안치(0G, PAUPER_BURIED) 횟수
var total_pauper_buried_count: int = 0
## 현 세대 활성 계승 저주 ID 목록 (generation-succession 연동)
var active_curses: Array[String] = []
## 현재 통치 세대 번호 (1-based)
var generation_number: int = 1
## 현 세대 원정 클리어 누적 횟수 (저주 세탁 방지 판정용)
var expeditions_cleared_this_gen: int = 0
## 역대 세대 영구 연대기 목록 (memorial-chronicle 연동)
var chronicle_entries: Array[Dictionary] = []
## 누적 심층 보스 봉인 횟수 (rift-seal-endless 연동)
var boss_sealed_count: int = 0
## 현재 세대의 활성 엔드리스 사이클 (세대 교체 시 0 리셋)
var endless_cycle: int = 0
## 전 세대 통산 최고 도달 엔드리스 사이클 (영구 보존)
var max_endless_cycle: int = 0
## 세대 교체 결산 화면(game_over.tscn) 전용 일시 요약 데이터 (비직렬화 transient)
var pending_succession_summary: Dictionary = {}
## 결산 화면을 보지 못하고 재접속했을 때 1회성 안내 배너를 띄우기 위한 플래그
var unseen_succession_notice: bool = false
## 총 스트레스 100 도달 시 자동 세대 교체 실행 여부 (격리 단위 테스트에서만 false 설정)
var auto_succession_enabled: bool = true
## 세대 교체 이중 진입 방지 가드
var _in_succession: bool = false
## 직전 스트레스 100 몰락 원인 태그
var _last_fall_cause: String = "OTHER"
## 6단계 일일 정산(4단계 day+=1 이후) 중 발생한 몰락인지 구분하는 내부 플래그
var _in_daily_settlement_fall: bool = false
## 현재 진행 중인 원정이 심층 보스 봉인 원정인지 여부
var is_boss_expedition: bool = false
## 심층 보스 격파 직후 엔딩 연출에 사용하는 일시 데이터 (비직렬화 transient)
var pending_ending: Dictionary = {}

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


## 원정 축복 버프의 기본 4-키 딕셔너리를 생성해 빈 딕셔너리 접근 오류를 방지한다.
static func _default_exploit_buff() -> Dictionary:
	return {
		"active": false,
		"atk": 0,
		"crit": 0.0,
		"source_relic_id": "",
	}


## 새 게임을 시작하며 모든 런·원혼·카운터 상태를 원자적으로 초기화한다.
func new_game(difficulty: String = "normal") -> void:
	var validated_diff: String = difficulty if DIFFICULTY_MULTS.has(difficulty) else "normal"
	_suppress_signals = true
	gold = 300
	manastone = 2
	iron_ore = 45
	max_action_points = 3
	action_points = max_action_points
	day = 1
	morale = 50
	dungeon_activity = 40
	monster_tier = 0
	stress_resolvable = 0
	stress_permanent = 0
	peak_permanent_stress = 0
	soul_relics.clear()
	relic_seq = 0
	brand_stacks = 0
	active_exploit_buff = _default_exploit_buff()
	difficulty_level = validated_diff
	total_exploited_count = 0
	total_memorialized_count = 0
	total_pauper_buried_count = 0
	active_curses.clear()
	generation_number = 1
	expeditions_cleared_this_gen = 0
	chronicle_entries.clear()
	boss_sealed_count = 0
	endless_cycle = 0
	max_endless_cycle = 0
	pending_succession_summary = {}
	unseen_succession_notice = false
	_in_succession = false
	_last_fall_cause = "OTHER"
	_in_daily_settlement_fall = false
	is_boss_expedition = false
	pending_ending = {}
	roster.clear()
	party.clear()
	death_log.clear()
	buildings = BuildingDb.default_levels()
	last_result = {}
	# 시작 용병 3명 지급
	for i in 3:
		roster.append(Mercenary.create_random("일반", _rng))
	_suppress_signals = false
	resources_changed.emit()
	stress_changed.emit()
	relics_changed.emit()
	roster_changed.emit()
	party_changed.emit()


# ── 자원 헬퍼 ──
func can_afford(cost_gold: int, cost_mana: int = 0) -> bool:
	return gold >= cost_gold and manastone >= cost_mana


func spend(cost_gold: int, cost_mana: int = 0) -> bool:
	if not can_afford(cost_gold, cost_mana):
		return false
	gold -= cost_gold
	manastone -= cost_mana
	if not _suppress_signals:
		resources_changed.emit()
	return true


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	if not _suppress_signals:
		resources_changed.emit()


func add_manastone(amount: int) -> void:
	manastone = maxi(0, manastone + amount)
	if not _suppress_signals:
		resources_changed.emit()


func add_iron_ore(amount: int) -> void:
	iron_ore = maxi(0, iron_ore + amount)
	if not _suppress_signals:
		resources_changed.emit()


func can_afford_forge(cost_gold: int, cost_ore: int, cost_mana: int) -> bool:
	return gold >= cost_gold and iron_ore >= cost_ore and manastone >= cost_mana


func spend_forge(cost_gold: int, cost_ore: int, cost_mana: int) -> bool:
	if not can_afford_forge(cost_gold, cost_ore, cost_mana):
		return false
	gold -= cost_gold
	iron_ore -= cost_ore
	manastone -= cost_mana
	if not _suppress_signals:
		resources_changed.emit()
	return true


func season() -> String:
	return SEASONS[((day - 1) / 7) % SEASONS.size()]


# ── 스트레스 ──
func total_stress() -> int:
	return clampi(stress_resolvable + stress_permanent, 0, MAX_STRESS)


func add_resolvable_stress(amount: int) -> void:
	stress_resolvable = maxi(0, stress_resolvable + amount)
	if not _suppress_signals:
		stress_changed.emit()
		_check_game_over()


func add_permanent_stress(amount: int) -> void:
	stress_permanent = clampi(stress_permanent + amount, 0, MAX_STRESS)
	peak_permanent_stress = maxi(peak_permanent_stress, stress_permanent)
	if not _suppress_signals:
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
	if _suppress_signals:
		return
	if total_stress() >= MAX_STRESS:
		if auto_succession_enabled and not _in_succession and pending_succession_summary.is_empty():
			begin_succession()
		game_over.emit()


## 건물 이름·별칭·유형을 기준으로 현재 영지 건물 레벨을 조회한다 (기본값 1).
func building_level(name_or_type: String) -> int:
	if buildings.has(name_or_type):
		return int(buildings[name_or_type])
	var alias: String = str(BuildingDb.ALIASES.get(name_or_type, ""))
	if alias != "" and buildings.has(alias):
		return int(buildings[alias])
	var def := BuildingDb.by_name_or_alias(name_or_type)
	var def_name: String = str(def.get("name", ""))
	if def_name != "" and buildings.has(def_name):
		return int(buildings[def_name])
	return 1


## 용병모집소 현재 레벨에 따른 신규 모집 용병 초기 최대 체력 보너스를 반환한다.
func guild_recruit_hp_bonus() -> int:
	return maxi(0, building_level("용병모집소") - 1) * 5


# ── 원혼/유품 착취 수식 헬퍼 ──
## 현재 난이도(`difficulty_level`)에 해당하는 낙인 디버프 배율(1.0 / 1.5 / 2.0)을 반환한다.
func difficulty_mult() -> float:
	return float(DIFFICULTY_MULTS.get(difficulty_level, 1.0))


## 용병 등급에 해당하는 착취 효과 배율(0.7 / 1.0 / 1.3, 미등록 등급 0.7 폴백)을 반환한다.
static func grade_mult(grade: String) -> float:
	return float(GRADE_MULTS.get(grade, 0.7))


## 전사 용병 레벨에 따른 착취 추가 영구 스트레스(6~12)를 계산한다.
static func exploit_permanent_stress_for(merc_level: int) -> int:
	var lv: int = maxi(1, merc_level)
	return clampi(6 + int(floor(float(lv) / 2.0)) * 1, 4, 12)


## 전사 용병 레벨·등급에 따른 균열 억제량(5~50)을 계산한다.
static func exploit_suppress_amount_for(merc_level: int, grade: String) -> int:
	var lv: int = maxi(1, merc_level)
	var raw: float = float(10 + lv * 3) * grade_mult(grade)
	return clampi(int(round(raw)), 5, 50)


## 전사 용병 레벨·등급에 따른 원정 축복(ATK/CRIT) 수치를 계산한다.
static func exploit_buff_values_for(merc_level: int, grade: String) -> Dictionary:
	var lv: int = maxi(1, merc_level)
	var gm: float = grade_mult(grade)
	var atk_val: int = maxi(1, int(round((1.0 + float(lv) * 1.2) * gm)))
	var crit_val: float = round((2.0 + float(lv) * 1.5) * gm * 10.0) / 10.0
	return {"atk": atk_val, "crit": crit_val}


## 현 세대 착취 낙인에 따른 모집비 할증율(%, 최대 100%)을 계산한다.
func brand_recruit_penalty_pct() -> float:
	return minf(CAP_RECRUIT_PEN, float(maxi(0, brand_stacks)) * 5.0 * difficulty_mult())


## 현재 영지 민심 구간에 따른 모집비 보정(고양 -10%, 붕괴 +20%)을 반환한다.
func morale_cost_mod_pct() -> float:
	if morale >= 75:
		return -10.0
	if morale == 0:
		return 20.0
	return 0.0


## 등급별 최종 용병 모집비(기본가 × (1 + (낙인 할증 + 민심 보정)/100))를 반환하는 단일 진실 공급원.
func recruit_cost(grade: String) -> int:
	var base_cost: int = int(JobDb.RECRUIT_COST.get(grade, 50))
	var mod_pct: float = brand_recruit_penalty_pct() + morale_cost_mod_pct()
	return maxi(1, int(round(float(base_cost) * (1.0 + mod_pct / 100.0))))


## 현 세대 착취 낙인에 따른 치료소 성공률 감소(%p, 최대 45%p)를 계산한다.
func brand_heal_penalty_pp() -> int:
	return mini(CAP_HEAL_PEN, int(round(float(maxi(0, brand_stacks)) * 3.0 * difficulty_mult())))


## 현 세대 착취 낙인에 따른 일일 민심 하락량(1스택부터 최소 1, 최대 10)을 계산한다.
func brand_daily_morale_loss() -> int:
	if brand_stacks <= 0:
		return 0
	return mini(CAP_MORALE_PEN, int(ceil(float(brand_stacks) * 0.5 * difficulty_mult())))


## 현재 미처리(UNRESOLVED) 유품 개수를 반환한다.
func unresolved_relic_count() -> int:
	var cnt: int = 0
	for rel in soul_relics:
		if str(rel.get("state", "")) == RELIC_STATE_UNRESOLVED:
			cnt += 1
	return cnt


## 미처리 유품 방치로 일일 정산 2단계에 가산되는 해소 스트레스(0~10)를 계산한다.
func unresolved_daily_stress() -> int:
	return mini(CAP_UNRESOLVED_STRESS, maxi(0, unresolved_relic_count()) * DAILY_STRESS_PER_RELIC)


## 정식 추모(25G) 또는 약식 안치(0G) 시 민심·스트레스 회복량(6스택 이상 50% 반감 반영)을 반환한다.
func memorial_restore_values(is_pauper: bool = false) -> Dictionary:
	if is_pauper:
		return {"morale": 0, "stress": 0}
	var mlv: int = clampi(building_level("기념관"), 1, 5)
	var mult: float = 0.5 if brand_stacks >= 6 else 1.0
	var base_m: int = 4 + (mlv - 1) * 2
	var base_s: int = 5 + (mlv - 1) * 2
	return {
		"morale": int(floor(float(base_m) * mult)),
		"stress": int(floor(float(base_s) * mult)),
	}


## 현재 로스터 전체(파티 편성 인원 포함)에서 출진 가능한(READY) 용병 수를 반환한다.
func ready_merc_count() -> int:
	var cnt: int = 0
	for m in roster:
		if m.is_available():
			cnt += 1
	return cnt


## 전멸 소프트락 방지용 비상 구제 '하루 휴식' 실행 가능 여부를 판정한다.
func can_rest_estate_day() -> bool:
	return ready_merc_count() == 0 and (gold < recruit_cost("일반") or action_points <= 0)


# ── 용병 모집 ──
## 지정 등급의 신규 용병을 고용하고 모집소 레벨 체력 보너스 및 잿빛 혈흔 저주를 반영한다.
func recruit(grade: String) -> Mercenary:
	var cost: int = recruit_cost(grade)
	if action_points <= 0:
		return null
	if not spend(cost):
		return null
	action_points -= 1
	var m := Mercenary.create_random(grade, _rng)
	var hp_bonus := guild_recruit_hp_bonus()
	if hp_bonus > 0:
		m.max_hp += hp_bonus
		m.hp = m.max_hp
	if active_curses.has("curse_ashen_blood"):
		m.max_hp = maxi(1, int(round(float(m.max_hp) * 0.9)))
		m.hp = m.max_hp
	roster.append(m)
	resources_changed.emit()
	roster_changed.emit()
	return m


# ── 파티 편성 ──
## 현재 원정에 대기 중이며 파티에 아직 편성되지 않은 가용 용병 목록을 반환한다.
func available_mercs() -> Array[Mercenary]:
	var out: Array[Mercenary] = []
	for m in roster:
		if m.is_available() and not party.has(m):
			out.append(m)
	return out


## 파티 편성 상태에서 해당 위치값(열)에 배치된 인원 수를 반환한다.
func party_row_count(row: int) -> int:
	var n := 0
	for p in party:
		if p.row == row:
			n += 1
	return n


## 용병을 자신의 위치값 열에만 편성한다(열당 최대 3명). 파티 배열은 전열→중열→후열 순으로 유지한다.
func add_to_party(m: Mercenary) -> bool:
	if party.size() >= MAX_PARTY or party.has(m) or not m.is_available():
		return false
	if party_row_count(m.row) >= Mercenary.ROW_SLOTS:
		return false
	# 열 순서를 유지하도록 같은 열 마지막 뒤에 삽입
	var idx := party.size()
	for i in party.size():
		if party[i].row > m.row:
			idx = i
			break
	party.insert(idx, m)
	party_changed.emit()
	return true


func remove_from_party(m: Mercenary) -> void:
	party.erase(m)
	party_changed.emit()


## 대기 상태(READY)인 용병을 영지 로스터에서 해고한다. 부상/패널티 보유 용병 유기 시 민심 하락 마찰을 적용한다.
func dismiss_merc(m: Mercenary) -> bool:
	if m == null or m.status != Mercenary.Status.READY or not roster.has(m):
		return false
	var has_injury: bool = m.penalties.size() > 0
	if party.has(m):
		party.erase(m)
		party_changed.emit()
	roster.erase(m)
	if has_injury:
		var morale_loss: int = 8 if brand_stacks >= 3 else 3
		morale = maxi(0, morale - morale_loss)
	roster_changed.emit()
	return true


## 대장간 레벨에 따른 순수 파티 공격력 보너스(UI 표시용).
func blacksmith_attack_bonus() -> int:
	return (building_level("대장간") - 1) * 2


## 원정 축복 착취 버프에 따른 1회성 파티 공격력 보너스.
func exploit_attack_bonus() -> int:
	return int(active_exploit_buff.get("atk", 0)) if bool(active_exploit_buff.get("active", false)) else 0


## 전투 DamagePipeline에 전달되는 총 파티 공격력 보너스(대장간 + 원정 축복).
func party_attack_bonus() -> int:
	return blacksmith_attack_bonus() + exploit_attack_bonus()


## 전투 DamagePipeline에 전달되는 원정 축복 치명타율 보너스(%).
func party_crit_bonus() -> float:
	return float(active_exploit_buff.get("crit", 0.0)) if bool(active_exploit_buff.get("active", false)) else 0.0


# ── 치료소 ──
## 치료소 1회 치료비(기본 80G, 착취 낙인 3스택 이상 시 +20G 할증)를 반환하는 단일 진실 공급원.
func treat_penalty_cost() -> int:
	return TREAT_PENALTY_COST + (TREAT_BRAND_SURCHARGE if brand_stacks >= 3 else 0)


## 치료소 최종 성공률(레벨 기본치 - 착취 낙인 감소 - 바랜 맹세 저주, 최종 하한 10%)을 반환한다.
func heal_success_rate() -> int:
	var lv: int = building_level("치료소")
	# Lv.1~5 에 따른 기본 치료 성공률: 50%, 62%, 74%, 82%, 90%
	var base_rate: int = [50, 62, 74, 82, 90][clampi(lv, 1, 5) - 1]
	var curse_pen: int = 8 if active_curses.has("curse_faded_oath") else 0
	return maxi(MIN_HEAL_RATE, base_rate - brand_heal_penalty_pp() - curse_pen)


func injured_mercs() -> Array[Mercenary]:
	var out: Array[Mercenary] = []
	for m in roster:
		if m.penalties.size() > 0 and m.status == Mercenary.Status.READY:
			out.append(m)
	return out


## 패널티 1건 완화 시도. cost가 음수(기본값)면 treat_penalty_cost()를 사용한다.
func treat_penalty(m: Mercenary, penalty: String, cost: int = -1) -> bool:
	if m == null or not m.penalties.has(penalty):
		return false
	var actual_cost: int = treat_penalty_cost() if cost < 0 else cost
	if not spend(actual_cost):
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


# ── 심층 보스 봉인 & 엔드리스 (Rift Seal & Endless) ──
## 심층 보스 원정 해금 조건(균열 활성도 30% 이하 또는 10일차 이상) 충족 여부를 반환한다.
func can_enter_boss_expedition() -> bool:
	return dungeon_activity <= BOSS_UNLOCK_MAX_ACTIVITY or day >= BOSS_UNLOCK_MIN_DAY


## 전 세대 누적 착취/추모 기준 폭군 성향 비율(0.0~1.0, 0 나눗셈 방어)을 반환한다.
func tyranny_ratio() -> float:
	var denom: int = maxi(1, total_exploited_count + total_memorialized_count)
	return float(total_exploited_count) / float(denom)


## 심층 보스 격파 시 속죄("ATONEMENT") vs 폭군("TYRANT") 엔딩 분기를 판정한다.
func evaluate_ending_type() -> String:
	# 전사자 발생 후 정식 추모 0회로 약식 안치만 반복한 무예우 런은 속죄 무임승차를 차단한다.
	if total_pauper_buried_count > 0 and total_memorialized_count == 0:
		return "TYRANT"
	if tyranny_ratio() >= TYRANNY_THRESHOLD or brand_stacks >= 4:
		return "TYRANT"
	return "ATONEMENT"


## 현재 엔드리스 사이클에 따른 몬스터 HP/ATK 스케일링 배율(1.0 + 0.20 * cycle)을 반환한다.
func endless_monster_mult() -> float:
	return 1.0 + float(maxi(0, endless_cycle)) * ENDLESS_SCALE_PER_CYCLE


## 심층 보스 격파 시 엔딩을 판정하고 연대기에 봉인 기록을 Upsert 커밋한 뒤 엔딩 요약 딕셔너리를 반환한다.
func seal_rift_boss() -> Dictionary:
	var ending_type: String = evaluate_ending_type()
	var outcome_str: String = "SEALED_ATONEMENT" if ending_type == "ATONEMENT" else "SEALED_TYRANT"
	var gen_mem: int = 0
	var gen_pauper: int = 0
	var gen_exp: int = 0
	var gen_expired: int = 0
	for rel in soul_relics:
		var st: String = str(rel.get("state", ""))
		if st == RELIC_STATE_MEMORIALIZED:
			gen_mem += 1
		elif st == RELIC_STATE_PAUPER_BURIED:
			gen_pauper += 1
		elif st == RELIC_STATE_EXPLOITED_SUPPRESS or st == RELIC_STATE_EXPLOITED_BUFF:
			gen_exp += 1
		elif st == RELIC_STATE_EXPIRED:
			gen_expired += 1

	commit_chronicle_generation({
		"generation": generation_number,
		"days_survived": day,
		"outcome": outcome_str,
		"sealed_boss": true,
		"memorialized_count": gen_mem,
		"pauper_buried_count": gen_pauper,
		"exploited_count": gen_exp,
		"expired_count": gen_expired,
		"peak_permanent_stress": maxi(peak_permanent_stress, stress_permanent),
		"inherited_curses": active_curses.duplicate(),
		"relic_records": soul_relics.duplicate(true),
	})

	pending_ending = {
		"ending_type": ending_type,
		"outcome": outcome_str,
		"tyranny_ratio": tyranny_ratio(),
		"generation": generation_number,
		"day": day,
		"brand_stacks": brand_stacks,
		"total_exploited_count": total_exploited_count,
		"total_memorialized_count": total_memorialized_count,
		"total_pauper_buried_count": total_pauper_buried_count,
		"next_endless_cycle": endless_cycle + 1,
	}
	return pending_ending


## 엔딩 연출 팝업에서 [연대기 계속하기] 선택 시 봉인 카운트·엔드리스 사이클을 증가시키고 저장한다.
func continue_endless_after_seal() -> void:
	if pending_ending.is_empty():
		return
	boss_sealed_count += 1
	endless_cycle += 1
	max_endless_cycle = maxi(max_endless_cycle, endless_cycle)
	pending_ending = {}
	is_boss_expedition = false
	resources_changed.emit()
	save_game()


# ── 원정 / 전투 결과 처리 ──
func generate_monsters() -> Array[Dictionary]:
	var count := _rng.randi_range(3, 5)
	var monsters: Array[Dictionary] = []
	var tier_mult := 1.0 + monster_tier * 0.25
	var act_mult := 1.0 + dungeon_activity / 100.0
	var end_mult := endless_monster_mult()
	for i in count:
		var hp := maxi(1, int(round(float(_rng.randi_range(40, 70)) * tier_mult * act_mult * end_mult)))
		var atk := maxi(1, int(round(float(_rng.randi_range(8, 16)) * tier_mult * act_mult * end_mult)))
		monsters.append({
			"name": "균열 몬스터 %d" % (i + 1),
			"hp": hp, "max_hp": hp, "attack": atk,
		})
	return monsters


## 회랑(스테이지) 번호와 최대 회랑 수에 따라 스케일링된 몬스터 무리(심층 보스전 최종 회랑 포함)를 생성한다.
func generate_stage_monsters(stage: int, max_stage: int = 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = generate_monsters()
	if out.size() > 3:
		out = out.slice(0, 3)
	var stage_mult := 1.0 + float(maxi(0, stage - 1)) * 0.22
	if is_boss_expedition and stage >= max_stage and not out.is_empty():
		var boss_base := out[0]
		var b_hp := maxi(1, int(round(float(boss_base["hp"]) * stage_mult * 2.2)))
		var b_atk := maxi(1, int(round(float(boss_base["attack"]) * stage_mult * 1.45)))
		var boss_list: Array[Dictionary] = [{
			"name": "심연의 군주 (균열 핵)",
			"hp": b_hp, "max_hp": b_hp, "attack": b_atk,
		}]
		if out.size() >= 2:
			var guard := out[1]
			var g_hp := maxi(1, int(round(float(guard["hp"]) * stage_mult)))
			var g_atk := maxi(1, int(round(float(guard["attack"]) * stage_mult)))
			boss_list.append({"name": "심연 근위병", "hp": g_hp, "max_hp": g_hp, "attack": g_atk})
		return boss_list
	var prefix := "심연 수호자" if stage >= max_stage else "제%d회랑 괴수" % stage
	for i in range(out.size()):
		var m := out[i]
		m["hp"] = maxi(1, int(round(float(m["hp"]) * stage_mult)))
		m["max_hp"] = m["hp"]
		m["attack"] = maxi(1, int(round(float(m["attack"]) * stage_mult)))
		m["name"] = "%s %d" % [prefix, i + 1]
	return out


func rng() -> RandomNumberGenerator:
	return _rng


## 던전 출진 단일 진입점: 파티 유효성을 검사하고 파티원 상태를 ON_EXPEDITION으로 통일 전환한다.
func start_expedition(boss_mode: bool = false) -> bool:
	if party.is_empty():
		return false
	if boss_mode and not can_enter_boss_expedition():
		return false
	is_boss_expedition = boss_mode
	for m in party:
		m.status = Mercenary.Status.ON_EXPEDITION
	roster_changed.emit()
	return true


## 던전 씬이 전투를 끝낸 뒤 호출. outcome: "clear"/"retreat"/"wipe"
## 사망/실종 처리, 전리품·스트레스·지표 계산 후 last_result 에 저장.
func finalize_expedition(outcome: String, base_gold: int) -> void:
	if outcome == "clear":
		expeditions_cleared_this_gen += 1
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
			activity_delta = -20 if active_curses.has("curse_whispering_rift") else -30
		"retreat":
			morale_delta = -5
			activity_delta = 0
		"wipe":
			morale_delta = -15
			activity_delta = 10
			monster_tier += 1

	var boss_sealed_now: bool = (outcome == "clear" and is_boss_expedition)
	if boss_sealed_now:
		seal_rift_boss()
	else:
		is_boss_expedition = false

	last_result = {
		"outcome": outcome,
		"boss_sealed": boss_sealed_now,
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

	# 원정 결과(clear/retreat/wipe)와 무관하게 활성 원정 축복 버프를 1회 소비한다.
	if bool(active_exploit_buff.get("active", false)):
		active_exploit_buff = _default_exploit_buff()
		if not _suppress_signals:
			relics_changed.emit()


func _maybe_add_penalty(m: Mercenary, likely: bool) -> void:
	var chance := 60 if likely else 20
	if _rng.randi_range(1, 100) <= chance:
		var p := JobDb.random_penalty(_rng)
		if not m.penalties.has(p):
			m.penalties.append(p)


# ── 원혼/유품 처리 액션 ──
## 지정 ID의 유품 딕셔너리 인덱스를 찾는다 (없으면 -1).
func _find_relic_index(relic_id: String) -> int:
	for i in range(soul_relics.size()):
		if str(soul_relics[i].get("id", "")) == relic_id:
			return i
	return -1


## 미처리 유품을 정식 추모(25G, MEMORIALIZED) 또는 약식 안치(0G, PAUPER_BURIED)로 원자적 마감한다.
func memorialize_relic(relic_id: String, is_pauper: bool = false) -> bool:
	var idx: int = _find_relic_index(relic_id)
	if idx == -1:
		return false
	var relic: Dictionary = soul_relics[idx]
	if str(relic.get("state", "")) != RELIC_STATE_UNRESOLVED:
		return false
	if not is_pauper and gold < MEMORIAL_COST_GOLD:
		return false

	_suppress_signals = true
	relic["state"] = RELIC_STATE_PAUPER_BURIED if is_pauper else RELIC_STATE_MEMORIALIZED
	relic["resolved_day"] = day
	if is_pauper:
		total_pauper_buried_count += 1
		morale = maxi(0, morale - PAUPER_MORALE_LOSS)
	else:
		gold -= MEMORIAL_COST_GOLD
		total_memorialized_count += 1
		var restore := memorial_restore_values(false)
		morale = clampi(morale + int(restore["morale"]), 0, 100)
		stress_resolvable = maxi(0, stress_resolvable - int(restore["stress"]))
	_suppress_signals = false

	relics_changed.emit()
	resources_changed.emit()
	stress_changed.emit()
	save_game()
	return true


## 미처리 유품을 균열 억제(EXPLOITED_SUPPRESS) 또는 원정 축복(EXPLOITED_BUFF) 연료로 원자적 착취한다.
## 착취로 총 스트레스가 100 이상이 되면 효과(버프/억제)를 미적용하고 game_over만 단 1회 발행한다.
func exploit_relic(relic_id: String, mode: String) -> bool:
	if mode != RELIC_STATE_EXPLOITED_SUPPRESS and mode != RELIC_STATE_EXPLOITED_BUFF:
		return false
	var idx: int = _find_relic_index(relic_id)
	if idx == -1:
		return false
	var relic: Dictionary = soul_relics[idx]
	if str(relic.get("state", "")) != RELIC_STATE_UNRESOLVED:
		return false
	if mode == RELIC_STATE_EXPLOITED_SUPPRESS and dungeon_activity <= 0 and monster_tier <= 0:
		return false
	if mode == RELIC_STATE_EXPLOITED_BUFF and bool(active_exploit_buff.get("active", false)):
		return false

	var merc_lv: int = maxi(1, int(relic.get("level", 1)))
	var merc_grade: String = str(relic.get("grade", "일반"))
	var stress_gain: int = exploit_permanent_stress_for(merc_lv)

	_suppress_signals = true
	relic["state"] = mode
	relic["resolved_day"] = day
	brand_stacks += 1
	total_exploited_count += 1
	stress_permanent = clampi(stress_permanent + stress_gain, 0, MAX_STRESS)
	peak_permanent_stress = maxi(peak_permanent_stress, stress_permanent)

	var lethal: bool = total_stress() >= MAX_STRESS
	if not lethal:
		if mode == RELIC_STATE_EXPLOITED_SUPPRESS:
			var sup_amt: int = exploit_suppress_amount_for(merc_lv, merc_grade)
			dungeon_activity = maxi(0, dungeon_activity - sup_amt)
			monster_tier = maxi(0, monster_tier - 1)
		else:
			var bv := exploit_buff_values_for(merc_lv, merc_grade)
			active_exploit_buff = {
				"active": true,
				"atk": int(bv["atk"]),
				"crit": float(bv["crit"]),
				"source_relic_id": relic_id,
			}
	_suppress_signals = false

	if lethal:
		# 치명적 몰락 시 중간 3종 시그널을 생략하고 _check_game_over()만 1회 호출한다.
		_last_fall_cause = "EXPLOIT"
		_in_daily_settlement_fall = false
		_check_game_over()
	else:
		relics_changed.emit()
		stress_changed.emit()
		resources_changed.emit()
		save_game()
	return true


# ── 세대 교체 & 저주 계승 (Generation Succession) ──
## 착취 낙인 스택 수에 따른 기본 계승 저주 개수(0 또는 1..3)를 계산한다.
static func inherited_curse_count(p_brand_stacks: int) -> int:
	if p_brand_stacks <= 0:
		return 0
	var max_c: int = mini(MAX_INHERITED_CURSES, CURSE_POOL.size())
	return clampi(1 + int(floor(float(p_brand_stacks - 1) / float(maxi(1, STACKS_PER_CURSE)))), 1, max_c)


## CURSE_POOL 화이트리스트 필터링 + 중복 제거 + 최대 개수 절단을 수행한다.
static func _sanitize_curses(raw_list: Array) -> Array[String]:
	var out: Array[String] = []
	var max_c: int = mini(MAX_INHERITED_CURSES, CURSE_POOL.size())
	for item in raw_list:
		var cid: String = str(item)
		if CURSE_POOL.has(cid) and not out.has(cid):
			out.append(cid)
			if out.size() >= max_c:
				break
	return out


## 주입된 RNG로 배열을 Fisher-Yates 셔플한 복사본을 반환한다.
static func _fisher_yates_shuffle(items: Array[String], r: RandomNumberGenerator) -> Array[String]:
	var arr: Array[String] = items.duplicate()
	for i in range(arr.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp: String = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


## 기념관 연대기 커밋 계약(동일 세대 보스 봉인 엔트리 존재 시 Upsert, 10세대 초과 시 상세 압축).
func commit_chronicle_generation(snapshot: Dictionary) -> void:
	var gen: int = int(snapshot.get("generation", generation_number))
	var existing_idx: int = -1
	for i in range(chronicle_entries.size()):
		if int(chronicle_entries[i].get("generation", -1)) == gen:
			existing_idx = i
			break

	var entry_copy: Dictionary = snapshot.duplicate(true)
	if existing_idx != -1:
		var cur: Dictionary = chronicle_entries[existing_idx]
		# 보스 봉인 완료 세대가 이후 몰락한 경우 봉인 기록과 outcome을 보존한 채 집계만 갱신한다.
		var was_sealed: bool = bool(cur.get("sealed_boss", false))
		var sealed_outcome: String = str(cur.get("outcome", "FALLEN"))
		cur["days_survived"] = int(entry_copy.get("days_survived", cur.get("days_survived", 1)))
		cur["memorialized_count"] = int(entry_copy.get("memorialized_count", 0))
		cur["pauper_buried_count"] = int(entry_copy.get("pauper_buried_count", 0))
		cur["exploited_count"] = int(entry_copy.get("exploited_count", 0))
		cur["expired_count"] = int(entry_copy.get("expired_count", 0))
		cur["peak_permanent_stress"] = maxi(int(cur.get("peak_permanent_stress", 0)), int(entry_copy.get("peak_permanent_stress", 0)))
		cur["inherited_curses"] = entry_copy.get("inherited_curses", []).duplicate()
		cur["relic_records"] = entry_copy.get("relic_records", []).duplicate(true)
		cur["sealed_boss"] = was_sealed or bool(entry_copy.get("sealed_boss", false))
		if was_sealed and sealed_outcome != "FALLEN":
			cur["outcome"] = sealed_outcome
		else:
			cur["outcome"] = str(entry_copy.get("outcome", "FALLEN"))
	else:
		chronicle_entries.append(entry_copy)

	# 10세대 초과 오래된 엔트리는 상세 relic_records를 비워 세이브 크기를 제한한다.
	var excess: int = chronicle_entries.size() - MAX_DETAILED_CHRONICLE_GENS
	for idx in range(maxi(0, excess)):
		chronicle_entries[idx]["relic_records"] = []


## 현 세대 영주 몰락 시 유품 마감·연대기 Upsert·저주 산출·완전 초기화·자동 저장을 원자적으로 실행한다.
func begin_succession(custom_rng: RandomNumberGenerator = null) -> bool:
	if _in_succession or not pending_succession_summary.is_empty():
		return false
	_in_succession = true

	var r: RandomNumberGenerator = custom_rng if custom_rng != null else _rng
	var fallen_gen: int = generation_number
	var days_survived_at_fall: int = maxi(1, day - 1) if _in_daily_settlement_fall else day
	var fallen_brand_stacks: int = brand_stacks
	var fallen_peak_stress: int = maxi(peak_permanent_stress, stress_permanent)
	var prev_curses: Array[String] = _sanitize_curses(active_curses)
	var prev_clears: int = expeditions_cleared_this_gen
	var prev_endless: int = endless_cycle
	var fallen_mercs_cnt: int = death_log.size()
	var max_b_lv: int = 1
	for k in buildings:
		max_b_lv = maxi(max_b_lv, int(buildings[k]))

	# 2단계: 잔여 UNRESOLVED 유품 선행 마감
	var expired_cnt: int = expire_unresolved_relics(days_survived_at_fall)

	# 현 세대 유품 상태 집계
	var gen_memorialized: int = 0
	var gen_pauper: int = 0
	var gen_exploited: int = 0
	for rel in soul_relics:
		var st: String = str(rel.get("state", ""))
		if st == RELIC_STATE_MEMORIALIZED:
			gen_memorialized += 1
		elif st == RELIC_STATE_PAUPER_BURIED:
			gen_pauper += 1
		elif st == RELIC_STATE_EXPLOITED_SUPPRESS or st == RELIC_STATE_EXPLOITED_BUFF:
			gen_exploited += 1

	# 3단계: 연대기 스냅샷 깊은 복사 Upsert 커밋
	var snapshot: Dictionary = {
		"generation": fallen_gen,
		"days_survived": days_survived_at_fall,
		"outcome": "FALLEN",
		"sealed_boss": false,
		"memorialized_count": gen_memorialized,
		"pauper_buried_count": gen_pauper,
		"exploited_count": gen_exploited,
		"expired_count": expired_cnt,
		"peak_permanent_stress": fallen_peak_stress,
		"inherited_curses": prev_curses.duplicate(),
		"relic_records": soul_relics.duplicate(true),
	}
	commit_chronicle_generation(snapshot)

	# 4단계: 저주 계승 산출 (조기 몰락 전량 유지 vs 정상 통치 무착취 점진 정화)
	var max_c: int = mini(MAX_INHERITED_CURSES, CURSE_POOL.size())
	var base_count: int = inherited_curse_count(fallen_brand_stacks)
	var is_early_fall: bool = (days_survived_at_fall < CLEANSING_BURN_MIN_DAYS) or (prev_clears < CLEANSING_BURN_MIN_CLEARS)
	var kept_curses: Array[String] = []
	var newly_drawn_curses: Array[String] = []

	if is_early_fall and not prev_curses.is_empty():
		# Case A: 조기 몰락 — 기존 저주 전량 유지 + 필요 시 CURSE_POOL \ prev_curses 에서 신규 추첨
		kept_curses = prev_curses.duplicate()
		var target_count: int = clampi(maxi(base_count, kept_curses.size()), 0, max_c)
		var need_new: int = maxi(0, target_count - kept_curses.size())
		if need_new > 0:
			var remaining_pool: Array[String] = []
			for cid in CURSE_POOL:
				if not prev_curses.has(cid):
					remaining_pool.append(cid)
			var shuffled_rem := _fisher_yates_shuffle(remaining_pool, r)
			for i in range(mini(need_new, shuffled_rem.size())):
				newly_drawn_curses.append(shuffled_rem[i])
	elif not is_early_fall and fallen_brand_stacks <= 0 and not prev_curses.is_empty():
		# Case B: 정상 통치 무착취 몰락 — 세대당 최대 1개 점진 정화
		var floor_keep: int = maxi(0, prev_curses.size() - 1)
		if floor_keep > 0:
			var shuffled_prev := _fisher_yates_shuffle(prev_curses, r)
			for i in range(floor_keep):
				kept_curses.append(shuffled_prev[i])
	else:
		# Case C: 정상 통치 (착취 1+ 또는 기존 저주 없음) — CURSE_POOL 전체에서 base_count 추첨
		if base_count > 0:
			var shuffled_all := _fisher_yates_shuffle(CURSE_POOL, r)
			for i in range(mini(base_count, shuffled_all.size())):
				newly_drawn_curses.append(shuffled_all[i])

	var next_curses: Array[String] = []
	next_curses.append_array(kept_curses)
	next_curses.append_array(newly_drawn_curses)

	# 5단계: 완전 초기화 (_suppress_signals = true 일괄 리셋)
	_suppress_signals = true
	generation_number = fallen_gen + 1
	max_endless_cycle = maxi(max_endless_cycle, prev_endless)
	endless_cycle = 0
	day = 1
	gold = 300
	manastone = 2
	iron_ore = 45
	max_action_points = 3
	action_points = max_action_points
	morale = 50
	dungeon_activity = 40
	monster_tier = 0
	stress_resolvable = 0
	stress_permanent = 0
	brand_stacks = 0
	relic_seq = 0
	expeditions_cleared_this_gen = 0
	active_exploit_buff = _default_exploit_buff()
	buildings = BuildingDb.default_levels()
	roster.clear()
	for i in 3:
		roster.append(Mercenary.create_random("일반", r))
	party.clear()
	death_log.clear()
	soul_relics.clear()
	last_result = {}

	active_curses = next_curses
	if active_curses.has("curse_heavy_crown"):
		stress_permanent = 10
	peak_permanent_stress = stress_permanent
	unseen_succession_notice = true

	pending_succession_summary = {
		"fallen_generation": fallen_gen,
		"next_generation": generation_number,
		"days_survived": days_survived_at_fall,
		"fall_cause": _last_fall_cause,
		"memorialized_count": gen_memorialized,
		"pauper_buried_count": gen_pauper,
		"exploited_count": gen_exploited,
		"expired_count": expired_cnt,
		"peak_permanent_stress": fallen_peak_stress,
		"brand_stacks": fallen_brand_stacks,
		"is_early_fall": is_early_fall,
		"kept_curses": kept_curses.duplicate(),
		"newly_drawn_curses": newly_drawn_curses.duplicate(),
		"max_building_level": max_b_lv,
		"total_fallen_mercs": fallen_mercs_cnt,
	}
	_suppress_signals = false
	_in_daily_settlement_fall = false
	_last_fall_cause = "OTHER"

	resources_changed.emit()
	stress_changed.emit()
	relics_changed.emit()
	roster_changed.emit()
	party_changed.emit()
	save_game()

	_in_succession = false
	return true


## 결산 화면 [제 N+1대 영지 시작] 클릭 시 일시 요약을 소비하고 자동 저장한다.
func consume_succession_summary() -> void:
	pending_succession_summary = {}
	unseen_succession_notice = false
	save_game()


## 세대 교체 직전 잔여 UNRESOLVED 유품을 EXPIRED_ON_SUCCESSION 상태로 일괄 마감하고 마감 건수를 반환한다.
func expire_unresolved_relics(resolved_day: int = -1) -> int:
	var rday: int = day if resolved_day < 0 else resolved_day
	var expired_cnt: int = 0
	for rel in soul_relics:
		if str(rel.get("state", "")) == RELIC_STATE_UNRESOLVED:
			rel["state"] = RELIC_STATE_EXPIRED
			rel["resolved_day"] = rday
			expired_cnt += 1
	return expired_cnt


## 원정 귀환 또는 비상 휴식 정산의 항목별 변동 내역을 사전 계산해 UI 귀인 표시에 제공한다.
func preview_return_settlement(r: Dictionary = {}, is_rest: bool = false) -> Dictionary:
	var src: Dictionary = last_result if (not is_rest and r.is_empty()) else r
	var base_income: int = 0
	var loot_gold: int = 0
	var activity_delta: int = 0
	var morale_delta: int = 0
	var resolvable_delta: int = 0
	var permanent_gain: int = 0
	var new_relics_count: int = 0

	if is_rest:
		base_income = DAILY_BASE_INCOME if gold < recruit_cost("일반") else 0
		activity_delta = 5
	else:
		base_income = DAILY_BASE_INCOME
		var raw_loot: int = int(src.get("gold_gain", 0))
		loot_gold = maxi(0, int(round(float(raw_loot) * 0.85))) if active_curses.has("curse_hollow_coffers") else raw_loot
		activity_delta = int(src.get("activity_delta", 0))
		morale_delta = int(src.get("morale_delta", 0))
		resolvable_delta = int(src.get("resolvable_delta", 0))
		permanent_gain = int(src.get("permanent_gain", 0))
		var dead_list: Array = src.get("dead", [])
		new_relics_count = dead_list.size()

	# 1단계 중간 클램프 시뮬레이션
	var m_after_1: int = clampi(morale + morale_delta, 0, 100)
	var s_after_1: int = maxi(0, stress_resolvable + resolvable_delta)
	var p_after_1: int = clampi(stress_permanent + permanent_gain, 0, MAX_STRESS)

	# 2단계: 기존 미처리 유품 방치 스트레스 + 낙인 일일 민심 하락
	var unresolved_stress: int = unresolved_daily_stress()
	var brand_morale_loss: int = brand_daily_morale_loss()
	var m_after_2: int = clampi(m_after_1 - brand_morale_loss, 0, 100)

	# 3단계: 최종 민심 구간 스트레스 (2단계 이후 민심 기준)
	var morale_stress: int = 0
	if m_after_2 == 0:
		morale_stress = 4
	elif m_after_2 <= 25:
		morale_stress = 2

	# 4단계: 주점(영웅숙소) 스트레스 완화
	var pub_relief: int = maxi(0, building_level("영웅숙소") - 1)
	var final_resolvable: int = maxi(0, s_after_1 + unresolved_stress + morale_stress - pub_relief)
	var final_total_stress: int = clampi(final_resolvable + p_after_1, 0, MAX_STRESS)

	return {
		"base_income": base_income,
		"loot_gold": loot_gold,
		"gold_total": base_income + loot_gold,
		"activity_delta": activity_delta,
		"morale_delta": morale_delta,
		"brand_morale_loss": brand_morale_loss,
		"final_morale": m_after_2,
		"resolvable_delta": resolvable_delta,
		"permanent_gain": permanent_gain,
		"unresolved_stress": unresolved_stress,
		"morale_stress": morale_stress,
		"pub_relief": pub_relief,
		"final_resolvable": final_resolvable,
		"final_permanent": p_after_1,
		"final_total_stress": final_total_stress,
		"will_fall": final_total_stress >= MAX_STRESS,
		"new_relics_count": new_relics_count,
	}


## 원정 귀환 및 비상 휴식이 공유하는 고정 6단계 일일 배치 정산을 실행한다.
func _run_daily_settlement(r: Dictionary, is_rest: bool) -> void:
	_suppress_signals = true

	# 1단계: 기본 수입·전리품·원정 델타 반영 후 중간 클램프
	if is_rest:
		if gold < recruit_cost("일반"):
			gold = maxi(0, gold + DAILY_BASE_INCOME)
		dungeon_activity = clampi(dungeon_activity + 5, 0, 100)
	else:
		var raw_loot: int = int(r.get("gold_gain", 0))
		var eff_loot: int = maxi(0, int(round(float(raw_loot) * 0.85))) if active_curses.has("curse_hollow_coffers") else raw_loot
		gold = maxi(0, gold + DAILY_BASE_INCOME + eff_loot)
		manastone = maxi(0, manastone + int(r.get("mana_gain", 0)))
		morale = clampi(morale + int(r.get("morale_delta", 0)), 0, 100)
		dungeon_activity = clampi(dungeon_activity + int(r.get("activity_delta", 0)), 0, 100)
		stress_resolvable = maxi(0, stress_resolvable + int(r.get("resolvable_delta", 0)))
		stress_permanent = clampi(stress_permanent + int(r.get("permanent_gain", 0)), 0, MAX_STRESS)

	# 2단계: 기존 미처리 유품 방치 스트레스 + 낙인 일일 민심 하락
	var unresolved_pen: int = unresolved_daily_stress()
	if unresolved_pen > 0:
		stress_resolvable = maxi(0, stress_resolvable + unresolved_pen)
	var brand_loss: int = brand_daily_morale_loss()
	if brand_loss > 0:
		morale = clampi(morale - brand_loss, 0, 100)

	# 3단계: 2단계 이후 최종 민심 기준 구간 일일 스트레스
	if morale == 0:
		stress_resolvable = maxi(0, stress_resolvable + 4)
	elif morale <= 25:
		stress_resolvable = maxi(0, stress_resolvable + 2)

	# 4단계: 일자 경과, 행동력 회복, 대기 용병 회복·실종자 생환, 주점 완화, 파티 해제
	day += 1
	action_points = 1 if is_rest else max_action_points
	for m in roster:
		if m.status == Mercenary.Status.READY and m.hp > 0:
			m.hp = mini(m.max_hp, m.hp + int(m.max_hp * 0.3))
		elif m.status == Mercenary.Status.MISSING:
			if _rng.randi_range(1, 100) <= 5:
				m.status = Mercenary.Status.READY
				m.hp = maxi(1, int(m.max_hp * 0.1))
	var pub: int = maxi(0, building_level("영웅숙소") - 1)
	if pub > 0:
		stress_resolvable = maxi(0, stress_resolvable - pub)
	if not is_rest:
		party.clear()

	# 5단계: (귀환 시) 당일 전사 용병(DEAD만, MISSING 제외) 유품 생성 후 last_result 초기화
	if not is_rest:
		var dead_list: Array = r.get("dead", [])
		var death_day: int = maxi(1, day - 1)
		for dead_item in dead_list:
			if dead_item is Mercenary:
				var dm: Mercenary = dead_item
				if dm.status == Mercenary.Status.MISSING:
					continue
				relic_seq += 1
				soul_relics.append({
					"id": "relic_d%02d_%03d" % [death_day, relic_seq],
					"merc_name": dm.merc_name,
					"job": dm.job,
					"grade": dm.grade,
					"level": clampi(dm.level, 1, 12),
					"death_day": death_day,
					"state": RELIC_STATE_UNRESOLVED,
					"resolved_day": 0,
				})
		last_result = {}

	# 6단계: peak_permanent_stress 갱신, 시그널 일괄 발행, 단 1회 _check_game_over()
	peak_permanent_stress = maxi(peak_permanent_stress, stress_permanent)
	_suppress_signals = false

	resources_changed.emit()
	stress_changed.emit()
	relics_changed.emit()
	roster_changed.emit()
	if not is_rest:
		party_changed.emit()

	if total_stress() >= MAX_STRESS:
		_last_fall_cause = "REST_SETTLEMENT" if is_rest else "EXPEDITION_RETURN"
		_in_daily_settlement_fall = true
		_check_game_over()
		_in_daily_settlement_fall = false
	else:
		save_game()


## 결과 화면 "영지로 귀환" 시 호출 — 고정 6단계 일일 배치 정산 및 게임오버 판정.
func return_to_estate() -> void:
	var r := last_result
	if r.is_empty():
		return
	_run_daily_settlement(r, false)


## 전멸 소프트락 방지용 비상 구제 '하루 휴식'을 실행한다. 조건 미충족 시 false 반환 및 상태 불변.
func rest_estate_day() -> bool:
	if not can_rest_estate_day():
		return false
	_run_daily_settlement({}, true)
	return true


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
		"peak_permanent_stress": peak_permanent_stress,
		"soul_relics": soul_relics.duplicate(true),
		"relic_seq": relic_seq,
		"brand_stacks": brand_stacks,
		"active_exploit_buff": active_exploit_buff.duplicate(),
		"difficulty_level": difficulty_level,
		"total_exploited_count": total_exploited_count,
		"total_memorialized_count": total_memorialized_count,
		"total_pauper_buried_count": total_pauper_buried_count,
		"active_curses": active_curses.duplicate(),
		"generation_number": generation_number,
		"expeditions_cleared_this_gen": expeditions_cleared_this_gen,
		"chronicle_entries": chronicle_entries.duplicate(true),
		"boss_sealed_count": boss_sealed_count,
		"endless_cycle": endless_cycle,
		"max_endless_cycle": max_endless_cycle,
		"unseen_succession_notice": unseen_succession_notice,
		"buildings": buildings.duplicate(),
		"death_log": death_log.duplicate(true),
		"roster": roster_data,
		"party_indices": party_indices,
	}


## 저장된 딕셔너리 데이터로부터 게임 상태를 복원한다 (JSON float 캐스팅 및 구버전 폴백 보장).
func from_dict(data: Dictionary) -> void:
	_suppress_signals = true
	gold = maxi(0, int(data.get("gold", 300)))
	manastone = maxi(0, int(data.get("manastone", 2)))
	iron_ore = maxi(0, int(data.get("iron_ore", 45)))
	max_action_points = maxi(1, int(data.get("max_action_points", 3)))
	action_points = maxi(0, int(data.get("action_points", max_action_points)))
	day = maxi(1, int(data.get("day", 1)))
	morale = clampi(int(data.get("morale", 50)), 0, 100)
	dungeon_activity = clampi(int(data.get("dungeon_activity", 40)), 0, 100)
	monster_tier = maxi(0, int(data.get("monster_tier", 0)))
	stress_resolvable = maxi(0, int(data.get("stress_resolvable", 0)))
	stress_permanent = clampi(int(data.get("stress_permanent", 0)), 0, MAX_STRESS)
	peak_permanent_stress = clampi(int(data.get("peak_permanent_stress", stress_permanent)), 0, MAX_STRESS)

	soul_relics.clear()
	var sr_raw: Variant = data.get("soul_relics", [])
	if sr_raw is Array:
		for item in sr_raw:
			if item is Dictionary:
				soul_relics.append({
					"id": str(item.get("id", "")),
					"merc_name": str(item.get("merc_name", "")),
					"job": str(item.get("job", "")),
					"grade": str(item.get("grade", "일반")),
					"level": clampi(int(item.get("level", 1)), 1, 12),
					"death_day": maxi(1, int(item.get("death_day", 1))),
					"state": str(item.get("state", RELIC_STATE_UNRESOLVED)),
					"resolved_day": maxi(0, int(item.get("resolved_day", 0))),
				})

	if data.has("relic_seq"):
		relic_seq = maxi(0, int(data.get("relic_seq", soul_relics.size())))
	else:
		relic_seq = soul_relics.size()

	brand_stacks = maxi(0, int(data.get("brand_stacks", 0)))

	var buff_raw: Variant = data.get("active_exploit_buff", {})
	if buff_raw is Dictionary and not (buff_raw as Dictionary).is_empty():
		var bd: Dictionary = buff_raw
		active_exploit_buff = {
			"active": bool(bd.get("active", false)),
			"atk": clampi(int(bd.get("atk", 0)), 0, 30),
			"crit": clampf(float(bd.get("crit", 0.0)), 0.0, 100.0),
			"source_relic_id": str(bd.get("source_relic_id", "")),
		}
	else:
		active_exploit_buff = _default_exploit_buff()

	var diff_raw: String = str(data.get("difficulty_level", "normal"))
	difficulty_level = diff_raw if DIFFICULTY_MULTS.has(diff_raw) else "normal"

	total_exploited_count = maxi(0, int(data.get("total_exploited_count", 0)))
	total_memorialized_count = maxi(0, int(data.get("total_memorialized_count", 0)))
	total_pauper_buried_count = maxi(0, int(data.get("total_pauper_buried_count", 0)))

	active_curses = _sanitize_curses(data.get("active_curses", []) if data.get("active_curses", []) is Array else [])
	generation_number = maxi(1, int(data.get("generation_number", 1)))
	expeditions_cleared_this_gen = maxi(0, int(data.get("expeditions_cleared_this_gen", 0)))
	boss_sealed_count = maxi(0, int(data.get("boss_sealed_count", 0)))
	endless_cycle = maxi(0, int(data.get("endless_cycle", 0)))
	max_endless_cycle = maxi(endless_cycle, int(data.get("max_endless_cycle", 0)))
	unseen_succession_notice = bool(data.get("unseen_succession_notice", false))
	pending_succession_summary = {}
	_in_succession = false

	chronicle_entries.clear()
	var c_data: Variant = data.get("chronicle_entries", [])
	if c_data is Array:
		for ce in c_data:
			if ce is Dictionary:
				chronicle_entries.append((ce as Dictionary).duplicate(true))

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
	_suppress_signals = false

	# 변경 시그널 일괄 방출
	resources_changed.emit()
	stress_changed.emit()
	relics_changed.emit()
	roster_changed.emit()
	party_changed.emit()


## 현재 진행 상태를 저장한다 (SaveManager를 통한 자동 저장 위임).
## 저장 성공 시 true, 실패 또는 매니저 부재 시 false를 반환하여 호출 측 씬 전환이 중단되지 않도록 보호한다.
func save_game() -> bool:
	var sm: Node = null
	if is_inside_tree():
		sm = get_node_or_null("/root/SaveManager")
	if sm == null:
		var ml := Engine.get_main_loop()
		if ml != null and "root" in ml and ml.root != null:
			sm = ml.root.get_node_or_null("SaveManager")
	if sm != null and sm.has_method("auto_save"):
		return sm.auto_save()
	push_warning("save_game: SaveManager를 찾을 수 없거나 auto_save 메서드가 없습니다.")
	return false
