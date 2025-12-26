extends Node

const Colyseus = preload("res://addons/godot_colyseus/lib/colyseus.gd")

# --- SCHEMA DEFINITIONS ---

class PlayerSchema extends Colyseus.Schema:
	static func define_fields():
		return [
			Colyseus.Field.new("x", Colyseus.NUMBER),
			Colyseus.Field.new("y", Colyseus.NUMBER)
		]
	
	func _to_string():
		return str("Player(", self.x, ",", self.y, ")")

class RoomStateSchema extends Colyseus.Schema:
	static func define_fields():
		return [
			Colyseus.Field.new("players", Colyseus.MAP, PlayerSchema)
		]

# --- NETWORK MANAGER ---

# Colyseus variables
var client
var room
var players = {} 

# Signals
signal on_player_joined(id, x, y)
signal on_player_moved(id, x, y)
signal on_player_left(id)
signal on_connected()

func _ready():
	client = Colyseus.Client.new("ws://localhost:2567")
	connect_to_server()

func connect_to_server():
	print("Connecting to server...")
	# Join 'my_room' using our RoomStateSchema to decode the state
	var promise = client.join_or_create(RoomStateSchema, "my_room")
	await promise.completed
	
	if promise.get_state() == Colyseus.Promise.State.Failed:
		print("Failed to connect:", promise.get_error())
		return

	room = promise.get_data()
	print("Connected to room!")
	
	# Setup listeners
	var state = room.get_state()
	state.listen("players:add").on(Callable(self, "_on_player_add"))
	state.listen("players:remove").on(Callable(self, "_on_player_remove"))
	
	on_connected.emit()

func send_move(x: float, y: float):
	if room:
		room.send("move", { "x": x, "y": y })

func get_my_id():
	if room:
		return room.session_id
	return ""

# --- EVENT HANDLERS ---

func _on_player_add(state, value, key):
	# 'value' is the PlayerSchema instance, 'key' is the session ID
	print("Player joined: " + key)
	on_player_joined.emit(key, value.x, value.y)
	
	# Listen for changes on this specific player schema instance
	value.listen(":change").on(Callable(self, "_on_player_change").bind(key))

func _on_player_remove(state, value, key):
	print("Player left: " + key)
	on_player_left.emit(key)

func _on_player_change(player_schema, key):
	# 'player_schema' is the target object that changed
	on_player_moved.emit(key, player_schema.x, player_schema.y)
