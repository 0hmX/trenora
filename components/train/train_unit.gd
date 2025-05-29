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

class_name Train_Unit
extends Node3D

var target_path_3d_node: Path3D:
	set = _set_target_path_3d_node,
	get = _get_target_path_3d_node

var next_route_path_3d_node: Path3D:
	set = _set_next_route_path_3d_node,
	get = _get_next_route_path_3d_node

var generate_node: Callable:
	set = _set_generate_node,
	get = _get_generate_node

var main_body_scene: PackedScene:
	set = _set_main_body_scene,
	get = _get_main_body_scene

var bogie_scene: PackedScene:
	set = _set_bogie_scene,
	get = _get_bogie_scene

var up_dir: Vector3 = Vector3.UP:
	set = _set_up_dir,
	get = _get_up_dir

var length: float = 5.0:
	set = _set_length,
	get = _get_length

var track_offset: float = 0.0:
	set = _set_track_offset,
	get = _get_track_offset

var main_mesh_offset_v: float = 1.0:
	set = _set_main_mesh_offset_v,
	get = _get_main_mesh_offset_v

var unit_identifier_prefix: String = "":
	set = _set_unit_identifier_prefix,
	get = _get_unit_identifier_prefix

signal jumped_to_next_path(new_path_node: Path3D, unit_node: Train_Unit)
signal reached_end_of_final_path(unit_node: Train_Unit)

const BASE_MAIN_BODY_NAME := "MainBody"
const BASE_FRONT_BOGIE_ASSEMBLY_NAME := "FrontBogieAssembly"
const BASE_REAR_BOGIE_ASSEMBLY_NAME := "RearBogieAssembly"
const BASE_BOGIE_MESH_INSTANCE_NAME := "BogieMeshInstance"

var _internal_front_bogie_follower_node: PathFollow3D
var _internal_rear_bogie_follower_node: PathFollow3D

var _internal_generated_main_body_name: StringName
var _internal_generated_front_bogie_assembly_name: StringName
var _internal_generated_rear_bogie_assembly_name: StringName
var _internal_generated_bogie_mesh_instance_name: StringName

var _internal_rear_bogie_path: Path3D
var _internal_rear_bogie_progress: float = 0.0
var _internal_front_bogie_path: Path3D
var _internal_front_bogie_progress: float = 0.0

var _internal_pending_jump_signal_emission: bool = false
var _internal_last_path_jumped_from: Path3D = null

var _internal_initial_generation_done := false
var _internal_attempt_initial_generate_call_count := 0
var _internal_setting_track_offset_from_generate: bool = false


static func create_train_unit(
	p_target_path: Path3D,
	p_length: float,
	p_main_body_scene: PackedScene = null,
	p_bogie_scene: PackedScene = null,
	p_next_route_path: Path3D = null,
	p_initial_track_offset: float = 0.0,
	p_up_dir: Vector3 = Vector3.UP,
	p_main_mesh_offset_v: float = 1.0,
	p_unit_identifier_prefix: String = ""
) -> Train_Unit:
	print_debug("create_train_unit called")
	var new_train_unit := Train_Unit.new()

	new_train_unit.target_path_3d_node = p_target_path
	new_train_unit.length = p_length
	new_train_unit.main_body_scene = p_main_body_scene
	new_train_unit.bogie_scene = p_bogie_scene
	new_train_unit.next_route_path_3d_node = p_next_route_path
	new_train_unit.track_offset = p_initial_track_offset
	new_train_unit.up_dir = p_up_dir
	new_train_unit.main_mesh_offset_v = p_main_mesh_offset_v
	new_train_unit.unit_identifier_prefix = p_unit_identifier_prefix

	new_train_unit._internal_rear_bogie_path = new_train_unit.target_path_3d_node
	new_train_unit._internal_rear_bogie_progress = new_train_unit.track_offset

	new_train_unit._internal_front_bogie_path = new_train_unit.target_path_3d_node
	new_train_unit._internal_front_bogie_progress = new_train_unit.track_offset + new_train_unit.length

	new_train_unit._update_generated_names()
	return new_train_unit

