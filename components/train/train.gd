"""
instruction For AI
- this is Godot 4.4
- all internal variable mus start with '_internal' keyword
- all public var must not have '_' or  '_internal' at the begnning
- avioid comments
- keep this instruction always at the top
- all public var should use 

setget
exmpale in Godot 4
var health: float = 100.0:
	set = _set_health,
	get = _get_health

func _set_health(new_value: float) -> void:
	health = new_value

func _get_health() -> float:
	return health
"""

class_name Train
extends Node3D

var number_of_units: int = 1:
	set = _set_number_of_units,
	get = _get_number_of_units

var speed: float = 5.0:
	set = _set_speed,
	get = _get_speed

var gap: float = 2.0:
	set = _set_gap,
	get = _get_gap

var input_forward_action: String = "move_forward":
	set = _set_input_forward_action,
	get = _get_input_forward_action

var input_backward_action: String = "move_backward":
	set = _set_input_backward_action,
	get = _get_input_backward_action

var initial_path: Path3D:
	set = _set_initial_path,
	get = _get_initial_path

var next_path_override: Path3D:
	set = _set_next_path_override,
	get = _get_next_path_override

var train_unit_scene: PackedScene:
	set = _set_train_unit_scene,
	get = _get_train_unit_scene

var head_unit_front_offset: float = 0.0:
	set = _set_head_unit_front_offset,
	get = _get_head_unit_front_offset

signal all_units_on_new_path(new_path_node: Path3D, train_node: Train)
signal train_reached_end_of_route(train_node: Train)

var _internal_train_unit_ref_array: Array[Train_Unit] = []
var _internal_current_train_path_node: Path3D
var _internal_train_unit_template_instance: Train_Unit = null
var _internal_setting_head_offset_from_movement: bool = false
var _internal_is_setup_complete: bool = false


func _init() -> void:
	pass

static func create_train(
	train_unit_template: Train_Unit,
	p_initial_path: Path3D,
	p_train_unit_scene: PackedScene = null,
	p_number_of_units: int = 4,
	p_speed: float = 5.0,
	p_gap: float = 2.0,
	p_next_path_override: Path3D = null,
	p_input_forward_action: String = "move_forward",
	p_input_backward_action: String = "move_backward",
	p_initial_head_unit_front_offset: float = 0.0
) -> Train:
	var new_train := Train.new()

	new_train._internal_train_unit_template_instance = train_unit_template
	new_train.initial_path = p_initial_path
	
	if is_instance_valid(p_train_unit_scene):
		new_train.train_unit_scene = p_train_unit_scene
	
	new_train.number_of_units = p_number_of_units
	new_train.speed = p_speed
	new_train.gap = p_gap
	new_train.next_path_override = p_next_path_override
		
	new_train.input_forward_action = p_input_forward_action
	new_train.input_backward_action = p_input_backward_action
	new_train.head_unit_front_offset = p_initial_head_unit_front_offset
	return new_train

func _set_number_of_units(new_value: int) -> void:
	if number_of_units == new_value:
		return
	number_of_units = new_value
	if _internal_is_setup_complete and is_inside_tree():
		call_deferred("setup")

func _get_number_of_units() -> int:
	return number_of_units

func _set_speed(new_value: float) -> void:
	speed = new_value

func _get_speed() -> float:
	return speed

func _set_gap(new_value: float) -> void:
	if gap == new_value:
		return
	gap = new_value
	if _internal_is_setup_complete and is_inside_tree():
		call_deferred("setup")

func _get_gap() -> float:
	return gap

func _set_input_forward_action(new_value: String) -> void:
	input_forward_action = new_value

func _get_input_forward_action() -> String:
	return input_forward_action

func _set_input_backward_action(new_value: String) -> void:
	input_backward_action = new_value

func _get_input_backward_action() -> String:
	return input_backward_action

func _set_initial_path(new_value: Path3D) -> void:
	if initial_path == new_value:
		return
	initial_path = new_value
	if _internal_is_setup_complete and is_inside_tree():
		call_deferred("setup")

