class_name EstateCommand
extends RefCounted

## [커맨드] 영지 행동 하나를 객체로 캡슐화한다: 비용(금화·마나석·행동력) + 선언적 효과 + 결과 문구.
## UI 는 버튼에 커맨드를 연결하고 can_execute()/execute() 만 호출한다.
## 게임 규칙(수치)은 아래 카탈로그에만 존재하므로 UI 코드에서 밸런스 값을 찾을 필요가 없다.

const MAX_MERC_LEVEL := 10

var id: String
var title: String
var desc: String
var gold: int = 0
var mana: int = 0
var ap: int = 0
var effects: Dictionary = {}
var notice: String = ""
var target: Mercenary = null


func _init(p_id: String, p_title: String, p_desc: String, cost: Dictionary, p_effects: Dictionary, p_notice: String, p_target: Mercenary = null) -> void:
	id = p_id
	title = p_title
	desc = p_desc
	gold = cost.get("gold", 0)
	mana = cost.get("mana", 0)
	ap = cost.get("ap", 0)
	effects = p_effects
	notice = p_notice
	target = p_target


## 비용·대상 조건을 만족하는지 검사한다.
func can_execute() -> bool:
	if not GameState.can_afford(gold, mana) or GameState.action_points < ap:
		return false
	if target != null:
		if not target.is_available():
			return false
		# 특훈은 최대 레벨에서 막는다
		if effects.has("level") and target.level >= MAX_MERC_LEVEL:
			return false
	return true


## 비용을 지불하고 효과를 적용한다. 조건 미충족 시 아무것도 바꾸지 않고 false.
func execute() -> bool:
	if not can_execute() or not GameState.spend(gold, mana):
		return false
	if ap > 0:
		GameState.action_points -= ap
	_apply_effects()
	return true


## 실행 결과 안내 문구 ({name}/{level}/{attack} 은 대상 용병 값으로 치환)
func notice_text() -> String:
	if target == null:
		return notice
	return notice.format({"name": target.merc_name, "level": target.level, "attack": target.attack})


## 버튼 표시용 비용 문자열 (예: "80G · ⚡1")
func cost_text() -> String:
	var parts: PackedStringArray = []
	if gold > 0: parts.append("%dG" % gold)
	if mana > 0: parts.append("마나석 %d" % mana)
	if ap > 0: parts.append("⚡%d" % ap)
	return " · ".join(parts) if not parts.is_empty() else "무료"


func _apply_effects() -> void:
	var roster_touched := false
	for k in effects:
		var v: int = effects[k]
		match k:
			"gold": GameState.add_gold(v)
			"mana": GameState.add_manastone(v)
			"morale": GameState.morale += v
			"activity": GameState.dungeon_activity += v
			"monster_tier": GameState.monster_tier += v
			"stress": GameState.add_resolvable_stress(v)
			"heal_ready":
				# 대기 중인 생존 용병만 회복 (사망·실종자는 제외)
				for m in GameState.roster:
					if m.status == Mercenary.Status.READY:
						m.hp = m.max_hp
				roster_touched = true
			"attack":
				target.attack += v
				roster_touched = true
			"level":
				target.level += v
				roster_touched = true
			"max_hp":
				target.max_hp += v
				target.hp = target.max_hp
				roster_touched = true
	if roster_touched:
		GameState.roster_changed.emit()


# ───────────────────────── 카탈로그 ─────────────────────────
# 건물 레벨에 따라 달라지는 수치는 생성 시점의 레벨로 계산한다 (팝업을 열 때마다 새로 생성).

static func _lv(building: String) -> int:
	return GameState.building_level(building)


## 훈련장 레벨에 따른 1회 실전 특훈 성장치(HP/공격력)를 계산해 반환한다.
static func training_gains(tlv: int = -1) -> Dictionary:
	var lv := tlv if tlv > 0 else _lv("훈련장")
	return {
		"level": 1,
		"hp": 10 + (lv - 1) * 4,
		"atk": 2 + int(lv / 2),
	}


