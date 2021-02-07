extends Spatial

const OPEN_SEE: Resource = preload("res://utils/OpenSeeGD.tscn")
const MODEL: Resource = preload("res://entities/basic-models/Person.tscn")
export var model_resource_path: String

var model
onready var model_parent: Spatial = $ModelParent

var model_initial_transform: Transform
var model_parent_initial_transform: Transform

var open_see: OpenSeeGD
var open_see_data: OpenSeeGD.OpenSeeData

class StoredOffsets:
	var translation_offset: Vector3
	var rotation_offset: Vector3
	var quat_offset: Quat
	var euler_offset: Vector3
var stored_offsets: StoredOffsets

export var face_id: int = 0
export var min_confidence: float = 0.2
export var show_gaze: bool = true

export var apply_translation: bool = true
export var translation_damp: float = 0.3
export var apply_rotation: bool = true
export var rotation_damp: float = 0.02

export var tracking_start_delay: float = 2.0

export var blink_threshold: float = 0.3

var updated: float = 0.0

# Input
var can_manipulate_model: bool = false
var should_spin_model: bool = false
var should_move_model: bool = false

export var zoom_strength: float = 0.05
export var mouse_move_strength: float = 0.002

###############################################################################
# Builtin functions                                                           #
###############################################################################

func _ready() -> void:
	if model_resource_path:
		var model_resource = load(model_resource_path)
		model = model_resource.instance()
	else:
		model = MODEL.instance()
	model.scale_object_local(Vector3(0.4, 0.4, 0.4))
	model_initial_transform = model.transform
	model_parent_initial_transform = model_parent.transform
	model_parent.call_deferred("add_child", model)

	self.open_see = OPEN_SEE.instance()
	self.call_deferred("add_child", open_see)

	var offset_timer: Timer = Timer.new()
	self.call_deferred("add_child", offset_timer)
	offset_timer.name = "OffsetTimer"
	offset_timer.connect("timeout", self, "_on_offset_timer_timeout")
	offset_timer.wait_time = tracking_start_delay
	offset_timer.autostart = true

func _process(_delta: float) -> void:
	if not stored_offsets:
		return

	self.open_see_data = open_see.get_open_see_data(face_id)

	if(not open_see_data or open_see_data.fit_3d_error > open_see.max_fit_3d_error):
		return
	
	if open_see_data.time > updated:
		updated = open_see_data.time
	else:
		return

	var head_translation: Vector3 = Vector3.ZERO
	var head_rotation: Vector3 = Vector3.ZERO
	if apply_translation:
		head_translation = (stored_offsets.translation_offset - open_see_data.translation) * translation_damp

	if apply_rotation:
		var corrected_euler: Vector3 = open_see_data.raw_euler
		if corrected_euler.x < 0.0:
			corrected_euler.x = 360 + corrected_euler.x
		head_rotation = (stored_offsets.euler_offset - corrected_euler) * rotation_damp

	# TODO solve for real head-to-camera translation + rotation
	# Moving head without rotation still causes rotation to be registered
	# because rotation is based off of head-to-camera position
	
	if not model.is_blinking:
		if(open_see_data.left_eye_open < blink_threshold and open_see_data.right_eye_open < blink_threshold):
			model.blink()
	elif model.is_blinking:
		if(open_see_data.left_eye_open > blink_threshold and open_see_data.right_eye_open > blink_threshold):
			model.unblink()

	model.move_head(
		Vector3(head_translation.x, -head_translation.y, head_translation.z),
		Vector3(-head_rotation.x, -head_rotation.y, head_rotation.z)
	)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_save_offsets()

	if event.is_action_pressed("allow_move_model"):
		can_manipulate_model = true
	elif event.is_action_released("allow_move_model"):
		can_manipulate_model = false
		should_spin_model = false
		should_move_model = false

	if can_manipulate_model:
		if event.is_action_pressed("left_click"):
			should_spin_model = true
		elif event.is_action_released("left_click"):
			should_spin_model = false
		
		# Reset model
		if event.is_action_pressed("middle_click"):
			model.transform = model_initial_transform
			model_parent.transform = model_parent_initial_transform
		
		if event.is_action_pressed("right_click"):
			should_move_model = true
		elif event.is_action_released("right_click"):
			should_move_model = false

		if event.is_action("scroll_up"):
			model_parent.translate(Vector3(0.0, 0.0, zoom_strength))
		elif event.is_action("scroll_down"):
			model_parent.translate(Vector3(0.0, 0.0, -zoom_strength))

		if(should_spin_model and event is InputEventMouseMotion):
			model.rotate_x(event.relative.y * mouse_move_strength)
			model.rotate_y(event.relative.x * mouse_move_strength)
		
		if(should_move_model and event is InputEventMouseMotion):
			model_parent.translate(Vector3(event.relative.x, -event.relative.y, 0.0) * mouse_move_strength)
	
	# TODO debug inputs for expressions for now
	if Input.is_key_pressed(KEY_1):
		model.change_expression_to(BasicModel.ExpressionTypes.DEFAULT)
	elif Input.is_key_pressed(KEY_2):
		model.change_expression_to(BasicModel.ExpressionTypes.HAPPY)
	elif Input.is_key_pressed(KEY_3):
		model.change_expression_to(BasicModel.ExpressionTypes.ANGRY)
	elif Input.is_key_pressed(KEY_4):
		model.change_expression_to(BasicModel.ExpressionTypes.SAD)
	elif Input.is_key_pressed(KEY_5):
		model.change_expression_to(BasicModel.ExpressionTypes.SHOCKED)
	elif Input.is_key_pressed(KEY_6):
		model.change_expression_to(BasicModel.ExpressionTypes.BASHFUL)

###############################################################################
# Connections                                                                 #
###############################################################################

func _on_offset_timer_timeout() -> void:
	get_node("OffsetTimer").queue_free()

	stored_offsets = StoredOffsets.new()
	open_see_data = open_see.get_open_see_data(face_id)
	_save_offsets()

###############################################################################
# Private functions                                                           #
###############################################################################

# TODO probably incorrect?
func _to_godot_quat(v: Quat) -> Quat:
	return Quat(v.x, -v.y, v.z, v.w)

func _save_offsets() -> void:
	stored_offsets.translation_offset = open_see_data.translation
	stored_offsets.rotation_offset = open_see_data.rotation
	stored_offsets.quat_offset = _to_godot_quat(open_see_data.raw_quaternion)
	var corrected_euler: Vector3 = open_see_data.raw_euler
	if corrected_euler.x < 0.0:
		corrected_euler.x = 360 + corrected_euler.x
	stored_offsets.euler_offset = corrected_euler

###############################################################################
# Public functions                                                            #
###############################################################################


