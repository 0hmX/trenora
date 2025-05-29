# instruction For AI
# - this is Godot 4.4
# - all internal variable mus start with '_internal' keyword
# - all public var must not have '_' or  '_internal' at the begnning
# - avioid comments
# - keep this instruction always at the top
# - all public var should use
# setget
# exmpale in Godot 4
# var health: float = 100.0:
# 	set = _set_health,
# 	get = _get_health
# func _set_health(new_value: float) -> void:
# 	health = new_value
# func _get_health() -> float:
# 	return health

class_name TrackManager
extends Node3D

@export_group("Generation Parameters")
@export var auto_generate_on_ready: bool = true
@export var initial_segments_to_generate: int = 5
@export var max_active_segments: int = 20

@export_group("Segment Properties")
@export var chunk_length: float = 20.0
@export var points_per_chunk: int = 10

@export_group("Visual Properties")
@export var track_width: float = 2.5
@export var track_material: StandardMaterial3D
@export var track_texture: Texture2D
@export var texture_tile_length_v: float = 10.0

@export_group("Initial State")
@export var initial_tangent_direction: Vector3 = Vector3.FORWARD
@export var initial_up_vector: Vector3 = Vector3.UP

@export_group("Train Spawning")
@export var spawn_train_action:= "sprint"
@export var desired_segments_ahead_of_train: int = 3

@export_group("Train Unit Template Properties")
@export var unit_length: float = 5.0
@export var unit_main_body_scene: PackedScene
@export var unit_bogie_scene: PackedScene
@export var unit_up_dir: Vector3 = Vector3.UP
@export var unit_main_mesh_offset_v: float = 1.0

@export_group("Train Properties")
@export var train_number_of_units: int = 4
@export var train_speed: float = 5.0
@export var train_gap: float = 2.0
@export var train_input_forward_action: String = "move_forward"
@export var train_input_backward_action: String = "move_backward"
@export var train_initial_head_unit_front_offset: float = 0.0


var _internal_segment_generator: TrackSegmentGenerator
var _internal_mesh_builder: TrackMeshBuilder
var _internal_track_strategy: TrackStrategy
var _internal_train_instance: Train

var _internal_active_segments_data: Array[TrackSegmentData] = []
var _internal_last_generated_position_w: Vector3
var _internal_last_generated_tangent_w: Vector3
var _internal_current_up_vector_w: Vector3

var _internal_next_segment_unique_id: int = 0
var _internal_is_initialized: bool = false

const _INTERNAL_DEFAULT_TRACK_TYPE_CONFIGURATIONS = {
	"straight": {"weight": 10.0, "params": {}},
	"circle_left": {"weight": 3.0, "params": {"radius": 50.0}},
	"circle_right": {"weight": 3.0, "params": {"radius": 50.0}},
	"up": {"weight": 1.5, "params": {"vertical_change": 5.0, "smooth_factor": 0.4, "length_override": 30.0}},
	"down": {"weight": 1.5, "params": {"vertical_change": -5.0, "smooth_factor": 0.4, "length_override": 30.0}},
	"s_curve": {
		"weight": 2.0,
		"sequence": [
			{"type": "circle_left", "params": {"radius": 40.0}, "length_override": 25.0, "num_points_override": 12},
			{"type": "straight", "length_override": 5.0, "num_points_override": 3},
			{"type": "circle_right", "params": {"radius": 40.0}, "length_override": 25.0, "num_points_override": 12}
		]
	}
}

func _ready() -> void:
	if not is_instance_valid(_internal_segment_generator): _internal_segment_generator = TrackSegmentGenerator.new()
	if not is_instance_valid(_internal_mesh_builder): _internal_mesh_builder = TrackMeshBuilder.new()
	if not is_instance_valid(_internal_track_strategy): _internal_track_strategy = TrackStrategy.new(_INTERNAL_DEFAULT_TRACK_TYPE_CONFIGURATIONS)

	_internal_last_generated_position_w = global_position
	_internal_last_generated_tangent_w = global_transform.basis * initial_tangent_direction.normalized()
	_internal_current_up_vector_w = global_transform.basis * initial_up_vector.normalized()
	if not _internal_current_up_vector_w.is_normalized(): _internal_current_up_vector_w = Vector3.UP

	if auto_generate_on_ready:
		_initialize_track_system()

