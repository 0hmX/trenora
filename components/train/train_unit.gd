class_name Train_Unit
extends Node3D

@export var target_path_3d_node: Path3D
@export var next_route_path_3d_node: Path3D

var generate_node: Callable = _generate_train

@export var main_body_scene: PackedScene
@export var bogie_scene: PackedScene
@export var up_dir: Vector3 = Vector3.UP

@export var length: float = 5.0
@export var track_offset: float = 0.0
@export var main_mesh_offset_v: float = 1.0

@export var unit_identifier_prefix: String = ""

signal jumped_to_next_path(new_path_node: Path3D, unit_node: Train_Unit)
signal reached_end_of_final_path(unit_node: Train_Unit)

const BASE_MAIN_BODY_NAME := "MainBody"
const BASE_FRONT_BOGIE_ASSEMBLY_NAME := "FrontBogieAssembly"
const BASE_REAR_BOGIE_ASSEMBLY_NAME := "RearBogieAssembly"
const BASE_BOGIE_MESH_INSTANCE_NAME := "BogieMeshInstance"

var _front_bogie_follower_node: PathFollow3D
var _rear_bogie_follower_node: PathFollow3D

var _generated_main_body_name: StringName
var _generated_front_bogie_assembly_name: StringName
var _generated_rear_bogie_assembly_name: StringName
var _generated_bogie_mesh_instance_name: StringName

var _rear_bogie_path: Path3D
var _rear_bogie_progress: float = 0.0
var _front_bogie_path: Path3D
var _front_bogie_progress: float = 0.0

var _pending_jump_signal_emission: bool = false
var _last_path_jumped_from: Path3D = null

var _initial_generation_done := false

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

	new_train_unit._rear_bogie_path = new_train_unit.target_path_3d_node
	new_train_unit._rear_bogie_progress = new_train_unit.track_offset

	new_train_unit._front_bogie_path = new_train_unit.target_path_3d_node
	new_train_unit._front_bogie_progress = new_train_unit.track_offset + new_train_unit.length

	new_train_unit._update_generated_names()
	return new_train_unit

func _update_generated_names() -> void:
	var prefix = unit_identifier_prefix
	if prefix.is_empty(): prefix = "Unit" + str(get_instance_id()) + "_"
	_generated_main_body_name = StringName(prefix + BASE_MAIN_BODY_NAME)
	_generated_front_bogie_assembly_name = StringName(prefix + BASE_FRONT_BOGIE_ASSEMBLY_NAME)
	_generated_rear_bogie_assembly_name = StringName(prefix + BASE_REAR_BOGIE_ASSEMBLY_NAME)
	_generated_bogie_mesh_instance_name = StringName(prefix + BASE_BOGIE_MESH_INSTANCE_NAME)

func _clear_generated_parts() -> void:
	_update_generated_names()

	for i in range(get_child_count() - 1, -1, -1):
		var child: Node = get_child(i)
		if child.name == _generated_main_body_name:
			remove_child(child); child.queue_free()

	var paths_bogies_were_on: Array[Path3D] = []
	if is_instance_valid(_front_bogie_follower_node) and _front_bogie_follower_node.is_inside_tree():
		var parent_path = _front_bogie_follower_node.get_parent()
		if is_instance_valid(parent_path) and parent_path is Path3D:
			paths_bogies_were_on.append(parent_path as Path3D)

	if is_instance_valid(_rear_bogie_follower_node) and _rear_bogie_follower_node.is_inside_tree():
		var parent_path = _rear_bogie_follower_node.get_parent()
		if is_instance_valid(parent_path) and parent_path is Path3D:
			if not paths_bogies_were_on.has(parent_path as Path3D):
				paths_bogies_were_on.append(parent_path as Path3D)

	for path_node in paths_bogies_were_on:
		if is_instance_valid(path_node):
			for i in range(path_node.get_child_count() - 1, -1, -1):
				var child: Node = path_node.get_child(i)
				if child.name == _generated_front_bogie_assembly_name or \
				   child.name == _generated_rear_bogie_assembly_name:
					path_node.remove_child(child); child.queue_free()

	_front_bogie_follower_node = null
	_rear_bogie_follower_node = null

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
	var m_n:Node3D=_instantiate_scene_or_placeholder(bogie_scene, _create_bogie_placeholder); m_n.name=_generated_bogie_mesh_instance_name

	fol.add_child(m_n)
	p_path.add_child(fol)
	return fol

