class_name DamagePipeline
extends RefCounted

## [책임 연쇄 패턴] 전투 데미지 계산 과정을 독립된 핸들러 체인으로 연결한다.
## 기본 공격력 → 대장간 파티 보너스 → 스킬 배율 → 치명타 판정 순으로 컨텍스트(Dictionary)를 가공한다.


## 데미지 계산 체인의 단일 핸들러 기반 클래스
class Handler extends RefCounted:
	var _next: Handler = null

	## 다음 핸들러를 연결하고 반환한다.
	func set_next(next_handler: Handler) -> Handler:
		_next = next_handler
		return next_handler

	## 컨텍스트를 처리하고 다음 핸들러로 넘긴다.
	func handle(ctx: Dictionary) -> Dictionary:
		_process(ctx)
		if _next != null:
			return _next.handle(ctx)
		return ctx

	## 하위 핸들러가 구현할 실제 계산 단계
	func _process(_ctx: Dictionary) -> void:
		pass


## 1단계: 공격자 기본 공격력과 난수 편차를 합산한다.
class BaseDamageHandler extends Handler:
	func _process(ctx: Dictionary) -> void:
		var rng: RandomNumberGenerator = ctx.get("rng")
		var base_atk: int = int(ctx.get("base_attack", 10))
		var spread: int = int(ctx.get("spread", 6))
		var roll: int = rng.randi_range(0, spread) if rng != null else 0
		ctx["damage"] = base_atk + roll


## 2단계: 아군 공격일 경우 대장간(무기 제련) 파티 공격력 보너스를 가산한다.
class BlacksmithBonusHandler extends Handler:
	func _process(ctx: Dictionary) -> void:
		if ctx.get("is_ally", false):
			var bonus: int = int(ctx.get("party_bonus", 0))
			ctx["damage"] = int(ctx.get("damage", 0)) + bonus


## 3단계: 일반 공격(1.0x) 또는 스킬/강타(1.4x 등) 배율을 적용한다.
class SkillMultiplierHandler extends Handler:
	func _process(ctx: Dictionary) -> void:
		var mult: float = float(ctx.get("multiplier", 1.0))
		ctx["damage"] = int(round(float(ctx.get("damage", 0)) * mult))


## 4단계: 치명타 확률을 판정하고 치명타 배율(아군 1.5x, 적군 1.4x)을 적용한다.
class CriticalHitHandler extends Handler:
	func _process(ctx: Dictionary) -> void:
		var rng: RandomNumberGenerator = ctx.get("rng")
		var is_ally: bool = ctx.get("is_ally", false)
		var is_skill: bool = ctx.get("is_skill", false)
		var crit_chance: int = (30 if is_skill else 12) if is_ally else 10
		var is_crit: bool = (rng.randi_range(1, 100) <= crit_chance) if rng != null else false
		ctx["is_crit"] = is_crit
		if is_crit:
			var crit_mult: float = 1.5 if is_ally else 1.4
			ctx["damage"] = int(float(ctx.get("damage", 0)) * crit_mult)


var _head: Handler


func _init() -> void:
	_head = BaseDamageHandler.new()
	_head.set_next(BlacksmithBonusHandler.new()) \
		.set_next(SkillMultiplierHandler.new()) \
		.set_next(CriticalHitHandler.new())


## 공격 컨텍스트를 체인에 통과시켜 최종 데미지와 치명타 여부를 반환한다.
func evaluate(ctx: Dictionary) -> Dictionary:
	return _head.handle(ctx)
