class_name BuildingPopups
extends RefCounted
## 건물 종류(def.type)별 팝업 클래스를 생성하는 팩토리. 팝업 11종을 한 곳에서 등록한다.

const _SCRIPTS: Dictionary = {
	"guild": preload("res://scenes/estate/buildings/guild_popup.gd"),
	"lodge": preload("res://scenes/estate/buildings/lodge_popup.gd"),
	"treatment": preload("res://scenes/estate/buildings/treatment_popup.gd"),
	"manor": preload("res://scenes/estate/buildings/manor_popup.gd"),
	"store": preload("res://scenes/estate/buildings/store_popup.gd"),
	"warehouse": preload("res://scenes/estate/buildings/warehouse_popup.gd"),
	"blacksmith": preload("res://scenes/estate/buildings/blacksmith_popup.gd"),
	"magic": preload("res://scenes/estate/buildings/magic_popup.gd"),
	"training": preload("res://scenes/estate/buildings/training_popup.gd"),
	"memorial": preload("res://scenes/estate/buildings/memorial_popup.gd"),
	"dungeon": preload("res://scenes/estate/buildings/dungeon_popup.gd"),
}


## 건물 정의에 맞는 팝업 인스턴스를 만든다. 등록되지 않은 종류면 공통 틀만 가진 기본 팝업을 반환한다.
static func create(estate: EstateWorld, def: Dictionary) -> BaseBuildingPopup:
	var script: GDScript = _SCRIPTS.get(def.type, null)
	if script == null:
		return BaseBuildingPopup.new(estate, def)
	return script.new(estate, def)
