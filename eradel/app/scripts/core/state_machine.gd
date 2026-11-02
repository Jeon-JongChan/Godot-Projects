class_name StateMachine
extends RefCounted

## [유한 상태 기계] 상태별 진입/이탈 콜백과 허용 전이 표를 갖는 범용 FSM.
## 허용되지 않은 전이는 거부해, 연출 중 중복 입력(이중 공격 등)을 구조적으로 막는다.

signal state_changed(from: Variant, to: Variant)

var state: Variant = null
var _enter := {}   # 상태 -> Callable
var _exit := {}    # 상태 -> Callable
var _next := {}    # 상태 -> 허용되는 다음 상태 배열 (빈 배열이면 모든 전이 허용)


## 상태를 등록한다. next 가 비어 있으면 어느 상태로든 전이 가능.
func add(s: Variant, on_enter: Callable = Callable(), on_exit: Callable = Callable(), next: Array = []) -> StateMachine:
	_enter[s] = on_enter
	_exit[s] = on_exit
	_next[s] = next
	return self


## 현재 상태에서 to 로 전이 가능한지 검사한다. 최초 진입(state == null)은 항상 허용.
func can_go(to: Variant) -> bool:
	if not _enter.has(to):
		return false
	if state == null:
		return true
	var allowed: Array = _next.get(state, [])
	return allowed.is_empty() or allowed.has(to)


## 전이를 수행한다. 이탈 → 상태 변경 → 시그널 → 진입 순서. 실패 시 false.
func go(to: Variant) -> bool:
	if not can_go(to):
		push_warning("StateMachine: 허용되지 않은 전이 %s -> %s" % [state, to])
		return false
	var from: Variant = state
	if from != null and _exit[from].is_valid():
		_exit[from].call()
	state = to
	state_changed.emit(from, to)
	if _enter[to].is_valid():
		_enter[to].call()
	return true


## 현재 상태가 s 인지 확인한다.
func is_in(s: Variant) -> bool:
	return state == s
