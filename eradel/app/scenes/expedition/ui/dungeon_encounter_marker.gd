class_name DungeonEncounterMarker
extends Control
## 갈림길에서 고른 목적지가 "저 앞 복도에 실제로 놓여 있는 것"처럼 보이게 하는 월드 오브젝트.
## 이모지가 떠다니는 대신, 기존 배경·횃불과 같은 pixelfx 도트 효과와 던전 스프라이트(몬스터·상인)를
## 복도 바닥(FEET_Y)에 세워 두고, 파티가 다가갈수록 어둠 속에서 서서히 드러나게 한다.
##   monster: 어둠 속 몬스터 실루엣(붉은 윤곽) / treasure: 닫힌 상자(도착 시 열림)
##   event  : 불안정한 균열(포털)             / shop    : 모닥불과 떠돌이 상인
##   boss   : 붉은 균열 앞의 거대한 실루엣

const CHEST_SHEET := "res://assets/sprites/vfx/chest_open/pickups/chest-open/chest-open.png"
const PORTAL_SHEET := "res://assets/sprites/vfx/portal/arcane/portal/portal.png"
const CAMPFIRE_SHEET := "res://assets/sprites/vfx/campfire/fire/campfire/campfire.png"
const MERCHANT_TEX := "res://assets/sprites/npc/npc_store.png"

## 전투 유닛(slot_y 165 + 도형 오프셋 20 + 발 146)과 같은 복도 바닥 y 좌표
const FEET_Y := 331.0
## 상자 시트에서 흔들림 구간이 끝나고 뚜껑이 열리기 시작하는 시각(초)
const CHEST_OPEN_FROM := 0.62
## 상자가 열리고 보물이 흩어져 자리잡을 때까지의 재생 길이(초)
const CHEST_OPEN_SEC := 2.2

## 목적지 종류(monster/treasure/event/shop/boss)
var kind: String = "monster"
## 오브젝트가 서는 가로 기준 좌표(스테이지 좌표계)
var anchor_x: float = 800.0
## 몬스터/보스 실루엣에 쓰는 몬스터 스프라이트
var mob_tex: Texture2D = null

var _t: float = 0.0
## 0 → 1: 파티가 다가오며 어둠 속에서 드러나는 정도
var _reveal: float = 0.0
## 도착 시 상자가 열리기 시작한 시각(-1이면 아직 닫힘)
var _open_at: float = -1.0
## 도착 순간 포털 등이 번쩍이는 세기(0~1)
var _flash: float = 0.0


## 종류와 실루엣 텍스처를 받아 위치와 입력 설정을 마친다.
func setup(p_kind: String, p_mob_tex: Texture2D = null) -> void:
	kind = p_kind
	mob_tex = p_mob_tex
	anchor_x = {"monster": 800.0, "treasure": 870.0, "event": 880.0, "shop": 800.0, "boss": 880.0}.get(kind, 820.0)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## 파티가 걸어가는 시간 동안 오브젝트가 어둠 속에서 드러나는 연출을 시작한다.