func _init() -> void:
	generate_node = Callable(self, "_generate_train")

func _ready() -> void:
	_update_generated_names()
	_attempt_initial_generate_if_possible()

func _can_safely_regenerate() -> bool:
	return is_instance_valid(target_path_3d_node) and target_path_3d_node.is_inside_tree()

func _set_target_path_3d_node(new_value: Path3D) -> void:
	if target_path_3d_node == new_value:
		return

	if is_instance_valid(target_path_3d_node):
		if target_path_3d_node.is_connected("tree_entered", Callable(self, "_on_target_path_entered_tree_for_initial_generate")):
			target_path_3d_node.disconnect("tree_entered", Callable(self, "_on_target_path_entered_tree_for_initial_generate"))

	var old_path = target_path_3d_node
	target_path_3d_node = new_value
	
	_internal_rear_bogie_path = null
	_internal_front_bogie_path = null


	if _internal_initial_generation_done and is_inside_tree():
		if is_instance_valid(target_path_3d_node) and target_path_3d_node.is_inside_tree():
			call_deferred("_generate_train")
		elif is_instance_valid(target_path_3d_node): # new path not in tree
			if not target_path_3d_node.is_connected("tree_entered", Callable(self, "_on_target_path_entered_tree_for_initial_generate")):
				target_path_3d_node.connect("tree_entered", Callable(self, "_on_target_path_entered_tree_for_initial_generate"), CONNECT_ONE_SHOT)
			_clear_generated_parts()
		else: # new path is null
			_clear_generated_parts()
	else: # Initial generation not done or not in tree
		_attempt_initial_generate_if_possible()

func _get_target_path_3d_node() -> Path3D:
	return target_path_3d_node

func _set_next_route_path_3d_node(new_value: Path3D) -> void:
	if next_route_path_3d_node == new_value:
		return
	next_route_path_3d_node = new_value
	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		call_deferred("_generate_train")

func _get_next_route_path_3d_node() -> Path3D:
	return next_route_path_3d_node

func _set_generate_node(new_value: Callable) -> void:
	# Raw assignment, no regeneration trigger as it's used by _generate_train
	# Ensure it's a valid callable if strict typing is desired
	if generate_node == new_value:
		return
	generate_node = new_value

func _get_generate_node() -> Callable:
	return generate_node

func _set_main_body_scene(new_value: PackedScene) -> void:
	if main_body_scene == new_value:
		return
	main_body_scene = new_value
	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		call_deferred("_generate_train")

func _get_main_body_scene() -> PackedScene:
	return main_body_scene

func _set_bogie_scene(new_value: PackedScene) -> void:
	if bogie_scene == new_value:
		return
	bogie_scene = new_value
	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		call_deferred("_generate_train")

func _get_bogie_scene() -> PackedScene:
	return bogie_scene

func _set_up_dir(new_value: Vector3) -> void:
	if up_dir == new_value:
		return
	up_dir = new_value
	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		call_deferred("_generate_train")

func _get_up_dir() -> Vector3:
	return up_dir

func _set_length(new_value: float) -> void:
	if length == new_value:
		return
	length = new_value
	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		call_deferred("_generate_train")

func _get_length() -> float:
	return length

func _set_track_offset(new_value: float) -> void:
	if track_offset == new_value and not _internal_setting_track_offset_from_generate:
		return

	var old_value = track_offset
	track_offset = new_value

	if _internal_setting_track_offset_from_generate:
		return

	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		if old_value != track_offset:
			call_deferred("_generate_train")

func _get_track_offset() -> float:
	return track_offset

func _set_main_mesh_offset_v(new_value: float) -> void:
	if main_mesh_offset_v == new_value:
		return
	main_mesh_offset_v = new_value
	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		call_deferred("_generate_train")

func _get_main_mesh_offset_v() -> float:
	return main_mesh_offset_v