## 대장간 장비 슬롯 제련 명세(현재·다음 레벨, 성공률, 요구 재료, 실행 가능 여부)를 단일 규칙으로 계산한다.
static func forge_slot_spec(m: Mercenary, slot: String) -> Dictionary:
	var cur_lv: int = 1
	var slot_kr := "무기"
	var canon_slot := "weapon"
	match slot:
		"weapon":
			cur_lv = m.weapon_level if m != null else 1
			slot_kr = "무기"
			canon_slot = "weapon"
		"armor":
			cur_lv = m.armor_level if m != null else 1
			slot_kr = "갑옷"
			canon_slot = "armor"
		"helmet":
			cur_lv = m.helmet_level if m != null else 1
			slot_kr = "투구"
			canon_slot = "helmet"
		"ring", "accessory":
			cur_lv = m.ring_level if m != null else 1
			slot_kr = "장신구"
			canon_slot = "accessory"

	var success_rate := clampi(85 - (cur_lv - 1) * 7, 40, 95)
	var req_ore := 10 + (cur_lv - 1) * 5
	var req_mana := 1 if cur_lv >= 2 else 0
	if cur_lv >= 4:
		req_mana = 2
	var req_gold := 300 + (cur_lv - 1) * 150
	var has_ore := GameState.iron_ore >= req_ore
	var has_mana := GameState.manastone >= req_mana
	var has_gold := GameState.gold >= req_gold
	return {
		"slot": canon_slot,
		"slot_name": slot_kr,
		"cur_lv": cur_lv,
		"next_lv": cur_lv + 1,
		"success_rate": success_rate,
		"req_ore": req_ore,
		"req_mana": req_mana,
		"req_gold": req_gold,
		"has_ore": has_ore,
		"has_mana": has_mana,
		"has_gold": has_gold,
		"can_forge": m != null and has_ore and has_mana and has_gold,
	}


## 대장간 제련 성공 시 용병의 해당 슬롯 레벨과 기본 스탯 보너스를 적용하고 결과를 반환한다.
static func apply_forge_stat_bonus(m: Mercenary, slot: String) -> Dictionary:
	if m == null:
		return {}
	var new_lv := 1
	var slot_kr := "무기"
	match slot:
		"weapon":
			m.weapon_level += 1
			m.attack += 2
			new_lv = m.weapon_level
			slot_kr = "무기"
		"armor":
			m.armor_level += 1
			m.max_hp += 8
			m.hp = mini(m.hp + 8, m.max_hp)
			new_lv = m.armor_level
			slot_kr = "갑옷"
		"helmet":
			m.helmet_level += 1
			m.max_hp += 5
			new_lv = m.helmet_level
			slot_kr = "투구"
		"ring", "accessory":
			m.ring_level += 1
			m.attack += 1
			new_lv = m.ring_level
			slot_kr = "장신구"
	return {"slot_name": slot_kr, "new_lv": new_lv}


