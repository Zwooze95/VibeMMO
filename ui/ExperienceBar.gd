extends ProgressBar

@export var leveling_component: LevelingComponent

@onready var level_label = $LevelLabel

func _ready():
	if leveling_component:
		initialize(leveling_component)

func initialize(component: LevelingComponent):
	leveling_component = component
	leveling_component.xp_gained.connect(_on_xp_gained)
	leveling_component.level_changed.connect(_on_level_changed)
	
	# Initialize values
	update_bar()

func _on_xp_gained(_amount, _new_xp, _xp_needed):
	update_bar()

func _on_level_changed(_new_level, _old_level):
	update_bar()

func update_bar():
	if not leveling_component:
		return
	
	var xp_needed = leveling_component.get_xp_needed_for_next_level()
	max_value = xp_needed
	value = leveling_component.current_xp
	
	# Update level label
	if level_label:
		level_label.text = "Lvl " + str(leveling_component.current_level)