func _get_initial_path() -> Path3D:
	return initial_path

func _set_next_path_override(new_value: Path3D) -> void:
	next_path_override = new_value

func _get_next_path_override() -> Path3D:
	return next_path_override

func _set_train_unit_scene(new_value: PackedScene) -> void:
	if train_unit_scene == new_value:
		return
	train_unit_scene = new_value
	if _internal_is_setup_complete and is_inside_tree():
		call_deferred("setup")

func _get_train_unit_scene() -> PackedScene:
	return train_unit_scene

func _set_head_unit_front_offset(new_value: float) -> void:
	if _internal_setting_head_offset_from_movement:
		head_unit_front_offset = new_value
		return
	
	if head_unit_front_offset == new_value:
		return
	head_unit_front_offset = new_value

func _get_head_unit_front_offset() -> float:
	return head_unit_front_offset

func setup() -> void:
	_internal_is_setup_complete = false
	_clear_existing_units()
	if not is_instance_valid(initial_path):
		printerr("Train setup (%s): InitialPath not set." % name)
		return
	
	if not initial_path.is_inside_tree():
		printerr("Train setup (%s): InitialPath '%s' is not in the scene tree." % [name, initial_path.name])
		if not initial_path.is_connected("tree_entered", Callable(self, "_on_initial_path_entered_tree_for_setup")):
			initial_path.connect("tree_entered", Callable(self, "_on_initial_path_entered_tree_for_setup"), CONNECT_ONE_SHOT)
		return

	var can_create_units_from_template = is_instance_valid(_internal_train_unit_template_instance)
	var can_create_units_from_scene = is_instance_valid(train_unit_scene) and train_unit_scene.can_instantiate()
	
	if not can_create_units_from_template and not can_create_units_from_scene:
		printerr("Train setup (%s): Neither a template Train_Unit instance nor a TrainUnitScene is available. Will use default Train_Unit.new()." % name)

	_internal_current_train_path_node = initial_path
	var current_placement_front_offset: float = self.head_unit_front_offset 
	
	var first_unit_instance_for_length_calc: Train_Unit = null
	if can_create_units_from_template:
		first_unit_instance_for_length_calc = _internal_train_unit_template_instance
	elif can_create_units_from_scene:
		var temp_inst = train_unit_scene.instantiate()
		if temp_inst is Train_Unit: 
			first_unit_instance_for_length_calc = temp_inst as Train_Unit
		else: 
			if is_instance_valid(temp_inst): temp_inst.queue_free()
	
	if not is_instance_valid(first_unit_instance_for_length_calc):
		first_unit_instance_for_length_calc = Train_Unit.new() 

	var unit_base_length = first_unit_instance_for_length_calc.length
	var single_unit_footprint = unit_base_length + self.gap
	var total_initial_train_length_approx = (single_unit_footprint * number_of_units) - self.gap

	if self.head_unit_front_offset < total_initial_train_length_approx :
		self.head_unit_front_offset = total_initial_train_length_approx
	current_placement_front_offset = self.head_unit_front_offset
	
	if is_instance_valid(first_unit_instance_for_length_calc) and \
	   first_unit_instance_for_length_calc != _internal_train_unit_template_instance and \
	   not first_unit_instance_for_length_calc.is_inside_tree():
		first_unit_instance_for_length_calc.queue_free()

	for i in range(number_of_units):
		var unit_node_instance: Train_Unit
		
		if can_create_units_from_template:
			var dup_node = _internal_train_unit_template_instance.duplicate()
			if dup_node is Train_Unit:
				unit_node_instance = dup_node as Train_Unit
			else:
				if is_instance_valid(dup_node): dup_node.queue_free()
				printerr("Train setup (%s): Failed to duplicate _internal_train_unit_template_instance correctly. Falling back." % name)
				unit_node_instance = Train_Unit.new()
		elif can_create_units_from_scene:
			var inst_node: Node = train_unit_scene.instantiate()
			if inst_node is Train_Unit: 
				unit_node_instance = inst_node as Train_Unit
			else: 
				if is_instance_valid(inst_node): inst_node.queue_free()
				printerr("Train setup (%s): train_unit_scene did not instantiate a Train_Unit. Falling back." % name)
				unit_node_instance = Train_Unit.new()
		else: 
			unit_node_instance = Train_Unit.new()
		
		unit_node_instance.name = "TrainUnit_Node_" + str(i)
		unit_node_instance.unit_identifier_prefix = "Train" + str(self.get_instance_id()) + "_Unit" + str(i) + "_"
		unit_node_instance.target_path_3d_node = self.initial_path
		if i == 0 and is_instance_valid(next_path_override):
			if next_path_override.is_inside_tree():
				unit_node_instance.next_route_path_3d_node = next_path_override
			else:
				printerr("Train setup (%s): next_path_override '%s' for unit 0 is not in the scene tree." % [name, next_path_override.name])
		
		var unit_len = unit_node_instance.length
		var calculated_track_offset = current_placement_front_offset - unit_len
		if calculated_track_offset < 0.0: 
			calculated_track_offset = 0.0
		
		unit_node_instance.track_offset = calculated_track_offset
		current_placement_front_offset = unit_node_instance.track_offset
		
		unit_node_instance.connect("jumped_to_next_path", Callable(self, "_on_train_unit_jumped_path"))
		unit_node_instance.connect("reached_end_of_final_path", Callable(self, "_on_train_unit_reached_end"))
		
		add_child(unit_node_instance)
		_internal_train_unit_ref_array.append(unit_node_instance)
		
		if is_instance_valid(unit_node_instance.target_path_3d_node) and \
		   unit_node_instance.target_path_3d_node.is_inside_tree():
			if is_instance_valid(unit_node_instance.generate_node) and unit_node_instance.generate_node.is_valid():
				unit_node_instance.generate_node.call_deferred()
			else:
				printerr("Train setup (%s): unit %s has invalid generate_node. Attempting direct _generate_train." % [name, i])
				if unit_node_instance.has_method("_generate_train"):
					unit_node_instance.call_deferred("_generate_train")
		elif is_instance_valid(unit_node_instance.target_path_3d_node):
			printerr("Train setup (%s): target_path_3d_node for unit %s is not in tree. Generation deferred by Train_Unit." % [name, i])
		else:
			printerr("Train setup (%s): target_path_3d_node for unit %s is invalid." % [name, i])
		
		current_placement_front_offset = unit_node_instance.track_offset - self.gap
	
	if _internal_train_unit_ref_array.size() > 0 and is_instance_valid(_internal_train_unit_ref_array[0]):
		var first_unit = _internal_train_unit_ref_array[0]
		_internal_setting_head_offset_from_movement = true
		self.head_unit_front_offset = first_unit.get_front_bogie_progress()
		_internal_setting_head_offset_from_movement = false
	
	_internal_is_setup_complete = true

