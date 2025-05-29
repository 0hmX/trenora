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

extends Node3D

var _internal_path1: Path3D
var _internal_path2: Path3D
var _internal_path3_not_in_tree: Path3D
var _internal_train_unit: Train_Unit

var _internal_test_step: int = 0

func _ready() -> void:
	_internal_path1 = Path3D.new()
	_internal_path1.name = "TestPath1"
	var curve1 := Curve3D.new()
	curve1.add_point(Vector3(0, 0, 0))
	curve1.add_point(Vector3(0, 0, 20))
	_internal_path1.curve = curve1
	add_child(_internal_path1)

	_internal_path2 = Path3D.new()
	_internal_path2.name = "TestPath2"
	var curve2 := Curve3D.new()
	curve2.add_point(Vector3(10, 0, 0))
	curve2.add_point(Vector3(10, 0, 20))
	_internal_path2.curve = curve2
	add_child(_internal_path2)

	_internal_train_unit = Train_Unit.create_train_unit(
		_internal_path1,
		5.0,
		null,
		null,
		null,
		1.0
	)
	_internal_train_unit.name = "TestTrainUnit"
	add_child(_internal_train_unit)

	call_deferred("_run_next_test_step")

func _run_next_test_step() -> void:
	_internal_test_step += 1
	print_debug("\n--- Executing Test Step ", _internal_test_step, " ---")

	match _internal_test_step:
		1:
			_perform_test_initial_state_verification()
			call_deferred("_run_next_test_step")
		2:
			_perform_action_change_to_path2()
			call_deferred("_run_next_test_step")
		3:
			_perform_test_path2_verification()
			call_deferred("_run_next_test_step")
		4:
			_perform_action_change_to_null_path()
			call_deferred("_run_next_test_step")
		5:
			_perform_test_null_path_verification()
			call_deferred("_run_next_test_step")
		6:
			_perform_action_change_back_to_path1()
			call_deferred("_run_next_test_step")
		7:
			_perform_test_path1_reverification()
			call_deferred("_run_next_test_step")
		8:
			_perform_action_change_to_path_not_in_tree()
			call_deferred("_run_next_test_step")
		9:
			_perform_test_path_not_in_tree_initial_verification()
			call_deferred("_run_next_test_step")
		10:
			_perform_action_add_path_to_tree()
			call_deferred("_run_next_test_step")
		11:
			_perform_test_path_now_in_tree_final_verification()
		_:
			print_debug("All test steps completed.")
			if get_tree() != null: get_tree().quit()

func _get_node_name_or_status(node: Node) -> String:
	if node == null: return "null_reference"
	if not is_instance_valid(node): return "invalid_instance"
	return node.name if node.name != &"" else "unnamed_node"

func _verify_bogie_paths(expected_rear_path: Path3D, expected_front_path: Path3D, test_label: String) -> bool:
	if not is_instance_valid(_internal_train_unit):
		printerr(test_label, ": FAILED. Train unit is not valid.")
		return false

	var rear_bogie_actual_path: Path3D = _internal_train_unit.get_rear_bogie_path()
	var front_bogie_actual_path: Path3D = _internal_train_unit.get_front_bogie_path()

	var rear_ok: bool
	if expected_rear_path == null: rear_ok = not is_instance_valid(rear_bogie_actual_path)
	elif not is_instance_valid(expected_rear_path): rear_ok = not is_instance_valid(rear_bogie_actual_path)
	else: rear_ok = rear_bogie_actual_path == expected_rear_path

	var front_ok: bool
	if expected_front_path == null: front_ok = not is_instance_valid(front_bogie_actual_path)
	elif not is_instance_valid(expected_front_path): front_ok = not is_instance_valid(front_bogie_actual_path)
	else: front_ok = front_bogie_actual_path == expected_front_path
	
	var overall_success = rear_ok and front_ok

	var rear_actual_name = _get_node_name_or_status(rear_bogie_actual_path)
	var expected_rear_name = _get_node_name_or_status(expected_rear_path)
	var front_actual_name = _get_node_name_or_status(front_bogie_actual_path)
	var expected_front_name = _get_node_name_or_status(expected_front_path)

	if overall_success:
		print_debug(test_label, ": PASSED.")
	else:
		printerr(test_label, ": FAILED.")

	print_debug("  Rear Bogie Path: Actual='", rear_actual_name, "', Expected='", expected_rear_name, "' (Match: ", rear_ok, ")")
	if is_instance_valid(_internal_train_unit._internal_rear_bogie_follower_node) and is_instance_valid(_internal_train_unit._internal_rear_bogie_follower_node.get_parent()):
		print_debug("    Rear Bogie Follower Parent: '", _get_node_name_or_status(_internal_train_unit._internal_rear_bogie_follower_node.get_parent()), "'")
	elif is_instance_valid(_internal_train_unit._internal_rear_bogie_follower_node):
		print_debug("    Rear Bogie Follower Parent: null_or_invalid")
	else:
		print_debug("    _internal_rear_bogie_follower_node is null or invalid.")

	print_debug("  Front Bogie Path: Actual='", front_actual_name, "', Expected='", expected_front_name, "' (Match: ", front_ok, ")")
	if is_instance_valid(_internal_train_unit._internal_front_bogie_follower_node) and is_instance_valid(_internal_train_unit._internal_front_bogie_follower_node.get_parent()):
		print_debug("    Front Bogie Follower Parent: '", _get_node_name_or_status(_internal_train_unit._internal_front_bogie_follower_node.get_parent()), "'")
	elif is_instance_valid(_internal_train_unit._internal_front_bogie_follower_node):
		print_debug("    Front Bogie Follower Parent: null_or_invalid")
	else:
		print_debug("    _internal_front_bogie_follower_node is null or invalid.")
	
	return overall_success

