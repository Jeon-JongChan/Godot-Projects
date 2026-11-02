class_name FloatingText
extends Control

## 피격 또는 회복 시 대상 머리 위에 데미지/상태 숫자를 띄우고 서서히 페이드아웃하는 컴포넌트.
## [오브젝트 풀] on_finished 콜백이 지정되면 queue_free() 대신 풀로 반환하여 노드를 재사용한다.

var _container: Control
var _label: Label
var on_finished: Callable = Callable()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


## 이전 재사용 자식을 정리하고 알파값을 복원한다.
func _reset_for_reuse() -> void:
	modulate = Color.WHITE
	scale = Vector2.ONE
	for c in get_children():
		c.queue_free()


func _finish() -> void:
	if on_finished.is_valid():
		on_finished.call(self)
	else:
		queue_free()


## 플로팅 텍스트 초기 설정 및 상승 페이드 애니메이션 실행.
## [param text]: 표시할 문자열 (예: "-24", "CRITICAL! -75")
## [param color]: 텍스트 색상
## [param start_pos]: 시작 위치 (글로벌 좌표)
## [param is_crit]: 크리티컬 여부 (크기, 외곽선, 강조 배너 적용)
func popup(text: String, color: Color, start_pos: Vector2, is_crit: bool = false) -> void:
	_reset_for_reuse()
	global_position = start_pos
	z_index = 60

	_container = Control.new()
	_container.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_container)

	if is_crit:
		# 크리티컬 전용 강조 배경 배너 ([경량화] 공유 StyleBox 사용)
		var banner := PanelContainer.new()
		banner.mouse_filter = MOUSE_FILTER_IGNORE
		banner.add_theme_stylebox_override("panel", UiKit.style(Color(0.18, 0.04, 0.04, 0.85), Color("ffcc00"), 6, 2, 14, 4))

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 0)
		banner.add_child(vbox)

		# 크리티컬 헤더 라벨
		var crit_header := Label.new()
		crit_header.text = "⚡ CRITICAL! ⚡"
		crit_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crit_header.add_theme_font_size_override("font_size", 13)
		crit_header.add_theme_color_override("font_color", Color("ffd700"))
		crit_header.add_theme_color_override("font_outline_color", Color.BLACK)
		crit_header.add_theme_constant_override("outline_size", 4)
		vbox.add_child(crit_header)

		# 대형 데미지 숫자
		_label = Label.new()
		_label.text = text
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 28)
		_label.add_theme_color_override("font_color", Color("ff3300"))
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 6)
		vbox.add_child(_label)

		banner.pivot_offset = Vector2(90, 30)
		banner.position = Vector2(-90, -35)
		_container.add_child(banner)

		# 크리티컬 펀치 스케일 & 바운스 애니메이션
		_container.scale = Vector2(0.2, 0.2)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_container, "scale", Vector2(1.8, 1.8), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(_container, "scale", Vector2(1.1, 1.1), 0.15).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

		# 높은 위치로 서서히 부유
		var move_tween := create_tween()
		move_tween.tween_property(self, "position:y", position.y - 65.0, 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		# 페이드아웃 후 풀 반환
		var fade_tween := create_tween()
		fade_tween.tween_interval(0.55)
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.4)
		fade_tween.tween_callback(_finish)
	else:
		# 일반 피격 데미지 텍스트
		_label = Label.new()
		_label.text = text
		_label.add_theme_font_size_override("font_size", 18)
		_label.add_theme_color_override("font_color", color)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.pivot_offset = Vector2(50, 15)
		_label.custom_minimum_size = Vector2(100, 30)
		_label.position = Vector2(-50, -15)
		_container.add_child(_label)

		# 팝업 바운스 및 상승 페이드아웃 후 풀 반환
		_container.scale = Vector2(0.5, 0.5)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_container, "scale", Vector2(1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(_container, "scale", Vector2(1.0, 1.0), 0.1)

		var move_tween := create_tween()
		move_tween.tween_property(self, "position:y", position.y - 45.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		var fade_tween := create_tween()
		fade_tween.tween_interval(0.35)
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.35)
		fade_tween.tween_callback(_finish)


