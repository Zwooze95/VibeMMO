class_name HealthComponent
extends Node

signal health_changed(new_value, old_value, max_value)
signal damaged(amount, damager)
signal healed(amount)
signal died(last_damager)

@export var max_health: float = 100.0
@export var immortal: bool = false

var last_damager: Node = null

var current_health: float:
	set(value):
		var old_health = current_health
		current_health = value
		emit_signal("health_changed", current_health, old_health, max_health)
		if current_health <= 0 and old_health > 0:
			emit_signal("died", last_damager)

func _ready():
	current_health = max_health
	emit_signal("health_changed", current_health, current_health, max_health)

func damage(amount: float, damager: Node = null):
	if immortal:
		return
	
	last_damager = damager
	current_health = clamp(current_health - amount, 0, max_health)
	emit_signal("damaged", amount, damager)

func heal(amount: float):
	current_health = clamp(current_health + amount, 0, max_health)
	emit_signal("healed", amount)
