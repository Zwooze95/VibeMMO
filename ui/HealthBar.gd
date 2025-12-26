extends ProgressBar

@export var health_component: HealthComponent

func _ready():
	if health_component:
		initialize(health_component)

func initialize(component: HealthComponent):
	health_component = component
	health_component.health_changed.connect(_on_health_changed)
	
	# Initialize values
	max_value = health_component.max_health
	value = health_component.current_health

func _on_health_changed(new_value, _old_value, max_val):
	max_value = max_val
	value = new_value