func _unhandled_input(event: InputEvent) -> void:
	if not _internal_is_initialized: return

	if event.is_action_pressed(spawn_train_action):
		if not is_instance_valid(_internal_train_instance):
			var initial_path_for_train: Path3D = null
			var next_path_for_train: Path3D = null

			if _internal_active_segments_data.size() > 0:
				initial_path_for_train = _internal_active_segments_data[0].path_3d_node
			if _internal_active_segments_data.size() > 1:
				next_path_for_train = _internal_active_segments_data[1].path_3d_node

			if is_instance_valid(initial_path_for_train):
				_spawn_and_setup_train(initial_path_for_train, next_path_for_train)
				get_viewport().set_input_as_handled()
			else:
				printerr("TrackManager: Not enough track segments generated to spawn train via action.")
		else:
			print_debug("TrackManager: Train already spawned.")


func _initialize_track_system():
	if _internal_is_initialized: return

	_clear_all_segments_and_train()

	_internal_last_generated_position_w = global_position
	_internal_last_generated_tangent_w = global_transform.basis * initial_tangent_direction.normalized()
	_internal_current_up_vector_w = global_transform.basis * initial_up_vector.normalized()
	if not _internal_current_up_vector_w.is_normalized(): _internal_current_up_vector_w = Vector3.UP

	_internal_active_segments_data.clear()
	_internal_next_segment_unique_id = 0

	var segments_to_generate_count = min(initial_segments_to_generate, max_active_segments)
	for i in range(segments_to_generate_count):
		if not _generate_next_segment_sequence():
			printerr("TrackManager: Generation stopped prematurely during initialization at segment %s." % (i + 1))
			break

	if _internal_active_segments_data.is_empty() and segments_to_generate_count > 0:
		printerr("TrackManager: Failed to generate any initial segments despite attempting to generate %s." % segments_to_generate_count)
	elif _internal_active_segments_data.size() < segments_to_generate_count:
		print_verbose("TrackManager: Generated %s segments, less than the target %s." % [_internal_active_segments_data.size(), segments_to_generate_count])

	_internal_is_initialized = true


func _spawn_and_setup_train(p_initial_train_path: Path3D, p_next_train_path_override: Path3D) -> void:
	if is_instance_valid(_internal_train_instance):
		_internal_train_instance.queue_free()
		_internal_train_instance = null

	if not is_instance_valid(p_initial_train_path):
		printerr("TrackManager: p_initial_train_path is not valid, cannot spawn train.")
		return

	if not p_initial_train_path.is_inside_tree():
		printerr("TrackManager: p_initial_train_path '%s' is not in the scene tree. Cannot spawn train." % p_initial_train_path.name)
		return
	if is_instance_valid(p_next_train_path_override) and not p_next_train_path_override.is_inside_tree():
		printerr("TrackManager: p_next_train_path_override '%s' is not in the scene tree." % p_next_train_path_override.name)


	var template_train_unit := Train_Unit.create_train_unit(
		p_initial_train_path,
		unit_length,
		unit_main_body_scene,
		unit_bogie_scene,
		p_next_train_path_override,
		0.0,
		unit_up_dir,
		unit_main_mesh_offset_v,
		"TemplateFor_"
	)

	if not is_instance_valid(template_train_unit):
		printerr("TrackManager: Failed to create template_train_unit.")
		return

	_internal_train_instance = Train.create_train(
		template_train_unit,
		p_initial_train_path,
		null,
		train_number_of_units,
		train_speed,
		train_gap,
		p_next_train_path_override,
		train_input_forward_action,
		train_input_backward_action,
		train_initial_head_unit_front_offset
	)

	if not is_instance_valid(_internal_train_instance):
		printerr("TrackManager: Failed to create train instance using Train.create_train.")
		if is_instance_valid(template_train_unit) and template_train_unit.get_parent() == null:
			template_train_unit.queue_free()
		return

	if is_instance_valid(template_train_unit) and template_train_unit.get_parent() == null:
		template_train_unit.queue_free()

	add_child(_internal_train_instance)

	if _internal_train_instance.has_method("setup"): # setup is public
		_internal_train_instance.call_deferred("setup")
	else:
		printerr("TrackManager: Train instance does not have a 'setup' method.")


	if not _internal_train_instance.is_connected("all_units_on_new_path", Callable(self, "_on_train_all_units_on_new_path")):
		var err = _internal_train_instance.connect("all_units_on_new_path", Callable(self, "_on_train_all_units_on_new_path"))
		if err != OK:
			printerr("TrackManager: Failed to connect train's all_units_on_new_path signal. Error: ", err)


