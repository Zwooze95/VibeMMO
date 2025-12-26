extends CanvasLayer

@onready var host_btn = $VBoxContainer/HostButton
@onready var join_btn = $VBoxContainer/JoinButton
@onready var address_entry = $VBoxContainer/AddressEntry
@onready var name_entry = $VBoxContainer/NameEntry

func _ready():
	print("MultiplayerUI: _ready called")
	
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	name_entry.text_changed.connect(_on_name_changed)
	
	# Initial validation
	_on_name_changed(name_entry.text)

func _on_name_changed(new_text):
	if new_text.length() > 10:
		name_entry.text = new_text.substr(0, 10)
		name_entry.caret_column = 10
	
	var is_valid = name_entry.text.strip_edges().length() > 0
	host_btn.disabled = not is_valid
	join_btn.disabled = not is_valid

func _update_manager_name():
	var manager = get_node("/root/MultiplayerManager")
	var name_text = name_entry.text.strip_edges()
	if name_text == "":
		name_text = "Player"
	manager.local_username = name_text

func _on_host_pressed():
	_update_manager_name()
	get_node("/root/MultiplayerManager").host_game()
	visible = false

func _on_join_pressed():
	_update_manager_name()
	get_node("/root/MultiplayerManager").join_game(address_entry.text)
	visible = false
