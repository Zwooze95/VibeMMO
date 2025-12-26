extends Node3D

@onready var players_node = $Players
@onready var spawner = $MultiplayerSpawner

func _ready():
	# Access Autoload dynamically to prevent compile issues
	var mp_manager = get_node("/root/MultiplayerManager")
	
	mp_manager.player_connected.connect(_on_player_connected)
	mp_manager.player_disconnected.connect(_on_player_disconnected)
	
	# If host, do NOT spawn self (Dedicated Host mode)
	if multiplayer.is_server():
		# Create a spectator camera so the Host can see the world
		var cam = Camera3D.new()
		cam.position = Vector3(0, 10, 10)
		cam.rotation_degrees = Vector3(-45, 0, 0)
		add_child(cam)
		cam.current = true


func _on_player_connected(id, _info):
	# Only the server spawns player scenes
	if not multiplayer.is_server():
		return
		
	# Dedicated Host: Do not spawn a player for the server itself (ID 1)
	if id == 1:
		return
		
	var player_scene = load("res://Player.tscn")
	var player = player_scene.instantiate()
	player.name = str(id) # Set name to peer ID for authority
	player.position = Vector3(0, 5, 0) # Spawn high in the air
	players_node.add_child(player)

func _on_player_disconnected(id):
	if not multiplayer.is_server():
		return
	if players_node.has_node(str(id)):
		players_node.get_node(str(id)).queue_free()
