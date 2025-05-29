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

const _internal_num_units = 2
const _internal_unit_len = 5.0
const _internal_gap = 2.0
const _internal_path_len = 50.0
const _internal_train_speed = 200.0 # High speed for quick testing
const _internal_action_fwd = "test_train_fwd"
const _internal_action_back = "test_train_back" # Not used in this test, but good practice

var _internal_path_a: Path3D
var _internal_path_b: Path3D
var _internal_train_unit_template: Train_Unit
var _internal_train: Train

var _internal_test_step: int = 0
var _internal_frames_to_wait_after_action: int = 5 # Number of full process & physics frames

var _internal_signal_all_units_data: Dictionary = {"emitted": false, "path": null}
var _internal_signal_train_reached_end_emitted: bool = false


func _ready() -> void:
	if not InputMap.has_action(_internal_action_fwd):
		InputMap.add_action(_internal_action_fwd)
	# if not InputMap.has_action(_internal_action_back): # Not strictly needed for this test
		# InputMap.add_action(_internal_action_back)

	_internal_path_a = Path3D.new()
	_internal_path_a.name = "TestPathA"
	var curve_a := Curve3D.new()
	curve_a.add_point(Vector3(0, 0, 0))
	curve_a.add_point(Vector3(0, 0, _internal_path_len))
	_internal_path_a.curve = curve_a
	add_child(_internal_path_a)

	_internal_path_b = Path3D.new()
	_internal_path_b.name = "TestPathB"
	var curve_b := Curve3D.new()
	curve_b.add_point(Vector3(10, 0, 0)) # Different origin for clarity
	curve_b.add_point(Vector3(10, 0, _internal_path_len))
	_internal_path_b.curve = curve_b
	add_child(_internal_path_b)

	_internal_train_unit_template = Train_Unit.new()
	_internal_train_unit_template.length = _internal_unit_len
	# The template is not added to the scene tree, it's just a template object.

	_internal_train = Train.create_train(
		_internal_train_unit_template,
		_internal_path_a,
		null, # p_train_unit_scene
		_internal_num_units,
		_internal_train_speed,
		_internal_gap,
		null, # p_next_path_override
		_internal_action_fwd,
		_internal_action_back,
		0.0 # p_initial_head_unit_front_offset - let train auto-calculate
	)
	_internal_train.name = "TestTrain"
	add_child(_internal_train)

	_internal_train.all_units_on_new_path.connect(_on_train_all_units_on_new_path)
	_internal_train.train_reached_end_of_route.connect(_on_train_reached_end_of_route)

	call_deferred("_run_next_test_step")


func _run_next_test_step() -> void:
	_internal_test_step += 1
	print_debug("\n--- Executing Test Step ", _internal_test_step, " ---")

	match _internal_test_step:
		1:
			_perform_test_initial_creation_and_setup()
			call_deferred("_run_next_test_step")
		2:
			_perform_action_force_next_path()
			call_deferred("_run_next_test_step")
		3:
			_perform_action_move_train_for_first_jump()
			call_deferred("_run_next_test_step")
		4:
			_perform_test_after_first_jump()
			call_deferred("_run_next_test_step")
		5:
			_perform_action_move_train_for_all_units_jump()
			call_deferred("_run_next_test_step")
		6:
			_perform_test_all_units_on_new_path()
			call_deferred("_run_next_test_step")
		7:
			_perform_action_move_train_to_end()
			call_deferred("_run_next_test_step")
		8:
			_perform_test_train_reached_end()
		_:
			print_debug("All test steps completed.")
			_cleanup_and_quit()

func _wait_for_signal_processing(num_frames: int = -1) -> void:
	if num_frames == -1: num_frames = _internal_frames_to_wait_after_action
	for _i in range(num_frames):
		await get_tree().process_frame
		if not get_tree().paused: # Only await physics_frame if tree is not paused
			await get_tree().physics_frame
		# If the tree might be paused and physics_frame is essential,
		# this part of the test might need adjustment or ensure tree is not paused.
		# For most tests, tree is not paused.


func _assert_true(condition: bool, message: String) -> bool:
	if condition:
		print_debug("  ASSERT PASSED: ", message)
	else:
		printerr("  ASSERT FAILED: ", message)
	return condition

