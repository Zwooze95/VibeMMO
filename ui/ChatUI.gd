extends Control

@onready var chat_log = $PanelContainer/VBoxContainer/RichTextLabel
@onready var input_field = $PanelContainer/VBoxContainer/LineEdit

func _ready():
	input_field.text_submitted.connect(_on_text_submitted)
	NetworkManager.on_chat_received.connect(add_log)
	add_to_group("Chat")

func _input(event):
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		if not input_field.has_focus():
			input_field.grab_focus()
			get_viewport().set_input_as_handled()
		else:
			# If empty and hit enter, just release focus
			if input_field.text.strip_edges() == "":
				input_field.release_focus()

func _on_text_submitted(text):
	if text.strip_edges() == "":
		input_field.release_focus()
		return

	NetworkManager.send_chat(text)
	input_field.text = ""
	input_field.release_focus()

# Called via Group call from Player.gd
func add_log(sender_name: String, msg: String):
	chat_log.text += "\n[b]" + sender_name + ":[/b] " + msg
	# Auto scroll logic handled by scroll_following property 