func _get_path_length(p_path: Path3D) -> float:
	if not is_instance_valid(p_path) or not is_instance_valid(p_path.curve): return 0.0
	var path_len = p_path.curve.get_baked_length()
	if path_len <= 1e-5: path_len = p_path.curve.get_length()
	return path_len

func _generate_train() -> void:
	print_debug("--- TrainUnit (", name, "): _generate_train CALLED ---") # New, more prominent marker
	print_stack() # <<< THIS IS THE MOST IMPORTANT LINE TO ADD NOW
	if not is_inside_tree():
		return

	_update_generated_names()
	_clear_generated_parts()

	if not is_instance_valid(_rear_bogie_path) and is_instance_valid(target_path_3d_node):
		_rear_bogie_path = target_path_3d_node
		_rear_bogie_progress = track_offset

	if not is_instance_valid(_front_bogie_path) and is_instance_valid(target_path_3d_node):
		_front_bogie_path = target_path_3d_node
		_front_bogie_progress = _rear_bogie_progress + length

	if not is_instance_valid(_rear_bogie_path):
		printerr("Train_Unit (%s): _rear_bogie_path is not valid. Cannot generate train." % name)
		return

	if not _rear_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _rear_bogie_path '%s' is not in the scene tree. Cannot generate bogies." % [name, _rear_bogie_path.name])
		return
	if _rear_bogie_path != _front_bogie_path and not _front_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _front_bogie_path '%s' is not in the scene tree. Cannot generate bogies." % [name, _front_bogie_path.name])
		return

	_rear_bogie_progress = self.track_offset

	var original_rear_path_before_this_evaluation = _rear_bogie_path
	var rear_jumped_this_cycle = false
	while true:
		if not is_instance_valid(_rear_bogie_path): break
		var current_rear_path_len = _get_path_length(_rear_bogie_path)

		var next_path_candidate_for_rear: Path3D = null
		if is_instance_valid(_front_bogie_path) and _rear_bogie_path != _front_bogie_path:
			next_path_candidate_for_rear = _front_bogie_path
		else:
			next_path_candidate_for_rear = next_route_path_3d_node

		if current_rear_path_len <= 1e-5:
			if is_instance_valid(next_path_candidate_for_rear) and _rear_bogie_path != next_path_candidate_for_rear:
				if not next_path_candidate_for_rear.is_inside_tree(): break
				_rear_bogie_path = next_path_candidate_for_rear
				_rear_bogie_progress = 0.0
				rear_jumped_this_cycle = true
				continue
			else: break

		if _rear_bogie_progress >= current_rear_path_len - 1e-5:
			var overflow = _rear_bogie_progress - current_rear_path_len
			if is_instance_valid(next_path_candidate_for_rear) and _rear_bogie_path != next_path_candidate_for_rear:
				if not next_path_candidate_for_rear.is_inside_tree(): break
				_rear_bogie_path = next_path_candidate_for_rear
				_rear_bogie_progress = max(0.0, overflow)
				rear_jumped_this_cycle = true
				continue
			else:
				_rear_bogie_progress = current_rear_path_len
				if not rear_jumped_this_cycle:
					var front_also_at_this_exact_end = (
						_front_bogie_path == _rear_bogie_path and
						_front_bogie_progress >= current_rear_path_len - 1e-5
					)
					if not front_also_at_this_exact_end and is_inside_tree():
						emit_signal("reached_end_of_final_path", self)
				break
		else: break

	if rear_jumped_this_cycle:
		_pending_jump_signal_emission = true
		_last_path_jumped_from = original_rear_path_before_this_evaluation

	self.track_offset = _rear_bogie_progress

	_front_bogie_path = _rear_bogie_path
	_front_bogie_progress = _rear_bogie_progress + length

	var front_jumped_this_cycle = false
	while true:
		if not is_instance_valid(_front_bogie_path): break
		var current_front_path_len = _get_path_length(_front_bogie_path)
		var next_path_candidate_for_front = next_route_path_3d_node

		if current_front_path_len <= 1e-5:
			if is_instance_valid(next_path_candidate_for_front) and _front_bogie_path != next_path_candidate_for_front:
				if not next_path_candidate_for_front.is_inside_tree(): break
				_front_bogie_path = next_path_candidate_for_front
				_front_bogie_progress = 0.0
				front_jumped_this_cycle = true
				continue
			else: break

		if _front_bogie_progress >= current_front_path_len - 1e-5:
			var overflow = _front_bogie_progress - current_front_path_len
			if is_instance_valid(next_path_candidate_for_front) and _front_bogie_path != next_path_candidate_for_front:
				if not next_path_candidate_for_front.is_inside_tree(): break
				_front_bogie_path = next_path_candidate_for_front
				_front_bogie_progress = max(0.0, overflow)
				front_jumped_this_cycle = true
				continue
			else:
				_front_bogie_progress = current_front_path_len
				if not front_jumped_this_cycle:
					var rear_also_at_this_effective_end = (
						_rear_bogie_path == _front_bogie_path and
						_rear_bogie_progress >= current_front_path_len - length - 1e-5
					)
					if not rear_also_at_this_effective_end and is_inside_tree():
						emit_signal("reached_end_of_final_path", self)
				break
		else: break

	if not is_instance_valid(_rear_bogie_path) or not is_instance_valid(_front_bogie_path):
		printerr("Train_Unit (%s): Bogie paths became invalid after transition. Cannot setup." % name)
		return

	if not _setup_bogies_individual():
		return

	_update_body_transform()
	_create_body_node_if_missing()
	_check_and_emit_jump_signal()

