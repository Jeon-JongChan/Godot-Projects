class_name VillageVisuals
extends RefCounted

## 클래시 오브 클랜 / 다키스트 던전 스타일의 2.5D 마을 지형, 건물 외관, 내부 일러스트, 영웅 초상화를
## 절차적 벡터/폴리곤 드로잉(CanvasItem._draw)으로 렌더링하는 시각 컴포넌트 모음.


## pixelfx 다중 행(Multi-row) 스프라이트 시트에서 현재 시각(t)에 해당하는 정확한 프레임 영역(Rect2)을 계산한다.
static func pixelfx_frame_rect(t: float, fps: float, total_frames: int, columns: int, frame_w: int, frame_h: int, frame_offset: int = 0) -> Rect2:
	var safe_total := maxi(1, total_frames)
	var safe_cols := maxi(1, columns)
	var idx := posmod(int(t * fps) + frame_offset, safe_total)
	var col := idx % safe_cols
	var row := int(idx / safe_cols)
	return Rect2(col * frame_w, row * frame_h, frame_w, frame_h)


## 마을 전체 배경 지형(하늘, 별, 산맥, 성벽, 잔디 언덕, 조약돌 도로, 가로등 불빛, 나무, 건물 터)을 그리는 캔버스
class VillageTerrainCanvas extends Control:
	var anim_time: float = 0.0
	var building_defs: Array[Dictionary] = []
	static var _estate_bg_tex: Texture2D = null
	static var _road_tex: Texture2D = null
	static var _torch_tex: Texture2D = null
	static var _campfire_tex: Texture2D = null

	## 초기화: 도트풍 텍스처 필터링(NEAREST) 및 도로 타일링(REPEAT) 활성화
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	## [업데이트 메서드] 상위 월드(EstateWorld)의 중앙 루프가 매 프레임 호출하여 애니메이션을 갱신한다.
	func update_tick(delta: float) -> void:
		anim_time += delta
		queue_redraw()

	## 다키스트 던전 1 스타일의 황혼녘 고딕 영지(The Estate) 도트풍 배경 지형을 렌더링한다.
	func _draw() -> void:
		var w := size.x
		var h := size.y

		# 고화질 도트풍 마을 배경 및 조약돌 도로 텍스처 지연 로드
		if _estate_bg_tex == null and ResourceLoader.exists("res://assets/sprites/textures/village_estate_bg.png"):
			_estate_bg_tex = load("res://assets/sprites/textures/village_estate_bg.png")
		if _road_tex == null and ResourceLoader.exists("res://assets/sprites/textures/village_cobblestone_road.png"):
			_road_tex = load("res://assets/sprites/textures/village_cobblestone_road.png")

		if _estate_bg_tex != null:
			# 2500x720 광폭 월드를 좌우 심리스 미러링으로 렌더링 (gl_compatibility 음수 Rect 폭 컬링 방지용 Transform2D 반전 적용)
			var half_w := w * 0.5
			draw_texture_rect(_estate_bg_tex, Rect2(0.0, 0.0, half_w, h), false)
			draw_set_transform(Vector2(w, 0.0), 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(_estate_bg_tex, Rect2(0.0, 0.0, half_w, h), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# 상단 하늘과 지평선 톤을 어둡게 눌러 건물과 UI 가독성 확보
			draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.04, 0.06, 0.25))
		else:
			# 폴백 단색 배경
			draw_rect(Rect2(0, 0, w, 255), Color("281014"))
			draw_rect(Rect2(0, 255, w, h - 255), Color("121014"))

		# 5. 마을 건물들을 연결하는 비에 젖은 어두운 조약돌 도로망 (Cobblestone)
		var road_paths := [
			[Vector2(40, 385), Vector2(185, 385), Vector2(315, 315), Vector2(600, 315), Vector2(710, 400), Vector2(1000, 315), Vector2(1292, 400), Vector2(1415, 315), Vector2(1705, 315), Vector2(1852, 410), Vector2(2182, 410)],
			[Vector2(315, 315), Vector2(457, 270), Vector2(1000, 260), Vector2(1557, 272), Vector2(1705, 315)],
			[Vector2(315, 315), Vector2(457, 542), Vector2(997, 542), Vector2(1552, 542), Vector2(1705, 315)],
			[Vector2(1000, 260), Vector2(1000, 542)],
		]
		for path in road_paths:
			_draw_cobblestone_path(path, 34.0)

		# 6. 어둠의 균열(dungeon_gate) 주변 붉은 기단 마법진만 은은히 유지하고 일반 건물 보라색 타원 기단은 제거
		for def in building_defs:
			if def.id == "dungeon_gate":
				var r: Rect2 = def.rect
				var center_bottom := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y - 16.0)
				var pad_rx := r.size.x * 0.42
				var pad_ry := 24.0
				_draw_ellipse(center_bottom, Vector2(pad_rx, pad_ry), Color(0.16, 0.04, 0.08, 0.36))
				_draw_ellipse_outline(center_bottom, Vector2(pad_rx - 4, pad_ry - 2), Color("6e2036", 0.55), 1.5)

		# 7. 묘지 십자가 비석들 (Cemetery Graves) 및 호박빛 횃불 랜턴
		var graves := [
			Vector2(320, 310), Vector2(350, 335), Vector2(640, 480), Vector2(1210, 245),
			Vector2(1520, 510), Vector2(1930, 530), Vector2(2380, 520)
		]
		for g in graves:
			_draw_cemetery_tombstone(g)

		# 불타오르는 철제 가로등 횃불
		var lamp_positions := [
			Vector2(305, 315), Vector2(585, 268), Vector2(585, 535),
			Vector2(830, 262), Vector2(1170, 262), Vector2(855, 535),
			Vector2(1145, 535), Vector2(1415, 315), Vector2(1705, 315),
			Vector2(1995, 405)
		]
		for lp in lamp_positions:
			_draw_street_lantern(lp)

		# 영웅숙소 앞마당 & 중앙 광장 pixelfx 모닥불 루프 애니메이션 (JSON 규격 통합 슬라이싱)
		for cpos in [Vector2(585, 305), Vector2(1000, 312)]:
			_draw_ellipse(cpos + Vector2(0, 6), Vector2(30, 12), Color(1.0, 0.55, 0.15, 0.24))
			UiKit.draw_pixelfx_frame(self, "res://assets/sprites/vfx/campfire/fire/campfire/campfire.png", Rect2(cpos.x - 32, cpos.y - 56, 64, 64), anim_time, 0, Color(1.0, 0.95, 0.85, 0.92))

		# 파노라마 전역을 떠다니는 미세 황혼 불티·반딧불 입자 (18개)
		_draw_ambient_fireflies(w, h)

	## 타원 채우기 헬퍼
	func _draw_ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in range(28):
			var a := float(i) * TAU / 28.0
			pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		draw_colored_polygon(pts, col)

	## 타원 외곽선 헬퍼
	func _draw_ellipse_outline(center: Vector2, radii: Vector2, col: Color, width: float = 1.5) -> void:
		var pts := PackedVector2Array()
		for i in range(29):
			var a := float(i) * TAU / 28.0
			pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		draw_polyline(pts, col, width)

	## 조약돌 도로 드로잉
	## 도트풍 조약돌 도로 텍스처 타일링 렌더링 (가장자리 고딕 음영 테두리 포함)
	func _draw_cobblestone_path(points: Array, width: float) -> void:
		for i in range(points.size() - 1):
			var p0: Vector2 = points[i]
			var p1: Vector2 = points[i + 1]
			var seg_len := p0.distance_to(p1)
			if seg_len < 1.0:
				continue

			# 도로 양옆 흙 경계선 및 그림자
			draw_line(p0, p1, Color("161215", 0.90), width + 10.0)
			draw_circle(p0, (width + 10.0) * 0.5, Color("161215", 0.90))
			draw_circle(p1, (width + 10.0) * 0.5, Color("161215", 0.90))

			if _road_tex != null:
				var dir := (p1 - p0).normalized()
				var perp := Vector2(-dir.y, dir.x) * (width * 0.5)
				var rep := maxf(1.0, seg_len / 52.0)

				var quad_pts := PackedVector2Array([p0 - perp, p1 - perp, p1 + perp, p0 + perp])
				var uvs := PackedVector2Array([Vector2(0, 0), Vector2(rep, 0), Vector2(rep, 1.0), Vector2(0, 1.0)])
				var cols := PackedColorArray([Color(0.85, 0.85, 0.9, 1.0), Color(0.85, 0.85, 0.9, 1.0), Color(0.85, 0.85, 0.9, 1.0), Color(0.85, 0.85, 0.9, 1.0)])
				draw_polygon(quad_pts, cols, uvs, _road_tex)

				# 교차점 이음새 조약돌 캡
				draw_circle(p0, width * 0.46, Color("2e2a32"))
				draw_circle(p1, width * 0.46, Color("2e2a32"))
			else:
				draw_line(p0, p1, Color("382f24"), width)
				draw_circle(p0, width * 0.5, Color("382f24"))
				draw_circle(p1, width * 0.5, Color("382f24"))

	## 다키스트 던전 스타일 앙상한 가시나무(Dead Tree) 드로잉
	func _draw_gothic_dead_tree(pos: Vector2) -> void:
		_draw_ellipse(pos + Vector2(0, 4), Vector2(16, 6), Color(0, 0, 0, 0.55))
		var trunk_c := Color("140f16")
		# 뒤틀린 줄기
		draw_line(pos, pos + Vector2(-3, -26), trunk_c, 5.0)
		draw_line(pos + Vector2(-3, -26), pos + Vector2(4, -48), trunk_c, 4.0)
		# 앙상한 가지들
		draw_line(pos + Vector2(-3, -26), pos + Vector2(-16, -42), trunk_c, 2.5)
		draw_line(pos + Vector2(-16, -42), pos + Vector2(-24, -50), trunk_c, 1.5)
		draw_line(pos + Vector2(4, -48), pos + Vector2(18, -62), trunk_c, 2.0)
		draw_line(pos + Vector2(4, -48), pos + Vector2(-8, -66), trunk_c, 2.0)
		# 나뭇가지 끝에 앉은 불길한 까마귀 실루엣
		draw_circle(pos + Vector2(18, -64), 2.5, Color("080608"))

	## 공동묘지 십자가 묘비(Tombstone) 드로잉
	func _draw_cemetery_tombstone(pos: Vector2) -> void:
		_draw_ellipse(pos + Vector2(0, 2), Vector2(10, 4), Color(0, 0, 0, 0.45))
		# 석조 비석 십자가
		var stone_c := Color("302a34")
		draw_rect(Rect2(pos.x - 2, pos.y - 18, 4, 18), stone_c)
		draw_rect(Rect2(pos.x - 7, pos.y - 14, 14, 4), stone_c)
		# 십자가 하이라이트
		draw_line(Vector2(pos.x, pos.y - 18), Vector2(pos.x, pos.y), Color("4a4252"), 1.0)

	## 마을 길가 횃불/가로등 및 pixelfx 실시간 불꽃·불티 드로잉
	func _draw_street_lantern(pos: Vector2) -> void:
		var pulse := 0.85 + 0.15 * sin(anim_time * 5.0 + pos.x)
		# 바닥 빛무리
		_draw_ellipse(pos + Vector2(0, 2), Vector2(38 * pulse, 17 * pulse), Color(0.95, 0.65, 0.20, 0.14 * pulse))
		# 기둥
		draw_rect(Rect2(pos.x - 2, pos.y - 26, 4, 28), Color("2b241d"))
		draw_line(Vector2(pos.x - 2, pos.y - 25), Vector2(pos.x + 7, pos.y - 25), Color("4a3e31"), 2.0)
		# 등불 코어 및 pixelfx torch 불꽃 합성
		var glow_pos := Vector2(pos.x + 7, pos.y - 22)
		draw_circle(glow_pos, 15.0 * pulse, Color(1.0, 0.68, 0.22, 0.24))
		draw_circle(glow_pos, 4.5, Color(1.0, 0.88, 0.45, 0.95))
		UiKit.draw_pixelfx_frame(self, "res://assets/sprites/vfx/torch/fire/torch/torch.png", Rect2(glow_pos.x - 10, glow_pos.y - 22, 20, 26), anim_time, int(pos.x * 0.1), Color(1.0, 0.92, 0.80, 0.90))
		# 가로등 위로 흩날리는 금빛 불티
		for e in range(2):
			var et := fmod(anim_time * 0.85 + pos.x * 0.01 + float(e) * 0.5, 1.0)
			var epos := glow_pos + Vector2(sin(et * 6.0 + float(e)) * 4.0, -8.0 - et * 18.0)
			draw_circle(epos, 1.4, Color(1.0, 0.82, 0.35, (1.0 - et) * 0.75))


	## 영지 파노라마 전역을 떠다니는 반딧불·황혼 부유 입자를 그린다.
	func _draw_ambient_fireflies(w: float, h: float) -> void:
		for i in range(18):
			var fi := float(i)
			var px := fmod(fi * 139.0 + sin(anim_time * 0.45 + fi * 1.7) * 32.0 + w, w)
			var py := 150.0 + fmod(fi * 97.0, h - 240.0) + cos(anim_time * 0.75 + fi * 1.3) * 14.0
			var glow := 0.28 + 0.42 * (0.5 + 0.5 * sin(anim_time * 2.4 + fi * 2.1))
			var col := Color(0.88, 0.45, 0.95, glow * 0.7) if px > 1950.0 else Color(1.0, 0.80, 0.36, glow)
			draw_circle(Vector2(px, py), 4.5, Color(col.r, col.g, col.b, col.a * 0.25))
			draw_circle(Vector2(px, py), 1.6, col)


