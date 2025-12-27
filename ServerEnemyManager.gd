extends Node3D

# Denna manager lyssnar på NetworkManager istället för gamla multiplayer-systemet
# Servern bestämmer när och var fiender spawnas

@export var enemy_scenes: Array[PackedScene] = [] # Lägg till olika enemy scenes här
@onready var enemies_container = $Enemies

var spawned_enemies = {} # { enemyId: enemy_node }
var recent_local_damage = {} # { enemyId: timestamp } - för att undvika double-damage

func _ready():
	print("[ServerEnemyManager] Lyssnar på NetworkManager...")
	
	# Koppla till NetworkManager's signaler
	NetworkManager.on_enemy_spawned.connect(_on_enemy_spawned)
	NetworkManager.on_enemy_died.connect(_on_enemy_died)
	NetworkManager.on_enemy_damaged.connect(_on_enemy_damaged)

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
	
	# Koppla damage-event om fienden har HealthComponent
	if enemy.has_node("HealthComponent"):
		var health_comp = enemy.get_node("HealthComponent")
		if health_comp.has_signal("damaged"):
			health_comp.damaged.connect(func(amount, _damager): _on_local_enemy_damaged(enemy_id, amount))

func _on_local_enemy_damaged(enemy_id: int, damage: float):
	# En fiende tog skada lokalt - meddela servern
	print("[ServerEnemyManager] Local enemy ", enemy_id, " took ", damage, " damage - meddelar servern")
	
	# Markera att vi just slog denna fiende (för att ignorera server echo)
	recent_local_damage[enemy_id] = Time.get_ticks_msec()
	
	NetworkManager.send_enemy_damage(enemy_id, damage)

func _on_enemy_damaged(enemy_id: int, damage: float):
	# Servern säger att fienden tog skada - applicera damage
	print("[ServerEnemyManager] Server säger: Enemy ", enemy_id, " tog ", damage, " damage")
	
	# Kolla om vi själva slog denna fiende nyligen (inom 100ms)
	if recent_local_damage.has(enemy_id):
		var time_since = Time.get_ticks_msec() - recent_local_damage[enemy_id]
		if time_since < 100:
			print("[ServerEnemyManager] Ignorerar server damage (echo från local hit)")
			recent_local_damage.erase(enemy_id)
			return
		else:
			recent_local_damage.erase(enemy_id)
	
	if spawned_enemies.has(enemy_id):
		var enemy = spawned_enemies[enemy_id]
		
		if is_instance_valid(enemy):
			# Applicera damage på HealthComponent (utan att trigga signal igen)
			if enemy.has_node("HealthComponent"):
				var health_comp = enemy.get_node("HealthComponent")
				# Applicera damage direkt utan att trigga damaged signal
				health_comp.current_health -= damage
				health_comp.current_health = max(0, health_comp.current_health)
				
				# Visa damage animation
				if enemy.has_method("_on_damaged"):
					enemy._on_damaged(damage, null)
				
				# Kolla om fienden dog (men skicka INTE death till servern igen)
				if health_comp.current_health <= 0 and not enemy.is_queued_for_deletion():
					print("[ServerEnemyManager] Enemy ", enemy_id, " dog från remote damage")
					# Servern kommer skicka ENEMY_DEATH snart, så vi väntar på det


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
