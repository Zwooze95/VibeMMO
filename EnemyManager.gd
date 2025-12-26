extends Node3D

@export var enemy_scene: PackedScene
@export var max_enemies: int = 5
@export var spawn_area_size: Vector3 = Vector3(10, 0, 10)
@export var spawn_interval: float = 3.0

@onready var spawner = $MultiplayerSpawner
@onready var timer = $Timer
@onready var enemies_container = $Enemies

func _ready():
	# Only server manages spawning
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		start_spawning()

# Removed _on_player_connected - not needed

func start_spawning():
	print("EnemyManager: Starting spawn loop")
	timer.wait_time = spawn_interval
	timer.timeout.connect(_on_timer_timeout)
	timer.start()
	_spawn_needed_enemies()

func _on_timer_timeout():
	_spawn_needed_enemies()

func _spawn_needed_enemies():
	if not multiplayer.is_server():
		return
		
	if enemies_container.get_child_count() < max_enemies:
		var x = randf_range(-spawn_area_size.x / 2, spawn_area_size.x / 2)
		var z = randf_range(-spawn_area_size.z / 2, spawn_area_size.z / 2)
		var spawn_pos = Vector3(x, 1, z)
		
		# Use standard spawning
		var enemy = enemy_scene.instantiate()
		enemy.position = spawn_pos
		enemies_container.add_child(enemy, true) # true = force_readable_name