func _physics_process(_delta: float) -> void:
	if not _internal_is_initialized:
		return

	if is_instance_valid(_internal_train_instance):
		var train_current_path: Path3D = null
		
		if _internal_train_instance.get_train_units().size() > 0:
			var lead_unit: Train_Unit = _internal_train_instance.get_leading_unit()
			if is_instance_valid(lead_unit):
				train_current_path = lead_unit.get_current_path() # Public API of Train_Unit

		if is_instance_valid(train_current_path):
			var train_segment_idx = -1
			for i in range(_internal_active_segments_data.size()):
				if _internal_active_segments_data[i].path_3d_node == train_current_path:
					train_segment_idx = i
					break

			if train_segment_idx != -1:
				var segments_ahead_of_train = _internal_active_segments_data.size() - 1 - train_segment_idx
				var effective_desired_segments_ahead = max(1, desired_segments_ahead_of_train)

				if segments_ahead_of_train < effective_desired_segments_ahead and _internal_active_segments_data.size() < max_active_segments:
					var num_to_generate = min(effective_desired_segments_ahead - segments_ahead_of_train, max_active_segments - _internal_active_segments_data.size())
					for _i in range(num_to_generate):
						if _internal_active_segments_data.size() >= max_active_segments: break
						if not _generate_next_segment_sequence():
							break