## 개별 마을 건물을 2.5D 다키스트 던전 도트 스프라이트와 애니메이션으로 그리는 캔버스
class VillageBuildingCanvas extends Control:
	var def: Dictionary = {}
	var is_hovered: bool = false
	var anim_time: float = 0.0
	static var _b_tex_cache: Dictionary = {}
	static var _portal_tex: Texture2D = null

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	## [업데이트 메서드] 개별 _process 대신 상위 월드의 단일 루프에서 일괄 호출된다.
	func update_tick(delta: float) -> void:
		anim_time += delta
		queue_redraw()

	func _get_building_texture(bid: String) -> Texture2D:
		if _b_tex_cache.has(bid):
			return _b_tex_cache[bid]
		var path := "res://assets/sprites/buildings/%s.png" % bid
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		_b_tex_cache[bid] = tex
		return tex

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var bid: String = def.get("id", "")
		var btype: String = def.get("type", "guild")

		# 건물 실제 바닥 접지 그림자 (보라색 타원 제거 후 은은한 검은 그림자만 유지)
		_draw_ellipse(Vector2(w * 0.5, h - 22), Vector2(w * 0.42, 16), Color(0.02, 0.02, 0.03, 0.45))

		# 호버 시 건물 바닥 황금빛 선택 오라 표시
		if is_hovered:
			_draw_ellipse(Vector2(w * 0.5, h - 20), Vector2(w * 0.46, 22), Color(0.95, 0.78, 0.32, 0.24))
			_draw_ellipse_outline(Vector2(w * 0.5, h - 20), Vector2(w * 0.46, 22), UiKit.GOLD2, 2.5)

		var tex := _get_building_texture(bid)
		if tex != null:
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			var fit_scale := minf((w * 0.96) / maxf(1.0, tw), (h * 0.96) / maxf(1.0, th))
			var draw_w := tw * fit_scale
			var draw_h := th * fit_scale
			var draw_x := (w - draw_w) * 0.5
			# PNG 하단 투명 여백 보정으로 건물이 명패 위에 공중 부양하지 않고 땅에 착지하도록 정렬
			var bottom_trim := 4.0
			if bid == "general_store":
				bottom_trim = 28.0
			elif bid in ["hero_lodge", "manor", "memorial_hall", "mercenary_outpost", "sanatorium", "training_camp", "dungeon_gate"]:
				bottom_trim = 10.0
			var draw_y := (h - 14.0) - draw_h + bottom_trim
			var tint := Color(1.16, 1.12, 1.04, 1.0) if is_hovered else Color.WHITE
			draw_texture_rect(tex, Rect2(draw_x, draw_y, draw_w, draw_h), false, tint)

			# 어둠의 균열(dungeon_gate) 위 pixelfx 차원문 에너지 애니메이션 합성
			if bid == "dungeon_gate":
				var p_dst := Rect2(w * 0.5 - 52, draw_y + draw_h * 0.30, 104, 80)
				UiKit.draw_pixelfx_frame(self, "res://assets/sprites/vfx/portal/arcane/portal/portal.png", p_dst, anim_time, 0, Color(1.0, 0.55, 0.75, 0.92))
			# 대장간 화덕 따뜻한 점멸 글로우 & 굴뚝 도트 연기
			elif bid == "blacksmith":
				var pulse := 0.22 + 0.12 * sin(anim_time * 7.0)
				draw_circle(Vector2(draw_x + draw_w * 0.65, draw_y + draw_h * 0.64), 24.0, Color(1.0, 0.42, 0.1, pulse))
			return

		match btype:
			"guild":
				_draw_guild_building(w, h)
			"lodge":
				_draw_lodge_building(w, h)
			"treatment":
				_draw_sanatorium_building(w, h)
			"manor":
				_draw_manor_building(w, h)
			"store":
				_draw_store_building(w, h)
			"blacksmith":
				_draw_blacksmith_building(w, h)
			"warehouse":
				_draw_warehouse_building(w, h)
			"training":
				_draw_training_building(w, h)
			"magic":
				_draw_magic_building(w, h)
			"memorial":
				_draw_memorial_building(w, h)
			"dungeon":
				_draw_dungeon_portal(w, h)

	func _draw_ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in range(24):
			var a := float(i) * TAU / 24.0
			pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		draw_colored_polygon(pts, col)

	func _draw_ellipse_outline(center: Vector2, radii: Vector2, col: Color, width: float = 2.0) -> void:
		var pts := PackedVector2Array()
		for i in range(25):
			var a := float(i) * TAU / 24.0
			pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		draw_polyline(pts, col, width)

	func _draw_window(rect: Rect2, lit: bool = true) -> void:
		draw_rect(rect.grow(2), Color("241c14"))
		var glow := Color(0.98, 0.78, 0.35, 0.92) if lit else Color("1c222e")
		draw_rect(rect, glow)
		# 창살 십자선
		draw_line(Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y), Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y), Color("241c14"), 2.0)
		draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5), Vector2(rect.end.x, rect.position.y + rect.size.y * 0.5), Color("241c14"), 2.0)

	## 1. 용병모집소 (중세 하프팀버 길드 회관 & 의뢰 게시판 & 깃발)
	func _draw_guild_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 석조 기단
		draw_rect(Rect2(cx - 72, base_y - 16, 144, 16), Color("3c352d"))
		# 본관 목조/회벽 몸체
		draw_rect(Rect2(cx - 66, base_y - 78, 132, 62), Color("524130"))
		draw_rect(Rect2(cx - 60, base_y - 74, 120, 54), Color("6b553f"))
		# 기둥 목재 프레임
		for px in [-62, -22, 22, 58]:
			draw_rect(Rect2(cx + px - 3, base_y - 78, 6, 62), Color("2e2218"))
		# 급경사 붉은 기와 지붕
		var roof := PackedVector2Array([
			Vector2(cx - 82, base_y - 74), Vector2(cx + 82, base_y - 74),
			Vector2(cx + 56, base_y - 126), Vector2(cx - 56, base_y - 126)
		])
		draw_colored_polygon(roof, Color("6e2822"))
		draw_polyline(roof, Color("3a1512"), 2.5)
		# 중앙 박공 다락 지붕
		var gable := PackedVector2Array([
			Vector2(cx - 34, base_y - 74), Vector2(cx, base_y - 138), Vector2(cx + 34, base_y - 74)
		])
		draw_colored_polygon(gable, Color("84322a"))
		draw_polyline(gable, Color("e0b865") if is_hovered else Color("4a1c17"), 2.5)
		# 출입문 및 계단
		draw_rect(Rect2(cx - 14, base_y - 44, 28, 36), Color("2a1c12"))
		draw_rect(Rect2(cx - 11, base_y - 41, 22, 33), Color("422b1b"))
		# 좌우 빛나는 창문
		_draw_window(Rect2(cx - 50, base_y - 60, 20, 22))
		_draw_window(Rect2(cx + 30, base_y - 60, 20, 22))
		# 우측 야외 의뢰 게시판 (Bounty Board)
		draw_rect(Rect2(cx + 50, base_y - 42, 28, 30), Color("332316"))
		draw_rect(Rect2(cx + 53, base_y - 39, 22, 18), Color("4d3622"))
		draw_rect(Rect2(cx + 55, base_y - 37, 7, 9), Color("d8c8a8"))
		draw_rect(Rect2(cx + 65, base_y - 36, 7, 10), Color("e6d8b8"))
		# 검과 방패 간판
		draw_circle(Vector2(cx, base_y - 98), 12.0, Color("c9a84c"))
		draw_circle(Vector2(cx, base_y - 98), 9.0, Color("6e2822"))
		# 좌측 붉은 길드 깃발
		var wave := sin(anim_time * 3.5) * 3.0
		draw_line(Vector2(cx - 72, base_y - 10), Vector2(cx - 72, base_y - 95), Color("4a3a28"), 3.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 72, base_y - 93), Vector2(cx - 48, base_y - 87 + wave), Vector2(cx - 72, base_y - 78)
		]), Color("c03830"))

	## 2. 영웅숙소 (2층 석조/목조 여관 & 굴뚝 연기 & 모닥불)
	func _draw_lodge_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 굴뚝 및 피어오르는 연기 애니메이션
		draw_rect(Rect2(cx + 42, base_y - 134, 16, 55), Color("4a3f37"))
		for s in range(3):
			var t := fmod(anim_time * 0.7 + float(s) * 0.33, 1.0)
			var spos := Vector2(cx + 50 + sin(t * 6.0) * 6.0, base_y - 138 - t * 28.0)
			draw_circle(spos, 5.0 + t * 6.0, Color(0.85, 0.85, 0.88, (1.0 - t) * 0.45))

		# 1층 석조 벽면 + 2층 목조 벽면
		draw_rect(Rect2(cx - 70, base_y - 45, 140, 35), Color("443e38"))
		draw_rect(Rect2(cx - 66, base_y - 82, 132, 39), Color("68533d"))
		# 푸른 갈색 박공 지붕
		var roof := PackedVector2Array([
			Vector2(cx - 80, base_y - 78), Vector2(cx + 80, base_y - 78),
			Vector2(cx + 60, base_y - 122), Vector2(cx - 60, base_y - 122)
		])
		draw_colored_polygon(roof, Color("354839"))
		draw_polyline(roof, Color("e0b865") if is_hovered else Color("1f2c22"), 2.5)
		# 1층, 2층 따뜻한 창문들
		_draw_window(Rect2(cx - 50, base_y - 72, 18, 18))
		_draw_window(Rect2(cx - 9, base_y - 72, 18, 18))
		_draw_window(Rect2(cx + 32, base_y - 72, 18, 18))
		_draw_window(Rect2(cx - 48, base_y - 40, 20, 18))
		# 여관 출입문
		draw_rect(Rect2(cx - 10, base_y - 42, 22, 32), Color("3a2414"))
		# 앞마당 모닥불 (Campfire)
		var fire_pos := Vector2(cx + 42, base_y - 16)
		draw_line(fire_pos + Vector2(-9, 3), fire_pos + Vector2(9, -2), Color("3d2616"), 4.0)
		draw_line(fire_pos + Vector2(-9, -2), fire_pos + Vector2(9, 3), Color("3d2616"), 4.0)
		var flicker := sin(anim_time * 8.0) * 2.5
		draw_circle(fire_pos + Vector2(0, -4), 14.0, Color(1.0, 0.55, 0.15, 0.25))
		draw_colored_polygon(PackedVector2Array([
			fire_pos + Vector2(-7, 0), fire_pos + Vector2(7, 0), fire_pos + Vector2(flicker, -16)
		]), Color("ff7722"))
		draw_colored_polygon(PackedVector2Array([
			fire_pos + Vector2(-4, 0), fire_pos + Vector2(4, 0), fire_pos + Vector2(flicker * 0.5, -10)
		]), Color("ffdd44"))

	## 3. 치료소 (고딕 백색 석조 성당 진료소 & 스테인드글라스 & 십자 엠블럼)
	func _draw_sanatorium_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 석조 본관
		draw_rect(Rect2(cx - 64, base_y - 78, 128, 68), Color("6e6a63"))
		draw_rect(Rect2(cx - 58, base_y - 74, 116, 60), Color("858078"))
		# 중앙 첨탑과 청회색 지붕
		var roof := PackedVector2Array([
			Vector2(cx - 74, base_y - 74), Vector2(cx + 74, base_y - 74),
			Vector2(cx + 50, base_y - 114), Vector2(cx - 50, base_y - 114)
		])
		draw_colored_polygon(roof, Color("2d4252"))
		var spire := PackedVector2Array([
			Vector2(cx - 28, base_y - 74), Vector2(cx, base_y - 142), Vector2(cx + 28, base_y - 74)
		])
		draw_colored_polygon(spire, Color("385266"))
		draw_polyline(spire, Color("e0b865") if is_hovered else Color("1d2b36"), 2.5)
		# 첨탑 꼭대기 황금 십자가
		draw_line(Vector2(cx, base_y - 156), Vector2(cx, base_y - 138), UiKit.GOLD2, 3.0)
		draw_line(Vector2(cx - 6, base_y - 150), Vector2(cx + 6, base_y - 150), UiKit.GOLD2, 3.0)
		# 스테인드글라스 아치 창문
		draw_rect(Rect2(cx - 46, base_y - 60, 16, 28), Color("48a8c8"))
		draw_rect(Rect2(cx + 30, base_y - 60, 16, 28), Color("48a8c8"))
		# 정면 적십자 엠블럼
		draw_circle(Vector2(cx, base_y - 94), 11.0, Color("f0ece1"))
		draw_rect(Rect2(cx - 3, base_y - 101, 6, 14), Color("c83232"))
		draw_rect(Rect2(cx - 7, base_y - 97, 14, 6), Color("c83232"))
		# 출입문
		draw_rect(Rect2(cx - 13, base_y - 42, 26, 32), Color("36281e"))

	## 4. 영주저택 (웅장한 중앙 성채 & 쌍둥이 탑 & 왕실 깃발)
	func _draw_manor_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 넓은 석조 테라스 기단 및 중앙 계단
		draw_rect(Rect2(cx - 125, base_y - 22, 250, 20), Color("3d3730"))
		draw_rect(Rect2(cx - 32, base_y - 22, 64, 22), Color("574e44"))
		# 좌우 쌍둥이 성탑
		for side in [-1.0, 1.0]:
			var tx: float = cx + float(side) * 88.0
			draw_rect(Rect2(tx - 26, base_y - 115, 52, 95), Color("4f483f"))
			draw_rect(Rect2(tx - 22, base_y - 112, 44, 90), Color("635a4f"))
			# 고깔 성탑 지붕
			var cone := PackedVector2Array([
				Vector2(tx - 32, base_y - 112), Vector2(tx + 32, base_y - 112), Vector2(tx, base_y - 158)
			])
			draw_colored_polygon(cone, Color("263e5c"))
			draw_polyline(cone, UiKit.GOLD, 2.0)
			_draw_window(Rect2(tx - 8, base_y - 92, 16, 24))

		# 중앙 본성 대강당
		draw_rect(Rect2(cx - 72, base_y - 98, 144, 78), Color("5c5348"))
		var main_roof := PackedVector2Array([
			Vector2(cx - 80, base_y - 96), Vector2(cx + 80, base_y - 96),
			Vector2(cx + 55, base_y - 142), Vector2(cx - 55, base_y - 142)
		])
		draw_colored_polygon(main_roof, Color("782424"))
		draw_polyline(main_roof, UiKit.GOLD2 if is_hovered else UiKit.GOLD, 2.5)
		# 중앙 첨탑 박공 및 황금 왕관 문장
		var center_gable := PackedVector2Array([
			Vector2(cx - 38, base_y - 96), Vector2(cx, base_y - 156), Vector2(cx + 38, base_y - 96)
		])
		draw_colored_polygon(center_gable, Color("912c2c"))
		draw_polyline(center_gable, UiKit.GOLD, 2.5)
		draw_circle(Vector2(cx, base_y - 118), 11.0, UiKit.GOLD)
		# 대형 아치 정문 및 창문
		draw_rect(Rect2(cx - 18, base_y - 56, 36, 38), Color("2b1d12"))
		draw_rect(Rect2(cx - 14, base_y - 52, 28, 34), Color("47301e"))
		_draw_window(Rect2(cx - 54, base_y - 78, 22, 28))
		_draw_window(Rect2(cx + 32, base_y - 78, 22, 28))
		# 붉은 왕실 배너 2개
		for bside in [-1.0, 1.0]:
			var bx: float = cx + float(bside) * 24.0
			draw_rect(Rect2(bx - 5, base_y - 88, 10, 34), Color("b82828"))
			draw_rect(Rect2(bx - 5, base_y - 88, 10, 4), UiKit.GOLD)

	## 5. 잡화점 (줄무늬 차양막 상점 & 포션 진열대 & 오크통)
	func _draw_store_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 상점 본체
		draw_rect(Rect2(cx - 60, base_y - 72, 120, 62), Color("5e4832"))
		var roof := PackedVector2Array([
			Vector2(cx - 70, base_y - 70), Vector2(cx + 70, base_y - 70),
			Vector2(cx + 48, base_y - 112), Vector2(cx - 48, base_y - 112)
		])
		draw_colored_polygon(roof, Color("7a4b24"))
		draw_polyline(roof, UiKit.GOLD if is_hovered else Color("3d2410"), 2.0)
		# 붉은색/금색 줄무늬 시장 차양막 (Striped Awning)
		for i in range(6):
			var ax := cx - 60 + i * 20.0
			var acol := Color("b83228") if (i % 2 == 0) else Color("e6d2a2")
			draw_rect(Rect2(ax, base_y - 56, 20, 18), acol)
		# 진열대 카운터 및 알록달록한 포션 병
		draw_rect(Rect2(cx - 52, base_y - 28, 72, 18), Color("3d2918"))
		draw_circle(Vector2(cx - 38, base_y - 33), 5.0, Color("e03c3c"))
		draw_circle(Vector2(cx - 22, base_y - 33), 5.0, Color("3c8ce0"))
		draw_circle(Vector2(cx - 6, base_y - 33), 5.0, Color("48c868"))
		# 우측 오크통과 상자
		draw_rect(Rect2(cx + 30, base_y - 32, 22, 22), Color("4f351e"))
		draw_rect(Rect2(cx + 30, base_y - 24, 22, 3), Color("242424"))
		# 황금 천칭 간판
		draw_circle(Vector2(cx, base_y - 90), 10.0, UiKit.GOLD)

	## 6. 대장간 (용광로 굴뚝 & 타오르는 화덕 불꽃 & 모루)
	func _draw_blacksmith_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 거대한 벽돌 용광로 굴뚝 + 불티 연기
		draw_rect(Rect2(cx - 58, base_y - 128, 34, 118), Color("3e2f2b"))
		draw_rect(Rect2(cx - 62, base_y - 132, 42, 8), Color("2b201d"))
		var spark_y := fmod(anim_time * 24.0, 26.0)
		draw_circle(Vector2(cx - 41, base_y - 138 - spark_y), 3.0, Color("ff8822"))
		# 대장간 석조 작업장
		draw_rect(Rect2(cx - 30, base_y - 74, 96, 64), Color("453e3a"))
		var roof := PackedVector2Array([
			Vector2(cx - 36, base_y - 72), Vector2(cx + 74, base_y - 72),
			Vector2(cx + 56, base_y - 104), Vector2(cx - 28, base_y - 104)
		])
		draw_colored_polygon(roof, Color("2b2625"))
		draw_polyline(roof, UiKit.GOLD if is_hovered else Color("5c4838"), 2.0)
		# 타오르는 용광로 화덕 아치 (Roaring Forge Fire)
		var pulse := 0.85 + 0.15 * sin(anim_time * 9.0)
		draw_rect(Rect2(cx - 18, base_y - 52, 36, 40), Color("1c1412"))
		draw_circle(Vector2(cx, base_y - 28), 16.0 * pulse, Color(1.0, 0.38, 0.08, 0.85))
		draw_circle(Vector2(cx, base_y - 26), 10.0 * pulse, Color(1.0, 0.78, 0.20, 0.95))
		# 앞마당 강철 모루(Anvil)
		draw_rect(Rect2(cx + 34, base_y - 22, 18, 12), Color("4a321e"))
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx + 26, base_y - 30), Vector2(cx + 60, base_y - 30),
			Vector2(cx + 52, base_y - 22), Vector2(cx + 32, base_y - 22)
		]), Color("7a828c"))

	## 7. 창고 (철제 보강 석조 금고 & 보물상자 & 마나석 결정)
	func _draw_warehouse_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 튼튼한 석조 창고 본체
		draw_rect(Rect2(cx - 64, base_y - 76, 128, 66), Color("4a4844"))
		# 철제 보강 띠
		draw_rect(Rect2(cx - 64, base_y - 56, 128, 5), Color("282a2e"))
		draw_rect(Rect2(cx - 64, base_y - 32, 128, 5), Color("282a2e"))
		# 아치형 지붕
		var roof := PackedVector2Array([
			Vector2(cx - 70, base_y - 74), Vector2(cx + 70, base_y - 74),
			Vector2(cx + 50, base_y - 108), Vector2(cx - 50, base_y - 108)
		])
		draw_colored_polygon(roof, Color("363a42"))
		draw_polyline(roof, UiKit.GOLD if is_hovered else Color("22252a"), 2.5)
		# 대형 철문 및 황금 자물쇠
		draw_rect(Rect2(cx - 22, base_y - 52, 44, 42), Color("2b3038"))
		draw_circle(Vector2(cx, base_y - 32), 7.0, UiKit.GOLD)
		# 앞마당 푸른 마나석 결정과 보물상자
		draw_rect(Rect2(cx - 54, base_y - 26, 22, 16), Color("6e4726"))
		draw_rect(Rect2(cx - 54, base_y - 20, 22, 3), UiKit.GOLD)
		var mana_pts := PackedVector2Array([
			Vector2(cx + 42, base_y - 10), Vector2(cx + 34, base_y - 24),
			Vector2(cx + 44, base_y - 38), Vector2(cx + 54, base_y - 22)
		])
		draw_colored_polygon(mana_pts, Color("3898ff"))

	## 8. 훈련장 (목책 연병장 & 허수아비 & 활 과녁판 & 군기)
	func _draw_training_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 모래 연병장 바닥
		_draw_ellipse(Vector2(cx, base_y - 22), Vector2(88, 24), Color("594833"))
		# 뒷편 통나무 목책(Palisade) 및 지휘 천막
		for i in range(-5, 6):
			var px := cx + i * 14.0
			draw_rect(Rect2(px - 5, base_y - 78, 10, 46), Color("4a3522"))
		var tent := PackedVector2Array([
			Vector2(cx - 56, base_y - 72), Vector2(cx + 56, base_y - 72), Vector2(cx, base_y - 116)
		])
		draw_colored_polygon(tent, Color("8a2e26"))
		draw_polyline(tent, UiKit.GOLD if is_hovered else Color("4a1814"), 2.5)
		# 좌측 훈련용 나무 허수아비 (Training Dummy)
		draw_line(Vector2(cx - 38, base_y - 14), Vector2(cx - 38, base_y - 54), Color("3d2816"), 4.0)
		draw_line(Vector2(cx - 52, base_y - 40), Vector2(cx - 24, base_y - 40), Color("3d2816"), 4.0)
		draw_rect(Rect2(cx - 45, base_y - 46, 14, 18), Color("9c7e54"))
		draw_circle(Vector2(cx - 38, base_y - 54), 7.0, Color("b89868"))
		# 우측 활 과녁판 (Archery Bullseye Target)
		var tpos := Vector2(cx + 36, base_y - 38)
		draw_circle(tpos, 16.0, Color("e8dcc8"))
		draw_circle(tpos, 11.0, Color("c83232"))
		draw_circle(tpos, 6.0, Color("e8dcc8"))
		draw_circle(tpos, 3.0, Color("c83232"))

	## 9. 마법사학회 (신비로운 비전 마탑 & 부유하는 마나 크리스탈)
	func _draw_magic_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 바닥 마법진 오라
		var pulse := 0.8 + 0.2 * sin(anim_time * 3.0)
		_draw_ellipse_outline(Vector2(cx, base_y - 16), Vector2(76, 20), Color(0.45, 0.35, 0.95, 0.55 * pulse), 2.0)
		# 마탑 원통형 석조 몸체
		draw_rect(Rect2(cx - 46, base_y - 98, 92, 86), Color("36324a"))
		draw_rect(Rect2(cx - 38, base_y - 96, 76, 84), Color("464060"))
		# 뾰족한 마법사 고깔 지붕
		var spire := PackedVector2Array([
			Vector2(cx - 58, base_y - 94), Vector2(cx + 58, base_y - 94), Vector2(cx, base_y - 152)
		])
		draw_colored_polygon(spire, Color("282048"))
		draw_polyline(spire, Color("9a7aff") if is_hovered else Color("5c4898"), 2.5)
		# 부유하는 비전 마나 수정 (Floating Crystal)
		var bob := sin(anim_time * 3.2) * 5.0
		var cpos := Vector2(cx, base_y - 166 + bob)
		draw_circle(cpos, 16.0, Color(0.55, 0.38, 1.0, 0.28))
		draw_colored_polygon(PackedVector2Array([
			cpos + Vector2(0, -12), cpos + Vector2(8, 0), cpos + Vector2(0, 12), cpos + Vector2(-8, 0)
		]), Color("70d8ff"))
		# 보랏빛 발광 창문
		draw_rect(Rect2(cx - 26, base_y - 76, 16, 24), Color("a868ff"))
		draw_rect(Rect2(cx + 10, base_y - 76, 16, 24), Color("a868ff"))
		draw_rect(Rect2(cx - 12, base_y - 42, 24, 30), Color("221a36"))

	## 10. 기념관 (고대 대리석 판테온 신전 & 영원의 푸른 불꽃 화로)
	func _draw_memorial_building(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 22.0
		# 3단 대리석 계단 기단
		draw_rect(Rect2(cx - 74, base_y - 18, 148, 10), Color("706c66"))
		draw_rect(Rect2(cx - 68, base_y - 26, 136, 8), Color("858079"))
		# 신전 뒷벽
		draw_rect(Rect2(cx - 54, base_y - 88, 108, 62), Color("423f3b"))
		# 4개의 대리석 기둥 (Fluted Columns)
		for px in [-52, -20, 12, 44]:
			draw_rect(Rect2(cx + px, base_y - 88, 10, 62), Color("b8b2a6"))
		# 삼각형 페디먼트 지붕 및 황금 문장
		var pediment := PackedVector2Array([
			Vector2(cx - 74, base_y - 88), Vector2(cx + 74, base_y - 88), Vector2(cx, base_y - 128)
		])
		draw_colored_polygon(pediment, Color("969086"))
		draw_polyline(pediment, UiKit.GOLD if is_hovered else Color("5c5852"), 2.5)
		draw_circle(Vector2(cx, base_y - 102), 8.0, UiKit.GOLD)
		# 중앙 영원의 추모 푸른 불꽃 화로
		draw_rect(Rect2(cx - 10, base_y - 36, 20, 10), Color("5c4828"))
		var flame_h := 16.0 + sin(anim_time * 6.0) * 3.0
		draw_circle(Vector2(cx, base_y - 44), 14.0, Color(0.35, 0.75, 1.0, 0.25))
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 7, base_y - 36), Vector2(cx + 7, base_y - 36), Vector2(cx, base_y - 36 - flame_h)
		]), Color("48b8ff"))

	## 11. 어둠의 균열 (흑요석 고대 비석 & 소용돌이치는 차원 포탈)
	func _draw_dungeon_portal(w: float, h: float) -> void:
		var cx := w * 0.5
		var base_y := h - 24.0
		var center := Vector2(cx, base_y - 78)

		# 포탈 외부 붉은/보랏빛 에너지 오라
		var pulse := 0.88 + 0.12 * sin(anim_time * 4.0)
		draw_circle(center, 66.0 * pulse, Color(0.75, 0.12, 0.28, 0.18))
		draw_circle(center, 48.0 * pulse, Color(0.55, 0.10, 0.65, 0.32))

		# 좌우 흑요석 고대 기둥 (Obsidian Monoliths)
		var left_pillar := PackedVector2Array([
			Vector2(cx - 74, base_y - 10), Vector2(cx - 46, base_y - 10),
			Vector2(cx - 32, base_y - 138), Vector2(cx - 58, base_y - 152)
		])
		var right_pillar := PackedVector2Array([
			Vector2(cx + 46, base_y - 10), Vector2(cx + 74, base_y - 10),
			Vector2(cx + 58, base_y - 152), Vector2(cx + 32, base_y - 138)
		])
		draw_colored_polygon(left_pillar, Color("1f1824"))
		draw_colored_polygon(right_pillar, Color("1f1824"))
		draw_polyline(left_pillar, Color("c03050") if is_hovered else Color("4a2838"), 2.5)
		draw_polyline(right_pillar, Color("c03050") if is_hovered else Color("4a2838"), 2.5)

		# 중심 차원 균열 코어 및 회전하는 에너지 링
		_draw_ellipse(center, Vector2(36 * pulse, 52 * pulse), Color("28081e"))
		_draw_ellipse(center, Vector2(24 * pulse, 36 * pulse), Color("901840"))
		_draw_ellipse(center, Vector2(12 * pulse, 20 * pulse), Color("ff4878"))
		for i in range(6):
			var ang := anim_time * 2.2 + float(i) * TAU / 6.0
			var p := center + Vector2(cos(ang) * 32.0, sin(ang) * 44.0)
			draw_circle(p, 3.5, Color("ff7098"))