func _set_unit_identifier_prefix(new_value: String) -> void:
	if unit_identifier_prefix == new_value:
		return
	unit_identifier_prefix = new_value
	_update_generated_names()
	if _internal_initial_generation_done and is_inside_tree() and _can_safely_regenerate():
		call_deferred("_generate_train")

func _get_unit_identifier_prefix() -> String:
	return unit_identifier_prefix


func _update_generated_names() -> void:
	var prefix = unit_identifier_prefix
	if prefix.is_empty(): prefix = "Unit" + str(get_instance_id()) + "_"
	_internal_generated_main_body_name = StringName(prefix + BASE_MAIN_BODY_NAME)
	_internal_generated_front_bogie_assembly_name = StringName(prefix + BASE_FRONT_BOGIE_ASSEMBLY_NAME)
	_internal_generated_rear_bogie_assembly_name = StringName(prefix + BASE_REAR_BOGIE_ASSEMBLY_NAME)
	_internal_generated_bogie_mesh_instance_name = StringName(prefix + BASE_BOGIE_MESH_INSTANCE_NAME)

func _clear_generated_parts() -> void:
	_update_generated_names()

	for i in range(get_child_count() - 1, -1, -1):
		var child: Node = get_child(i)
		if child.name == _internal_generated_main_body_name:
			remove_child(child); child.queue_free()

	var paths_bogies_were_on: Array[Path3D] = []
	if is_instance_valid(_internal_front_bogie_follower_node) and _internal_front_bogie_follower_node.is_inside_tree():
		var parent_path = _internal_front_bogie_follower_node.get_parent()
		if is_instance_valid(parent_path) and parent_path is Path3D:
			paths_bogies_were_on.append(parent_path as Path3D)

	if is_instance_valid(_internal_rear_bogie_follower_node) and _internal_rear_bogie_follower_node.is_inside_tree():
		var parent_path = _internal_rear_bogie_follower_node.get_parent()
		if is_instance_valid(parent_path) and parent_path is Path3D:
			if not paths_bogies_were_on.has(parent_path as Path3D):
				paths_bogies_were_on.append(parent_path as Path3D)

	for path_node in paths_bogies_were_on:
		if is_instance_valid(path_node):
			for i in range(path_node.get_child_count() - 1, -1, -1):
				var child: Node = path_node.get_child(i)
				if child.name == _internal_generated_front_bogie_assembly_name or \
				   child.name == _internal_generated_rear_bogie_assembly_name:
					path_node.remove_child(child); child.queue_free()

	_internal_front_bogie_follower_node = null
	_internal_rear_bogie_follower_node = null

func _create_main_body_placeholder() -> Node3D:
	var ph_mi=MeshInstance3D.new(); var ph_m=CylinderMesh.new(); ph_m.top_radius=0.8; ph_m.bottom_radius=0.8; ph_m.height=length*0.8; ph_mi.mesh=ph_m; return ph_mi

func _create_bogie_placeholder() -> Node3D:
	var ph_mi=MeshInstance3D.new(); var ph_m=BoxMesh.new(); ph_m.size=Vector3(1,0.5,1.5); ph_mi.mesh=ph_m; return ph_mi

func _instantiate_scene_or_placeholder(p_scene: PackedScene, p_fallback: Callable) -> Node3D:
	var n3d:Node3D; var r_n:Node = p_scene.instantiate() if p_scene != null and p_scene.can_instantiate() else p_fallback.call()
	if r_n is Node3D: n3d = r_n as Node3D
	else: n3d = Node3D.new(); n3d.add_child(r_n)
	return n3d

func _create_bogie_assembly(p_path: Path3D, p_name: StringName, p_progress: float) -> PathFollow3D:
	if not is_instance_valid(p_path): return null
	if not p_path.is_inside_tree():
		printerr("Train_Unit (%s): Path3D '%s' is not inside the scene tree. Cannot add PathFollow3D." % [name, p_path.name])
		return null

	var fol=PathFollow3D.new(); fol.name=p_name; fol.progress=p_progress; fol.loop=false; fol.rotation_mode=PathFollow3D.ROTATION_XYZ
	var m_n:Node3D=_instantiate_scene_or_placeholder(bogie_scene, _create_bogie_placeholder); m_n.name=_internal_generated_bogie_mesh_instance_name

	fol.add_child(m_n)
	p_path.add_child(fol)
	return fol

