class_name Mercenary
extends Resource

## 용병 한 명. 런타임 엔티티지만 추후 저장 대비 Resource 로 둔다.

enum Status { READY, ON_EXPEDITION, MISSING, DEAD }

@export var merc_name: String = "이름 없음"
@export var category: String = "전사"
@export var job: String = "검사"
@export var grade: String = "일반"
@export var level: int = 1
@export var max_hp: int = 80
@export var attack: int = 10

@export var hp: int = 80
## 다키스트 던전 스트레스 수치 (0 ~ 100, 100 도달 시 고통/붕괴 상태 진입 위험)
@export var stress: int = 0
## 대장간 강화 무기 레벨 (1 ~ 5)
@export var weapon_level: int = 1
## 대장간 강화 방어구 레벨 (1 ~ 5)
@export var armor_level: int = 1
## 대장간 강화 투구 레벨 (1 ~ 5)
@export var helmet_level: int = 1
## 대장간 강화 장신구/반지 레벨 (1 ~ 5)
@export var ring_level: int = 1
# 패널티는 프로토타입 단계에서는 전투 능력치에 영향을 주지 않으며 순수 기록용으로 사용됨
@export var penalties: Array[String] = []
@export var status: int = Status.READY


static func create_random(grade: String, rng: RandomNumberGenerator) -> Mercenary:
	var m := Mercenary.new()
	m.grade = grade
	m.category = JobDb.random_category(rng)
	m.job = JobDb.random_job(rng, m.category)
	m.merc_name = JobDb.random_name(rng)
	var range_lv: Array = JobDb.GRADE_LEVEL.get(grade, [1, 3])
	m.level = rng.randi_range(range_lv[0], range_lv[1])
	var grade_mult := 1.0
	if grade == "정예":
		grade_mult = 1.15
	elif grade == "특수":
		grade_mult = 1.35
	m.max_hp = int((60 + m.level * 12) * grade_mult)
	m.attack = int((6 + m.level * 3) * grade_mult)
	m.hp = m.max_hp
	return m


func is_available() -> bool:
	return status == Status.READY


func is_alive() -> bool:
	return status != Status.DEAD and status != Status.MISSING and hp > 0


func status_text() -> String:
	match status:
		Status.READY: return "대기"
		Status.ON_EXPEDITION: return "원정중"
		Status.MISSING: return "실종"
		Status.DEAD: return "사망"
		_: return "?"


## 사망 시 누적되는 영구 스트레스 (기획서 7장).
func permanent_stress_value() -> int:
	if level <= 3:
		return 3
	elif level <= 6:
		return 6
	elif level <= 9:
		return 10
	return 15


## 저장용 딕셔너리로 직렬화한다.
func to_dict() -> Dictionary:
	return {
		"merc_name": merc_name,
		"category": category,
		"job": job,
		"grade": grade,
		"level": level,
		"max_hp": max_hp,
		"attack": attack,
		"hp": hp,
		"stress": stress,
		"weapon_level": weapon_level,
		"armor_level": armor_level,
		"helmet_level": helmet_level,
		"ring_level": ring_level,
		"penalties": penalties.duplicate(),
		"status": status,
	}


## 딕셔너리 데이터로부터 용병 객체를 복원한다.
static func from_dict(data: Dictionary) -> Mercenary:
	var m := Mercenary.new()
	m.merc_name = data.get("merc_name", "이름 없음")
	m.category = data.get("category", "전사")
	m.job = data.get("job", "검사")
	m.grade = data.get("grade", "일반")
	m.level = int(data.get("level", 1))
	m.max_hp = int(data.get("max_hp", 80))
	m.attack = int(data.get("attack", 10))
	m.hp = int(data.get("hp", m.max_hp))
	m.stress = int(data.get("stress", 0))
	m.weapon_level = int(data.get("weapon_level", 1))
	m.armor_level = int(data.get("armor_level", 1))
	m.helmet_level = int(data.get("helmet_level", 1))
	m.ring_level = int(data.get("ring_level", 1))
	var pens: Array = data.get("penalties", [])
	m.penalties.clear()
	for p in pens:
		m.penalties.append(str(p))
	m.status = int(data.get("status", Status.READY))
	return m


## 다키스트 던전 6대 전투 능력치: 명중률(ACC)을 계산합니다.
func get_acc() -> int:
	var base := 90 + level * 2
	if category == "레인저":
		base += 5
	return base


## 다키스트 던전 6대 전투 능력치: 치명타율(CRIT %)을 계산합니다.
func get_crit() -> float:
	var base := 5.0 + float(level) * 1.5
	if category == "레인저":
		base += 3.0
	return base


## 다키스트 던전 6대 전투 능력치: 최소 피해량(DMG Min)을 계산합니다.
func get_dmg_min() -> int:
	return maxi(1, attack - 2 + (weapon_level - 1) * 2)


## 다키스트 던전 6대 전투 능력치: 최대 피해량(DMG Max)을 계산합니다.
func get_dmg_max() -> int:
	return maxi(2, attack + 3 + (weapon_level - 1) * 3)


## 다키스트 던전 6대 전투 능력치: 회피율(DODGE)을 계산합니다.
func get_dodge() -> int:
	var base := 8 + level * 3
	if category == "레인저":
		base += 6
	return base


## 다키스트 던전 6대 전투 능력치: 방어력/피해감소율(PROT %)을 계산합니다.
func get_prot() -> int:
	var prot := 0
	if category == "전사":
		prot = 10 + (armor_level - 1) * 3
	elif category == "성직자":
		prot = 5 + (armor_level - 1) * 2
	return prot


## 다키스트 던전 6대 전투 능력치: 턴 속도(SPD)를 계산합니다.
func get_spd() -> int:
	var spd := 4 + level
	if category == "레인저":
		spd += 3
	elif category == "전사":
		spd -= 1
	return maxi(1, spd)
