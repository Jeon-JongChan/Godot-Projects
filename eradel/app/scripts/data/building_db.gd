class_name BuildingDb
extends RefCounted

## [경량화] 영지 건물의 불변 데이터(이름·배치·아이콘·설명·유형)를 한 곳에 두고 모두가 공유한다.
## 변하는 상태(레벨)는 GameState.buildings 에만 둔다 — 고유 상태와 공유 상태의 분리.
## 기획서(면기본 메인화.docx) 스케치 배치: 10개 마을 건물 + 어둠의 균열.

const DEFS: Array[Dictionary] = [
	{"id": "mercenary_outpost", "name": "용병모집소", "icon": "📜", "rect": Rect2(85, 250, 225, 175),
		"tag": "모험가 길드 · 용병 영입", "effect_desc": "레벨당 신규 모집 용병의 최대 체력 +5 보너스", "type": "guild"},
	{"id": "hero_lodge", "name": "영웅숙소", "icon": "🛏️", "rect": Rect2(375, 105, 230, 175),
		"tag": "용병 숙소 · 원정대 편성", "effect_desc": "레벨당 원정 귀환 시 일일 스트레스 자연 감소 +1", "type": "lodge"},
	{"id": "sanatorium", "name": "치료소", "icon": "⚕️", "rect": Rect2(375, 365, 230, 175),
		"tag": "성당 진료소 · 부상 및 스트레스 치유", "effect_desc": "레벨업 시 부상/패널티 치료 성공률 상승 (최대 90%)", "type": "treatment"},
	{"id": "manor", "name": "영주저택", "icon": "🏰", "rect": Rect2(760, 62, 340, 200),
		"tag": "영주 관저 · 통치 결단 및 시설 증축", "effect_desc": "Lv.3 / Lv.5 달성 시 영주 최대 행동력 +1 증가", "type": "manor"},
	{"id": "general_store", "name": "잡화점", "icon": "⚖️", "rect": Rect2(705, 298, 215, 165),
		"tag": "만물상 · 원정 보급품 상점", "effect_desc": "레벨당 모든 보급 물자 구매 가격 10% 할인", "type": "store"},
	{"id": "warehouse", "name": "창고", "icon": "📦", "rect": Rect2(995, 295, 220, 170),
		"tag": "영지 비축고 · 마나석 교역소", "effect_desc": "레벨당 마나석 매각 교역 금화 +15G 추가 획득", "type": "warehouse"},
	{"id": "blacksmith", "name": "대장간", "icon": "⚒️", "rect": Rect2(725, 488, 230, 165),
		"tag": "드워프 대장간 · 무기 제련 및 강화", "effect_desc": "레벨당 원정 파티 전체 공격력 +2 영구 증가", "type": "blacksmith"},
	{"id": "mage_guild", "name": "마법사학회", "icon": "🔮", "rect": Rect2(1155, 478, 240, 178),
		"tag": "비전 마탑 · 차원 균열 억제 및 연성", "effect_desc": "레벨당 차원문 억제 시 던전 활성도 추가 -5% 감소", "type": "magic"},
	{"id": "training_camp", "name": "훈련장", "icon": "🎯", "rect": Rect2(1345, 130, 250, 180),
		"tag": "전술 연병장 · 용병 실전 특훈", "effect_desc": "레벨당 특훈 시 용병 추가 체력 +4 / 공격력 성장 증가", "type": "training"},
	{"id": "memorial_hall", "name": "기념관", "icon": "🏛️", "rect": Rect2(1685, 260, 235, 190),
		"tag": "영령의 전당 · 추모비 및 연대기", "effect_desc": "레벨당 추모 헌화 시 민심 회복 및 스트레스 완화 증가", "type": "memorial"},
	{"id": "dungeon_gate", "name": "어둠의 균열", "icon": "🌌", "rect": Rect2(2035, 195, 275, 230),
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