func _on_initial_path_entered_tree_for_setup():
	if is_inside_tree() and is_instance_valid(initial_path) and initial_path.is_inside_tree():
		call_deferred("setup")

func _clear_existing_units() -> void:
	for unit_node in _internal_train_unit_ref_array:
		if is_instance_valid(unit_node):
			if unit_node.is_connected("jumped_to_next_path", Callable(self, "_on_train_unit_jumped_path")):
				unit_node.disconnect("jumped_to_next_path", Callable(self, "_on_train_unit_jumped_path"))
			if unit_node.is_connected("reached_end_of_final_path", Callable(self, "_on_train_unit_reached_end")):
				unit_node.disconnect("reached_end_of_final_path", Callable(self, "_on_train_unit_reached_end"))
			unit_node.queue_free()
	_internal_train_unit_ref_array.clear()
	for i in range(get_child_count() - 1, -1, -1):
		var child = get_child(i)
		if child is Train_Unit: child.queue_free()

func _on_train_unit_jumped_path(new_path_node_for_unit: Path3D, unit_that_jumped: Train_Unit) -> void:
	var unit_index = _internal_train_unit_ref_array.find(unit_that_jumped)
	if unit_index == -1: return

	if unit_index + 1 < _internal_train_unit_ref_array.size():
		var unit_behind = _internal_train_unit_ref_array[unit_index + 1]
		if is_instance_valid(unit_behind) and unit_behind.next_route_path_3d_node != new_path_node_for_unit:
			unit_behind.next_route_path_3d_node = new_path_node_for_unit
	
	if unit_index == 0: 
		_internal_current_train_path_node = new_path_node_for_unit
		if self.next_path_override == new_path_node_for_unit:
			self.next_path_override = null

	var all_on_new_path = true
	for unit_node_from_array in _internal_train_unit_ref_array:
		if not is_instance_valid(unit_node_from_array) or unit_node_from_array.get_current_path() != new_path_node_for_unit:
			all_on_new_path = false
			break
	if all_on_new_path:
		emit_signal("all_units_on_new_path", new_path_node_for_unit, self)

