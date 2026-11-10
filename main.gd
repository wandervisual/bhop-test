extends Node3D

const PORT = 7000
var peer = ENetMultiplayerPeer.new()

@export var player_scene: PackedScene = preload("res://player.tscn")

var canvas: CanvasLayer
var nickname_input: LineEdit
var current_nickname: String = "Игрок"

func _ready():
	OS.low_processor_usage_mode = false
	create_menu()

func create_menu():
	if canvas: canvas.queue_free()
	canvas = CanvasLayer.new()
	add_child(canvas)
	
	nickname_input = LineEdit.new()
	nickname_input.placeholder_text = "Введите ваш ник..."
	nickname_input.text = current_nickname
	nickname_input.size = Vector2(300, 50)
	nickname_input.position = Vector2(50, 50)
	canvas.add_child(nickname_input)
	
	var btn_host = Button.new()
	btn_host.text = "Создать server (Host)"
	btn_host.size = Vector2(300, 50)
	btn_host.position = Vector2(50, 120)
	btn_host.pressed.connect(start_host)
	canvas.add_child(btn_host)
	
	var btn_join = Button.new()
	btn_join.text = "Подключиться (Client)"
	btn_join.size = Vector2(300, 50)
	btn_join.position = Vector2(50, 190)
	btn_join.pressed.connect(start_client)
	canvas.add_child(btn_join)

func save_nickname():
	if nickname_input and nickname_input.text != "":
		current_nickname = nickname_input.text

# УМНАЯ АВТОУЗНАЙКА IP ДЛЯ АВТОПОДКЛЮЧЕНИЯ
func get_target_ip() -> String:
	# Если мы запускаем на ПК два окна, то для второго окна используем локалхост
	if not DisplayServer.is_touchscreen_available():
		return "127.0.0.1"
		
	# Если мы на телефоне, сканируем сеть, чтобы найти базовый IP компа
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			# Берем подсеть телефона (например, 192.168.11.X)
			var parts = ip.split(".")
			if parts.size() == 4:
				# Подставляем вместо последней цифры адрес твоего хоста. 
				# В прошлый раз твой комп выдал 192.168.11.246, так что забиваем жестко финал!
				return parts[0] + "." + parts[1] + "." + parts[2] + ".246"
	
	return "127.0.0.1"

func start_host():
	save_nickname()
	
	if canvas: canvas.queue_free()
	
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	add_player(multiplayer.get_unique_id())

func start_client():
	save_nickname()
	
	# Умный автовыбор: на ПК пойдет на 127.0.0.1, а на телефоне САМ постучится на твой комп!
	var target_ip = get_target_ip()
	print("Автоподключение ломится на IP: ", target_ip)
	
	if canvas: canvas.queue_free()
	peer.create_client(target_ip, PORT)
	multiplayer.multiplayer_peer = peer
	
	multiplayer.connected_to_server.connect(func():
		rpc_id(1, "send_nickname_to_server", multiplayer.get_unique_id(), current_nickname)
	)

func add_player(id: int):
	if player_scene:
		var player = player_scene.instantiate()
		player.name = str(id)
		player.position = Vector3(randf_range(-3, 3), 10.0, randf_range(-3, 3))
		
		if id == multiplayer.get_unique_id():
			player.player_nickname = current_nickname
			
		add_child(player)

func remove_player(id: int):
	var player = get_node_or_null(str(id))
	if player:
		player.queue_free()

@rpc("any_peer", "call_local")
func send_nickname_to_server(id: int, new_nickname: String):
	var player = get_node_or_null(str(id))
	if player:
		player.player_nickname = new_nickname
