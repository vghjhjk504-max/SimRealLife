extends Node
# Autoload "Net" — единый ди-джей всей сети.

const PORT := 27015
const MAX_PLAYERS := 16
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"

signal join_failed

var nickname := "Бро"
var parting_msg := ""

func _ready() -> void:
	_setup_input()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(WORLD_SCENE)
	return OK

func join(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func back_to_menu(msg := "") -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	parting_msg = msg
	get_tree().change_scene_to_file(MENU_SCENE)

func lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"

func _on_connected() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit()

func _on_server_disconnected() -> void:
	back_to_menu("Хост закрыл сессию, дым рассеялся...")

func _setup_input() -> void:
	var binds := {
		&"move_forward": KEY_W, &"move_back": KEY_S,
		&"move_left": KEY_A, &"move_right": KEY_D,
		&"jump": KEY_SPACE, &"sprint": KEY_SHIFT,
		&"reload": KEY_R, &"weapon_1": KEY_1, &"weapon_2": KEY_2,
		&"weapon_3": KEY_3, &"weapon_wheel": KEY_TAB, &"mute": KEY_M,
	}
	for action: StringName in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = binds[action]
		InputMap.action_add_event(action, ev)
	if not InputMap.has_action(&"fire"):
		InputMap.add_action(&"fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(&"fire", mb)