func _assert_equals(val1, val2, message: String) -> bool:
	if val1 == val2:
		print_debug("  ASSERT PASSED: ", message, " (", str(val1), " == ", str(val2), ")")
		return true
	else:
		printerr("  ASSERT FAILED: ", message, " (Expected: ", str(val2), ", Got: ", str(val1), ")")
		return false

func _perform_test_initial_creation_and_setup() -> void:
	print_debug("Verifying initial creation and setup...")
	_internal_train.setup() # Call setup explicitly
	await _wait_for_signal_processing()

	_assert_equals(_internal_train.get_train_units().size(), _internal_num_units, "Correct number of units created")
	var all_units_on_path_a = true
	for unit_node in _internal_train.get_train_units():
		if not is_instance_valid(unit_node) or unit_node.get_current_path() != _internal_path_a:
			all_units_on_path_a = false
			var current_path_name = "N/A"
			if is_instance_valid(unit_node) and is_instance_valid(unit_node.get_current_path()):
				current_path_name = unit_node.get_current_path().name
			printerr("  Unit ", unit_node.name if is_instance_valid(unit_node) else "INVALID", " not on PathA. Actual: ", current_path_name)
			break
	_assert_true(all_units_on_path_a, "All units initially on Path A")
	_assert_equals(_internal_train.get_current_train_path(), _internal_path_a, "Train's current path is Path A")

	var expected_head_offset = (_internal_unit_len * _internal_num_units) + (_internal_gap * (_internal_num_units - 1))
	_assert_equals(_internal_train.head_unit_front_offset, expected_head_offset, "Train head_unit_front_offset auto-calculated correctly")


func _perform_action_force_next_path() -> void:
	print_debug("Action: Forcing next path to Path B...")
	_internal_train.force_next_path_for_train(_internal_path_b)
	await _wait_for_signal_processing()

	_assert_equals(_internal_train.next_path_override, _internal_path_b, "Train's next_path_override is Path B")
	if _internal_num_units > 0:
		var lead_unit = _internal_train.get_leading_unit()
		if is_instance_valid(lead_unit):
			_assert_equals(lead_unit.next_route_path_3d_node, _internal_path_b, "Leading unit's next_route_path_3d_node is Path B")
		else:
			_assert_true(false, "Leading unit is invalid after forcing next path")


func _simulate_train_movement_forward(distance: float) -> void:
	var time_to_move = 0.0
	if _internal_train_speed > 0:
		time_to_move = distance / _internal_train_speed
	elif distance > 0: # If speed is zero but distance is required, simulate for a few frames
		time_to_move = (1.0 / Engine.get_physics_ticks_per_second()) * 5.0 # 5 physics frames
		printerr("Warning: _internal_train_speed is zero or negative, simulating fixed frames for movement.")
	else: # No distance and no speed, do nothing
		return


	Input.action_press(_internal_action_fwd)

	var time_elapsed = 0.0
	var physics_step_delta = 1.0 / Engine.get_physics_ticks_per_second()
	
	if physics_step_delta <= 0.000001: # Safety for very high physics ticks or zero
		printerr("Physics step delta is too small or zero. Aborting simulation.")
		Input.action_release(_internal_action_fwd)
		return

	while time_elapsed < time_to_move:
		_internal_train._physics_process(physics_step_delta)

		if not get_tree().paused:
			await get_tree().physics_frame
		await get_tree().process_frame
		
		time_elapsed += physics_step_delta
		
		if time_elapsed >= time_to_move:
			break

	Input.action_release(_internal_action_fwd)
	await _wait_for_signal_processing()


func _perform_action_move_train_for_first_jump() -> void:
	print_debug("Action: Moving train for first unit to jump to Path B...")
	var lead_unit = _internal_train.get_leading_unit()
	if not is_instance_valid(lead_unit):
		_assert_true(false, "Cannot move, leading unit is invalid.")
		call_deferred("_run_next_test_step") # Skip to next test if this fails critically
		return

	var distance_to_path_end = _internal_path_len - lead_unit.get_front_bogie_progress()
	var move_distance = distance_to_path_end + _internal_unit_len * 0.5 # Move half unit length past the end
	
	_simulate_train_movement_forward(move_distance)