## 대형 팝업 좌측에 표시되는 건물 내부 도트 일러스트 및 NPC 쇼케이스 캔버스
class BuildingInteriorCanvas extends Control:
	var btype: String = "guild"
	var anim_time: float = 0.0
	static var _int_bg_cache: Dictionary = {}
	static var _npc_cache: Dictionary = {}
	static var _dungeon_portal_tex: Texture2D = null

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	## [업데이트 메서드] 팝업이 열려 있을 때만 상위 월드 루프가 호출한다.
	func update_tick(delta: float) -> void:
		anim_time += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y

		# 1. 건물별 도트 내부 배경 로드
		var bg_path := "res://assets/sprites/interiors/%s_bg.png" % btype
		if btype == "blacksmith":
			bg_path = "res://assets/sprites/ui/blacksmith_interior_bg.png"
		var bg_tex: Texture2D = null
		if _int_bg_cache.has(bg_path):
			bg_tex = _int_bg_cache[bg_path]
		elif ResourceLoader.exists(bg_path):
			bg_tex = load(bg_path)
			_int_bg_cache[bg_path] = bg_tex

		if bg_tex != null:
			draw_texture_rect(bg_tex, Rect2(0, 0, w, h), false)

			# 어둠의 균열일 경우 pixelfx 차원문 루프 (JSON 규격 다중 행 자동 슬라이싱)
			if btype == "dungeon":
				UiKit.draw_pixelfx_frame(self, "res://assets/sprites/vfx/portal/arcane/portal/portal.png", Rect2(w * 0.28, h * 0.24, 152, 116), anim_time, 0, Color(1, 0.7, 0.9, 0.95))

			# 건물 유형별 실내 분위기 광원 펄스
			var mood_col := _interior_mood_color(btype)
			var mood_pulse := 0.14 + 0.05 * sin(anim_time * 2.6)
			draw_circle(Vector2(w * 0.35, h * 0.42), minf(w, h) * 0.42, Color(mood_col.r, mood_col.g, mood_col.b, mood_pulse))

			# 2. 건물별 담당 NPC 도트 스프라이트 렌더링 (발밑 그림자 + 호흡 스케일 + 상하 바운스)
			var npc_path := "res://assets/sprites/npc/npc_%s.png" % btype
			var npc_tex: Texture2D = null
			if _npc_cache.has(npc_path):
				npc_tex = _npc_cache[npc_path]
			elif ResourceLoader.exists(npc_path):
				npc_tex = load(npc_path)
				_npc_cache[npc_path] = npc_tex

			if npc_tex != null:
				var breath := 1.0 + sin(anim_time * 2.8) * 0.012
				var target_h := h * 0.88 * breath
				var scale_ratio := target_h / maxf(1.0, float(npc_tex.get_height()))
				var nw := float(npc_tex.get_width()) * scale_ratio
				var nh := target_h
				var bob := sin(anim_time * 2.8) * 2.0
				var nx := w - nw - 14.0
				var ny := (h - 6.0) - nh + bob
				# 발밑 접촉 그림자 타원
				_draw_interior_ellipse(Vector2(nx + nw * 0.5, h - 8.0), Vector2(nw * 0.34, 8.0), Color(0, 0, 0, 0.45))
				draw_texture_rect(npc_tex, Rect2(nx, ny, nw, nh), false)

			# 실내 빛줄기 속을 부유하는 미세 먼지 입자 (8개)
			for m_idx in range(8):
				var fm := float(m_idx)
				var mt := fmod(anim_time * 0.22 + fm * 0.13, 1.0)
				var mx := fmod(fm * 63.0 + sin(mt * TAU + fm) * 18.0 + w, w)
				var my := (1.0 - mt) * (h - 20.0) + 10.0
				var ma := sin(mt * PI) * 0.48
				draw_circle(Vector2(mx, my), 1.6, Color(mood_col.r, mood_col.g, mood_col.b, ma))

			# 3. 이중 고딕 액자 프레임 및 금빛 모서리 브래킷 마감
			draw_rect(Rect2(0, 0, w, h), UiKit.BORDER2, false, 2.0)
			draw_rect(Rect2(4, 4, w - 8, h - 8), Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.28), false, 1.0)
			_draw_corner_brackets(w, h, UiKit.GOLD2, 12.0)
			return

		# 폴백: 내부 석조/목조 배경 액자
		draw_rect(Rect2(0, 0, w, h), Color("120f0b"))
		# 뒷벽 석조 타일 무늬
		for row in range(5):
			for col in range(6):
				var bx := col * 52.0 + (24.0 if row % 2 == 1 else 0.0)
				var by := row * 32.0
				draw_rect(Rect2(bx, by, 48, 28), Color("1b1611"))
		# 바닥 마루/석판
		draw_rect(Rect2(0, h - 48, w, 48), Color("241b13"))
		draw_line(Vector2(0, h - 48), Vector2(w, h - 48), UiKit.BORDER2, 2.0)

		# 중앙 분위기 조명 후광
		var pulse := 0.88 + 0.12 * sin(anim_time * 4.0)
		var accent := UiKit.GOLD
		if btype == "dungeon" or btype == "blacksmith":
			accent = UiKit.RED
		elif btype == "magic" or btype == "memorial":
			accent = UiKit.BLUE
		elif btype == "treatment":
			accent = UiKit.GREEN

		draw_circle(Vector2(w * 0.5, h * 0.48), 68.0 * pulse, Color(accent.r, accent.g, accent.b, 0.16))

		# 내부에 해당 건물 아트워크 확대 렌더링
		var bcanvas_w := w
		var bcanvas_h := h - 8.0
		# 건물 내부 상징 오브젝트 연출
		match btype:
			"blacksmith":
				# 거대 화덕과 모루 클로즈업
				draw_rect(Rect2(30, 25, 95, 115), Color("362822"))
				draw_circle(Vector2(78, 98), 28.0 * pulse, Color(1.0, 0.45, 0.1, 0.9))
				draw_circle(Vector2(78, 102), 16.0 * pulse, Color(1.0, 0.85, 0.25, 0.95))
				draw_rect(Rect2(165, 105, 50, 28), Color("4a321e"))
				draw_colored_polygon(PackedVector2Array([
					Vector2(150, 85), Vector2(230, 85), Vector2(215, 105), Vector2(165, 105)
				]), Color("8a929c"))
			"guild":
				# 길드장 집무 책상, 촛불, 현상수배 게시판
				draw_rect(Rect2(25, 22, 110, 75), Color("3d2918"))
				draw_rect(Rect2(32, 28, 96, 63), Color("543922"))
				draw_rect(Rect2(40, 35, 22, 28), Color("e6d6b5"))
				draw_rect(Rect2(70, 38, 22, 26), Color("d8c49e"))
				draw_rect(Rect2(100, 34, 20, 28), Color("e6d6b5"))
				draw_rect(Rect2(145, 95, 110, 42), Color("4a301c"))
				draw_circle(Vector2(200, 78), 14.0 * pulse, Color(1.0, 0.8, 0.3, 0.35))
			_:
				# 아치형 기둥과 샹들리에/배너 연출
				draw_rect(Rect2(24, 15, 18, h - 63), Color("3a3024"))
				draw_rect(Rect2(w - 42, 15, 18, h - 63), Color("3a3024"))
				draw_rect(Rect2(w * 0.5 - 28, 22, 56, 78), accent.darkened(0.35))
				draw_rect(Rect2(w * 0.5 - 28, 22, 56, 6), UiKit.GOLD)
				draw_circle(Vector2(w * 0.5, 60), 16.0, UiKit.GOLD)

		# 테두리 액자 마감
		draw_rect(Rect2(1, 1, w - 2, h - 2), UiKit.BORDER2, false, 2.0)

	## 건물 유형에 어울리는 실내 조명 색상을 반환한다.
	func _interior_mood_color(type_id: String) -> Color:
		match type_id:
			"blacksmith":
				return Color(1.0, 0.52, 0.16)
			"magic", "memorial":
				return Color(0.45, 0.72, 1.0)
			"treatment":
				return Color(0.45, 0.90, 0.62)
			"dungeon":
				return Color(0.92, 0.24, 0.42)
			_:
				return Color(1.0, 0.78, 0.36)

	## 실내 바닥 접촉 그림자용 타원을 그린다.
	func _draw_interior_ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in range(16):
			var ang := float(i) * TAU / 16.0
			pts.append(center + Vector2(cos(ang) * radii.x, sin(ang) * radii.y))
		draw_colored_polygon(pts, col)

	## 네 모서리에 고딕 금빛 L자 브래킷 장식을 그린다.
	func _draw_corner_brackets(w: float, h: float, col: Color, arm_len: float) -> void:
		var c := Color(col.r, col.g, col.b, 0.85)
		draw_line(Vector2(2, 2), Vector2(2 + arm_len, 2), c, 2.0)
		draw_line(Vector2(2, 2), Vector2(2, 2 + arm_len), c, 2.0)
		draw_line(Vector2(w - 2, 2), Vector2(w - 2 - arm_len, 2), c, 2.0)
		draw_line(Vector2(w - 2, 2), Vector2(w - 2, 2 + arm_len), c, 2.0)
		draw_line(Vector2(2, h - 2), Vector2(2 + arm_len, h - 2), c, 2.0)
		draw_line(Vector2(2, h - 2), Vector2(2, h - 2 - arm_len), c, 2.0)
		draw_line(Vector2(w - 2, h - 2), Vector2(w - 2 - arm_len, h - 2), c, 2.0)
		draw_line(Vector2(w - 2, h - 2), Vector2(w - 2, h - 2 - arm_len), c, 2.0)


