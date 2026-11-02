extends RefCounted

## 클래시 오브 클랜 / 다키스트 던전 스타일의 2.5D 마을 지형, 건물 외관, 내부 일러스트, 영웅 초상화를
## 절차적 벡터/폴리곤 드로잉(CanvasItem._draw)으로 렌더링하는 시각 컴포넌트 모음.


## 마을 전체 배경 지형(하늘, 별, 산맥, 성벽, 잔디 언덕, 조약돌 도로, 가로등 불빛, 나무, 건물 터)을 그리는 캔버스
class VillageTerrainCanvas extends Control:
	var anim_time: float = 0.0
	var building_defs: Array[Dictionary] = []

	## [업데이트 메서드] 상위 월드(EstateWorld)의 중앙 루프가 매 프레임 호출하여 애니메이션을 갱신한다.
	func update_tick(delta: float) -> void:
		anim_time += delta
		queue_redraw()

	## 마을 배경과 도로망, 건물 터, 가로등, 자연물을 렌더링한다.
	func _draw() -> void:
		var w := size.x
		var h := size.y

		# 1. 다단계 밤하늘/황혼 그라데이션 (상단 심연 남색 -> 지평선 호박빛 어둠)
		var sky_bands := [
			{"y0": 0.0, "y1": 70.0, "c": Color("070910")},
			{"y0": 70.0, "y1": 140.0, "c": Color("0c101b")},
			{"y0": 140.0, "y1": 210.0, "c": Color("141622")},
			{"y0": 210.0, "y1": 270.0, "c": Color("1e1a18")},
		]
		for b in sky_bands:
			draw_rect(Rect2(0, b.y0, w, b.y1 - b.y0 + 2), b.c)

		# 2. 반짝이는 별빛과 초승달
		for i in range(55):
			var sx := fmod(float(i * 197 + 43), w - 40.0) + 20.0
			var sy := fmod(float(i * 73 + 19), 185.0) + 12.0
			var twinkle := 0.45 + 0.45 * sin(anim_time * (1.5 + fmod(float(i), 3.0)) + float(i))
			var r := 1.2 if (i % 3 != 0) else 2.0
			draw_circle(Vector2(sx, sy), r, Color(0.95, 0.92, 0.80, twinkle))

		# 달무리와 달
		var moon_pos := Vector2(1120, 62)
		draw_circle(moon_pos, 54.0, Color(0.92, 0.84, 0.55, 0.05))
		draw_circle(moon_pos, 34.0, Color(0.95, 0.88, 0.62, 0.12))
		draw_circle(moon_pos, 18.0, Color(0.98, 0.93, 0.74, 0.92))
		draw_circle(moon_pos + Vector2(6, -3), 15.0, Color("0c101b"))

		# 3. 원경 설산 산맥 실루엣
		var far_mtn := PackedVector2Array([
			Vector2(0, 250), Vector2(140, 165), Vector2(290, 215), Vector2(460, 145),
			Vector2(650, 205), Vector2(890, 130), Vector2(1120, 195), Vector2(1340, 150),
			Vector2(1580, 210), Vector2(1820, 140), Vector2(2060, 190), Vector2(2280, 125),
			Vector2(w, 190), Vector2(w, 290), Vector2(0, 290)
		])
		draw_colored_polygon(far_mtn, Color("12151e"))

		# 중경 침엽수림 능선 및 원경 성곽 실루엣
		var mid_hills := PackedVector2Array([
			Vector2(0, 265), Vector2(220, 225), Vector2(520, 250), Vector2(910, 210),
			Vector2(1280, 248), Vector2(1650, 220), Vector2(2020, 245), Vector2(w, 225),
			Vector2(w, 320), Vector2(0, 320)
		])
		draw_colored_polygon(mid_hills, Color("151914"))

		# 4. 마을 대지 (클래시 오브 클랜 스타일의 입체적인 녹색/암갈색 잔디 평원)
		draw_rect(Rect2(0, 245, w, h - 245), Color("192014"))

		# 지형 음영 패치 (언덕과 분지 느낌 부여)
		_draw_ellipse(Vector2(930, 195), Vector2(290, 85), Color("222a1b"))
		_draw_ellipse(Vector2(500, 320), Vector2(340, 170), Color("1d2617"))
		_draw_ellipse(Vector2(1450, 360), Vector2(380, 190), Color("1c2416"))
		# 우측 어둠의 균열 주변 오염된 보랏빛/암적색 대지
		_draw_ellipse(Vector2(2180, 350), Vector2(260, 165), Color("22131c"))
		_draw_ellipse(Vector2(2180, 350), Vector2(185, 115), Color("2d1424"))

		# 5. 마을 건물들을 연결하는 입체 조약돌 도로망 (Cobblestone Roads)
		var road_paths := [
			# 메인 가로 가도 (좌측 입구 -> 중앙 광장 -> 우측 기념관 -> 차원문)
			[Vector2(40, 410), Vector2(230, 410), Vector2(500, 350), Vector2(840, 460), Vector2(1120, 460), Vector2(1480, 360), Vector2(1810, 440), Vector2(2180, 390)],
			# 영웅숙소 & 영주저택 북측 연결로
			[Vector2(500, 350), Vector2(500, 260), Vector2(935, 250), Vector2(1480, 290), Vector2(1480, 360)],
			# 치료소 & 대장간 & 마법사학회 남측 연결로
			[Vector2(500, 350), Vector2(500, 525), Vector2(850, 625), Vector2(1285, 625), Vector2(1480, 360)],
			# 중앙 영주저택 광장 종단로
			[Vector2(935, 250), Vector2(935, 460)],
		]
		for path in road_paths:
			_draw_cobblestone_path(path, 34.0)

		# 영주 저택 앞 중앙 원형 석조 광장
		_draw_ellipse(Vector2(935, 275), Vector2(115, 36), Color("2c251d"))
		_draw_ellipse(Vector2(935, 275), Vector2(102, 30), Color("383025"))
		_draw_ellipse_outline(Vector2(935, 275), Vector2(102, 30), Color("524534"), 2.0)

		# 6. 각 건물 아래의 마을 터/기단 (Isometric Building Plot Pad)
		for def in building_defs:
			var r: Rect2 = def.rect
			var center_bottom := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y - 12.0)
			var pad_rx := r.size.x * 0.54
			var pad_ry := 34.0
			var is_dungeon: bool = (def.id == "dungeon_gate")
			# 그림자 및 잔디/석조 테두리 기단
			_draw_ellipse(center_bottom + Vector2(0, 6), Vector2(pad_rx + 8, pad_ry + 5), Color(0, 0, 0, 0.42))
			_draw_ellipse(center_bottom, Vector2(pad_rx, pad_ry), Color("2e1828") if is_dungeon else Color("2a3321"))
			_draw_ellipse(center_bottom, Vector2(pad_rx - 8, pad_ry - 5), Color("241220") if is_dungeon else Color("342c22"))
			_draw_ellipse_outline(center_bottom, Vector2(pad_rx - 4, pad_ry - 2), Color("7a2848") if is_dungeon else Color("4d402e"), 2.0)

		# 7. 마을 조경 소품 (소나무, 참나무, 울타리, 바위, 가로등 횃불)
		var tree_positions := [
			Vector2(55, 230), Vector2(295, 195), Vector2(335, 320), Vector2(280, 535),
			Vector2(655, 175), Vector2(655, 465), Vector2(1165, 175), Vector2(1225, 250),
			Vector2(1080, 560), Vector2(1505, 495), Vector2(1645, 195), Vector2(1635, 515),
			Vector2(1955, 175), Vector2(1945, 520), Vector2(2360, 195), Vector2(2380, 500)
		]
		for tp in tree_positions:
			_draw_village_tree(tp)

		# 가로등/화톳불 위치 (따스한 주황색 불빛 풀 연출)
		var lamp_positions := [
			Vector2(245, 420), Vector2(365, 275), Vector2(365, 515),
			Vector2(685, 280), Vector2(825, 285), Vector2(1045, 285),
			Vector2(695, 455), Vector2(975, 455), Vector2(1265, 360),
			Vector2(1640, 390), Vector2(1960, 385)
		]
		for lp in lamp_positions:
			_draw_street_lantern(lp)

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
	func _draw_cobblestone_path(points: Array, width: float) -> void:
		for i in range(points.size() - 1):
			var p0: Vector2 = points[i]
			var p1: Vector2 = points[i + 1]
			draw_line(p0, p1, Color("251f18"), width + 6.0)
			draw_line(p0, p1, Color("382f24"), width)
			draw_circle(p0, width * 0.5, Color("382f24"))
			draw_circle(p1, width * 0.5, Color("382f24"))
			# 징검돌 디테일
			var dist := p0.distance_to(p1)
			var steps := maxi(2, int(dist / 26.0))
			for s in range(steps):
				var t := float(s) / float(steps)
				var pos := p0.lerp(p1, t)
				var off := Vector2(sin(float(s * 3 + i)) * 6.0, cos(float(s * 5 + i)) * 4.0)
				_draw_ellipse(pos + off, Vector2(7, 4), Color("483d2e"))

	## 마을 나무(침엽수/활엽수) 드로잉
	func _draw_village_tree(pos: Vector2) -> void:
		# 그림자
		_draw_ellipse(pos + Vector2(0, 4), Vector2(22, 8), Color(0, 0, 0, 0.45))
		# 기둥
		draw_rect(Rect2(pos.x - 4, pos.y - 18, 8, 22), Color("3b2818"))
		# 3단 잎사귀 레이어
		var sway := sin(anim_time * 1.6 + pos.x * 0.05) * 2.0
		var c1 := PackedVector2Array([Vector2(pos.x - 24, pos.y - 12), Vector2(pos.x + 24, pos.y - 12), Vector2(pos.x + sway, pos.y - 44)])
		var c2 := PackedVector2Array([Vector2(pos.x - 20, pos.y - 26), Vector2(pos.x + 20, pos.y - 26), Vector2(pos.x + sway * 1.2, pos.y - 58)])
		var c3 := PackedVector2Array([Vector2(pos.x - 14, pos.y - 40), Vector2(pos.x + 14, pos.y - 40), Vector2(pos.x + sway * 1.5, pos.y - 70)])
		draw_colored_polygon(c1, Color("182c1b"))
		draw_colored_polygon(c2, Color("203823"))
		draw_colored_polygon(c3, Color("29452c"))

	## 마을 길가 횃불/가로등 드로잉
	func _draw_street_lantern(pos: Vector2) -> void:
		var pulse := 0.85 + 0.15 * sin(anim_time * 5.0 + pos.x)
		# 바닥 빛무리
		_draw_ellipse(pos + Vector2(0, 2), Vector2(36 * pulse, 16 * pulse), Color(0.95, 0.65, 0.20, 0.12 * pulse))
		# 기둥
		draw_rect(Rect2(pos.x - 2, pos.y - 26, 4, 28), Color("2b241d"))
		draw_line(Vector2(pos.x - 2, pos.y - 25), Vector2(pos.x + 7, pos.y - 25), Color("4a3e31"), 2.0)
		# 등불 코어 및 후광
		var glow_pos := Vector2(pos.x + 7, pos.y - 22)
		draw_circle(glow_pos, 14.0 * pulse, Color(1.0, 0.68, 0.22, 0.22))
		draw_circle(glow_pos, 4.5, Color(1.0, 0.88, 0.45, 0.95))


