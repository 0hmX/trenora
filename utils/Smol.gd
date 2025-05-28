class_name Smol

static var CMP_EPSILON = 0.00001

static func get_hms_time_string() -> String:
	var t = Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]

static func set_node_name(n: Node, t: String) -> void:
	n.name = t + " " + get_hms_time_string() + " " + str(randi())