## 다키스트 던전 스타일의 16비트 도트 초상화 및 등급 프레임 위젯
class HeroPortraitCanvas extends Control:
	var category: String = "전사"
	var grade: String = "일반"
	var hero_name: String = ""
	static var _p_tex_cache: Dictionary = {}

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	## 직업군별 초상화 텍스처를 JobDb 단일 카탈로그 및 UiKit 공용 캐시로 로드한다.
	func _get_portrait_texture(cat: String) -> Texture2D:
		var path := str(JobDb.visual_spec(cat).get("portrait", ""))
		return UiKit.get_cached_texture(path)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var accent := JobDb.category_color(category)

		var tex := _get_portrait_texture(category)
		if tex != null:
			draw_texture_rect(tex, Rect2(1, 1, w - 2, h - 2), false)
			var frame_c := JobDb.grade_color(grade)
			draw_rect(Rect2(1, 1, w - 2, h - 2), frame_c, false, 2.0)
			return

		# 폴백 벡터 드로잉
		draw_rect(Rect2(0, 0, w, h), Color("0c0a0d"))
		# 후면 은은한 직업 상징 메달리온 원형광채
		draw_circle(Vector2(w * 0.5, h * 0.48), minf(w, h) * 0.44, Color(accent.r, accent.g, accent.b, 0.16))

		var cx := w * 0.5
		var cy := h * 0.42

		# 2. 어깨 갑옷 / 가죽 코트 / 로브 실루엣 (깊은 먹선 및 다키스트 던전 스타일 섀도우)
		var shoulder_poly := PackedVector2Array([
			Vector2(cx - w * 0.38, h - 2),
			Vector2(cx - w * 0.28, cy + h * 0.14),
			Vector2(cx - w * 0.16, cy + h * 0.08),
			Vector2(cx + w * 0.16, cy + h * 0.08),
			Vector2(cx + w * 0.28, cy + h * 0.14),
			Vector2(cx + w * 0.38, h - 2)
		])
		draw_colored_polygon(shoulder_poly, Color("14121a"))
		# 옷깃/견갑 음영 하이라이트
		draw_polyline(shoulder_poly, Color(accent.r * 0.8, accent.g * 0.8, accent.b * 0.8, 0.6), 1.5)

		# 3. 직업별 다키스트 던전 고딕 페이스 & 헤어/장비 드로잉
		match category:
			"전사":
				# 성전사/검사: 은빛 철제 투구, T자형 섀도우 슬릿 (눈이 깊은 그림자에 가려짐)
				var helm_poly := PackedVector2Array([
					Vector2(cx - w * 0.20, cy - h * 0.18),
					Vector2(cx + w * 0.20, cy - h * 0.18),
					Vector2(cx + w * 0.24, cy + h * 0.10),
					Vector2(cx, cy + h * 0.22),
					Vector2(cx - w * 0.24, cy + h * 0.10)
				])
				draw_colored_polygon(helm_poly, Color("323640"))
				draw_polyline(helm_poly, Color("586070"), 1.5)
				# 다키스트 던전 시그니처: 검은색 T자형 바이저 섀도우
				draw_line(Vector2(cx - w * 0.16, cy - h * 0.02), Vector2(cx + w * 0.16, cy - h * 0.02), Color("08080a"), 4.0)
				draw_line(Vector2(cx, cy - h * 0.02), Vector2(cx, cy + h * 0.16), Color("08080a"), 4.0)
				# 황금빛 십자가 리벳
				draw_circle(Vector2(cx, cy - h * 0.10), 3.0, Color("d4af37"))

			"마법사", "성직자":
				# 사제/수도사/마법사: 깊은 후드, 챙 그늘에 가려진 얼굴, 굳게 다문 입술
				var hood_poly := PackedVector2Array([
					Vector2(cx, cy - h * 0.26),
					Vector2(cx + w * 0.26, cy + h * 0.14),
					Vector2(cx - w * 0.26, cy + h * 0.14)
				])
				draw_colored_polygon(hood_poly, Color("20162a"))
				# 얼굴 섀도우 (완전한 암흑)
				draw_colored_polygon(PackedVector2Array([
					Vector2(cx, cy - h * 0.14),
					Vector2(cx + w * 0.16, cy + h * 0.10),
					Vector2(cx - w * 0.16, cy + h * 0.10)
				]), Color("0a070e"))
				# 후드 테두리 금빛 룬 장식
				draw_line(Vector2(cx, cy - h * 0.26), Vector2(cx + w * 0.26, cy + h * 0.14), Color("9966cc"), 1.5)
				draw_line(Vector2(cx, cy - h * 0.26), Vector2(cx - w * 0.26, cy + h * 0.14), Color("9966cc"), 1.5)

			"레인저", "도적":
				# 도굴꾼/현상금 사냥꾼: 비스듬히 눌러쓴 챙 넓은 모자, 입가를 가린 복면
				var hat_brim := PackedVector2Array([
					Vector2(cx - w * 0.32, cy - h * 0.04),
					Vector2(cx + w * 0.32, cy - h * 0.12),
					Vector2(cx + w * 0.18, cy - h * 0.26),
					Vector2(cx - w * 0.18, cy - h * 0.20)
				])
				draw_colored_polygon(hat_brim, Color("2a2018"))
				# 모자 아래 짙은 그림자
				draw_rect(Rect2(cx - w * 0.20, cy - h * 0.06, w * 0.40, h * 0.12), Color("0a0806"))
				# 입가를 가린 가죽 마스크
				draw_colored_polygon(PackedVector2Array([
					Vector2(cx - w * 0.16, cy + h * 0.04),
					Vector2(cx + w * 0.16, cy + h * 0.04),
					Vector2(cx, cy + h * 0.20)
				]), Color("3a2c20"))

			_:
				# 기본 고딕 실루엣
				draw_circle(Vector2(cx, cy), w * 0.20, Color("221e28"))
				draw_rect(Rect2(cx - w * 0.16, cy - h * 0.06, w * 0.32, h * 0.08), Color("0a080e"))

		# 4. 등급별(일반/정예/특수) 고딕 액자 프레임
		var frame_c := JobDb.grade_color(grade)
		draw_rect(Rect2(1, 1, w - 2, h - 2), frame_c, false, 2.0)
		# 네 모서리 철제 장식 팁
		var corner_size := 5.0
		draw_line(Vector2(1, 1), Vector2(1 + corner_size, 1), Color("ffffff"), 1.5)
		draw_line(Vector2(1, 1), Vector2(1, 1 + corner_size), Color("ffffff"), 1.5)
		draw_line(Vector2(w - 2, 1), Vector2(w - 2 - corner_size, 1), Color("ffffff"), 1.5)
		draw_line(Vector2(w - 2, 1), Vector2(w - 2, 1 + corner_size), Color("ffffff"), 1.5)