func _get_path_length(p_path: Path3D) -> float:
	if not is_instance_valid(p_path) or not is_instance_valid(p_path.curve): return 0.0
	var path_len = p_path.curve.get_baked_length()
	if path_len <= 1e-5: path_len = p_path.curve.get_length()
	return path_len

func _generate_train() -> void:
	print_debug("--- TrainUnit (", name, "): _generate_train CALLED ---")
	if not is_inside_tree():
		return

	_update_generated_names()
	_clear_generated_parts()

	if not is_instance_valid(_internal_rear_bogie_path) and is_instance_valid(target_path_3d_node):
		_internal_rear_bogie_path = target_path_3d_node
		_internal_rear_bogie_progress = track_offset

	if not is_instance_valid(_internal_front_bogie_path) and is_instance_valid(target_path_3d_node):
		_internal_front_bogie_path = target_path_3d_node
		_internal_front_bogie_progress = _internal_rear_bogie_progress + length

	if not is_instance_valid(_internal_rear_bogie_path):
		printerr("Train_Unit (%s): _internal_rear_bogie_path is not valid. Cannot generate train." % name)
		return

	if not _internal_rear_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _internal_rear_bogie_path '%s' is not in the scene tree. Cannot generate bogies." % [name, _internal_rear_bogie_path.name])
		return
	if _internal_rear_bogie_path != _internal_front_bogie_path and not _internal_front_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _internal_front_bogie_path '%s' is not in the scene tree. Cannot generate bogies." % [name, _internal_front_bogie_path.name])
		return

	_internal_rear_bogie_progress = self.track_offset

	var original_rear_path_before_this_evaluation = _internal_rear_bogie_path
	var rear_jumped_this_cycle = false
	while true:
		if not is_instance_valid(_internal_rear_bogie_path): break
		var current_rear_path_len = _get_path_length(_internal_rear_bogie_path)

		var next_path_candidate_for_rear: Path3D = null
		if is_instance_valid(_internal_front_bogie_path) and _internal_rear_bogie_path != _internal_front_bogie_path:
			next_path_candidate_for_rear = _internal_front_bogie_path
		else:
			next_path_candidate_for_rear = next_route_path_3d_node

		if current_rear_path_len <= 1e-5:
			if is_instance_valid(next_path_candidate_for_rear) and _internal_rear_bogie_path != next_path_candidate_for_rear:
				if not next_path_candidate_for_rear.is_inside_tree(): break
				_internal_rear_bogie_path = next_path_candidate_for_rear
				_internal_rear_bogie_progress = 0.0
				rear_jumped_this_cycle = true
				continue
			else: break

		if _internal_rear_bogie_progress >= current_rear_path_len - 1e-5:
			var overflow = _internal_rear_bogie_progress - current_rear_path_len
			if is_instance_valid(next_path_candidate_for_rear) and _internal_rear_bogie_path != next_path_candidate_for_rear:
				if not next_path_candidate_for_rear.is_inside_tree(): break
				_internal_rear_bogie_path = next_path_candidate_for_rear
				_internal_rear_bogie_progress = max(0.0, overflow)
				rear_jumped_this_cycle = true
				continue
			else:
				_internal_rear_bogie_progress = current_rear_path_len
				if not rear_jumped_this_cycle:
					var front_also_at_this_exact_end = (
						_internal_front_bogie_path == _internal_rear_bogie_path and
						_internal_front_bogie_progress >= current_rear_path_len - 1e-5
					)
					if not front_also_at_this_exact_end and is_inside_tree():
						emit_signal("reached_end_of_final_path", self)
				break
		else: break

	if rear_jumped_this_cycle:
		_internal_pending_jump_signal_emission = true
		_internal_last_path_jumped_from = original_rear_path_before_this_evaluation

	_internal_setting_track_offset_from_generate = true
	self.track_offset = _internal_rear_bogie_progress
	_internal_setting_track_offset_from_generate = false

	_internal_front_bogie_path = _internal_rear_bogie_path
	_internal_front_bogie_progress = _internal_rear_bogie_progress + length

	var front_jumped_this_cycle = false
	while true:
		if not is_instance_valid(_internal_front_bogie_path): break
		var current_front_path_len = _get_path_length(_internal_front_bogie_path)
		var next_path_candidate_for_front = next_route_path_3d_node

		if current_front_path_len <= 1e-5:
			if is_instance_valid(next_path_candidate_for_front) and _internal_front_bogie_path != next_path_candidate_for_front:
				if not next_path_candidate_for_front.is_inside_tree(): break
				_internal_front_bogie_path = next_path_candidate_for_front
				_internal_front_bogie_progress = 0.0
				front_jumped_this_cycle = true
				continue
			else: break

		if _internal_front_bogie_progress >= current_front_path_len - 1e-5:
			var overflow = _internal_front_bogie_progress - current_front_path_len
			if is_instance_valid(next_path_candidate_for_front) and _internal_front_bogie_path != next_path_candidate_for_front:
				if not next_path_candidate_for_front.is_inside_tree(): break
				_internal_front_bogie_path = next_path_candidate_for_front
				_internal_front_bogie_progress = max(0.0, overflow)
				front_jumped_this_cycle = true
				continue
			else:
				_internal_front_bogie_progress = current_front_path_len
				if not front_jumped_this_cycle:
					var rear_also_at_this_effective_end = (
						_internal_rear_bogie_path == _internal_front_bogie_path and
						_internal_rear_bogie_progress >= current_front_path_len - length - 1e-5
					)
					if not rear_also_at_this_effective_end and is_inside_tree():
						emit_signal("reached_end_of_final_path", self)
				break
		else: break

	if not is_instance_valid(_internal_rear_bogie_path) or not is_instance_valid(_internal_front_bogie_path):
		printerr("Train_Unit (%s): Bogie paths became invalid after transition. Cannot setup." % name)
		return

	if not _setup_bogies_individual():
		return

	_update_body_transform()
	_create_body_node_if_missing()
	_check_and_emit_jump_signal()

