class_name TrackSegmentGenerator
extends RefCounted

func generate_segment_data(
	type_key: String,
	params_override: Dictionary,
	base_type_config: Dictionary,
	num_pts: int,
	current_chunk_len: float,
	last_gen_pos_w: Vector3,
	last_gen_tangent_w: Vector3,
	current_up_w: Vector3
) -> TrackSegmentData:
	var effective_params = base_type_config.get("params", {}).duplicate(true)
	effective_params.merge(params_override, true)

	var generated_points_info: Dictionary
	match type_key:
		"straight":
			generated_points_info = _gen_straight_pts(last_gen_pos_w, last_gen_tangent_w, num_pts, current_chunk_len)
		"circle_left":
			generated_points_info = _gen_circle_pts(last_gen_pos_w, last_gen_tangent_w, effective_params.get("radius", 25.0), -1, num_pts, current_chunk_len, current_up_w)
		"circle_right":
			generated_points_info = _gen_circle_pts(last_gen_pos_w, last_gen_tangent_w, effective_params.get("radius", 25.0), 1, num_pts, current_chunk_len, current_up_w)
		"up":
			generated_points_info = _gen_slope_pts(last_gen_pos_w, last_gen_tangent_w, effective_params.get("vertical_change", 3.0), effective_params.get("smooth_factor", 0.33), num_pts, current_chunk_len, current_up_w)
		"down":
			generated_points_info = _gen_slope_pts(last_gen_pos_w, last_gen_tangent_w, effective_params.get("vertical_change", -3.0), effective_params.get("smooth_factor", 0.33), num_pts, current_chunk_len, current_up_w)
		_:
			printerr("TrackSegmentGenerator: Unknown basic track type: '%s'" % type_key)
			return null

	if generated_points_info.is_empty() or not generated_points_info.has("points_w"):
		printerr("TrackSegmentGenerator: Failed to generate points for type '%s'." % type_key)
		return null

	var segment_data = TrackSegmentData.new(type_key, generated_points_info.get("actual_length", current_chunk_len))
	segment_data.points_w = generated_points_info.points_w
	segment_data.end_tangent_w = generated_points_info.end_tangent_w
	
	return segment_data


func _gen_straight_pts(start_pos_w: Vector3, start_tan_w: Vector3, num_pts_for_segment: int, p_chunk_len: float) -> Dictionary:
	var pts_w = _generate_points_linearly(start_pos_w, start_tan_w, p_chunk_len, num_pts_for_segment)
	return { "points_w": pts_w, "end_tangent_w": start_tan_w.normalized(), "actual_length": p_chunk_len, "type": "straight"}

func _gen_slope_pts(start_pos_w: Vector3, start_tan_w: Vector3, y_change: float, smooth_factor: float, num_pts_for_segment: int, p_chunk_len: float, p_current_up_w: Vector3) -> Dictionary:
	var pts_w: Array[Vector3] = []
	var horiz_dist_sq = p_chunk_len*p_chunk_len - y_change*y_change
	var horiz_dist = 0.0
	if horiz_dist_sq > Smol.CMP_EPSILON: horiz_dist = sqrt(horiz_dist_sq)
	else:
		horiz_dist = 0.0
		if abs(y_change) > p_chunk_len: y_change = sign(y_change) * p_chunk_len

	var horiz_dir_w = start_tan_w.slide(p_current_up_w).normalized()
	if horiz_dir_w.is_zero_approx(): horiz_dir_w = _get_an_orthogonal_vector(p_current_up_w)

	var p0 = start_pos_w
	var p3 = start_pos_w + horiz_dir_w * horiz_dist + p_current_up_w * y_change
	var t0_dir = start_tan_w.normalized()
	var t3_dir: Vector3
	
	if (p3 - p0).length_squared() < Smol.CMP_EPSILON * Smol.CMP_EPSILON : t3_dir = t0_dir
	else:
		t3_dir = (p3 - p0).normalized()
		var t3_horiz_proj = t3_dir.slide(p_current_up_w)
		if t3_horiz_proj.length_squared() > Smol.CMP_EPSILON and horiz_dist > Smol.CMP_EPSILON:
			t3_dir = (horiz_dir_w * horiz_dist + p_current_up_w * y_change).normalized()

	var handle_len = p_chunk_len * clampf(smooth_factor, 0.01, 0.49)
	var ctrl1 = p0 + t0_dir * handle_len
	var ctrl2 = p3 - t3_dir * handle_len

	for i in range(num_pts_for_segment):
		var t: float = 0.0
		if num_pts_for_segment > 1: t = float(i) / float(num_pts_for_segment - 1)
		pts_w.append(p0.bezier_interpolate(ctrl1, ctrl2, p3, t))
	
	var end_tan_w = t3_dir
	if pts_w.size() >= 2 and not pts_w[-1].is_equal_approx(pts_w[-2]):
		end_tan_w = (pts_w[-1] - pts_w[-2]).normalized()
	if end_tan_w.is_zero_approx(): end_tan_w = start_tan_w
	return { "points_w": pts_w, "end_tangent_w": end_tan_w, "actual_length": p_chunk_len, "type": "slope" }

