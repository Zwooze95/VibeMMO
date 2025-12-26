extends Node

signal on_player_joined(id, x, y)
signal on_player_moved(id, x, y)
signal on_player_left(id)
signal on_connected()
signal on_enemy_spawned(enemy_id, x, y, type)
signal on_enemy_died(enemy_id)
signal on_my_id_received(my_id) # Emitteras när vi får vårt ID från servern

var socket = WebSocketPeer.new()
var http_request = HTTPRequest.new()
var server_url = "http://localhost:2567"
var ws_url = "ws://localhost:2567"
var room_name = "my_room"
var session_id = ""
var _was_connected = false
var my_numeric_id = 0

enum OP {
	JOIN,
	MOVE,
	LEAVE,
	ENEMY_SPAWN,
	ENEMY_DEATH,
	COLYSEUS_JOIN_ROOM = 10,
	COLYSEUS_JOIN_ERROR = 11,
	COLYSEUS_LEAVE_ROOM = 12
}

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
			
			# DEBUG: Visa alla paket
			print("[NetworkManager] Packet received! Size: ", packet.size(), " is_string: ", socket.was_string_packet())
			
			if socket.was_string_packet():
				# Text-meddelande från Colyseus
				var text = packet.get_string_from_utf8()
				print("[NetworkManager] Text message: ", text)
				
				# Försök tolka som JSON
				var json = JSON.new()
				if json.parse(text) == OK:
					var data = json.data
					
					# Kolla om det är ett Colyseus message med type
					if data is Array and data.size() > 0:
						var msg_type = data[0]
						
						# "welcome" message
						if msg_type == "welcome":
							if data.size() > 1 and data[1] is Dictionary:
								var msg_data = data[1]
								if msg_data.has("myId"):
									my_numeric_id = msg_data.myId
									print("[NetworkManager] Jag har fått ID: ", my_numeric_id)
									on_my_id_received.emit(my_numeric_id)
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
		OP.JOIN: # JOIN (11 bytes: 1 op + 2 id + 4 x + 4 y)
			if bytes.size() < 11:
				print("[NetworkManager] ERROR: JOIN-paket för kort! Behöver 11 bytes, fick ", bytes.size())
				return
			var pId = buffer.get_u16() # Läs 2 bytes
			var x = buffer.get_float() # Läs 4 bytes
			var y = buffer.get_float() # Läs 4 bytes
			print("[NetworkManager] JOIN: ID=%d, X=%.2f, Y=%.2f" % [pId, x, y])
			on_player_joined.emit(pId, x, y)
			
		OP.MOVE: # MOVE (11 bytes)
			if bytes.size() < 11:
				print("[NetworkManager] ERROR: MOVE-paket för kort! Behöver 11 bytes, fick ", bytes.size())
				return
			var pId = buffer.get_u16()
			var x = buffer.get_float()
			var y = buffer.get_float()
			print("[NetworkManager] MOVE: ID=%d, X=%.2f, Y=%.2f" % [pId, x, y])
			on_player_moved.emit(pId, x, y)
			
		OP.LEAVE: # LEAVE (3 bytes: 1 op + 2 id)
			if bytes.size() < 3:
				print("[NetworkManager] ERROR: LEAVE-paket för kort! Behöver 3 bytes, fick ", bytes.size())
				return
			var pId = buffer.get_u16()
			print("[NetworkManager] LEAVE: ID=%d" % pId)
			on_player_left.emit(pId)
		
		OP.ENEMY_SPAWN: # ENEMY_SPAWN (14 bytes: 1 op + 4 id + 4 x + 4 y + 1 type)
			if bytes.size() < 14:
				print("[NetworkManager] ERROR: ENEMY_SPAWN-paket för kort! Behöver 14 bytes, fick ", bytes.size())
				return
			var enemyId = buffer.get_u32() # 4 bytes
			var x = buffer.get_float() # 4 bytes
			var y = buffer.get_float() # 4 bytes
			var type = buffer.get_u8() # 1 byte
			print("[NetworkManager] ENEMY_SPAWN: ID=%d, X=%.2f, Y=%.2f, Type=%d" % [enemyId, x, y, type])
			on_enemy_spawned.emit(enemyId, x, y, type)
		
		OP.ENEMY_DEATH: # ENEMY_DEATH (5 bytes: 1 op + 4 id)
			if bytes.size() < 5:
				print("[NetworkManager] ERROR: ENEMY_DEATH-paket för kort! Behöver 5 bytes, fick ", bytes.size())
				return
			var enemyId = buffer.get_u32()
			print("[NetworkManager] ENEMY_DEATH: ID=%d" % enemyId)
			on_enemy_died.emit(enemyId)
			
		OP.COLYSEUS_JOIN_ROOM:
			print("[NetworkManager] Connected to Colyseus Room confirmed.")
			
		OP.COLYSEUS_LEAVE_ROOM:
			print("[NetworkManager] Left Colyseus Room.")
		_:
			print("[NetworkManager] ERROR: Okänd OpCode: ", op_code)

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
	buffer.put_u8(OP.MOVE) # Använd OP enum istället för hårdkodat värde
	buffer.put_float(x) # X position (4 bytes)
	buffer.put_float(y) # Y position (4 bytes)
	socket.send(buffer.data_array)

# Skicka enemy death till servern (JSON för enkelhetens skull)
func send_enemy_death(enemy_id: int):
	var msg = {"enemyId": enemy_id}
	socket.send_text(JSON.stringify(msg))