func _setup_bogies_individual() -> bool:
	_update_generated_names()

	if not is_instance_valid(_internal_rear_bogie_path) or not is_instance_valid(_internal_front_bogie_path):
		printerr("Train_Unit (%s): Invalid paths for bogie setup." % name)
		return false

	if not _internal_rear_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _internal_rear_bogie_path '%s' is not in scene tree. Cannot create rear bogie." % [name, _internal_rear_bogie_path.name])
		return false
	if _internal_front_bogie_path != _internal_rear_bogie_path and not _internal_front_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _internal_front_bogie_path '%s' is not in scene tree. Cannot create front bogie." % [name, _internal_front_bogie_path.name])
		return false

	var rear_prog_on_path = _internal_rear_bogie_progress
	var rear_path_actual_len = _get_path_length(_internal_rear_bogie_path)
	if rear_path_actual_len > 1e-5: rear_prog_on_path = clampf(_internal_rear_bogie_progress, 0.0, rear_path_actual_len)
	else: rear_prog_on_path = 0.0
	_internal_rear_bogie_follower_node = _create_bogie_assembly(_internal_rear_bogie_path, _internal_generated_rear_bogie_assembly_name, rear_prog_on_path)

	var front_prog_on_path = _internal_front_bogie_progress
	var front_path_actual_len = _get_path_length(_internal_front_bogie_path)
	if front_path_actual_len > 1e-5: front_prog_on_path = clampf(_internal_front_bogie_progress, 0.0, front_path_actual_len)
	else: front_prog_on_path = 0.0
	_internal_front_bogie_follower_node = _create_bogie_assembly(_internal_front_bogie_path, _internal_generated_front_bogie_assembly_name, front_prog_on_path)

	if not is_instance_valid(_internal_rear_bogie_follower_node) or not is_instance_valid(_internal_front_bogie_follower_node):
		return false

	return true

