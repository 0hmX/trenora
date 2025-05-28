class_name Train
extends Node3D

@export var number_of_units := 4

@export var speed := 5.0
@export var gap := 2.0

@export var input_forward_action := "move_forward"
@export var input_backward_action := "move_backward"

@export var initial_path : Path3D
@export var next_path_override : Path3D

@export var train_unit_scene: PackedScene

signal all_units_on_new_path(new_path_node: Path3D, train_node: Train)
signal train_reached_end_of_route(train_node: Train)

var internalTrainUnitRefArray: Array[Train_Unit] = []
var head_unit_front_offset: float = 0.0 

var _current_train_path_node: Path3D
var _train_unit_template_instance: Train_Unit = null


#@export_tool_button("Setup_Train") 
var _setup_button_callable: Callable = setup

static func create_train(
	train_unit_template: Train_Unit,
	p_initial_path: Path3D,
	p_train_unit_scene: PackedScene = null,
	p_number_of_units: int = 4,
	p_speed: float = 5.0,
	p_gap: float = 2.0,
	p_next_path_override: Path3D = null,
	p_unit_main_body_scene: PackedScene = null,
	p_unit_bogie_scene: PackedScene = null,
	p_input_forward_action: String = "move_forward",
	p_input_backward_action: String = "move_backward",
	p_initial_head_unit_front_offset: float = 0.0
) -> Train:
	var new_train := Train.new()

	new_train._train_unit_template_instance = train_unit_template
	new_train.initial_path = p_initial_path
	
	if is_instance_valid(p_train_unit_scene):
		new_train.train_unit_scene = p_train_unit_scene
	
	new_train.number_of_units = p_number_of_units
	new_train.speed = p_speed
	new_train.gap = p_gap
	new_train.next_path_override = p_next_path_override
	
	if is_instance_valid(p_unit_main_body_scene):
		new_train.unit_main_body_scene = p_unit_main_body_scene
	if is_instance_valid(p_unit_bogie_scene):
		new_train.unit_bogie_scene = p_unit_bogie_scene
		
	new_train.input_forward_action = p_input_forward_action
	new_train.input_backward_action = p_input_backward_action
	new_train.head_unit_front_offset = p_initial_head_unit_front_offset
			
	# IMPORTANT: setup() will add units to the tree.
	# _generate_train() on units should be called AFTER they are in the tree.
	# The Train's setup method should handle this.
	# new_train.setup() # Call setup AFTER new_train is added to the main scene tree by the caller.
	return new_train