## 대상 없는 건물 행동 목록 (건물 유형별)
static func catalog(building_type: String) -> Array[EstateCommand]:
	var out: Array[EstateCommand] = []
	match building_type:
		"manor":
			out.append(EstateCommand.new("festival", "🎉 광장 축제 개최", "민심 +15% 상승\n해소가능 스트레스 -12",
				{"gold": 80, "ap": 1}, {"morale": 15, "stress": -12},
				"광장 축제를 개최하여 영지 민심이 크게 오르고 스트레스가 감소했습니다!"))
			out.append(EstateCommand.new("guard", "🛡️ 변경 경비대 파견", "던전 활성도 -15% 억제\n변경 치안 안정화",
				{"gold": 60, "ap": 1}, {"activity": -15},
				"경비대를 차원문 외곽에 파견하여 던전 활성도를 15% 억제했습니다!"))
			out.append(EstateCommand.new("tax", "🪙 긴급 특별 징세", "금화 +140G 즉시 확보\n민심 -10%, 스트레스 +6",
				{"ap": 1}, {"morale": -10, "stress": 6, "gold": 140},
				"특별 징세를 단행하여 금화 140G를 확보했습니다. (민심 -10%)"))
		"store":
			var d := 1.0 - float(_lv("잡화점") - 1) * 0.10
			out.append(EstateCommand.new("potion", "🧪 최상급 치유 비약 상자", "대기 중인 모든 용병의 체력을 즉시 100% 회복합니다.",
				{"gold": int(round(60.0 * d))}, {"heal_ready": 1},
				"최상급 치유 비약을 사용하여 모든 용병의 체력을 회복했습니다!"))
			out.append(EstateCommand.new("incense", "🕯️ 청명한 성수 향로", "영지 전역에 향을 피워 해소가능 스트레스를 15만큼 즉시 낮춥니다.",
				{"gold": int(round(80.0 * d))}, {"stress": -15},
				"청명한 성수 향로를 피워 영지 스트레스가 15 감소했습니다!"))
			out.append(EstateCommand.new("scroll", "🗺️ 고대 차원문 정찰 두루마리", "차원문 내부의 동향을 파악하여 던전 활성도를 15% 낮춥니다.",
				{"gold": int(round(100.0 * d))}, {"activity": -15},
				"정찰 두루마리를 활용하여 던전 활성도를 15% 낮추었습니다!"))
			out.append(EstateCommand.new("mana", "💎 정제된 마나석 결정", "상단에서 입수한 고순도 마나석 1개를 즉시 구입하여 비축합니다.",
				{"gold": int(round(160.0 * d))}, {"mana": 1},
				"정제된 마나석 1개를 구입하여 창고에 비축했습니다!"))
		"warehouse":
			var sell := 110 + (_lv("창고") - 1) * 15
			out.append(EstateCommand.new("sell", "💎 마나석 황실 납품 (매각)", "비축된 마나석 1개를 제국 상단에 매각하여 금화 %dG를 즉시 확보합니다." % sell,
				{"mana": 1}, {"gold": sell},
				"마나석 1개를 납품하여 금화 %dG를 획득했습니다!" % sell))
			out.append(EstateCommand.new("relief", "🌾 영지 구호 물자 방출", "창고의 비축 식량과 자금을 풀어 민심을 +12% 높이고 스트레스를 8 낮춥니다.",
				{"gold": 70}, {"morale": 12, "stress": -8},
				"비축 구호 물자를 방출하여 민심이 +12% 상승했습니다!"))
		"lodge":
			out.append(EstateCommand.new("feast", "🍲 숙소 특식 배급", "전원 HP 100% 회복",
				{"gold": 40}, {"heal_ready": 1},
				"숙소 특식을 배급하여 모든 용병의 체력이 최대치로 회복되었습니다!"))
		"treatment":
			out.append(EstateCommand.new("pray", "🙏 성당 치유 기도회", "영지민과 용병들의 불안감을 달래어 해소가능 스트레스를 15 감소시킵니다.",
				{"gold": 60}, {"stress": -15},
				"성당 치유 기도회를 통해 영지 스트레스가 완화되었습니다!"))
			out.append(EstateCommand.new("ward", "🌿 병동 집중 치료", "대기 중인 모든 용병의 체력(HP)을 즉시 최대치로 회복시킵니다.",
				{"gold": 50}, {"heal_ready": 1},
				"병동 집중 치료로 모든 용병의 생명력이 완전히 회복되었습니다!"))
		"magic":
			var sup := 20 + (_lv("마법사학회") - 1) * 5
			out.append(EstateCommand.new("suppress", "🌌 차원문 폭주 억제 대술식", "마나석의 순수 에너지를 역류시켜 어둠의 균열 활성도를 %d%% 감소시키고, 몬스터 강화 단계를 1단계 억제합니다." % sup,
				{"mana": 1}, {"activity": -sup, "monster_tier": -1},
				"차원문 억제 술식이 발동되어 던전 활성도가 %d%% 감소했습니다!" % sup))
			out.append(EstateCommand.new("synth", "💎 비전 마나 결정 연성", "학회 마법사들과 함께 대기 중의 마력을 응축하여 마나석 1개를 인공 연성합니다.",
				{"gold": 110, "ap": 1}, {"mana": 1},
				"비전 마력 응축에 성공하여 마나석 1개를 획득했습니다!"))
		"memorial":
			var mlv := _lv("기념관")
			var gain := 8 + mlv * 2
			out.append(EstateCommand.new("honor", "🕯️ 영령 추모 헌화 의식", "영지를 위해 싸운 영웅들을 기리며 민심을 +%d%% 회복하고 해소가능 스트레스를 %d 완화합니다." % [gain, gain],
				{"gold": 50}, {"morale": gain, "stress": -gain},
				"영령 추모 헌화 의식을 거행하여 민심이 +%d%% 오르고 스트레스가 감소했습니다!" % gain))
	return out


## 대상 용병이 필요한 행동 (대장간 제련, 훈련장 특훈)
static func for_merc(cmd_id: String, m: Mercenary) -> EstateCommand:
	match cmd_id:
		"forge":
			return EstateCommand.new("forge", "⚒️ 무기 제련", "개인 공격력 +2",
				{"gold": 90}, {"attack": 2},
				"{name}의 무기를 제련하여 개인 공격력이 {attack}(으)로 상승했습니다!", m)
		"train":
			var tg := training_gains()
			var hp_gain: int = int(tg["hp"])
			var atk_gain: int = int(tg["atk"])
			return EstateCommand.new("train", "🎯 실전 특훈", "레벨 +1, 최대 체력 +%d, 공격력 +%d" % [hp_gain, atk_gain],
				{"gold": 80, "ap": 1}, {"level": 1, "max_hp": hp_gain, "attack": atk_gain},
				"{name} 용병이 특훈을 마치고 Lv.{level}(으)로 성장했습니다! (HP +%d, 공격력 +%d)" % [hp_gain, atk_gain], m)
	return null
