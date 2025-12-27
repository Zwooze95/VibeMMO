extends CharacterBody3D

signal enemy_died() # Emittera när fienden dör så ServerEnemyManager kan meddela servern

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
	
	# Emittera signal FÖRST så ServerEnemyManager kan meddela servern
	enemy_died.emit()
	
	# Vänta en frame innan vi tar bort noden
	await get_tree().process_frame
	
	# Ta bort fienden
	queue_free()

func _on_damaged(_amount, _damager):
	# Flash White
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(10, 10, 10, 1), 0.05) # Super bright
	tween.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.05) # Back to normal White

func _physics_process(delta):
	# Alla klienter kör samma physics (fiender rör sig inte, bara faller)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		move_and_slide()
