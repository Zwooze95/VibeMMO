extends CharacterBody3D

@export var level: int = 1
@export var xp_reward: int = 50 # XP granted on death

@onready var health_component = $HealthComponent
@onready var sprite = $Sprite3D
@onready var health_bar_sprite = $HealthBarSprite
@onready var health_bar_viewport = $HealthBarSprite/SubViewport
@onready var health_bar = $HealthBarSprite/SubViewport/HealthBar

func _ready():
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	
	# Calculate XP reward based on level
	xp_reward = LevelingComponent.calculate_xp_reward(level)
	
	# Wire up the healthbar
	health_bar.initialize(health_component)
	
	# Assign viewport texture to sprite3d
	health_bar_sprite.texture = health_bar_viewport.get_texture()

func _on_died(killer):
	print("Enemy died!")
	
	# Award XP to the killer
	if killer and killer.has_node("LevelingComponent"):
		var leveling = killer.get_node("LevelingComponent")
		leveling.add_xp(xp_reward)
		print("Awarded ", xp_reward, " XP to ", killer.name)
	
	# Explicit RPC to ensure death on all clients
	if multiplayer.is_server():
		die.rpc()

@rpc("call_local", "authority", "reliable")
func die():
	queue_free()

func _on_damaged(_amount, _damager):
	# Flash White
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(10, 10, 10, 1), 0.05) # Super bright
	tween.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.05) # Back to normal White

@rpc("unreliable_ordered", "authority", "call_remote")
func update_pos(server_pos: Vector3):
	global_position = server_pos

func _physics_process(delta):
	# Only the server moves the enemies (authoritative physics)
	if multiplayer.is_server():
		# Add gravity so they don't float
		if not is_on_floor():
			velocity.y -= 9.8 * delta
			move_and_slide()
		
		# Send RPC to all clients
		update_pos.rpc(global_position)
