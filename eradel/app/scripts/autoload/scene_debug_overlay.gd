extends CanvasLayer

## 씬 디버그 오버레이 — 사용자 요청에 따라 모든 화면에서 완전히 숨김 처리됨.


func _ready() -> void:
	# 모든 화면에서 보이지 않도록 즉시 제거
	queue_free()