func _setup_bogies_individual() -> bool:
	_update_generated_names()

	if not is_instance_valid(_rear_bogie_path) or not is_instance_valid(_front_bogie_path):
		printerr("Train_Unit (%s): Invalid paths for bogie setup." % name)
		return false

	if not _rear_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _rear_bogie_path '%s' is not in scene tree. Cannot create rear bogie." % [name, _rear_bogie_path.name])
		return false
	if _front_bogie_path != _rear_bogie_path and not _front_bogie_path.is_inside_tree():
		printerr("Train_Unit (%s): _front_bogie_path '%s' is not in scene tree. Cannot create front bogie." % [name, _front_bogie_path.name])
		return false

	var rear_prog_on_path = _rear_bogie_progress
	var rear_path_actual_len = _get_path_length(_rear_bogie_path)
	if rear_path_actual_len > 1e-5: rear_prog_on_path = clampf(_rear_bogie_progress, 0.0, rear_path_actual_len)
	else: rear_prog_on_path = 0.0
	_rear_bogie_follower_node = _create_bogie_assembly(_rear_bogie_path, _generated_rear_bogie_assembly_name, rear_prog_on_path)

	var front_prog_on_path = _front_bogie_progress
	var front_path_actual_len = _get_path_length(_front_bogie_path)
	if front_path_actual_len > 1e-5: front_prog_on_path = clampf(_front_bogie_progress, 0.0, front_path_actual_len)
	else: front_prog_on_path = 0.0
	_front_bogie_follower_node = _create_bogie_assembly(_front_bogie_path, _generated_front_bogie_assembly_name, front_prog_on_path)

	if not is_instance_valid(_rear_bogie_follower_node) or not is_instance_valid(_front_bogie_follower_node):
		return false

	return true