func _create_body_node_if_missing() -> void:
	_update_generated_names()
	if not has_node(NodePath(_internal_generated_main_body_name)):
		var b_node:Node3D = _instantiate_scene_or_placeholder(main_body_scene, _create_main_body_placeholder)
		b_node.name = _internal_generated_main_body_name
		b_node.position = up_dir.normalized() * main_mesh_offset_v
		add_child(b_node)

func _update_body_transform() -> void:
	if not is_instance_valid(_internal_rear_bogie_follower_node) or not is_instance_valid(_internal_front_bogie_follower_node): return

	if not _internal_rear_bogie_follower_node.is_inside_tree() or not _internal_front_bogie_follower_node.is_inside_tree():
		return

	var r_pos=_internal_rear_bogie_follower_node.global_position; var f_pos=_internal_front_bogie_follower_node.global_position
	global_position=r_pos.lerp(f_pos,0.5); var fwd_v=(f_pos-r_pos)

	if fwd_v.length_squared()<1e-6:
		var path_to_sample = _internal_front_bogie_path if _internal_front_bogie_path != _internal_rear_bogie_path else _internal_rear_bogie_path
		var progress_to_sample = _internal_front_bogie_progress if _internal_front_bogie_path != _internal_rear_bogie_path else (_internal_rear_bogie_progress + _internal_front_bogie_progress) / 2.0

		if is_instance_valid(path_to_sample) and is_instance_valid(path_to_sample.curve):
			var c = path_to_sample.curve
			var cl = _get_path_length(path_to_sample)
			if cl > 0.001:
				var p1p=clampf(progress_to_sample - 0.005, 0.0, cl)
				var p2p=clampf(progress_to_sample + 0.005, 0.0, cl)
				if p1p >= p2p - 1e-6 : p1p = max(0.0, p2p - 0.001)

				var p1_world_pos: Vector3
				var p2_world_pos: Vector3

				var path_global_xform = Transform3D.IDENTITY
				if path_to_sample.is_inside_tree():
					path_global_xform = path_to_sample.global_transform

				if c.get_baked_length() > 1e-5:
					p1_world_pos = path_global_xform * c.sample_baked(p1p, true)
					p2_world_pos = path_global_xform * c.sample_baked(p2p, true)
				else:
					p1_world_pos = path_global_xform * c.samplef(p1p / cl if cl > 1e-5 else 0.0)
					p2_world_pos = path_global_xform * c.samplef(p2p / cl if cl > 1e-5 else 0.0)
				fwd_v = (p2_world_pos - p1_world_pos)

		if fwd_v.length_squared()<1e-6:
			fwd_v = global_transform.basis.z
		if fwd_v.length_squared()<1e-6: fwd_v=Vector3.FORWARD

	fwd_v=fwd_v.normalized()
	var up_g=up_dir.normalized()

	if _internal_rear_bogie_follower_node.is_inside_tree() and _internal_front_bogie_follower_node.is_inside_tree():
		var r_u=_internal_rear_bogie_follower_node.global_transform.basis.y.normalized()
		var f_u=_internal_front_bogie_follower_node.global_transform.basis.y.normalized()
		if r_u.length_squared()>0.5 and f_u.length_squared()>0.5: up_g=r_u.slerp(f_u,0.5).normalized()

	var fin_up=up_g
	if abs(fwd_v.dot(up_g))>0.999:
		var alt_u=fwd_v.cross(Vector3.RIGHT if abs(fwd_v.x) < 0.9 else Vector3.FORWARD)
		if alt_u.length_squared()<1e-5: alt_u=fwd_v.cross(Vector3.UP)
		if alt_u.length_squared()>1e-5: fin_up=alt_u.normalized()
		else:
			fin_up = Vector3.UP if not fwd_v.is_equal_approx(Vector3.UP) and not fwd_v.is_equal_approx(Vector3.DOWN) else Vector3.FORWARD

	global_transform.basis=Basis.looking_at(-fwd_v, fin_up)