func setup() -> void:
	_clear_existing_units()
	if not is_instance_valid(initial_path):
		printerr("Train setup (%s): InitialPath not set." % name)
		return
	
	if not initial_path.is_inside_tree() and not Engine.is_editor_hint():
		printerr("Train setup (%s): InitialPath '%s' is not in the scene tree." % [name, initial_path.name])
		# Optionally, connect to initial_path.tree_entered and defer setup.
		if not initial_path.is_connected("tree_entered", Callable(self, "_on_initial_path_entered_tree_for_setup")):
			initial_path.connect("tree_entered", Callable(self, "_on_initial_path_entered_tree_for_setup"), CONNECT_ONE_SHOT)
		return

	var can_create_units = is_instance_valid(_train_unit_template_instance) or \
						   (is_instance_valid(train_unit_scene) and train_unit_scene.can_instantiate())
	
	if not can_create_units:
		printerr("Train setup (%s): Neither a template Train_Unit instance nor a TrainUnitScene is available. Will use default Train_Unit.new()." % name)

	_current_train_path_node = initial_path
	var current_placement_front_offset: float = self.head_unit_front_offset 
	
	var first_unit_instance_for_length_calc: Train_Unit = null
	# ... (rest of your length calculation logic - it's mostly fine as it doesn't add to tree yet) ...
	if is_instance_valid(_train_unit_template_instance):
		first_unit_instance_for_length_calc = _train_unit_template_instance
	elif is_instance_valid(train_unit_scene) and train_unit_scene.can_instantiate():
		var temp_inst = train_unit_scene.instantiate()
		if temp_inst is Train_Unit: 
			first_unit_instance_for_length_calc = temp_inst as Train_Unit
		else: 
			if is_instance_valid(temp_inst): temp_inst.queue_free()
	
	if not is_instance_valid(first_unit_instance_for_length_calc):
		first_unit_instance_for_length_calc = Train_Unit.new() 

	var single_unit_footprint = first_unit_instance_for_length_calc.length + self.gap
	var total_initial_train_length_approx = (single_unit_footprint * number_of_units) - self.gap

	if self.head_unit_front_offset < total_initial_train_length_approx :
		self.head_unit_front_offset = total_initial_train_length_approx
	current_placement_front_offset = self.head_unit_front_offset
	
	if is_instance_valid(first_unit_instance_for_length_calc) and \
	   first_unit_instance_for_length_calc != _train_unit_template_instance and \
	   not first_unit_instance_for_length_calc.is_inside_tree():
		first_unit_instance_for_length_calc.queue_free()


	for i in range(number_of_units):
		var unit_node_instance: Train_Unit
		
		if is_instance_valid(_train_unit_template_instance):
			var dup_node = _train_unit_template_instance.duplicate()
			if dup_node is Train_Unit:
				unit_node_instance = dup_node as Train_Unit
			else:
				if is_instance_valid(dup_node): dup_node.queue_free()
				printerr("Train setup (%s): Failed to duplicate _train_unit_template_instance correctly. Falling back." % name)
				unit_node_instance = Train_Unit.new() # Fallback
		elif is_instance_valid(train_unit_scene) and train_unit_scene.can_instantiate():
			var inst_node: Node = train_unit_scene.instantiate()
			if inst_node is Train_Unit: 
				unit_node_instance = inst_node as Train_Unit
			else: 
				if is_instance_valid(inst_node): inst_node.queue_free()
				printerr("Train setup (%s): train_unit_scene did not instantiate a Train_Unit. Falling back." % name)
				unit_node_instance = Train_Unit.new() # Fallback
		else: 
			unit_node_instance = Train_Unit.new()
		
		unit_node_instance.name = "TrainUnit_Node_" + str(i)
		unit_node_instance.unit_identifier_prefix = "Train" + str(self.get_instance_id()) + "_Unit" + str(i) + "_"

		unit_node_instance.target_path_3d_node = self.initial_path # This path MUST be in the tree
		if i == 0 and is_instance_valid(next_path_override):
			# Ensure next_path_override is also in the tree if it's going to be used soon
			if next_path_override.is_inside_tree() or Engine.is_editor_hint():
				unit_node_instance.next_route_path_3d_node = next_path_override
			else:
				printerr("Train setup (%s): next_path_override '%s' for unit 0 is not in the scene tree." % [name, next_path_override.name])
		
		if not is_instance_valid(unit_node_instance.main_body_scene) and is_instance_valid(self.unit_main_body_scene):
			unit_node_instance.main_body_scene = self.unit_main_body_scene
		if not is_instance_valid(unit_node_instance.bogie_scene) and is_instance_valid(self.unit_bogie_scene):
			unit_node_instance.bogie_scene = self.unit_bogie_scene
		
		var unit_len = unit_node_instance.length
		unit_node_instance.track_offset = current_placement_front_offset - unit_len
		if unit_node_instance.track_offset < 0.0: 
			unit_node_instance.track_offset = 0.0
			current_placement_front_offset = unit_node_instance.track_offset + unit_len

		unit_node_instance.connect("jumped_to_next_path", _on_train_unit_jumped_path)
		unit_node_instance.connect("reached_end_of_final_path", _on_train_unit_reached_end)
		
		add_child(unit_node_instance) # NOW the unit_node_instance is in the tree (assuming 'self' (Train) is)
		
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root != null:
			if unit_node_instance.owner == null: unit_node_instance.owner = get_tree().edited_scene_root
		
		internalTrainUnitRefArray.append(unit_node_instance)
		
		# Call _generate_train AFTER adding to tree.
		# Ensure its target_path_3d_node is also in the tree.
		if is_instance_valid(unit_node_instance.target_path_3d_node) and \
		   (unit_node_instance.target_path_3d_node.is_inside_tree() or Engine.is_editor_hint()):
			if unit_node_instance.has_method("_generate_train"):
				unit_node_instance.call_deferred("_generate_train") # Use call_deferred
		elif is_instance_valid(unit_node_instance.target_path_3d_node):
			printerr("Train setup (%s): target_path_3d_node for unit %s is not in tree. Generation deferred." % [name, i])
			# Train_Unit._enter_tree will attempt to call _generate_train.
		else:
			printerr("Train setup (%s): target_path_3d_node for unit %s is invalid." % [name, i])
		
		current_placement_front_offset = unit_node_instance.track_offset - self.gap
	
	if internalTrainUnitRefArray.size() > 0 and is_instance_valid(internalTrainUnitRefArray[0]):
		var first_unit = internalTrainUnitRefArray[0]
		self.head_unit_front_offset = first_unit.track_offset + first_unit.length

func _on_initial_path_entered_tree_for_setup():
	# Called if initial_path wasn't in tree when setup was first attempted
	if is_inside_tree() and is_instance_valid(initial_path) and initial_path.is_inside_tree():
		call_deferred("setup") # Retry setup


func _ready() -> void:
	if not Engine.is_editor_hint():
		# If Train is added to scene, and initial_path is already in scene, setup will run.
		# If initial_path is not in scene, setup will connect to its tree_entered.
		if is_inside_tree(): # Ensure the Train itself is in the tree before calling setup
			call_deferred("setup") # Defer to ensure all nodes are ready
		else:
			# This case is less common if Train is instantiated and then added.
			# If Train is part of a scene being instanced, _enter_tree is better.
			pass

# In your Train.gd script