func _create_body_node_if_missing() -> void:
	_update_generated_names()
	if not has_node(NodePath(_generated_main_body_name)):
		var b_node:Node3D = _instantiate_scene_or_placeholder(main_body_scene, _create_main_body_placeholder)
		b_node.name = _generated_main_body_name
		b_node.position = up_dir.normalized() * main_mesh_offset_v
		add_child(b_node)

func _update_body_transform() -> void:
	if not is_instance_valid(_rear_bogie_follower_node) or not is_instance_valid(_front_bogie_follower_node): return

	if not _rear_bogie_follower_node.is_inside_tree() or not _front_bogie_follower_node.is_inside_tree():
		return

	var r_pos=_rear_bogie_follower_node.global_position; var f_pos=_front_bogie_follower_node.global_position
	global_position=r_pos.lerp(f_pos,0.5); var fwd_v=(f_pos-r_pos)

	if fwd_v.length_squared()<1e-6:
		var path_to_sample = _front_bogie_path if _front_bogie_path != _rear_bogie_path else _rear_bogie_path
		var progress_to_sample = _front_bogie_progress if _front_bogie_path != _rear_bogie_path else (_rear_bogie_progress + _front_bogie_progress) / 2.0

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

	if _rear_bogie_follower_node.is_inside_tree() and _front_bogie_follower_node.is_inside_tree():
		var r_u=_rear_bogie_follower_node.global_transform.basis.y.normalized()
		var f_u=_front_bogie_follower_node.global_transform.basis.y.normalized()
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

	if _pending_jump_signal_emission and _rear_bogie_progress >= -0.001:
		if is_instance_valid(_last_path_jumped_from) and is_instance_valid(_rear_bogie_path) and \
		   _last_path_jumped_from != _rear_bogie_path:
			emit_signal("jumped_to_next_path", _rear_bogie_path, self)

		_pending_jump_signal_emission = false
		_last_path_jumped_from = null
	elif _last_path_jumped_from != null and _last_path_jumped_from == _rear_bogie_path:
		_pending_jump_signal_emission = false
		_last_path_jumped_from = null

func move_forward_on_path(distance_to_move: float) -> void:
	if not is_inside_tree(): return
	if distance_to_move <= 0.0: return
	self.track_offset += distance_to_move
	_generate_train()

func get_current_path() -> Path3D:
	return _rear_bogie_path

func get_rear_bogie_path() -> Path3D:
	return _rear_bogie_path

func get_rear_bogie_progress() -> float:
	return _rear_bogie_progress

func get_front_bogie_path() -> Path3D:
	return _front_bogie_path

func get_front_bogie_progress() -> float:
	return _front_bogie_progress

func get_front_offset_on_current_path() -> float:
	return _front_bogie_progress

func _on_target_path_entered_tree_for_initial_generate():
	print_debug("_on_target_path_entered_tree_for_initial_generate called for: ", name)
	call_deferred("_attempt_initial_generate")

var _attempt_initial_generate_call_count := 0 # Add this member variable

func _attempt_initial_generate():
	_attempt_initial_generate_call_count += 1
	print_debug(">>> _attempt_initial_generate CALLED for: ", name, " (Call #", _attempt_initial_generate_call_count, ")")
	print_debug("    Current _initial_generation_done state: ", _initial_generation_done)

	if not _initial_generation_done:
		print_debug("    Condition (not _initial_generation_done) is TRUE for ", name)
		if is_inside_tree() and is_instance_valid(target_path_3d_node) and target_path_3d_node.is_inside_tree():
			print_debug("    Attempting actual initial generation for: ", name)
			_generate_train() # This is where your log "_generate_train called for: ..." comes from
			print_debug("    Setting _initial_generation_done = true for ", name)
			_initial_generation_done = true
		else:
			print_debug("    Conditions (in_tree/path_valid/path_in_tree) NOT MET for actual generation for ", name)
	else:
		print_debug("    Condition (not _initial_generation_done) is FALSE for ", name, ". Skipping generation.")
	print_debug("<<< _attempt_initial_generate FINISHED for: ", name)
