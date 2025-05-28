# Filename: TrackSegmentData.gd
class_name TrackSegmentData
extends RefCounted

var id: int = -1                         # Assigned by TrackManager
var type: String = "unknown"
var length: float = 0.0

var points_w: Array[Vector3] = []      # Populated by TrackSegmentGenerator
var end_tangent_w: Vector3 = Vector3.FORWARD # Set by TrackSegmentGenerator

var path_3d_node: Path3D = null          # <<<< ADDED: Assigned by TrackManager
var mesh_instance: MeshInstance3D = null # Assigned by TrackManager (via TrackMeshBuilder)

# These were in your original TrackSegmentData definition.
# Keep them if they are used by your TrackSegmentGenerator or TrackMeshBuilder.
var points_count_in_curve: int = 0
var start_curve_idx_in_main_curve: int = 0

func _init(p_type: String = "unknown", p_length: float = 0.0):
	self.type = p_type
	self.length = p_length
	# points_w is typically populated by the generator after instantiation.
	# end_tangent_w is also set by the generator.

func clear_mesh():
	if is_instance_valid(mesh_instance):
		var parent = mesh_instance.get_parent()
		# Ensure mesh_instance is indeed a child of 'parent' before removing.
		if is_instance_valid(parent) and mesh_instance.get_parent() == parent:
			parent.remove_child(mesh_instance)
		mesh_instance.queue_free() # Use queue_free() for nodes for safer, deferred deletion.
		mesh_instance = null