## 개별 마을 건물을 2.5D 건축물 일러스트 형태로 그리는 캔버스
class VillageBuildingCanvas extends Control:
	var def: Dictionary = {}
	var is_hovered: bool = false
	var anim_time: float = 0.0

	## [업데이트 메서드] 개별 _process 대신 상위 월드의 단일 루프에서 일괄 호출된다.
	func update_tick(delta: float) -> void:
		anim_time += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var btype: String = def.get("type", "guild")

		# 호버 시 건물 바닥 황금빛 선택 오라 표시
		if is_hovered:
			_draw_ellipse(Vector2(w * 0.5, h - 18), Vector2(w * 0.48, 28), Color(0.95, 0.78, 0.32, 0.28))
			_draw_ellipse_outline(Vector2(w * 0.5, h - 18), Vector2(w * 0.48, 28), UiKit.GOLD2, 3.0)

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


## 대형 팝업 좌측에 표시되는 건물 내부 일러스트 쇼케이스 캔버스
class BuildingInteriorCanvas extends Control:
	var btype: String = "guild"
	var anim_time: float = 0.0

	## [업데이트 메서드] 팝업이 열려 있을 때만 상위 월드 루프가 호출한다.
	func update_tick(delta: float) -> void:
		anim_time += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# 내부 석조/목조 배경 액자
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


## 용병 카드 및 파티 슬롯에 사용되는 직업별 고딕 캐릭터 실루엣 초상화 위젯
class HeroPortraitCanvas extends Control:
	var category: String = "전사"
	var grade: String = "일반"

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var accent := JobDb.category_color(category)
		# 배경 메달리온
		draw_rect(Rect2(0, 0, w, h), Color("16130e"))
		draw_circle(Vector2(w * 0.5, h * 0.5), w * 0.42, Color(accent.r, accent.g, accent.b, 0.18))
		# 망토/갑옷 어깨
		var cx := w * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 16, h * 0.48), Vector2(cx + 16, h * 0.48),
			Vector2(cx + 22, h - 4), Vector2(cx - 22, h - 4)
		]), accent.darkened(0.45))
		# 투구/후드/고깔모자 머리
		if category == "마법사":
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx, h * 0.14), Vector2(cx + 16, h * 0.48), Vector2(cx - 16, h * 0.48)
			]), accent.lightened(0.15))
		else:
			draw_circle(Vector2(cx, h * 0.34), 11.0, accent.lightened(0.15))
		# 테두리
		draw_rect(Rect2(1, 1, w - 2, h - 2), JobDb.grade_color(grade), false, 2.0)