func _on_train_unit_reached_end(unit_node: Train_Unit) -> void:
	var unit_index = _internal_train_unit_ref_array.find(unit_node)
	if unit_index == -1: return

	if unit_index == _internal_train_unit_ref_array.size() - 1:
		emit_signal("train_reached_end_of_route", self)

func _handle_train_movement(delta: float) -> void:
	var movement_input: float = Input.get_axis(input_backward_action, input_forward_action)
	
	var effective_movement_input = 0.0
	if movement_input > 1e-3 : 
		effective_movement_input = movement_input
	
	if abs(effective_movement_input) < 1e-3: return

	var distance_this_frame: float = effective_movement_input * self.speed * delta

	for i in range(_internal_train_unit_ref_array.size()):
		var unit_node = _internal_train_unit_ref_array[i]
		if not is_instance_valid(unit_node): continue
		
		if i == 0 and is_instance_valid(self.next_path_override):
			if unit_node.get_current_path() != self.next_path_override and \
			   unit_node.next_route_path_3d_node != self.next_path_override:
				unit_node.next_route_path_3d_node = self.next_path_override
		
		unit_node.move_forward_on_path(distance_this_frame)

	if _internal_train_unit_ref_array.size() > 0 and is_instance_valid(_internal_train_unit_ref_array[0]):
		var first_unit = _internal_train_unit_ref_array[0]
		_internal_setting_head_offset_from_movement = true
		self.head_unit_front_offset = first_unit.get_front_bogie_progress() 
		_internal_setting_head_offset_from_movement = false

func _physics_process(delta: float) -> void:
	if not _internal_is_setup_complete: 
		return
	_handle_train_movement(delta)

func get_train_units() -> Array[Train_Unit]:
	return _internal_train_unit_ref_array.duplicate()

func get_leading_unit() -> Train_Unit:
	if _internal_train_unit_ref_array.size() > 0 and is_instance_valid(_internal_train_unit_ref_array[0]):
		return _internal_train_unit_ref_array[0]
	return null

func get_trailing_unit() -> Train_Unit:
	if _internal_train_unit_ref_array.size() > 0 and is_instance_valid(_internal_train_unit_ref_array.back()):
		return _internal_train_unit_ref_array.back()
	return null

func get_current_train_path() -> Path3D:
	return _internal_current_train_path_node

func force_next_path_for_train(p_next_path: Path3D) -> void:
	self.next_path_override = p_next_path
	if _internal_train_unit_ref_array.size() > 0 and is_instance_valid(_internal_train_unit_ref_array[0]):
		var lead_unit = _internal_train_unit_ref_array[0]
		if lead_unit.get_current_path() != p_next_path and lead_unit.next_route_path_3d_node != p_next_path:
			lead_unit.next_route_path_3d_node = p_next_path