func _perform_test_initial_state_verification() -> void:
	print_debug("Verifying initial state of TrainUnit on Path1.")
	_verify_bogie_paths(_internal_path1, _internal_path1, "Initial State")

func _perform_action_change_to_path2() -> void:
	print_debug("Action: Changing target_path_3d_node to Path2.")
	_internal_train_unit.target_path_3d_node = _internal_path2

func _perform_test_path2_verification() -> void:
	print_debug("Verifying TrainUnit has moved to Path2.")
	_verify_bogie_paths(_internal_path2, _internal_path2, "Path Change to Path2")

func _perform_action_change_to_null_path() -> void:
	print_debug("Action: Changing target_path_3d_node to null.")
	_internal_train_unit.target_path_3d_node = null

func _perform_test_null_path_verification() -> void:
	print_debug("Verifying TrainUnit bogies are cleared (target path is null).")
	var rear_follower_valid = is_instance_valid(_internal_train_unit._internal_rear_bogie_follower_node)
	var front_follower_valid = is_instance_valid(_internal_train_unit._internal_front_bogie_follower_node)
	
	var paths_correct = _verify_bogie_paths(null, null, "Path Change to null")
	if paths_correct and not rear_follower_valid and not front_follower_valid:
		print_debug("  Null Path Follower Check: PASSED. Bogie followers are invalid/null as expected.")
	else:
		printerr("  Null Path Follower Check: FAILED.")
		if rear_follower_valid: printerr("    _internal_rear_bogie_follower_node is still valid.")
		if front_follower_valid: printerr("    _internal_front_bogie_follower_node is still valid.")

func _perform_action_change_back_to_path1() -> void:
	print_debug("Action: Changing target_path_3d_node back to Path1.")
	_internal_train_unit.target_path_3d_node = _internal_path1

func _perform_test_path1_reverification() -> void:
	print_debug("Verifying TrainUnit has moved back to Path1.")
	_verify_bogie_paths(_internal_path1, _internal_path1, "Path Change back to Path1")

func _perform_action_change_to_path_not_in_tree() -> void:
	print_debug("Action: Changing target_path_3d_node to Path3 (not yet in tree).")
	_internal_path3_not_in_tree = Path3D.new()
	_internal_path3_not_in_tree.name = "TestPath3_NotInTree"
	var curve3 := Curve3D.new()
	curve3.add_point(Vector3(-10, 0, 0))
	curve3.add_point(Vector3(-10, 0, 20))
	_internal_path3_not_in_tree.curve = curve3
	_internal_train_unit.target_path_3d_node = _internal_path3_not_in_tree

func _perform_test_path_not_in_tree_initial_verification() -> void:
	print_debug("Verifying bogies cleared (new target path Path3 is not in tree).")
	var rear_follower_valid = is_instance_valid(_internal_train_unit._internal_rear_bogie_follower_node)
	var front_follower_valid = is_instance_valid(_internal_train_unit._internal_front_bogie_follower_node)

	var paths_correct = _verify_bogie_paths(null, null, "Path Change to Path Not In Tree (Before Add)")
	if paths_correct and not rear_follower_valid and not front_follower_valid:
		print_debug("  Path Not In Tree Follower Check: PASSED. Bogie followers invalid/null.")
	else:
		printerr("  Path Not In Tree Follower Check: FAILED.")
		if rear_follower_valid: printerr("    _internal_rear_bogie_follower_node is still valid.")
		if front_follower_valid: printerr("    _internal_front_bogie_follower_node is still valid.")

func _perform_action_add_path_to_tree() -> void:
	print_debug("Action: Adding Path3 to the scene tree.")
	if is_instance_valid(_internal_path3_not_in_tree) and not _internal_path3_not_in_tree.is_inside_tree():
		add_child(_internal_path3_not_in_tree)
	else:
		printerr("Path3 was not valid or already in tree before intended add action.")

func _perform_test_path_now_in_tree_final_verification() -> void:
	print_debug("Verifying TrainUnit regenerates on Path3 after Path3 entered tree.")
	_verify_bogie_paths(_internal_path3_not_in_tree, _internal_path3_not_in_tree, "Path3 Entered Tree")
	print_debug("Final verification complete. Test will now quit.")
	if get_tree() != null: get_tree().quit()
