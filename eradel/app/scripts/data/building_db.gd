class_name BuildingDb
extends RefCounted

## [경량화] 영지 건물의 불변 데이터(이름·배치·아이콘·설명·유형)를 한 곳에 두고 모두가 공유한다.
## 변하는 상태(레벨)는 GameState.buildings 에만 둔다 — 고유 상태와 공유 상태의 분리.
## 기획서(면기본 메인화.docx) 스케치 배치: 10개 마을 건물 + 어둠의 균열.

const DEFS: Array[Dictionary] = [
	{"id": "mercenary_outpost", "name": "용병모집소", "icon": "📜", "rect": Rect2(75, 210, 220, 168),
		"tag": "모험가 길드 · 용병 영입", "effect_desc": "레벨당 신규 모집 용병의 최대 체력 +5 보너스", "type": "guild"},
	{"id": "hero_lodge", "name": "영웅숙소", "icon": "🛏️", "rect": Rect2(345, 95, 225, 168),
		"tag": "용병 숙소 · 원정대 편성", "effect_desc": "레벨당 원정 귀환 시 일일 스트레스 자연 감소 +1", "type": "lodge"},
	{"id": "sanatorium", "name": "치료소", "icon": "⚕️", "rect": Rect2(345, 370, 225, 168),
		"tag": "성당 진료소 · 부상 및 스트레스 치유", "effect_desc": "레벨업 시 부상/패널티 치료 성공률 상승 (최대 90%)", "type": "treatment"},
	{"id": "general_store", "name": "잡화점", "icon": "⚖️", "rect": Rect2(605, 235, 210, 158),
		"tag": "만물상 · 원정 보급품 상점", "effect_desc": "레벨당 모든 보급 물자 구매 가격 10% 할인", "type": "store"},
	{"id": "manor", "name": "영주저택", "icon": "🏰", "rect": Rect2(840, 72, 320, 182),
		"tag": "영주 관저 · 통치 결단 및 시설 증축", "effect_desc": "Lv.3 / Lv.5 달성 시 영주 최대 행동력 +1 증가", "type": "manor"},
	{"id": "blacksmith", "name": "대장간", "icon": "⚒️", "rect": Rect2(885, 375, 225, 162),
		"tag": "드워프 대장간 · 무기 제련 및 강화", "effect_desc": "레벨당 원정 파티 전체 공격력 +2 영구 증가", "type": "blacksmith"},
	{"id": "warehouse", "name": "창고", "icon": "📦", "rect": Rect2(1185, 235, 215, 162),
		"tag": "영지 비축고 · 마나석 교역소", "effect_desc": "레벨당 마나석 매각 교역 금화 +15G 추가 획득", "type": "warehouse"},
	{"id": "training_camp", "name": "훈련장", "icon": "🎯", "rect": Rect2(1435, 95, 245, 172),
		"tag": "전술 연병장 · 용병 실전 특훈", "effect_desc": "레벨당 특훈 시 용병 추가 체력 +4 / 공격력 성장 증가", "type": "training"},
	{"id": "mage_guild", "name": "마법사학회", "icon": "🔮", "rect": Rect2(1435, 370, 235, 168),
		"tag": "비전 마탑 · 차원 균열 억제 및 연성", "effect_desc": "레벨당 차원문 억제 시 던전 활성도 추가 -5% 감소", "type": "magic"},
	{"id": "memorial_hall", "name": "기념관", "icon": "🏛️", "rect": Rect2(1735, 225, 235, 182),
		"tag": "영령의 전당 · 추모비 및 연대기", "effect_desc": "레벨당 추모 헌화 시 민심 회복 및 스트레스 완화 증가", "type": "memorial"},
	{"id": "dungeon_gate", "name": "어둠의 균열", "icon": "🌌", "rect": Rect2(2045, 185, 275, 225),
		"tag": "차원문 · 던전 원정 출진", "effect_desc": "원정 파티를 편성하여 어둠의 균열 심층부로 출진합니다.", "type": "dungeon"},
]

## 구버전 건물 이름 ↔ 신규 이름. 증축 시 양쪽 레벨을 함께 맞춘다 (구 씬·세이브 호환).
const ALIASES := {
	"용병모집소": "모험가 길드", "모험가 길드": "용병모집소",
	"영웅숙소": "주점", "주점": "영웅숙소",
	"영주저택": "영주 저택", "영주 저택": "영주저택",
	"마법사학회": "마탑", "마탑": "마법사학회",
}

const MAX_LEVEL := 5


## 새 게임/로드 시 쓰는 기본 레벨 표 (별칭 포함 전부 Lv.1)
static func default_levels() -> Dictionary:
	var out := {}
	for d in DEFS:
		if d.type != "dungeon":
			out[d.name] = 1
	for alias in ALIASES:
		out[alias] = 1
	return out


## 유형(type)으로 건물 정의를 찾는다.
static func by_type(t: String) -> Dictionary:
	for d in DEFS:
		if d.type == t:
			return d
	return {}


## 이름, 구버전 별칭, id, 또는 type 으로 건물 정의 딕셔너리를 조회한다.
static func by_name_or_alias(name_or_type: String) -> Dictionary:
	var target := name_or_type
	var alt: String = str(ALIASES.get(target, ""))
	for d in DEFS:
		if d.name == target or d.id == target or d.type == target or (alt != "" and d.name == alt):
			return d
	return {}


## 건물 이름·별칭·유형에 해당하는 효과 설명을 반환한다 (건물 관리 UI 단일 진실 공급원).
static func effect_desc(name_or_type: String) -> String:
	var def := by_name_or_alias(name_or_type)
	return str(def.get("effect_desc", ""))