func approach(sec: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "_reveal", 1.0, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tw


## 도착 연출을 재생하고 연출이 끝나기까지 걸리는 시간(초)을 돌려준다.
func play_arrival() -> float:
	if kind == "treasure":
		_open_at = _t
		return CHEST_OPEN_SEC
	if kind == "event" or kind == "boss":
		_flash = 1.0
		create_tween().tween_property(self, "_flash", 0.0, 0.6)
		return 0.6
	return 0.0


## 서서히 사라진 뒤 스스로 제거한다.
func dismiss(sec: float = 0.3) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, sec)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 종류별 오브젝트를 복도 바닥에 그린다.
func _draw() -> void:
	var r := _reveal
	var alpha := smoothstep(0.0, 0.55, r)
	if alpha <= 0.0:
		return
	var fog := Color(0.42, 0.42, 0.52).lerp(Color.WHITE, r)
	fog.a = alpha
	var s := lerpf(0.88, 1.0, r)
	_draw_floor_glow(alpha, s)
	match kind:
		"monster":
			_draw_silhouette(fog, s, 1.0, alpha)
		"treasure":
			_draw_chest(fog, s)
		"event":
			_draw_portal(fog, s, 1.55, Color.WHITE)
		"shop":
			_draw_camp(fog, s)
		"boss":
			_draw_portal(fog, s, 2.0, Color(1.0, 0.42, 0.42))
			_draw_silhouette(fog, s, 1.35, alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 바닥에 퍼지는 종류별 색 조명(부드러운 다중 타원)과 접지 그림자.
func _draw_floor_glow(alpha: float, s: float) -> void:
	var glow := {
		"monster": Color(0.75, 0.1, 0.1), "treasure": Color(1.0, 0.8, 0.3),
		"event": Color(0.6, 0.4, 1.0), "shop": Color(1.0, 0.55, 0.2), "boss": Color(0.9, 0.12, 0.12),
	}.get(kind, Color.WHITE) as Color
	var pulse := 0.85 + 0.15 * sin(_t * 3.0)
	draw_set_transform(Vector2(anchor_x, FEET_Y), 0.0, Vector2(1.0, 0.25))
	# 경계가 딱딱해 보이지 않도록 5겹의 반투명 타원으로 부드럽게 퍼뜨린다
	for layer in [[175.0, 0.04], [140.0, 0.055], [108.0, 0.07], [78.0, 0.085], [52.0, 0.08]]:
		draw_circle(Vector2.ZERO, float(layer[0]) * s, Color(glow, float(layer[1]) * alpha * pulse))
	draw_circle(Vector2.ZERO, 44.0 * s, Color(0, 0, 0, 0.38 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 어둠 속에 웅크린 몬스터 실루엣: 거의 검은 몸체 + 맥동하는 붉은 윤곽.
func _draw_silhouette(fog: Color, s: float, size_mult: float, alpha: float) -> void:
	if mob_tex == null:
		return
	var h := 130.0 * size_mult
	var w := h * float(mob_tex.get_width()) / maxf(1.0, float(mob_tex.get_height()))
	var bob := sin(_t * 2.1) * 1.6
	draw_set_transform(Vector2(anchor_x - 30.0 * (size_mult - 1.0), FEET_Y + bob), 0.0, Vector2(s, s))
	var rect := Rect2(-w * 0.5, -h, w, h)
	var rim := 0.3 + 0.22 * sin(_t * 2.6)
	for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(-2, -2), Vector2(2, -2)]:
		draw_texture_rect(mob_tex, Rect2(rect.position + off, rect.size), false, Color(0.85, 0.12, 0.1, rim * alpha))
	draw_texture_rect(mob_tex, rect, false, Color(0.05, 0.04, 0.06, alpha))


## 닫힌 보물 상자(도착하면 뚜껑이 열리고 금화가 흩어진다).
func _draw_chest(fog: Color, s: float) -> void:
	var sc := 2.6 * s
	var t := fmod(_t, 0.5)
	if _open_at >= 0.0:
		t = CHEST_OPEN_FROM + minf(_t - _open_at, CHEST_OPEN_SEC)
	_draw_sheet(CHEST_SHEET, Vector2(176, 112), Vector2(88, 96), Vector2(anchor_x, FEET_Y), sc, t, fog)


## 불안정하게 일렁이는 균열(포털). 도착 순간 번쩍인다.
func _draw_portal(fog: Color, s: float, scale_mult: float, tint: Color) -> void:
	var c := fog * tint
	c = Color(minf(c.r + _flash * 0.6, 2.0), minf(c.g + _flash * 0.6, 2.0), minf(c.b + _flash * 0.6, 2.0), fog.a)
	_draw_sheet(PORTAL_SHEET, Vector2(152, 116), Vector2(76, 106), Vector2(anchor_x, FEET_Y), scale_mult * s, _t, c)


## 모닥불 옆에 선 떠돌이 상인.
func _draw_camp(fog: Color, s: float) -> void:
	_draw_sheet(CAMPFIRE_SHEET, Vector2(128, 128), Vector2(64, 112), Vector2(anchor_x - 75.0, FEET_Y), 1.35 * s, _t, fog)
	var tex := UiKit.get_cached_texture(MERCHANT_TEX)
	if tex == null:
		return
	var h := 150.0
	var w := h * float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	var breathe := 1.0 + 0.006 * sin(_t * 1.8)
	draw_set_transform(Vector2(anchor_x + 40.0, FEET_Y), 0.0, Vector2(s, s * breathe))
	draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false, fog * Color(1.0, 0.9, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## pixelfx 시트의 한 프레임을 pivot(바닥 기준점)이 지정 위치에 오도록 그린다.
func _draw_sheet(path: String, frame: Vector2, pivot: Vector2, feet: Vector2, sc: float, time: float, c: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var dst := Rect2(feet - pivot * sc, frame * sc)
	UiKit.draw_pixelfx_frame(self, path, dst, time, 0, c)
