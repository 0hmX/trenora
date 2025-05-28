class_name TrackMeshBuilder
extends RefCounted

func build_mesh_for_segment(
	segment_data: TrackSegmentData,
	path_global_transform: Transform3D, # To convert to local space for mesh vertices
	current_up_w: Vector3,
	p_track_width: float,
	p_track_material: StandardMaterial3D, # From TrackManager
	p_track_png: Texture2D,              # From TrackManager
	p_texture_tile_length_v: float     # From TrackManager
) -> MeshInstance3D:
	var points_w = segment_data.points_w
	var p_chunk_actual_length = segment_data.length
	
	if points_w.size() < 2: return null
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up_for_side_vector_calc_w = current_up_w.normalized()
	if up_for_side_vector_calc_w.is_zero_approx(): up_for_side_vector_calc_w = Vector3.UP
	
	var path_inv_basis = path_global_transform.basis.inverse()
	var path_origin = path_global_transform.origin

	# Need a reliable initial tangent if the segment is very short or first point
	var last_known_good_tangent_w = Vector3.FORWARD # Fallback
	if points_w.size() > 1 and not points_w[0].is_equal_approx(points_w[1]):
		last_known_good_tangent_w = (points_w[1] - points_w[0]).normalized()


	for i in range(points_w.size()):
		var p_curr_w = points_w[i]
		var tangent_w: Vector3
		if i < points_w.size() - 1: tangent_w = (points_w[i+1] - p_curr_w)
		elif i > 0: tangent_w = (p_curr_w - points_w[i-1])
		else: tangent_w = last_known_good_tangent_w # Use initial tangent for the very first point

		if tangent_w.is_zero_approx(): # Attempt to recover tangent
			if i > 0 and i < points_w.size() - 1: tangent_w = (points_w[i+1] - points_w[i-1])
			elif i > 0 : tangent_w = (p_curr_w - points_w[i-1])
			else: tangent_w = last_known_good_tangent_w
		
		tangent_w = tangent_w.normalized()
		if tangent_w.is_zero_approx(): tangent_w = last_known_good_tangent_w
		last_known_good_tangent_w = tangent_w # Update for next iteration's fallback

		var geo_left_dir_w = tangent_w.cross(up_for_side_vector_calc_w).normalized()
		var surface_normal_w : Vector3
		if geo_left_dir_w.is_zero_approx():
			var alt_ref_vec = Vector3.RIGHT
			if abs(tangent_w.dot(alt_ref_vec)) > 1.0 - Smol.CMP_EPSILON: alt_ref_vec = Vector3.FORWARD
			geo_left_dir_w = tangent_w.cross(alt_ref_vec).normalized()
			if geo_left_dir_w.is_zero_approx(): geo_left_dir_w = TrackSegmentGenerator._get_an_orthogonal_vector(tangent_w) # Use static from other class or move here
		
		surface_normal_w = geo_left_dir_w.cross(tangent_w).normalized()
		if surface_normal_w.is_zero_approx(): surface_normal_w = up_for_side_vector_calc_w

		var v_geo_right_w  = p_curr_w - geo_left_dir_w * p_track_width * 0.5
		var v_geo_left_w = p_curr_w + geo_left_dir_w * p_track_width * 0.5
		
		# Convert to path_node's local space for mesh vertices
		var v_geo_right_local = path_inv_basis * (v_geo_right_w - path_origin)
		var v_geo_left_local  = path_inv_basis * (v_geo_left_w - path_origin)
		
		var normal_local = (path_inv_basis * surface_normal_w).normalized()
		var v_tex_coord: float = 0.0
		if points_w.size() > 1: v_tex_coord = float(i) / float(points_w.size() - 1)

		st.set_normal(normal_local); st.set_uv(Vector2(1, v_tex_coord)); st.add_vertex(v_geo_right_local)
		st.set_normal(normal_local); st.set_uv(Vector2(0, v_tex_coord)); st.add_vertex(v_geo_left_local)

		if i > 0:
			var idx_prev_geo_right  = 2 * (i-1); var idx_prev_geo_left = idx_prev_geo_right + 1
			var idx_curr_geo_right  = 2 * i;     var idx_curr_geo_left = idx_curr_geo_right + 1
			st.add_index(idx_prev_geo_right); st.add_index(idx_curr_geo_right); st.add_index(idx_prev_geo_left)
			st.add_index(idx_curr_geo_right); st.add_index(idx_curr_geo_left); st.add_index(idx_prev_geo_left)

	var array_mesh: ArrayMesh = st.commit()
	if not is_instance_valid(array_mesh): return null
	var mesh_instance = MeshInstance3D.new(); mesh_instance.mesh = array_mesh
	
	if is_instance_valid(p_track_material): mesh_instance.material_override = p_track_material
	else:
		var default_mat = StandardMaterial3D.new()
		if is_instance_valid(p_track_png):
			default_mat.albedo_texture = p_track_png
			if p_texture_tile_length_v > 0.0 and p_chunk_actual_length > 0.0:
				default_mat.uv1_scale = Vector3(1, p_chunk_actual_length / p_texture_tile_length_v, 1)
		else: default_mat.albedo_color = Color.DARK_GRAY
		default_mat.metallic = 0.1; default_mat.roughness = 0.9
		mesh_instance.material_override = default_mat
	return mesh_instance
