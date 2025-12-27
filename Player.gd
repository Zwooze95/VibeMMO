extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var username = "Player":
	set(value):
		username = value
		if is_node_ready():
			label_3d.text = username

@onready var animation_player = $AnimationPlayer
@onready var sprite_3d = $Sprite3D
@onready var weapon = $WeaponPivot
@onready var camera = $Camera3D
@onready var label_3d = $Label3D
@onready var chat_bubble = $ChatBubble
@onready var chat_timer = $ChatTimer
@onready var leveling_component = $LevelingComponent

var is_local = false # Sätts till true om detta är vår lokala spelare

func _ready():
	# Lyssna på när vi får vårt ID från servern
	NetworkManager.on_my_id_received.connect(_on_my_id_received)
	
	# Kolla om NetworkManager redan har ett ID (för spelare som spawnar sent)
	var my_id = NetworkManager.get_my_id()
	if my_id > 0:
		_on_my_id_received(my_id)
	
	# Update label initially (in case synced before ready)
	update_nameplate()
	
	# Connect Timer
	chat_timer.timeout.connect(_on_chat_timeout)
	
	# Connect Leveling signals
	if leveling_component:
		leveling_component.leveled_up.connect(_on_leveled_up)
		leveling_component.level_changed.connect(_on_level_changed)
	
	# Delay UI check to avoid race conditions
	get_tree().create_timer(0.1).timeout.connect(_check_ui_authority)

func _on_my_id_received(my_id: int):
	# Nu vet vi vårt ID, kolla om detta är vår lokala spelare
	var player_id = int(name) # name är satt till ID i MainScene
	is_local = (player_id == my_id)
	
	print("[Player] Player ", name, " ID received. is_local=", is_local, " (my_id=", my_id, ")")
	
	# Sätt kamera för lokal spelare
	if camera:
		camera.current = is_local


func _check_ui_authority():
	if not is_local:
		if has_node("CanvasLayer"):
			var ui = get_node("CanvasLayer")
			ui.visible = false
			ui.process_mode = Node.PROCESS_MODE_DISABLED
			ui.queue_free()


func _on_chat_timeout():
	chat_bubble.text = ""

func _on_leveled_up(new_level: int):
	print(username, " leveled up to level ", new_level)
	update_nameplate()
	
	# Show level-up notification if we have UI
	if has_node("CanvasLayer/LevelUpLabel"):
		var level_up_label = get_node("CanvasLayer/LevelUpLabel")
		level_up_label.show_level_up(new_level)

func _on_level_changed(_new_level: int, _old_level: int):
	update_nameplate()

func update_nameplate():
	if leveling_component:
		label_3d.text = username + " [Lvl " + str(leveling_component.current_level) + "]"
	else:
		label_3d.text = username

@rpc("call_local", "any_peer", "reliable")
func speak(msg: String):
	# Update visual bubble
	chat_bubble.text = msg
	chat_timer.start(4.0)
	
	# Update global chat log
	get_tree().call_group("Chat", "add_log", username, msg)


func _physics_process(delta):
	# Debug every 60 frames (endast för lokal spelare)
	if Engine.get_frames_drawn() % 60 == 0:
		if is_local:
			print(name + " (Local) Pos: " + str(position) + " OnFloor: " + str(is_on_floor()))

	# NETWORK: Only move if this is the local player
	if not is_local:
		return # Do nothing! Server will send position updates.

	# Stop movement if typing in chat
	if get_viewport().gui_get_focus_owner():
		return

	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# ATTACK LOGIC (Space bar)
	# Hits are now handled by the Weapon's internal Area3D
	if Input.is_action_just_pressed("ui_accept"):
		swing_weapon.rpc()

	# DAMAGE TEST (Self)
	if Input.is_physical_key_pressed(KEY_K):
		var health_comp = get_node_or_null("HealthComponent")
		if health_comp:
			health_comp.damage(1.0) # Damage over time if held, or tap for 1 damage per frame

	# Get the input direction and handle the movement/deceleration.
	# We check for both UI actions (arrow keys) and physical keys (WASD) manually
	# to ensure it works without modifying the Input Map settings.
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1
	
	input_dir = input_dir.normalized()
	
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		
		# Animation: Walk
		animation_player.play("walk")
		
		# Flip Sprite based on X direction
		if direction.x < 0:
			sprite_3d.flip_h = true
			weapon.position.x = -0.4 # Move weapon to left
			weapon.scale.x = -1 # Flip weapon swing
		elif direction.x > 0:
			sprite_3d.flip_h = false
			weapon.position.x = 0.4 # Move weapon to right
			weapon.scale.x = 1 # Reset weapon swing
			
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		
		# Animation: Idle
		animation_player.play("idle")

	move_and_slide()
	
	# Send position to server if we moved (and are authority)
	if velocity.length() > 0:
		# Använd vårt egna binära protokoll
		NetworkManager.send_move_binary(position.x, position.z)

@rpc("call_local")
func swing_weapon():
	weapon.swing()
