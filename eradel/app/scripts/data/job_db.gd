class_name JobDb
extends RefCounted

## 기획서 12장 직업 체계 / 9장 모집 비용 기반 정적 데이터.

const CATEGORIES := {
	"전사": ["정규기사", "검사", "마검사", "광전사", "룬대장장이"],
	"마법사": ["정규마법사", "흑마법사", "소환사", "정령사", "룬마법사"],
	"레인저": ["궁수", "헌터", "암살자", "척후병"],
	"성직자": ["사제", "드루이드", "성기사"],
}

const RECRUIT_COST := {"일반": 50, "정예": 150, "특수": 350}

## 등급별 레벨 범위 (기획서 14장 구간 참고)
const GRADE_LEVEL := {
	"일반": [1, 3],
	"정예": [3, 5],
	"특수": [5, 7],
}

const NAME_PREFIX := [
	"부러진", "붉은", "그림자", "조용한", "술고래", "강철", "잿빛", "외눈",
	"늙은", "굶주린", "침묵의", "피투성이", "녹슨", "창백한", "마지막",
]
const NAME_SUFFIX := [
	"칼", "룬", "발소리", "주먹", "눈", "방패", "송곳니", "손", "그림자",
	"심장", "낙인", "맹세", "잿더미", "사냥꾼", "십자가",
]

const PENALTY_POOL := ["골절", "시력 손상", "극도의 피로", "마력 역류", "타박상", "내상"]


static func random_name(rng: RandomNumberGenerator) -> String:
	var p: String = NAME_PREFIX[rng.randi_range(0, NAME_PREFIX.size() - 1)]
	var s: String = NAME_SUFFIX[rng.randi_range(0, NAME_SUFFIX.size() - 1)]
	return "%s %s" % [p, s]


static func random_category(rng: RandomNumberGenerator) -> String:
	var keys := CATEGORIES.keys()
	return keys[rng.randi_range(0, keys.size() - 1)]


static func random_job(rng: RandomNumberGenerator, category: String) -> String:
	var jobs: Array = CATEGORIES[category]
	return jobs[rng.randi_range(0, jobs.size() - 1)]


static func random_penalty(rng: RandomNumberGenerator) -> String:
	return PENALTY_POOL[rng.randi_range(0, PENALTY_POOL.size() - 1)]


static func category_color(category: String) -> Color:
	match category:
		"전사": return UiKit.GOLD
		"마법사": return UiKit.PURPLE
		"레인저": return UiKit.GREEN
		"성직자": return UiKit.BLUE
		_: return UiKit.TEXT2


static func grade_color(grade: String) -> Color:
	match grade:
		"정예": return UiKit.BLUE
		"특수": return UiKit.PURPLE
		_: return UiKit.TEXT2