## 대장간의 4대 장비(무기, 갑옷, 투구, 장신구)를 고딕 도트 아이콘 텍스처로 그리는 캔버스
class EquipmentIconCanvas extends Control:
	var slot_type: String = "weapon" # weapon, armor, helmet, accessory
	var item_level: int = 1
	var is_selected: bool = false
	static var _eq_tex_cache: Dictionary = {}

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _get_eq_texture(stype: String) -> Texture2D:
		if _eq_tex_cache.has(stype):
			return _eq_tex_cache[stype]
		var path := "res://assets/sprites/ui/icon_%s.png" % stype
		if not ResourceLoader.exists(path) and stype == "accessory":
			path = "res://assets/sprites/ui/icon_ring.png"
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		_eq_tex_cache[stype] = tex
		return tex

	func _draw() -> void:
		var w := size.x
		var h := size.y

		# 1. 고딕 장비 슬롯 배경 (어두운 주철 텍스처)
		var bg_c := Color("141118") if not is_selected else Color("221b16")
		draw_rect(Rect2(0, 0, w, h), bg_c)

		var tex := _get_eq_texture(slot_type)
		if tex != null:
			var pad := 6.0
			var max_dim := minf(w, h) - pad * 2.0
			var sc := minf(max_dim / float(tex.get_width()), max_dim / float(tex.get_height()))
			var dw := float(tex.get_width()) * sc
			var dh := float(tex.get_height()) * sc
			draw_texture_rect(tex, Rect2((w - dw) * 0.5, (h - dh) * 0.5, dw, dh), false)
			if is_selected:
				draw_rect(Rect2(0, 0, w, h), Color("f6d355"), false, 3.0)
				draw_rect(Rect2(-2, -2, w + 4, h + 4), Color(0.96, 0.83, 0.33, 0.35), false, 2.0)
			else:
				draw_rect(Rect2(0, 0, w, h), Color("2e2a34"), false, 1.5)
			return

		var cx := w * 0.5
		var cy := h * 0.5

		# 2. 장비 타입별 고품질 절차적 벡터/도트 렌더링
		match slot_type:
			"weapon":
				# 고대 은빛 검 (대각선으로 배치된 날카로운 장검)
				# 칼날
				var blade_poly := PackedVector2Array([
					Vector2(cx + 20, cy - 22),
					Vector2(cx + 25, cy - 20),
					Vector2(cx - 10, cy + 15),
					Vector2(cx - 14, cy + 11)
				])
				draw_colored_polygon(blade_poly, Color("c2cad6"))
				# 칼날 중심 하이라이트 라인
				draw_line(Vector2(cx + 22, cy - 21), Vector2(cx - 12, cy + 13), Color("ffffff"), 1.5)
				# 십자 코등이 (Crossguard - 금빛)
				draw_line(Vector2(cx - 18, cy + 6), Vector2(cx - 6, cy + 18), Color("d4af37"), 4.0)
				# 손잡이 (Grip) & 폼멜 (Pommel)
				draw_line(Vector2(cx - 12, cy + 12), Vector2(cx - 20, cy + 20), Color("4a321a"), 3.0)
				draw_circle(Vector2(cx - 22, cy + 22), 3.5, Color("d4af37"))

			"armor":
				# 묵직한 강철 판금 흉갑 (Plate Armor)
				var chest_poly := PackedVector2Array([
					Vector2(cx - 16, cy - 16), Vector2(cx + 16, cy - 16),
					Vector2(cx + 20, cy - 6), Vector2(cx + 14, cy + 18),
					Vector2(cx - 14, cy + 18), Vector2(cx - 20, cy - 6)
				])
				draw_colored_polygon(chest_poly, Color("4a5360"))
				# 가슴 중앙 엠보싱 리벳 라인
				draw_line(Vector2(cx, cy - 16), Vector2(cx, cy + 16), Color("2e3540"), 2.0)
				draw_line(Vector2(cx - 14, cy - 6), Vector2(cx + 14, cy - 6), Color("727e90"), 2.0)
				# 금빛 버클
				draw_circle(Vector2(cx, cy + 10), 3.0, Color("d4af37"))

			"helmet":
				# 기사의 그레이트 헬름 (Great Helm)
				var helm_poly := PackedVector2Array([
					Vector2(cx - 15, cy - 18), Vector2(cx + 15, cy - 18),
					Vector2(cx + 18, cy + 8), Vector2(cx, cy + 20),
					Vector2(cx - 18, cy + 8)
				])
				draw_colored_polygon(helm_poly, Color("505866"))
				# T자형 흑철 시야 슬릿
				draw_line(Vector2(cx - 12, cy - 2), Vector2(cx + 12, cy - 2), Color("121418"), 3.0)
				draw_line(Vector2(cx, cy - 2), Vector2(cx, cy + 14), Color("121418"), 3.0)
				# 투구 상단 금빛 브로우 밴드
				draw_line(Vector2(cx - 15, cy - 12), Vector2(cx + 15, cy - 12), Color("d4af37"), 2.0)

			"ring", "accessory":
				# 신비로운 룬이 각인된 황금 마법 반지
				draw_circle(Vector2(cx, cy), 18.0, Color("c8982a"))
				draw_circle(Vector2(cx, cy), 12.0, bg_c)
				# 상단에 박힌 찬란한 사파이어/루비 보석
				draw_circle(Vector2(cx, cy - 16), 5.5, Color("22b8ff"))
				draw_circle(Vector2(cx, cy - 16), 2.5, Color("ffffff")) # 광채 하이라이트

		# 3. 테두리 및 선택 강조 효과 (image2.png처럼 선택 시 황금빛 오라!)
		if is_selected:
			# 황금빛 외곽선 + 네 모서리 하이라이트
			draw_rect(Rect2(0, 0, w, h), Color("f6d355"), false, 3.0)
			draw_rect(Rect2(-2, -2, w + 4, h + 4), Color(0.96, 0.83, 0.33, 0.35), false, 2.0)
		else:
			draw_rect(Rect2(0, 0, w, h), Color("2e2a34"), false, 1.5)


