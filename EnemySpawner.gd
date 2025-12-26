extends Node3D

@export var enemy_scene: PackedScene
@export var max_enemies: int = 5
@export var spawn_area_size: Vector3 = Vector3(10, 0, 10)
@export var spawn_interval: float = 3.0

@onready var spawner = $MultiplayerSpawner
@onready var timer = $Timer

# We use a container node for enemies so the spawner only watches this
@onready var enemies_container = $Enemies

func _ready():
	# Register the custom spawn function (Must happen on ALL peers!)
	spawner.spawn_function = _spawn_enemy_setup

	# Debug on all peers
	enemies_container.child_entered_tree.connect(_on_enemy_spawned_client)

	# Only start spawning if we are an ACTIVE server (not offline unique_id=1)
	if is_active_server():
		start_spawning()
	else:
		# Wait for server specific signal or check periodically?
		# Easiest: Listen to MultiplayerManager to tell us when we host.
		var manager = get_node_or_null("/root/MultiplayerManager")
		if manager:
			# When we host, we "connect" as player 1
			manager.player_connected.connect(_on_player_connected)

func is_active_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func _on_player_connected(id, _info):
	# If ID 1 connects, that means WE just became the host
	if id == 1:
		start_spawning()

func start_spawning():
	print("EnemySpawner: Starting spawn loop on Server")
	timer.wait_time = spawn_interval
	timer.timeout.connect(_on_timer_timeout)
	timer.start()
	_spawn_needed_enemies()

# This function is run on ALL peers when the server calls spawner.spawn()
func _spawn_enemy_setup(data):
	var spawn_pos = data
	var enemy = enemy_scene.instantiate()
	enemy.position = spawn_pos
	# Note: Do NOT add_child here. MultiplayerSpawner does it automatically.
	return enemy

func _on_enemy_spawned_client(node):
	print("Enemy observed: " + str(node.name) + " at " + str(node.position))

func _on_timer_timeout():
	_spawn_needed_enemies()

func _spawn_needed_enemies():
	var current_count = enemies_container.get_child_count()
	if current_count < max_enemies:
		spawn_enemy()

func spawn_enemy():
	# Random position within bounds
	var random_x = randf_range(-spawn_area_size.x / 2, spawn_area_size.x / 2)
	var random_z = randf_range(-spawn_area_size.z / 2, spawn_area_size.z / 2)
	var spawn_pos = Vector3(random_x, 1, random_z)
	
	# Request the spawn (Server only)
	spawner.spawn(spawn_pos)
