extends RefCounted

const MOVING_OUT_EVENT_ID: String = "moving_out"
const FOR_SALE_SIGN_NODE_PATH: NodePath = ^"ForSaleSign"

var events: Array[String] = [
	MOVING_OUT_EVENT_ID
]

var _last_event_id: String = ""
var _active_event_id: String = ""
var _events_enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func setup(world_root: Node) -> void:
	_rng.randomize()
	_active_event_id = ""
	_apply_event("", world_root)

func run_for_day(_day_number: int, world_root: Node) -> void:
	_active_event_id = _choose_event()
	if _events_enabled:
		_apply_event(_active_event_id, world_root)
	else:
		_apply_event("", world_root)
	_last_event_id = _active_event_id

func set_events_enabled(is_enabled: bool, world_root: Node) -> void:
	_events_enabled = is_enabled
	if _events_enabled:
		_apply_event(_active_event_id, world_root)
	else:
		_apply_event("", world_root)

func _choose_event() -> String:
	if events.is_empty():
		return ""

	var candidate_event_id: String = events[_rng.randi_range(0, events.size() - 1)]

	if candidate_event_id == _last_event_id:
		return ""
	return candidate_event_id

func _apply_event(event_id: String, world_root: Node) -> void:
	var moving_out_active: bool = event_id == MOVING_OUT_EVENT_ID
	_set_for_sale_sign_visible(world_root, moving_out_active)

func _set_for_sale_sign_visible(world_root: Node, is_visible: bool) -> void:
	var for_sale_sign := world_root.get_node_or_null(FOR_SALE_SIGN_NODE_PATH)
	if for_sale_sign and for_sale_sign is Node3D:
		(for_sale_sign as Node3D).visible = is_visible
