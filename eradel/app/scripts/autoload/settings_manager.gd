extends Node

## 환경설정 관리자 — 게임플레이, 비디오, 오디오, 조작키 설정을 관리하고 즉시 반영한다.
## 기획서 5장(Setting 팝업) 및 스케치 기반.

const SETTINGS_FILE_PATH: String = "user://settings.json"

signal settings_changed(category: String)

var gameplay := {
	"battle_speed": 1,        # 1, 2, 4
	"show_tooltips": true,    # ON / OFF
	"text_speed": 1,          # 1, 2, 4
	"always_show_hp": true,   # ON / OFF
	"screen_shake": true,     # ON / OFF
	"photosensitivity": false,# ON / OFF (광과민성 보호: ON 시 화면흔들림 강제 OFF)
}

var video := {
	"window_mode": 1,         # 0: 전체화면, 1: 창모드, 2: 전체 창모드(Borderless)
	"resolution_w": 1280,
	"resolution_h": 720,
	"max_fps": 60,            # 30, 60, 120, 144, 0 (0은 제한 없음)
	"graphic_quality": "medium", # high, medium, low
	"texture_quality": "medium",
	"shadow_quality": "medium",
	"antialiasing": "medium",
	"brightness": 50,         # 0 ~ 100
}

var audio := {
	"master_volume": 80,      # 0 ~ 100
	"bgm_volume": 70,         # 0 ~ 100
	"sfx_volume": 80,         # 0 ~ 100
	"ui_volume": 80,          # 0 ~ 100
	"output_device": "기본 장치",
	"mute_in_background": true, # 포커스 해제 시 음소거
	"subtitles": true,        # 자막 표시 여부
}

var controls := {
	"inventory": KEY_I,       # 인벤토리
	"map": KEY_M,             # 지도
	"menu": KEY_ESCAPE,       # 영지/메뉴
	"end_turn": KEY_SPACE,    # 턴 종료/대기
}

var _default_controls := {
	"inventory": KEY_I,
	"map": KEY_M,
	"menu": KEY_ESCAPE,
	"end_turn": KEY_SPACE,
}


func _ready() -> void:
	load_settings()
	apply_all_settings()


func _notification(what: int) -> void:
	# 창 포커스 잃었을 때 음소거 처리
	if audio.get("mute_in_background", true):
		if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
			var bus_idx := AudioServer.get_bus_index("Master")
			if bus_idx >= 0:
				AudioServer.set_bus_mute(bus_idx, true)
		elif what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
			var bus_idx := AudioServer.get_bus_index("Master")
			if bus_idx >= 0:
				AudioServer.set_bus_mute(bus_idx, false)


## 모든 설정을 파일에서 불러온 후 엔진에 적용한다.
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		return

	var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if file == null:
		return
	var json_str := file.get_as_text()
	file.close()

	var parse_res = JSON.parse_string(json_str)
	if not (parse_res is Dictionary):
		return

	var data: Dictionary = parse_res
	if data.has("gameplay") and data["gameplay"] is Dictionary:
		for k in data["gameplay"]:
			gameplay[k] = data["gameplay"][k]

	if data.has("video") and data["video"] is Dictionary:
		for k in data["video"]:
			video[k] = data["video"][k]

	if data.has("audio") and data["audio"] is Dictionary:
		for k in data["audio"]:
			audio[k] = data["audio"][k]

	if data.has("controls") and data["controls"] is Dictionary:
		for k in data["controls"]:
			controls[k] = int(data["controls"][k])


## 현재 설정을 파일에 즉시 영구 저장한다.
func save_settings() -> void:
	var payload := {
		"gameplay": gameplay,
		"video": video,
		"audio": audio,
		"controls": controls,
	}
	var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


## 모든 카테고리의 설정을 실제 엔진에 즉시 반영한다.
func apply_all_settings() -> void:
	apply_gameplay()
	apply_video()
	apply_audio()
	apply_controls()


## 게임플레이 관련 설정을 적용한다.
func apply_gameplay() -> void:
	# 광과민성 보호가 켜져 있으면 화면 흔들림을 강제 비활성화
	if gameplay.get("photosensitivity", false):
		gameplay["screen_shake"] = false
	settings_changed.emit("gameplay")


## 비디오 설정을 실제 창 및 렌더링에 적용한다.
func apply_video() -> void:
	var mode: int = int(video.get("window_mode", 1))
	var w: int = int(video.get("resolution_w", 1280))
	var h: int = int(video.get("resolution_h", 720))
	var max_fps: int = int(video.get("max_fps", 60))
	var screen_size := DisplayServer.screen_get_size()

	var ml = Engine.get_main_loop()
	var root_win: Window = ml.root if (ml and "root" in ml) else null

	# 1. 창 모드 및 창 크기/위치 설정 (Window 노드 및 DisplayServer 동시 제어)
	match mode:
		0: # 전체화면
			if root_win != null:
				root_win.borderless = false
				root_win.mode = Window.MODE_FULLSCREEN
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		1: # 일반 창모드
			if root_win != null:
				root_win.mode = Window.MODE_WINDOWED
				root_win.borderless = false
				root_win.size = Vector2i(w, h)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(Vector2i(w, h))

			# 모니터 화면 중앙 정렬
			var center_pos := (screen_size - Vector2i(w, h)) / 2
			center_pos.x = max(0, center_pos.x)
			center_pos.y = max(0, center_pos.y)
			DisplayServer.window_set_position(center_pos)
			if root_win != null:
				root_win.position = center_pos
		2: # 테두리 없는 전체 창모드 (Borderless Windowed)
			if root_win != null:
				root_win.mode = Window.MODE_WINDOWED
				root_win.borderless = true
				root_win.size = screen_size
				root_win.position = Vector2i.ZERO
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_position(Vector2i.ZERO)

	# 2. 렌더링 뷰포트 해상도 스케일 즉시 반영
	# 기본 도화지 크기는 1280x720으로 고정하여 창 크기 변경 시에도 빈 공간이나 돋보기 현상 없이 꽉 차게 스케일링되도록 함
	if root_win != null:
		root_win.content_scale_size = Vector2i(1280, 720)
		root_win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

	# 3. 프레임 제한 설정
	Engine.max_fps = max_fps
	settings_changed.emit("video")


## 오디오 설정을 AudioServer에 즉각 적용한다.
func apply_audio() -> void:
	var master_vol: float = float(audio.get("master_volume", 80)) / 100.0
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		if master_vol <= 0.01:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(master_vol))

	# 출력 장치 선택
	var dev_name: String = str(audio.get("output_device", "기본 장치"))
	if dev_name != "기본 장치":
		AudioServer.set_output_device(dev_name)

	settings_changed.emit("audio")


## 조작키를 InputMap에 등록 및 갱신한다.
func apply_controls() -> void:
	for action in controls:
		var key_code: int = int(controls[action])
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)

		var ev := InputEventKey.new()
		ev.physical_keycode = key_code as Key
		InputMap.action_add_event(action, ev)

	settings_changed.emit("controls")


## 조작키 설정을 초기 기본값으로 되돌린다.
func reset_controls_to_default() -> void:
	for action in _default_controls:
		controls[action] = _default_controls[action]
	apply_controls()
	save_settings()


## 키 코드의 읽기 쉬운 라벨 문자열을 반환한다.
func get_key_label(key_code: int) -> String:
	return OS.get_keycode_string(key_code as Key)
