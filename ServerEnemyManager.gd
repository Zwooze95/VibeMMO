extends Node3D

# Denna manager lyssnar på NetworkManager istället för gamla multiplayer-systemet
# Servern bestämmer när och var fiender spawnas

@export var enemy_scenes: Array[PackedScene] = [] # Lägg till olika enemy scenes här
@onready var enemies_container = $Enemies

var spawned_enemies = {} # { enemyId: enemy_node }

func _ready():
	print("[ServerEnemyManager] Lyssnar på NetworkManager...")
	
	# Koppla till NetworkManager's signaler
	NetworkManager.on_enemy_spawned.connect(_on_enemy_spawned)
	NetworkManager.on_enemy_died.connect(_on_enemy_died)

func _on_enemy_spawned(enemy_id: int, x: float, y: float, type: int):
	print("[ServerEnemyManager] Spawnar enemy ID: ", enemy_id, " vid (", x, ", ", y, ") typ: ", type)
	
	# Välj rätt enemy scene baserat på type
	var enemy_scene: PackedScene
	if type < enemy_scenes.size() and type >= 0:
		enemy_scene = enemy_scenes[type]
	else:
		print("[ServerEnemyManager] WARNING: Ingen enemy scene för typ ", type)
		return
	
	# Spawna fienden
	var enemy = enemy_scene.instantiate()
	enemy.name = str(enemy_id) # Sätt namn till ID för att hitta den senare
	enemy.position = Vector3(x, 1, y) # Z är Y i 2D-termer
	
	# Lägg till i container
	enemies_container.add_child(enemy)
	spawned_enemies[enemy_id] = enemy
	
	# Koppla death-event om fienden har ett
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(func(): _on_local_enemy_died(enemy_id))

func _on_local_enemy_died(enemy_id: int):
	# En fiende dog lokalt (spelaren slog den)
	# Meddela servern
	print("[ServerEnemyManager] Local enemy died: ", enemy_id, " - meddelar servern")
	NetworkManager.send_enemy_death(enemy_id)

func _on_enemy_died(enemy_id: int):
	# Servern säger att fienden ska tas bort
	print("[ServerEnemyManager] Server säger: Enemy ", enemy_id, " död - tar bort")
	
	if spawned_enemies.has(enemy_id):
		var enemy = spawned_enemies[enemy_id]
		
		# Kolla om noden fortfarande är valid (kan redan vara borta)
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy.queue_free()
		
		spawned_enemies.erase(enemy_id)
