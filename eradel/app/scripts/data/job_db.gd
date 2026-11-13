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


## 직업별 시각 자산·문양·공격 연출 타입 단일 카탈로그
const VISUAL_SPECS := {
	"전사": {
		"key": "warrior",
		"portrait": "res://assets/sprites/characters/portrait_warrior.png",
		"hero_sprite": "res://assets/sprites/characters/hero_warrior.png",
		"glyph": "⚔",
		"default_atk_type": "slash",
		"skill_atk_type": "crush",
	},
	"마법사": {
		"key": "mage",
		"portrait": "res://assets/sprites/characters/portrait_mage.png",
		"hero_sprite": "res://assets/sprites/characters/hero_mage.png",
		"glyph": "✦",
		"default_atk_type": "lightning",
		"skill_atk_type": "lightning",
	},
	"레인저": {
		"key": "ranger",
		"portrait": "res://assets/sprites/characters/portrait_ranger.png",
		"hero_sprite": "res://assets/sprites/characters/hero_ranger.png",
		"glyph": "➶",
		"default_atk_type": "arrow",
		"skill_atk_type": "gun",
	},
	"성직자": {
		"key": "cleric",
		"portrait": "res://assets/sprites/characters/portrait_cleric.png",
		"hero_sprite": "res://assets/sprites/characters/hero_cleric.png",
		"glyph": "✚",
		"default_atk_type": "holy",
		"skill_atk_type": "holy",
	},
}


## 무작위 페널티 문자열을 반환한다.
static func random_penalty(rng: RandomNumberGenerator) -> String:
	return PENALTY_POOL[rng.randi_range(0, PENALTY_POOL.size() - 1)]


## 직업군(또는 별칭)에 해당하는 시각·연출 스펙 딕셔너리를 반환한다.
static func visual_spec(category: String) -> Dictionary:
	var key := category
	if category == "도적":
		key = "레인저"
	return VISUAL_SPECS.get(key, VISUAL_SPECS["전사"])


## 직업군과 스킬 여부에 따른 전투 공격 연출 타입을 반환한다.
static func attack_type_for(category: String, is_skill: bool = false) -> String:
	var spec := visual_spec(category)
	return str(spec.get("skill_atk_type" if is_skill else "default_atk_type", "slash"))


## 직업군 대표 색상을 반환한다 (UiKit 순환 참조 방지를 위해 리터럴 Color 사용).
static func category_color(category: String) -> Color:
	match category:
		"전사": return Color("c8a24a")
		"마법사": return Color("7c588c")
		"레인저", "도적": return Color("4a8c5c")
		"성직자": return Color("4a749c")
		_: return Color("9a8d7a")


## 용병 등급 색상을 반환한다.
static func grade_color(grade: String) -> Color:
	match grade:
		"정예": return Color("4a749c")
		"특수": return Color("7c588c")
		_: return Color("9a8d7a")