func _on_train_all_units_on_new_path(new_path_node_for_train: Path3D, p_train_node: Train) -> void:
	if not is_instance_valid(p_train_node) or p_train_node != _internal_train_instance: return
	if not is_instance_valid(new_path_node_for_train): return

	var current_segment_index: int = -1
	for i in range(_internal_active_segments_data.size()):
		var segment_data: TrackSegmentData = _internal_active_segments_data[i]
		if is_instance_valid(segment_data) and segment_data.path_3d_node == new_path_node_for_train:
			current_segment_index = i
			break

	if current_segment_index == -1:
		printerr("TrackManager: Could not find segment data for path train moved to: ", new_path_node_for_train.name)
		if is_instance_valid(_internal_train_instance):
			_internal_train_instance.next_path_override = null # Public var with setget
		return

	var next_segment_index = current_segment_index + 1
	var new_next_path_for_train: Path3D = null
	if next_segment_index < _internal_active_segments_data.size():
		var next_segment_data: TrackSegmentData = _internal_active_segments_data[next_segment_index]
		if is_instance_valid(next_segment_data) and is_instance_valid(next_segment_data.path_3d_node):
			new_next_path_for_train = next_segment_data.path_3d_node

	if is_instance_valid(_internal_train_instance):
		_internal_train_instance.next_path_override = new_next_path_for_train # Public var with setget

	var num_to_prune_due_to_limit = _internal_active_segments_data.size() - max_active_segments
	var actual_pruned_count = 0
	if num_to_prune_due_to_limit > 0:
		for _i in range(min(num_to_prune_due_to_limit, current_segment_index)):
			if _internal_active_segments_data.is_empty(): break
			var segment_to_remove: TrackSegmentData = _internal_active_segments_data.pop_front()
			if is_instance_valid(segment_to_remove):
				segment_to_remove.clear_mesh()
				if is_instance_valid(segment_to_remove.path_3d_node):
					segment_to_remove.path_3d_node.queue_free()
				actual_pruned_count += 1
	else:
		var max_segments_to_keep_behind = 0
		var segments_to_prune_behind = current_segment_index - max_segments_to_keep_behind
		if segments_to_prune_behind > 0:
			for _i in range(segments_to_prune_behind):
				if _internal_active_segments_data.is_empty(): break
				var segment_to_remove: TrackSegmentData = _internal_active_segments_data.pop_front()
				if is_instance_valid(segment_to_remove):
					segment_to_remove.clear_mesh()
					if is_instance_valid(segment_to_remove.path_3d_node):
						segment_to_remove.path_3d_node.queue_free()
					actual_pruned_count += 1

	if actual_pruned_count > 0:
		var found_again = false
		for i_new in range(_internal_active_segments_data.size()):
			if is_instance_valid(_internal_active_segments_data[i_new]) and _internal_active_segments_data[i_new].path_3d_node == new_path_node_for_train:
				current_segment_index = i_new
				found_again = true
				break
		if not found_again:
			printerr("TrackManager: CRITICAL - Could not re-locate train's current path after pruning.")
			return

	var segments_ahead_of_train = _internal_active_segments_data.size() - 1 - current_segment_index
	var effective_desired_segments_ahead = max(1, desired_segments_ahead_of_train)
	var num_to_generate_proactively = 0
	if segments_ahead_of_train < effective_desired_segments_ahead:
		num_to_generate_proactively = effective_desired_segments_ahead - segments_ahead_of_train

	num_to_generate_proactively = min(num_to_generate_proactively, max_active_segments - _internal_active_segments_data.size())

	if num_to_generate_proactively > 0:
		for _i in range(num_to_generate_proactively):
			if _internal_active_segments_data.size() < max_active_segments:
				if not _generate_next_segment_sequence(): break
			else: break