func _perform_test_after_first_jump() -> void:
	print_debug("Verifying state after first unit jumped...")
	var lead_unit = _internal_train.get_leading_unit()
	if not is_instance_valid(lead_unit):
		_assert_true(false, "Leading unit is invalid after first jump attempt.")
		return

	_assert_equals(lead_unit.get_current_path(), _internal_path_b, "Leading unit is on Path B")
	_assert_equals(_internal_train.get_current_train_path(), _internal_path_b, "Train's current path is Path B")
	_assert_equals(_internal_train.next_path_override, null, "Train's next_path_override is null after jump")

	if _internal_num_units > 1:
		var second_unit = _internal_train.get_train_units()[1]
		if is_instance_valid(second_unit):
			_assert_equals(second_unit.next_route_path_3d_node, _internal_path_b, "Second unit's next_route_path_3d_node is Path B")
		else:
			_assert_true(false, "Second unit is invalid.")


func _perform_action_move_train_for_all_units_jump() -> void:
	print_debug("Action: Moving train for all units to jump to Path B...")
	var total_train_length_approx = _internal_num_units * _internal_unit_len + (_internal_num_units -1) * _internal_gap
	_simulate_train_movement_forward(total_train_length_approx + _internal_gap)


func _perform_test_all_units_on_new_path() -> void:
	print_debug("Verifying all units are on Path B and signal emitted...")
	_assert_true(_internal_signal_all_units_data.emitted, "'all_units_on_new_path' signal was emitted")
	if _internal_signal_all_units_data.emitted:
		_assert_equals(_internal_signal_all_units_data.path, _internal_path_b, "Signal emitted with correct new path (Path B)")

	var all_on_path_b = true
	for unit_node in _internal_train.get_train_units():
		if not is_instance_valid(unit_node) or unit_node.get_current_path() != _internal_path_b:
			all_on_path_b = false
			var current_path_name = "N/A"
			if is_instance_valid(unit_node) and is_instance_valid(unit_node.get_current_path()):
				current_path_name = unit_node.get_current_path().name
			printerr("  Unit ", unit_node.name if is_instance_valid(unit_node) else "INVALID", " not on PathB. Actual: ", current_path_name)
			break
	_assert_true(all_on_path_b, "All units are now on Path B")


func _perform_action_move_train_to_end() -> void:
	print_debug("Action: Moving train to the end of Path B...")
	var trailing_unit = _internal_train.get_trailing_unit()
	if not is_instance_valid(trailing_unit):
		_assert_true(false, "Cannot move to end, trailing unit is invalid.")
		call_deferred("_run_next_test_step") # Skip
		return

	var distance_to_move = _internal_path_len - trailing_unit.get_rear_bogie_progress()
	distance_to_move += _internal_unit_len # Ensure it properly triggers "reached end"
	
	_simulate_train_movement_forward(distance_to_move)


func _perform_test_train_reached_end() -> void:
	print_debug("Verifying 'train_reached_end_of_route' signal...")
	_assert_true(_internal_signal_train_reached_end_emitted, "'train_reached_end_of_route' signal was emitted")
	call_deferred("_run_next_test_step") # To proceed to quit

func _on_train_all_units_on_new_path(new_path_node: Path3D, _train_node: Train) -> void:
	print_debug("  SIGNAL RECEIVED: all_units_on_new_path (Path: ", new_path_node.name, ")")
	_internal_signal_all_units_data.emitted = true
	_internal_signal_all_units_data.path = new_path_node

func _on_train_reached_end_of_route(_train_node: Train) -> void:
	print_debug("  SIGNAL RECEIVED: train_reached_end_of_route")
	_internal_signal_train_reached_end_emitted = true

func _cleanup_and_quit() -> void:
	if is_instance_valid(_internal_train_unit_template) and not _internal_train_unit_template.is_inside_tree():
		_internal_train_unit_template.free()
	
	if get_tree() != null:
		get_tree().quit()

func _exit_tree() -> void:
	if InputMap.has_action(_internal_action_fwd):
		InputMap.erase_action(_internal_action_fwd)
	# if InputMap.has_action(_internal_action_back):
		# InputMap.erase_action(_internal_action_back)
