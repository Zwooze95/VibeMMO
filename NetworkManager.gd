extends Node

signal on_player_joined(id, x, y)
signal on_player_moved(id, x, y)
signal on_player_left(id)
signal on_connected()

var socket = WebSocketPeer.new()
var http_request = HTTPRequest.new()
var server_url = "http://localhost:2567"
var ws_url = "ws://localhost:2567"
var room_name = "my_room"
var session_id = ""
var _was_connected = false
var my_numeric_id = 0

func _ready():
	add_child(http_request)
	http_request.request_completed.connect(_on_seat_reserved)
	
	print("[NetworkManager] Bokar plats via HTTP...")
	var url = server_url + "/matchmake/joinOrCreate/" + room_name
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, "{}")
	
	if error != OK:
		print("[NetworkManager] HTTP request failed: ", error)

func _on_seat_reserved(_result, response_code, _headers, body):
	if response_code != 200:
		print("[NetworkManager] Booking failed. Code: ", response_code)
		return
	
	var json_str = body.get_string_from_utf8()
	print("[NetworkManager] Svar från server: ", json_str) # Bra debug!
	
	var json = JSON.new()
	var error_code = json.parse(json_str) # <--- Detta returnerar en INT (Error code)
	
	if error_code != OK:
		print("[NetworkManager] JSON parse error on line ", json.get_error_line())
		print("Error message: ", json.get_error_message())
		return
	
	# HÄR hämtar vi den faktiska datan
	var data = json.data # <--- Detta är din Dictionary
	
	print("[NetworkManager] Seat reserved! Data: ", data)
	
	# Nu kan vi läsa sessionId utan att det kraschar
	if data.has("sessionId"):
		session_id = data["sessionId"]
		
		var room_data = data["room"]
		var process_id = room_data["processId"]
		var room_id = room_data["roomId"]
		
		var connect_url = "%s/%s/%s?sessionId=%s" % [ws_url, process_id, room_id, session_id]
		print("[NetworkManager] Connecting to: ", connect_url)
		
		var err = socket.connect_to_url(connect_url)
		if err != OK:
			print("[NetworkManager] WS connection failed: ", err)
		else:
			print("[NetworkManager] WS connecting...")
	else:
		print("[NetworkManager] Error: JSON saknar 'sessionId'")

func _process(_delta):
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet() # PackedByteArray
			
			if socket.was_string_packet():
				# Hybrid: Vi kan fortfarande ta emot JSON (t.ex. Welcome)
				var text = packet.get_string_from_utf8()
				_handle_json_message(text)
			else:
				# BINÄRT! Här händer magin.
				_handle_binary_message(packet)

func _handle_binary_message(bytes: PackedByteArray):
	# === DEBUG: Visa rå bytes ===
	print("[NetworkManager] Binärt paket! Längd: ", bytes.size(), " bytes")
	var hex_str = ""
	for b in bytes:
		hex_str += "%02X " % b
	print("[NetworkManager] Raw bytes: ", hex_str)
	
	# === FELHANTERING: Kolla att vi har minst 1 byte (OpCode) ===
	if bytes.size() < 1:
		print("[NetworkManager] ERROR: Tom buffert!")
		return
	
	# === Skapa StreamPeerBuffer och läs data ===
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = bytes
	
	# 1. Läs första byten (OpCode)
	var op_code = buffer.get_u8()
	print("[NetworkManager] OpCode: ", op_code)
	
	match op_code:
		1: # JOIN (11 bytes: 1 op + 2 id + 4 x + 4 y)
			if bytes.size() < 11:
				print("[NetworkManager] ERROR: JOIN-paket för kort! Behöver 11 bytes, fick ", bytes.size())
				return
			var pId = buffer.get_u16() # Läs 2 bytes
			var x = buffer.get_float() # Läs 4 bytes
			var y = buffer.get_float() # Läs 4 bytes
			print("[NetworkManager] JOIN: ID=%d, X=%.2f, Y=%.2f" % [pId, x, y])
			on_player_joined.emit(pId, x, y)
			
		2: # MOVE (11 bytes)
			if bytes.size() < 11:
				print("[NetworkManager] ERROR: MOVE-paket för kort! Behöver 11 bytes, fick ", bytes.size())
				return
			var pId = buffer.get_u16()
			var x = buffer.get_float()
			var y = buffer.get_float()
			print("[NetworkManager] MOVE: ID=%d, X=%.2f, Y=%.2f" % [pId, x, y])
			on_player_moved.emit(pId, x, y)
			
		3: # LEAVE (3 bytes: 1 op + 2 id)
			if bytes.size() < 3:
				print("[NetworkManager] ERROR: LEAVE-paket för kort! Behöver 3 bytes, fick ", bytes.size())
				return
			var pId = buffer.get_u16()
			print("[NetworkManager] LEAVE: ID=%d" % pId)
			on_player_left.emit(pId)
		
		_:
			print("[NetworkManager] ERROR: Okänd OpCode: ", op_code)

func _handle_json_message(json_str):
	var json = JSON.new()
	json.parse(json_str)
	var data = json.data
	if data.get("type") == "welcome":
		my_numeric_id = data.myId
		print("Jag har fått ID: ", my_numeric_id)

# Hämta mitt numeriska ID
func get_my_id() -> int:
	return my_numeric_id

# Skicka move som JSON (servern förväntar sig detta format just nu)
func send_move(x, y):
	var msg = {"type": "move", "x": x, "y": y}
	socket.send_text(JSON.stringify(msg))

# ALTERNATIV: Skicka binär move (om du vill implementera binär INPUT också)
# Du måste då ändra servern för att ta emot binärt istället för JSON
func send_move_binary(x: float, y: float):
	var buffer = StreamPeerBuffer.new()
	# Skapa paket: 1 byte (OP) + 4 bytes (X) + 4 bytes (Y) = 9 bytes
	buffer.put_u8(2) # OpCode för MOVE
	buffer.put_float(x) # X position
	buffer.put_float(y) # Y position
	socket.send(buffer.data_array)
