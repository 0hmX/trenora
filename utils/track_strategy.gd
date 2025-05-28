class_name TrackStrategy
extends RefCounted

var _track_type_configurations: Dictionary 
var _track_type_keys: Array[String] = []
var _total_weight: float = 0.0

func _init(p_configurations: Dictionary):
	_track_type_configurations = p_configurations
	_init_track_type_weights()

func _init_track_type_weights():
	_track_type_keys.clear(); _total_weight = 0.0
	for type_key in _track_type_configurations:
		var config = _track_type_configurations[type_key]
		if config is Dictionary and config.has("weight"):
			_track_type_keys.append(type_key)
			_total_weight += float(config.get("weight", 1.0))

func get_next_segment_type(active_chunks: Array[TrackSegmentData]) -> String: # active_chunks now Array[TrackSegmentData]
	var selected_master_type_key = _get_random_track_type()

	if active_chunks.is_empty() or active_chunks.size() <= 1 or selected_master_type_key == "straight":
		return selected_master_type_key

	var last_chunk_data = active_chunks[-1] 
	var last_chunk_generic_type = last_chunk_data.type # Assuming .type on TrackSegmentData

	var current_master_config = _track_type_configurations[selected_master_type_key]
	var first_sub_chunk_specific_type_if_sequence = ""
	if current_master_config.has("sequence") and current_master_config.sequence is Array:
		var sequence_items: Array = current_master_config.sequence
		if not sequence_items.is_empty():
			var first_item = sequence_items[0]
			if first_item is Dictionary and first_item.has("type"):
				first_sub_chunk_specific_type_if_sequence = first_item.type
	
	var effective_current_specific_type_for_rule = first_sub_chunk_specific_type_if_sequence \
		if not first_sub_chunk_specific_type_if_sequence.is_empty() else selected_master_type_key

	var current_is_circle_rule = effective_current_specific_type_for_rule.begins_with("circle")
	var current_is_slope_rule = effective_current_specific_type_for_rule == "up" or effective_current_specific_type_for_rule == "down"
	var last_is_circle_rule = last_chunk_generic_type == "circle"
	var last_is_slope_rule = last_chunk_generic_type == "slope"
	var force_straight = false
	if last_is_circle_rule and current_is_circle_rule and randf() < 0.75: force_straight = true
	elif last_is_slope_rule and current_is_slope_rule and randf() < 0.85: force_straight = true
	if force_straight and _track_type_configurations.has("straight"): return "straight"
	return selected_master_type_key

func _get_random_track_type() -> String:
	if _track_type_keys.is_empty() or _total_weight <= 0: return "straight"
	var rand_val = randf_range(0, _total_weight)
	var cumulative_weight: float = 0.0
	for type_key in _track_type_keys:
		cumulative_weight += float(_track_type_configurations[type_key].get("weight", 0.0))
		if rand_val <= cumulative_weight: return type_key
	return _track_type_keys[-1] if not _track_type_keys.is_empty() else "straight"

func get_base_config_for_type(type_key: String) -> Dictionary:
	return _track_type_configurations.get(type_key, {})

func has_type_config(type_key: String) -> bool:
	return _track_type_configurations.has(type_key)
