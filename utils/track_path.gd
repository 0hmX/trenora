class_name TrackPath
extends Node

var path_3d_node: Path3D
var curve: Curve3D

func _ready() -> void:
	Smol.set_node_name(self, "TrackPath")

func setup(owner_node_for_path: Node, editor_owner_node = null):
	print_debug()
	if is_instance_valid(path_3d_node) and path_3d_node.get_parent() == owner_node_for_path:
		printerr("TrackPath.setup: Path3D node already exists and is parented. Reusing.")
		if not is_instance_valid(path_3d_node.curve): # Ensure curve exists
			curve = Curve3D.new()
			path_3d_node.curve = curve
		else:
			curve = path_3d_node.curve
		return

	# If a node with the target name already exists, remove it first to avoid conflicts
	var existing_node = owner_node_for_path.find_child("GeneratedPath_From_TrackPath", false, false)
	if is_instance_valid(existing_node):
		printerr("TrackPath.setup: Removing pre-existing 'GeneratedPath_From_TrackPath' node.")
		owner_node_for_path.remove_child(existing_node)
		existing_node.free()

	path_3d_node = Path3D.new()
	path_3d_node.name = "GeneratedPath_From_TrackPath"
	owner_node_for_path.add_child(path_3d_node)
	
	if Engine.is_editor_hint():
		if not path_3d_node.is_inside_tree():
			printerr("TrackPath.setup WARNING: path_3d_node reports NOT in tree immediately after add_child to '%s'." % owner_node_for_path.name)
		if is_instance_valid(editor_owner_node):
			path_3d_node.owner = editor_owner_node
		elif is_instance_valid(owner_node_for_path.owner):
			path_3d_node.owner = owner_node_for_path.owner

	curve = Curve3D.new()
	path_3d_node.curve = curve

func _get_node() -> Path3D:
	if not is_instance_valid(path_3d_node):
		printerr("TrackPath.get_node: path_3d_node is INVALID.")
		return null
	return path_3d_node

func get_curve_length() -> float:
	if not is_instance_valid(curve):
		printerr("TrackPath.get_curve_length: curve is INVALID.")
		return 0.0
	return curve.get_baked_length()

func _get_valid_path_node_for_transform() -> Path3D:
	if not is_instance_valid(path_3d_node):
		printerr("TrackPath (Transform): path_3d_node is invalid.")
		return null
	if not path_3d_node.is_inside_tree():
		printerr("TrackPath (Transform) WARNING: path_3d_node '%s' (parent: '%s') is NOT considered inside tree for transform!" % [path_3d_node.name, path_3d_node.get_parent().name if is_instance_valid(path_3d_node.get_parent()) else "None"])
		# In critical situations, you might try to use parent's transform if local is identity
		# but this indicates a deeper timing issue.
		return null # Force failure if not in tree
	return path_3d_node

func add_points_to_curve(world_points: Array[Vector3]) -> int:
	var valid_path_node = _get_valid_path_node_for_transform()
	if world_points.is_empty() or not is_instance_valid(valid_path_node) or not is_instance_valid(curve):
		if not is_instance_valid(valid_path_node): printerr("TrackPath.add_points_to_curve: Path node for transform is invalid.")
		return 0

	var points_added_count = 0
	var start_idx_in_world_points = 0

	if curve.point_count > 0:
		var last_curve_pt_local = curve.get_point_position(curve.point_count - 1)
		var last_curve_pt_world = valid_path_node.to_global(last_curve_pt_local) # Needs valid_path_node in tree
		if world_points[0].is_equal_approx(last_curve_pt_world):
			start_idx_in_world_points = 1

	for i in range(start_idx_in_world_points, world_points.size()):
		curve.add_point(valid_path_node.to_local(world_points[i])) # Needs valid_path_node in tree
		points_added_count += 1
	
	return points_added_count

func remove_points_from_start(count: int):
	if not is_instance_valid(curve): return
	for _i in range(count):
		if curve.point_count > 0:
			curve.remove_point(0)
		else: break

func clear_all_points():
	if is_instance_valid(curve):
		curve.clear_points()
	# Also clear any visual remnants if path_3d_node still has old meshes
	if is_instance_valid(path_3d_node):
		for i in range(path_3d_node.get_child_count() -1, -1, -1):
			var child = path_3d_node.get_child(i)
			if child is MeshInstance3D: # Or more specific check if needed
				path_3d_node.remove_child(child)
				child.free()


func attach_mesh_to_path(mesh_node: MeshInstance3D, editor_owner_node = null):
	var valid_path_node = _get_node() # Use the basic getter here
	if is_instance_valid(valid_path_node) and is_instance_valid(mesh_node):
		valid_path_node.add_child(mesh_node)
		if Engine.is_editor_hint():
			if is_instance_valid(editor_owner_node):
				mesh_node.owner = editor_owner_node
			elif is_instance_valid(valid_path_node.owner):
				mesh_node.owner = valid_path_node.owner


func get_path_transform() -> Transform3D:
	var valid_path_node = _get_valid_path_node_for_transform()
	if not is_instance_valid(valid_path_node):
		printerr("TrackPath.get_path_transform: Could not get valid path node for transform. Returning IDENTITY.")
		return Transform3D.IDENTITY
	return valid_path_node.global_transform
