extends Node3D

@onready var players_node = $Players
@onready var spawner = $MultiplayerSpawner

func _ready():
	print("[Main] Main scene redo. Lyssnar på NetworkManager...")
	
	# Koppla signaler
	NetworkManager.on_player_joined.connect(_on_player_joined)
	NetworkManager.on_player_moved.connect(_on_player_moved)
	NetworkManager.on_player_left.connect(_on_player_left)
	
	# VIKTIGT FÖR NYANSLUTNING:
	# Om vi anslöt innan denna scen laddades klart, be NetworkManager skicka infon igen
	# Eller (enklare): NetworkManager borde redan ha en lista på spelare om du byter scener.
	# Men för detta demo, låt oss bara se om printen kommer.

func _on_player_joined(id, x, y):
	print("[Main] _on_player_joined anropades för ID: ", id) # <--- KOMMER DENNA?
	
	var player_scene = load("res://Player.tscn")
	var player = player_scene.instantiate()
	player.name = str(id)
	player.position = Vector3(x, 5, y) # Z är Y i 2D
	
	players_node.add_child(player)
	
	# Kolla om detta är vår lokala spelare
	if id == NetworkManager.get_my_id():
		print("Detta är min gubbe! Aktiverar styrning.")
		# Antag att ditt Player.gd har en funktion 'setup_local_player()'
		# eller att du sätter en variabel is_local_player = true
		if player.has_method("setup_local_player"):
			player.setup_local_player()
		else:
			# Fallback om du inte har den funktionen än
			player.set_process_input(true)
			# player.get_node("Camera3D").current = true # Om du har kamera
	else:
		# Andra spelare ska inte styras av tangentbordet
		player.set_process_input(false)

func _on_player_left(id):
	if players_node.has_node(str(id)):
		players_node.get_node(str(id)).queue_free()

func _on_player_moved(id, x, y):
	var player = players_node.get_node_or_null(str(id))
	if player:
		# Interpolation could be added here, currently snapping
		player.position.x = x
		player.position.z = y
