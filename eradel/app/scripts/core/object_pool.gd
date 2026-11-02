class_name ObjectPool
extends RefCounted

## [오브젝트 풀] 자주 생성·해제되는 노드(데미지 텍스트, 효과음 플레이어)를 재사용한다.
## 해제된 노드는 트리에 남긴 채 숨겨두고, 다음 acquire() 때 다시 꺼내 쓴다.

var _factory: Callable
var _parent: Node
var _free: Array[Node] = []
var _created: int = 0


## factory: 새 노드를 만드는 Callable, parent: 생성 노드를 붙일 부모, prewarm: 미리 만들어 둘 개수
func _init(factory: Callable, parent: Node, prewarm: int = 0) -> void:
	_factory = factory
	_parent = parent
	for i in prewarm:
		release(_create())


## 풀에서 노드 하나를 꺼낸다. 비어 있으면 새로 만든다.
func acquire() -> Node:
	var n: Node = null
	# 부모와 함께 해제된 노드는 건너뛴다
	while not _free.is_empty() and n == null:
		var c: Node = _free.pop_back()
		if is_instance_valid(c):
			n = c
	if n == null:
		n = _create()
	if n is CanvasItem:
		n.visible = true
	return n


## 노드를 풀로 돌려보낸다. 중복 반환은 무시한다.
func release(n: Node) -> void:
	if not is_instance_valid(n) or _free.has(n):
		return
	if n is CanvasItem:
		n.visible = false
	_free.append(n)


## 지금까지 실제로 생성된 노드 수 (재사용 검증용)
func created_count() -> int:
	return _created


## 반환되어 대기 중인 노드 수
func free_count() -> int:
	return _free.size()


func _create() -> Node:
	var n: Node = _factory.call()
	_parent.add_child(n)
	_created += 1
	return n
