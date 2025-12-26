extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected

const PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1"

var local_username = "Player"
var players = {}
var player_info = {"name": "Player"}

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func join_game(address = ""):
	if address == "":
		address = DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error:
		return error
	multiplayer.multiplayer_peer = peer

func host_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, 32)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	
	_on_peer_connected(1)

func _on_peer_connected(id):
	print("Player connected: " + str(id))
	player_connected.emit(id, player_info)

func _on_peer_disconnected(id):
	print("Player disconnected: " + str(id))
	player_disconnected.emit(id)

func _on_connected_ok():
	print("Connected to server!")

func _on_connected_fail():
	print("Connection failed!")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()