func _generate_next_segment_sequence() -> bool:
	if _internal_active_segments_data.size() >= max_active_segments:
		return false

	if not is_instance_valid(_internal_track_strategy):
		printerr("TrackManager: _internal_track_strategy is not valid!")
		return false
	var master_type_key = _internal_track_strategy.get_next_segment_type(_internal_active_segments_data)
	var master_config = _internal_track_strategy.get_base_config_for_type(master_type_key)

	if master_config == null:
		printerr("TrackManager: No configuration found for master type '%s'." % master_type_key)
		return false

	var segments_in_sequence: Array[Dictionary] = []
	if master_config.has("sequence"):
		var raw_sequence = master_config.get("sequence")
		if raw_sequence is Array and not raw_sequence.is_empty():
			for item in raw_sequence:
				if item is Dictionary:
					segments_in_sequence.append(item)
				else:
					printerr("TrackManager: Item in master_config.sequence is not a Dictionary. Skipping. Item: ", item)

	if segments_in_sequence.is_empty():
		segments_in_sequence.append({"type": master_type_key, "params": master_config.get("params", {})})

	var overall_success_for_sequence = true
	for sub_segment_config in segments_in_sequence:
		if _internal_active_segments_data.size() >= max_active_segments:
			overall_success_for_sequence = false; break

		var specific_type_key = sub_segment_config.get("type", "straight")
		var params_override = sub_segment_config.get("params", {})
		var base_type_config = _internal_track_strategy.get_base_config_for_type(specific_type_key)

		if base_type_config == null:
			printerr("TrackManager: No base configuration found for sub-segment type '%s'." % specific_type_key)
			overall_success_for_sequence = false; break

		var current_segment_length = sub_segment_config.get("length_override", chunk_length)
		var num_points = sub_segment_config.get("num_points_override", points_per_chunk)

		if not is_instance_valid(_internal_segment_generator):
			printerr("TrackManager: _internal_segment_generator is not valid!")
			return false

		var segment_data_obj: TrackSegmentData = _internal_segment_generator.generate_segment_data(
			specific_type_key, params_override, base_type_config, num_points,
			current_segment_length, _internal_last_generated_position_w,
			_internal_last_generated_tangent_w, _internal_current_up_vector_w)

		if not is_instance_valid(segment_data_obj) or segment_data_obj.points_w.size() < 2:
			printerr("TrackManager: Failed to generate segment data for type '%s'." % specific_type_key)
			overall_success_for_sequence = false
			break

		var path_node = Path3D.new()
		path_node.name = "TrackSegmentPath_" + str(_internal_next_segment_unique_id)
		add_child(path_node)
		path_node.global_transform = Transform3D.IDENTITY

		segment_data_obj.path_3d_node = path_node
		segment_data_obj.id = _internal_next_segment_unique_id
		_internal_next_segment_unique_id += 1

		if not is_instance_valid(path_node.curve):
			path_node.curve = Curve3D.new()

		for p_w in segment_data_obj.points_w:
			path_node.curve.add_point(path_node.to_local(p_w))


		if not is_instance_valid(_internal_mesh_builder):
			printerr("TrackManager: _internal_mesh_builder is not valid!")
			overall_success_for_sequence = false; break

		var mesh_instance = _internal_mesh_builder.build_mesh_for_segment(segment_data_obj, path_node.global_transform,
			_internal_current_up_vector_w, track_width, track_material, track_texture, texture_tile_length_v)

		if is_instance_valid(mesh_instance):
			segment_data_obj.mesh_instance = mesh_instance
			path_node.add_child(mesh_instance)
		else:
			printerr("TrackManager: Failed to build mesh for segment %s." % path_node.name)

		_internal_active_segments_data.append(segment_data_obj)
		_internal_last_generated_position_w = segment_data_obj.points_w[-1]
		_internal_last_generated_tangent_w = segment_data_obj.end_tangent_w.normalized()

		var new_right_w = _internal_last_generated_tangent_w.cross(_internal_current_up_vector_w).normalized()
		if new_right_w.is_zero_approx():
			var temp_reference_vec = Vector3.RIGHT if abs(_internal_last_generated_tangent_w.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
			new_right_w = _internal_last_generated_tangent_w.cross(temp_reference_vec).normalized()
			if new_right_w.is_zero_approx():
				var up_hint = Vector3.UP
				if (_internal_last_generated_tangent_w - Vector3.UP).length_squared() < 0.0001 or \
				   (_internal_last_generated_tangent_w - Vector3.DOWN).length_squared() < 0.0001:
					up_hint = Vector3.FORWARD
				_internal_current_up_vector_w = Transform3D().looking_at(_internal_last_generated_tangent_w, up_hint).basis.y.normalized()
			else:
				_internal_current_up_vector_w = new_right_w.cross(_internal_last_generated_tangent_w).normalized()
		else:
			_internal_current_up_vector_w = new_right_w.cross(_internal_last_generated_tangent_w).normalized()

		if _internal_current_up_vector_w.is_zero_approx() or not _internal_current_up_vector_w.is_finite():
			printerr("TrackManager: Degenerate up vector. Resetting to Vector3.UP.")
			_internal_current_up_vector_w = Vector3.UP

	return overall_success_for_sequence

func _clear_all_segments_and_train():
	if is_instance_valid(_internal_train_instance):
		if _internal_train_instance.is_connected("all_units_on_new_path", Callable(self, "_on_train_all_units_on_new_path")):
			_internal_train_instance.disconnect("all_units_on_new_path", Callable(self, "_on_train_all_units_on_new_path"))
		_internal_train_instance.queue_free()
		_internal_train_instance = null

	for segment_data in _internal_active_segments_data:
		if is_instance_valid(segment_data):
			segment_data.clear_mesh()
			if is_instance_valid(segment_data.path_3d_node):
				segment_data.path_3d_node.queue_free()
	_internal_active_segments_data.clear()
