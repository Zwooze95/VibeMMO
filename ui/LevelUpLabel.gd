extends Label

@onready var animation_player = $AnimationPlayer

func show_level_up(new_level: int):
	text = "LEVEL UP!\nLevel " + str(new_level)
	visible = true
	
	if animation_player and animation_player.has_animation("level_up"):
		animation_player.play("level_up")
	else:
		# Fallback if no animation
		await get_tree().create_timer(3.0).timeout
		visible = false

func _hide():
	visible = false