# ... (other parts of Train.gd) ...

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		# This check is to avoid running setup automatically when the scene containing this Train
		# is just being opened or manipulated in the editor, but not when it's part of the
		# 'edited_scene_root' directly (which is what @tool scripts often operate on).
		# A more robust check for "is this node being actively edited vs. running in game"
		# can be complex. For runtime, Engine.is_editor_hint() is the main guard.
		# If the Train node's owner is the edited scene root, it might be part of a @tool setup.
		# However, for runtime instantiation, owner might be null or the instantiating scene.
		var is_part_of_edited_scene = false
		if get_tree() and get_tree().edited_scene_root:
			if owner == get_tree().edited_scene_root:
				is_part_of_edited_scene = true # This node is directly part of the scene being edited
			# You could also check if this node is a descendant of the edited_scene_root,
			# but that might be overly broad if you only want to exclude the top-level edited scene.

		if not is_part_of_edited_scene: # Only run setup if not directly part of the actively edited scene
			call_deferred("setup")
	# If Engine.is_editor_hint() is true, the @tool button is the explicit way to call setup.
	# _ready() also handles some editor scenarios for initial placement.
func _clear_existing_units() -> void:
	for unit_node in internalTrainUnitRefArray:
		if is_instance_valid(unit_node):
			if unit_node.is_connected("jumped_to_next_path", _on_train_unit_jumped_path):
				unit_node.disconnect("jumped_to_next_path", _on_train_unit_jumped_path)
			if unit_node.is_connected("reached_end_of_final_path", _on_train_unit_reached_end):
				unit_node.disconnect("reached_end_of_final_path", _on_train_unit_reached_end)
			unit_node.queue_free()
	internalTrainUnitRefArray.clear()
	for i in range(get_child_count() - 1, -1, -1):
		var child = get_child(i)
		if child is Train_Unit: child.queue_free()
	# _units_fully_on_current_train_path = 0 # This var is not currently used for critical logic

func _on_train_unit_jumped_path(new_path_node_for_unit: Path3D, unit_that_jumped: Train_Unit) -> void:
	var unit_index = internalTrainUnitRefArray.find(unit_that_jumped)
	if unit_index == -1: return

	if unit_index + 1 < internalTrainUnitRefArray.size():
		var unit_behind = internalTrainUnitRefArray[unit_index + 1]
		if is_instance_valid(unit_behind) and unit_behind.next_route_path_3d_node != new_path_node_for_unit:
			unit_behind.next_route_path_3d_node = new_path_node_for_unit
	
	if unit_index == 0: # If the leading unit jumped
		_current_train_path_node = new_path_node_for_unit
		# If the train's overall next_path_override was the one just taken by the leading unit,
		# clear it, as it's now "consumed" for this immediate next step.
		# The leading unit might get its *next* next path from new_path_node_for_unit's properties or another system.
		if self.next_path_override == new_path_node_for_unit:
			self.next_path_override = null

	var all_on_new_path = true
	for unit in internalTrainUnitRefArray:
		if not is_instance_valid(unit) or unit.get_current_path() != new_path_node_for_unit:
			all_on_new_path = false
			break
	if all_on_new_path:
		emit_signal("all_units_on_new_path", new_path_node_for_unit, self)

func _on_train_unit_reached_end(unit_node: Train_Unit) -> void:
	var unit_index = internalTrainUnitRefArray.find(unit_node)
	if unit_index == -1: return

	# If it's the last unit in the train that reached its end
	if unit_index == internalTrainUnitRefArray.size() - 1:
		emit_signal("train_reached_end_of_route", self)

func _handle_train_movement(delta: float) -> void:
	if Engine.is_editor_hint(): return
	var movement_input: float = Input.get_axis(input_backward_action, input_forward_action)
	
	# For this system, we only allow positive (forward) movement via API.
	# Input.get_axis can return negative, so we handle that.
	var effective_movement_input = 0.0
	if movement_input > 1e-3 : # Threshold for forward
		effective_movement_input = movement_input
	# If you want to support backward movement from input, handle `movement_input < -1e-3` here.
	# For now, only forward movement via input is processed.
	
	if abs(effective_movement_input) < 1e-3: return


	var distance_this_frame: float = effective_movement_input * self.speed * delta
	# Distance must be positive due to effective_movement_input check.
	# if distance_this_frame <= 0 : return # Redundant if effective_movement_input is always positive

	for i in range(internalTrainUnitRefArray.size()):
		var unit_node = internalTrainUnitRefArray[i]
		if not is_instance_valid(unit_node): continue
		
		# Ensure the leading unit knows about the train's overall next_path_override
		if i == 0 and is_instance_valid(self.next_path_override):
			# This check ensures we don't redundantly set it or overwrite a more specific one from elsewhere.
			if unit_node.get_current_path() != self.next_path_override and \
			   unit_node.next_route_path_3d_node != self.next_path_override:
				unit_node.next_route_path_3d_node = self.next_path_override
		
		unit_node.move_forward_on_path(distance_this_frame)

	# Update informational head_unit_front_offset
	if internalTrainUnitRefArray.size() > 0 and is_instance_valid(internalTrainUnitRefArray[0]):
		var first_unit = internalTrainUnitRefArray[0]
		# get_front_offset_on_current_path() is actually get_front_bogie_progress()
		self.head_unit_front_offset = first_unit.get_front_bogie_progress() 

func _physics_process(delta: float) -> void:
	_handle_train_movement(delta)