func _check_and_emit_jump_signal() -> void:
	if not is_inside_tree(): return

	if _internal_pending_jump_signal_emission and _internal_rear_bogie_progress >= -0.001:
		if is_instance_valid(_internal_last_path_jumped_from) and is_instance_valid(_internal_rear_bogie_path) and \
		   _internal_last_path_jumped_from != _internal_rear_bogie_path:
			emit_signal("jumped_to_next_path", _internal_rear_bogie_path, self)

		_internal_pending_jump_signal_emission = false
		_internal_last_path_jumped_from = null
	elif _internal_last_path_jumped_from != null and _internal_last_path_jumped_from == _internal_rear_bogie_path:
		_internal_pending_jump_signal_emission = false
		_internal_last_path_jumped_from = null

func move_forward_on_path(distance_to_move: float) -> void:
	if not is_inside_tree(): return
	if distance_to_move <= 0.0: return
	self.track_offset += distance_to_move # This will call _set_track_offset
	# _generate_train will be called by _set_track_offset if conditions are met

func get_current_path() -> Path3D:
	return _internal_rear_bogie_path

func get_rear_bogie_path() -> Path3D:
	return _internal_rear_bogie_path

func get_rear_bogie_progress() -> float:
	return _internal_rear_bogie_progress

func get_front_bogie_path() -> Path3D:
	return _internal_front_bogie_path

func get_front_bogie_progress() -> float:
	return _internal_front_bogie_progress

func get_front_offset_on_current_path() -> float:
	return _internal_front_bogie_progress

func _on_target_path_entered_tree_for_initial_generate():
	print_debug("_on_target_path_entered_tree_for_initial_generate called for: ", name)
	call_deferred("_attempt_initial_generate")

func _attempt_initial_generate_if_possible() -> void:
	if not _internal_initial_generation_done and is_inside_tree() and \
	   is_instance_valid(target_path_3d_node) and target_path_3d_node.is_inside_tree():
		call_deferred("_attempt_initial_generate")
	elif is_instance_valid(target_path_3d_node) and not target_path_3d_node.is_inside_tree():
		if not target_path_3d_node.is_connected("tree_entered", Callable(self, "_on_target_path_entered_tree_for_initial_generate")):
			target_path_3d_node.connect("tree_entered", Callable(self, "_on_target_path_entered_tree_for_initial_generate"), CONNECT_ONE_SHOT)


func _attempt_initial_generate():
	_internal_attempt_initial_generate_call_count += 1
	print_debug(">>> _attempt_initial_generate CALLED for: ", name, " (Call #", _internal_attempt_initial_generate_call_count, ")")
	print_debug("    Current _internal_initial_generation_done state: ", _internal_initial_generation_done)

	if not _internal_initial_generation_done:
		print_debug("    Condition (not _internal_initial_generation_done) is TRUE for ", name)
		if is_inside_tree() and is_instance_valid(target_path_3d_node) and target_path_3d_node.is_inside_tree():
			print_debug("    Attempting actual initial generation for: ", name)
			if is_instance_valid(generate_node) and generate_node.is_valid():
				generate_node.call()
			else:
				printerr("Train_Unit (", name, "): generate_node is not valid.")

			print_debug("    Setting _internal_initial_generation_done = true for ", name)
			_internal_initial_generation_done = true
		else:
			print_debug("    Conditions (in_tree/path_valid/path_in_tree) NOT MET for actual generation for ", name)
			_attempt_initial_generate_if_possible() # Re-check connections if path not ready
	else:
		print_debug("    Condition (not _internal_initial_generation_done) is FALSE for ", name, ". Skipping generation.")
	print_debug("<<< _attempt_initial_generate FINISHED for: ", name)
