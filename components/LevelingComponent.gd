class_name LevelingComponent
extends Node

signal level_changed(new_level, old_level)
signal xp_gained(amount, new_xp, xp_needed)
signal leveled_up(new_level)

@export var current_level: int = 1:
	set(value):
		var old_level = current_level
		current_level = value
		emit_signal("level_changed", current_level, old_level)

@export var current_xp: int = 0:
	set(value):
		current_xp = value
		emit_signal("xp_gained", 0, current_xp, get_xp_needed_for_next_level())

@export var base_xp_per_level: int = 100 # XP needed for level 2

func _ready():
	# Emit initial signals
	emit_signal("level_changed", current_level, current_level)
	emit_signal("xp_gained", 0, current_xp, get_xp_needed_for_next_level())

# Calculate XP needed to reach the next level
func get_xp_needed_for_next_level() -> int:
	return base_xp_per_level * current_level

# Add XP and handle level-ups
func add_xp(amount: int):
	if amount <= 0:
		return
	
	current_xp += amount
	emit_signal("xp_gained", amount, current_xp, get_xp_needed_for_next_level())
	
	# Check for level up
	while current_xp >= get_xp_needed_for_next_level():
		level_up()

# Handle leveling up
func level_up():
	var xp_needed = get_xp_needed_for_next_level()
	current_xp -= xp_needed
	
	var old_level = current_level
	current_level += 1
	
	emit_signal("leveled_up", current_level)
	emit_signal("level_changed", current_level, old_level)
	
	print("Level Up! Now level " + str(current_level))

# Get XP reward for killing an entity of a given level
static func calculate_xp_reward(enemy_level: int) -> int:
	return enemy_level * 50
