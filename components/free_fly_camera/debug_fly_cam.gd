extends Node3D

@onready var cam := $"Free fly camera/Camera3D"
@onready var tarackmanager: TrackManager

#func _ready() -> void:
	#tarackmanager = get_parent().get_node("TrackManager")
	#$"Free fly camera".set_physics_process(cam.current)
	#$"Free fly camera".set_process(cam.current)
	#tarackmanager.set_process(!cam.current)
	#tarackmanager.set_physics_process(!cam.current)
#
#func _input(event: InputEvent) -> void:
	#if Input.is_action_just_pressed("sprint"):
		#cam.current = !cam.current
		#$"Free fly camera".set_physics_process(cam.current)
		#$"Free fly camera".set_process(cam.current)
		#tarackmanager.set_process(!cam.current)
		#tarackmanager.set_physics_process(!cam.current)