## 대장간 팝업 내부의 타오르는 용광로, 모루, 4단계 드워프 애니메이션 및 모루질 불꽃 이펙트 캔버스
class BlacksmithInteriorCanvas extends Control:
	enum DwarfState { IDLE, HAMMERING, SUCCESS, FAIL }

	var current_state: DwarfState = DwarfState.IDLE:
		set(val):
			current_state = val
			queue_redraw()

	var flash_alpha: float = 0.0
	var hammer_strike_t: float = 0.0
	var sparks: Array[Dictionary] = []
	var anim_time: float = 0.0
	static var _bg_tex: Texture2D = null
	static var _brazier_tex: Texture2D = null
	static var _npc_tex: Texture2D = null

	func _ready() -> void:
		set_process(true)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if _bg_tex == null and ResourceLoader.exists("res://assets/sprites/ui/blacksmith_interior_bg.png"):
			_bg_tex = load("res://assets/sprites/ui/blacksmith_interior_bg.png")
		if _brazier_tex == null and ResourceLoader.exists("res://assets/sprites/vfx/brazier/fire/brazier/brazier.png"):
			_brazier_tex = load("res://assets/sprites/vfx/brazier/fire/brazier/brazier.png")
		if _npc_tex == null and ResourceLoader.exists("res://assets/sprites/npc/npc_blacksmith.png"):
			_npc_tex = load("res://assets/sprites/npc/npc_blacksmith.png")

	func _process(delta: float) -> void:
		anim_time += delta
		if flash_alpha > 0.0:
			flash_alpha = maxf(0.0, flash_alpha - delta * 3.5)
		if hammer_strike_t > 0.0:
			hammer_strike_t = maxf(0.0, hammer_strike_t - delta * 4.0)

		# 불꽃 스파크 물리 시뮬레이션
		var i := sparks.size() - 1
		while i >= 0:
			var s: Dictionary = sparks[i]
			s["pos"] += s["vel"] * delta
			s["vel"].y += 240.0 * delta # 중력
			s["life"] -= delta
			if s["life"] <= 0.0:
				sparks.remove_at(i)
			i -= 1

		queue_redraw()

	## 모루질 타격 시 호출되어 모루 타격 모션, 섬광 및 24개의 불꽃 스파크를 방출한다.
	func trigger_hammer_strike() -> void:
		flash_alpha = 0.85
		hammer_strike_t = 1.0
		# 모루 위치 (중앙 약간 좌측 Vector2(210, 185))
		var anvil_pos := Vector2(210, 185)
		for k in range(24):
			var angle := randf_range(-PI * 0.85, -PI * 0.15)
			var spd := randf_range(90.0, 320.0)
			sparks.append({
				"pos": anvil_pos + Vector2(randf_range(-12, 12), randf_range(-4, 4)),
				"vel": Vector2(cos(angle), sin(angle)) * spd,
				"life": randf_range(0.25, 0.65),
				"max_life": 0.65,
				"color": Color("fff380") if (k % 2 == 0) else Color("ff7722"),
				"size": randf_range(2.0, 4.5)
			})
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y

		if _bg_tex != null:
			# 1. 고화질 다키스트 던전 고딕 대장간 배경 렌더링
			draw_texture_rect(_bg_tex, Rect2(0, 0, w, h), false)

			# 2. 화덕 위 pixelfx brazier 불꽃 애니메이션 가미
			UiKit.draw_pixelfx_frame(self, "res://assets/sprites/vfx/brazier/fire/brazier/brazier.png", Rect2(w * 0.44, h * 0.22, 120, 136), anim_time, 0, Color(1, 0.9, 0.8, 0.85))

			# 3. 고딕 대장장이 장인 NPC 스프라이트 렌더링
			if _npc_tex != null:
				var npc_w := h * 0.65
				var npc_h := h * 0.85
				var npc_x := w * 0.52
				var npc_y := h * 0.15

				# 타격 또는 상태별 애니메이션 오프셋
				var bob_y := 0.0
				var npc_mod := Color.WHITE
				match current_state:
					DwarfState.IDLE:
						bob_y = sin(anim_time * 2.5) * 2.0
					DwarfState.HAMMERING:
						bob_y = hammer_strike_t * 14.0 # 망치 강타 반동
						npc_mod = Color("ffddaa")
					DwarfState.SUCCESS:
						npc_mod = Color("ffe57f")
						# 황금 아우라
						draw_circle(Vector2(npc_x + npc_w * 0.5, npc_y + npc_h * 0.5), npc_w * 0.45, Color(0.96, 0.84, 0.32, 0.15 + 0.08 * sin(anim_time * 6.0)))
					DwarfState.FAIL:
						npc_mod = Color("8c949e")

				draw_texture_rect(_npc_tex, Rect2(npc_x, npc_y + bob_y, npc_w, npc_h), false, npc_mod)
			else:
				# 폴백 드워프 캐릭터
				var floor_y := h * 0.72
				var a_x := w * 0.45
				var a_y := floor_y - 20.0
				_draw_dwarf_character(w, h, a_x + 55.0, a_y - 20.0)

			# 4. 모루질 실시간 스파크 렌더링
			for s in sparks:
				var alpha: float = clampf(s["life"] / s["max_life"], 0.0, 1.0)
				var c: Color = s["color"]
				c.a = alpha
				draw_circle(s["pos"], s["size"] * alpha, c)

			# 5. 모루 강타 시 섬광 플래시
			if flash_alpha > 0.0:
				draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.95, 0.85, flash_alpha * 0.55))
			return

		# 1. 고풍스러운 대장간 석조 벽면 & 목조 대들보 인테리어
		draw_rect(Rect2(0, 0, w, h), Color("181416"))
		# 석조 벽돌 패턴
		var brick_c := Color(0.24, 0.20, 0.22, 0.45)
		for row in range(8):
			var by := row * (h * 0.12)
			draw_line(Vector2(0, by), Vector2(w, by), brick_c, 1.0)
			var offset := (row % 2) * (w * 0.08)
			var bx := offset
			while bx < w:
				draw_line(Vector2(bx, by), Vector2(bx, by + h * 0.12), brick_c, 1.0)
				bx += w * 0.16

		# 2. 좌측 햇살이 비쳐 들어오는 아치형 격자 창문 & 햇살 빛줄기 (God Rays)
		var win_x := w * 0.14
		var win_y := h * 0.12
		var win_w := w * 0.18
		var win_h := h * 0.44
		# 창밖 푸른 하늘과 초록빛 언덕
		draw_rect(Rect2(win_x, win_y, win_w, win_h), Color("7baed8"))
		draw_rect(Rect2(win_x, win_y + win_h * 0.55, win_w, win_h * 0.45), Color("4e8242"))
		# 아치형 창틀
		draw_rect(Rect2(win_x, win_y, win_w, win_h), Color("3a2618"), false, 4.0)
		draw_line(Vector2(win_x + win_w * 0.5, win_y), Vector2(win_x + win_w * 0.5, win_y + win_h), Color("3a2618"), 3.0)
		draw_line(Vector2(win_x, win_y + win_h * 0.45), Vector2(win_x + win_w, win_y + win_h * 0.45), Color("3a2618"), 3.0)
		# 쏟아지는 따스한 황금빛 햇살 (God Rays)
		var ray_poly := PackedVector2Array([
			Vector2(win_x + win_w * 0.2, win_y + win_h * 0.3),
			Vector2(win_x + win_w, win_y + win_h * 0.2),
			Vector2(win_x + win_w * 2.2, h * 0.85),
			Vector2(win_x + win_w * 0.8, h * 0.85)
		])
		draw_colored_polygon(ray_poly, Color(1.0, 0.92, 0.70, 0.10))

		# 3. 중앙 후면의 거대한 석조 아치형 용광로 화덕 (Stone Arch Fireplace)
		var f_cx := w * 0.58
		var f_cy := h * 0.45
		var f_w := w * 0.28
		var f_h := h * 0.42
		# 굴뚝 & 화덕 외벽
		draw_rect(Rect2(f_cx - f_w * 0.35, 0, f_w * 0.7, f_cy - f_h * 0.5), Color("2c2422"))
		draw_colored_polygon(PackedVector2Array([
			Vector2(f_cx - f_w * 0.5, f_cy + f_h * 0.5),
			Vector2(f_cx - f_w * 0.5, f_cy - f_h * 0.3),
			Vector2(f_cx, f_cy - f_h * 0.55),
			Vector2(f_cx + f_w * 0.5, f_cy - f_h * 0.3),
			Vector2(f_cx + f_w * 0.5, f_cy + f_h * 0.5)
		]), Color("322a28"))
		# 화덕 내부 아치 (검붉은 심연)
		draw_colored_polygon(PackedVector2Array([
			Vector2(f_cx - f_w * 0.36, f_cy + f_h * 0.5),
			Vector2(f_cx - f_w * 0.36, f_cy - f_h * 0.1),
			Vector2(f_cx, f_cy - f_h * 0.3),
			Vector2(f_cx + f_w * 0.36, f_cy - f_h * 0.1),
			Vector2(f_cx + f_w * 0.36, f_cy + f_h * 0.5)
		]), Color("140804"))
		# 타오르는 장작과 이글거리는 주황빛 불꽃 오라
		var aura_pulse := 0.35 + 0.15 * sin(anim_time * 5.0)
		draw_circle(Vector2(f_cx, f_cy + f_h * 0.2), f_w * 0.35, Color(1.0, 0.42, 0.08, aura_pulse))
		# 불꽃 폴리곤들
		for fi in range(6):
			var fh := (f_h * 0.3) + (f_h * 0.12) * sin(anim_time * 8.0 + float(fi) * 1.5)
			var fx := f_cx - f_w * 0.24 + float(fi) * (f_w * 0.09)
			var fy := f_cy + f_h * 0.45
			draw_colored_polygon(PackedVector2Array([
				Vector2(fx - 10, fy), Vector2(fx, fy - fh), Vector2(fx + 10, fy)
			]), Color("ff7711"))
			draw_colored_polygon(PackedVector2Array([
				Vector2(fx - 5, fy), Vector2(fx, fy - fh * 0.7), Vector2(fx + 5, fy)
			]), Color("ffea44"))

		# 4. 바닥 묵직한 돌판 타일 (Stone Floor)
		var floor_y := h * 0.72
		draw_rect(Rect2(0, floor_y, w, h - floor_y), Color("1e1b1e"))
		draw_line(Vector2(0, floor_y), Vector2(w, floor_y), Color("383238"), 3.0)

		# 5. 중앙 전면의 흑철 모루 (Anvil) & 달궈진 쇳덩이
		var a_x := w * 0.45
		var a_y := floor_y - 20.0
		# 모루 밑둥 & 상단 날
		var anvil_poly := PackedVector2Array([
			Vector2(a_x - 30, a_y + 35), Vector2(a_x - 18, a_y),
			Vector2(a_x - 45, a_y - 5), Vector2(a_x + 35, a_y - 5),
			Vector2(a_x + 22, a_y), Vector2(a_x + 30, a_y + 35)
		])
		draw_colored_polygon(anvil_poly, Color("2a2f38"))
		draw_polyline(anvil_poly, Color("454f5e"), 2.0)
		# 달궈진 붉은 쇳덩이 (모루 상단에 놓여 빛남)
		var glow_c := Color("ff3300").lerp(Color("ffea66"), 0.5 + 0.5 * sin(anim_time * 6.0))
		draw_rect(Rect2(a_x - 15, a_y - 12, 34, 10), glow_c)

		# 6. 드워프 대장장이 캐릭터 드로잉 (상태별 포즈)
		_draw_dwarf_character(w, h, a_x + 55.0, a_y - 20.0)

		# 7. 모루질 불꽃 파티클 렌더링
		for s in sparks:
			var alpha: float = clampf(s["life"] / s["max_life"], 0.0, 1.0)
			var c: Color = s["color"]
			c.a = alpha
			draw_circle(s["pos"], s["size"] * alpha, c)

		# 8. 타격 시 화면 전체 섬광 플래시
		if flash_alpha > 0.0:
			draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.95, 0.85, flash_alpha * 0.55))

	## 드워프 대장장이 캐릭터 렌더링 (image2.png 완벽 반영)
	func _draw_dwarf_character(w: float, h: float, dx: float, dy: float) -> void:
		match current_state:
			DwarfState.IDLE:
				# 모루 앞에 늠름하게 서서 망치를 들고 있는 모습
				# 부츠 및 다리
				draw_rect(Rect2(dx - 18, dy + 32, 16, 25), Color("281810"))
				draw_rect(Rect2(dx + 6, dy + 32, 16, 25), Color("281810"))
				# 가죽 앞치마와 옷
				draw_colored_polygon(PackedVector2Array([
					Vector2(dx - 26, dy - 18), Vector2(dx + 26, dy - 18),
					Vector2(dx + 30, dy + 34), Vector2(dx - 30, dy + 34)
				]), Color("4e2e1a"))
				# 두꺼운 가죽 벨트
				draw_rect(Rect2(dx - 28, dy + 10, 56, 9), Color("1a120b"))
				draw_rect(Rect2(dx - 7, dy + 8, 14, 13), Color("d4af37"))
				# 풍성한 주황빛 드워프 턱수염
				draw_colored_polygon(PackedVector2Array([
					Vector2(dx - 22, dy - 30), Vector2(dx + 22, dy - 30),
					Vector2(dx + 16, dy + 16), Vector2(dx, dy + 25), Vector2(dx - 16, dy + 16)
				]), Color("c65318"))
				# 머리/코
				draw_circle(Vector2(dx, dy - 38), 18.0, Color("f4b288"))
				draw_circle(Vector2(dx - 7, dy - 35), 6.5, Color("e48e64")) # 둥근 매부리코
				# 머리띠/두건
				draw_rect(Rect2(dx - 19, dy - 52, 38, 10), Color("2c4436"))
				# 오른손의 대형 대장장이 해머
				draw_line(Vector2(dx - 22, dy - 10), Vector2(dx - 38, dy - 50), Color("5c3c24"), 6.0)
				draw_rect(Rect2(dx - 52, dy - 62, 28, 18), Color("6c7585"))

			DwarfState.HAMMERING:
				# 망치를 높이 들어 모루를 강타하는 역동적 포즈
				var strike_progress := hammer_strike_t
				# 숙여진 몸통
				draw_colored_polygon(PackedVector2Array([
					Vector2(dx - 34, dy - 12), Vector2(dx + 18, dy - 22),
					Vector2(dx + 22, dy + 34), Vector2(dx - 32, dy + 34)
				]), Color("4e2e1a"))
				# 수염 날림
				draw_colored_polygon(PackedVector2Array([
					Vector2(dx - 30, dy - 26), Vector2(dx + 10, dy - 28),
					Vector2(dx - 8, dy + 20), Vector2(dx - 28, dy + 12)
				]), Color("c65318"))
				draw_circle(Vector2(dx - 12, dy - 36), 18.0, Color("f4b288"))
				# 해머 타격 모션 각도
				var h_ang := lerpf(-1.1, 0.45, strike_progress)
				var h_base := Vector2(dx - 15, dy - 15)
				var h_tip := h_base + Vector2(cos(h_ang), sin(h_ang)) * 72.0
				draw_line(h_base, h_tip, Color("5c3c24"), 7.0)
				draw_rect(Rect2(h_tip.x - 14, h_tip.y - 12, 28, 24), Color("828d9e"))

			DwarfState.SUCCESS:
				# 강화 성공: 양팔을 끼고 고개를 들며 호탕하게 웃는 승리 포즈 + 찬란한 황금 아우라
				draw_circle(Vector2(dx, dy - 10), 65.0, Color(0.96, 0.84, 0.32, 0.18 + 0.1 * sin(anim_time * 5.0)))
				draw_colored_polygon(PackedVector2Array([
					Vector2(dx - 26, dy - 20), Vector2(dx + 26, dy - 20),
					Vector2(dx + 30, dy + 34), Vector2(dx - 30, dy + 34)
				]), Color("4e2e1a"))
				# 팔짱 낀 두 팔
				draw_rect(Rect2(dx - 25, dy - 2, 50, 18), Color("683c22"))
				# 수염
				draw_colored_polygon(PackedVector2Array([
					Vector2(dx - 22, dy - 32), Vector2(dx + 22, dy - 32),
					Vector2(dx + 18, dy + 14), Vector2(dx, dy + 24), Vector2(dx - 18, dy + 14)
				]), Color("c65318"))
				draw_circle(Vector2(dx, dy - 42), 18.0, Color("f4b288"))
				# 웃는 눈과 입
				draw_line(Vector2(dx - 8, dy - 46), Vector2(dx - 2, dy - 44), Color("341608"), 2.5)
				draw_line(Vector2(dx + 2, dy - 44), Vector2(dx + 8, dy - 46), Color("341608"), 2.5)

			DwarfState.FAIL:
				# 강화 실패: 좌측 창문 쪽을 바라보며 고개를 떨군 쓸쓸한 뒷모습 실루엣
				var dim_c := Color("1c1822")
				draw_colored_polygon(PackedVector2Array([
					Vector2(dx - 22, dy - 14), Vector2(dx + 22, dy - 18),
					Vector2(dx + 25, dy + 36), Vector2(dx - 24, dy + 36)
				]), dim_c)
				# 고개 숙인 뒷머리와 묶은 머리
				draw_circle(Vector2(dx - 6, dy - 32), 17.0, dim_c)
				# 바닥에 힘없이 내려놓은 망치
				draw_line(Vector2(dx - 45, dy + 42), Vector2(dx - 15, dy + 42), Color("382418"), 5.0)
				draw_rect(Rect2(dx - 55, dy + 36, 14, 12), Color("444c58"))
