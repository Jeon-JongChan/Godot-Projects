class_name DungeonCombatBackgroundCanvas
extends Control
## 고화질 던전 전투 배경 텍스처 및 실시간 횃불 파티클 애니메이션을 렌더링하는 전용 캔버스 클래스
var anim_time: float = 0.0
static var _bg_tex: Texture2D = null
static var _torch_tex: Texture2D = null

func _ready() -> void:
	set_process(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _bg_tex == null and ResourceLoader.exists("res://assets/sprites/textures/dungeon_combat_bg.png"):
		_bg_tex = load("res://assets/sprites/textures/dungeon_combat_bg.png")
	if _torch_tex == null and ResourceLoader.exists("res://assets/sprites/vfx/torch/fire/torch/torch.png"):
		_torch_tex = load("res://assets/sprites/vfx/torch/fire/torch/torch.png")

func _process(delta: float) -> void:
	anim_time += delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y

	# 1. 고화질 던전 전투 배경 텍스처 렌더링 (960x540)
	if _bg_tex != null:
		draw_texture_rect(_bg_tex, Rect2(0, 0, w, h), false)
	else:
		draw_rect(Rect2(0, 0, w, h), Color("0a0910"))

	# 2. 벽면 4개 횃불 위치에 pixelfx 실시간 횃불 화염 애니메이션 및 호박빛 조명 펄스 합성
	var arch_cx := w * 0.5
	var torch_xs := [arch_cx - 450.0, arch_cx - 190.0, arch_cx + 190.0, arch_cx + 450.0]
	var torch_y := 142.0

	for tx in torch_xs:
		# 화염 빛 파동 (배경 벽면 횃불과 자연스럽게 융합)
		var pulse := 0.22 + 0.08 * sin(anim_time * 6.0 + tx * 0.05)
		draw_circle(Vector2(tx, torch_y - 12.0), 42.0, Color(1.0, 0.45, 0.1, pulse * 0.35))
		draw_circle(Vector2(tx, torch_y - 12.0), 20.0, Color(1.0, 0.70, 0.2, pulse * 0.65))

		# pixelfx torch 실제 화염 시트 프레임 렌더링 (JSON 규격 통합 슬라이싱)
		var dst_r := Rect2(tx - 18.0, torch_y - 48.0, 36.0, 60.0)
		UiKit.draw_pixelfx_frame(self, "res://assets/sprites/vfx/torch/fire/torch/torch.png", dst_r, anim_time, int(tx), Color(1.0, 0.9, 0.8, 0.95))