func _gen_circle_pts(start_pos_w: Vector3, start_tan_w: Vector3, radius: float, turn_sign: int, num_pts_for_segment: int, p_chunk_len: float, p_current_up_w: Vector3) -> Dictionary:
	if radius <= 0.1 : return _gen_straight_pts(start_pos_w, start_tan_w, num_pts_for_segment, p_chunk_len)
	var pts_w: Array[Vector3] = [start_pos_w]
	var rot_axis_w = p_current_up_w.normalized()
	var to_center_dir_w = -start_tan_w.cross(rot_axis_w).normalized() * float(turn_sign)
	if to_center_dir_w.is_zero_approx():
		printerr("TrackSegmentGenerator: Failed to generate circle curve (to_center_dir_w is zero). Generating straight segment.")
		return _gen_straight_pts(start_pos_w, start_tan_w, num_pts_for_segment, p_chunk_len)

	var center_w = start_pos_w + to_center_dir_w * radius
	var num_segments_in_curve_float = float(max(1, num_pts_for_segment - 1))
	var angle_total_rad = p_chunk_len / radius
	var angle_step_rad = angle_total_rad / num_segments_in_curve_float
	var vec_center_to_pt_w = start_pos_w - center_w

	for _i in range(num_pts_for_segment - 1):
		vec_center_to_pt_w = vec_center_to_pt_w.rotated(rot_axis_w, angle_step_rad * float(turn_sign))
		pts_w.append(center_w + vec_center_to_pt_w)
	
	var end_tan_w = start_tan_w
	if not pts_w.is_empty():
		var final_radial_vec_w = pts_w[-1] - center_w
		end_tan_w = (rot_axis_w.cross(final_radial_vec_w) * float(turn_sign)).normalized()
		if end_tan_w.is_zero_approx():
			if pts_w.size() >=2 and not pts_w[-1].is_equal_approx(pts_w[-2]):
				end_tan_w = (pts_w[-1] - pts_w[-2]).normalized()
	if end_tan_w.is_zero_approx(): end_tan_w = start_tan_w
	return { "points_w": pts_w, "end_tangent_w": end_tan_w, "actual_length": p_chunk_len, "type": "circle" }

func _generate_points_linearly(p_start_pos_w: Vector3, p_direction_w: Vector3, p_total_length: float, p_num_points: int) -> Array[Vector3]:
	var points_w: Array[Vector3] = [p_start_pos_w]
	if p_num_points <= 1 : return points_w
	var current_pos_w = p_start_pos_w
	var num_segments_float = float(max(1, p_num_points - 1))
	var step_vector_w = p_direction_w.normalized() * (p_total_length / num_segments_float)
	for _i in range(p_num_points - 1):
		current_pos_w += step_vector_w
		points_w.append(current_pos_w)
	return points_w

static func _get_an_orthogonal_vector(v: Vector3) -> Vector3:
	var v_norm = v.normalized()
	var cross_x = v_norm.cross(Vector3.RIGHT)
	return cross_x.normalized() if cross_x.length_squared() > Smol.CMP_EPSILON else v_norm.cross(Vector3.FORWARD).normalized()
