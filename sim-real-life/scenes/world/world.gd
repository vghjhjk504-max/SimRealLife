extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

@onready var spawner: MultiplayerSpawner = $Spawner
@onready var players: Node3D = $Players
@onready var combat: Node = $Combat

var _nicks: Dictionary = {}

func _ready() -> void:
	_build_city()
	add_child(HUD_SCENE.instantiate())
	spawner.spawn_function = _spawn_player
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left)
		_nicks[1] = Net.nickname
		_spawn_for(1)
	else:
		rpc_id(1, &"_im_ready", Net.nickname)

@rpc("any_peer", "call_remote", "reliable")
func _im_ready(nick: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has_node(str(id)):
		return
	_nicks[id] = nick.strip_edges().substr(0, 24)
	_spawn_for(id)

func _spawn_for(id: int) -> void:
	var a := randf() * TAU
	spawner.spawn({
		"id": id,
		"nick": _nicks.get(id, "Бро"),
		"pos": Vector3(cos(a) * 5.0, 1.0, sin(a) * 5.0),
	})
	combat.register(id)

func _spawn_player(data: Dictionary) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data.id)
	p.nick = data.nick
	p.position = data.pos
	p.set_multiplayer_authority(data.id)
	return p

func _on_peer_left(id: int) -> void:
	_nicks.erase(id)
	combat.unregister(id)
	var p := players.get_node_or_null(str(id))
	if p:
		p.queue_free()

func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Color(0.16, 0.16, 0.18))
	var palette := [
		Color(0.55, 0.5, 0.45), Color(0.4, 0.42, 0.5),
		Color(0.6, 0.55, 0.5), Color(0.35, 0.3, 0.32),
	]
	for i in 26:
		var x := rng.randf_range(-34.0, 34.0)
		var z := rng.randf_range(-34.0, 34.0)
		if Vector2(x, z).length() < 9.0:
			continue
		var w := rng.randf_range(2.5, 6.0)
		var h := rng.randf_range(3.0, 14.0)
		var d := rng.randf_range(2.5, 6.0)
		_box(Vector3(x, h * 0.5, z), Vector3(w, h, d), palette[i % palette.size()])

func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	mesh_inst.mesh = mesh
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(mesh_inst)
	body.add_child(col)
	add_child(body)