extends Node3D

const HitParticles = preload("res://HitParticles.tscn")
@onready var anim = $AnimationPlayer
@onready var collision_area = $Sprite3D/Area3D

func swing():
	if not anim.is_playing():
		anim.play("swing")
		

func _on_area_3d_body_entered(body):
	if body == get_parent():
		return # Don't hit yourself!
		
	if body.has_node("HealthComponent"):
		var health = body.get_node("HealthComponent")
		var attacker = get_parent() # The player wielding the weapon
		health.damage(10.0, attacker)
		print("Hit ", body.name)
		
		# Spawn Particles
		var particles = HitParticles.instantiate()
		get_tree().root.add_child(particles)
		particles.global_position = global_position
		# Offset slightly to verify hit location near tip
		particles.global_position += -global_transform.basis.z * 0.5
