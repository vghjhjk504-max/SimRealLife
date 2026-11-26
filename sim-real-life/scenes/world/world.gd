extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

@onready var spawner: MultiplayerSpawner = $Spawner
@onready var players: Node3D = $Players
@onready var combat: Node = $Combat
@onready var traffic: Traffic = $Traffic

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
	var p := PLAYER_SCENE.instantiate() as Player
	p.name = str(data.id)
	p.nick = data.nick
	p.position = data.pos
	p.set_multiplayer_authority(data.id)
	return p

func _on_peer_left(id: int) -> void:
	_nicks.erase(id)
	combat.unregister(id)
	traffic.release_driver(id)
	var p := players.get_node_or_null(str(id))
	if p:
		p.queue_free()

func _build_city() -> void:
	var L := City.layout()
	var span := City.HALF * 2.0 + 8.0
	_box(Vector3(0, -0.5, 0), Vector3(span, 1, span), Color(0.13, 0.13, 0.15))
	for p in L.parks:
		_flat(Vector3(p.x, 0.015, p.y), Vector2(32, 32), Color(0.16, 0.34, 0.18))
	for line in City.ROAD_LINES:
		_flat(Vector3(line, 0.012, 0), Vector2(0.3, span), Color(0.75, 0.6, 0.2))
		_flat(Vector3(0, 0.012, line), Vector2(span, 0.3), Color(0.75, 0.6, 0.2))
	for b in L.buildings:
		_box(b.pos, b.size, b.color)
	for t in L.trees:
		_tree(t)
	for r in L.ramps:
		_ramp(r.pos, r.size, r.rot)
	# периметр — бетонные стены, чтоб тачки не улетали в нарнию
	var h := City.HALF + 2.0
	_box(Vector3(0, 1.25, -h), Vector3(span, 2.5, 1.5), Color(0.3, 0.3, 0.33))
	_box(Vector3(0, 1.25, h), Vector3(span, 2.5, 1.5), Color(0.3, 0.3, 0.33))
	_box(Vector3(-h, 1.25, 0), Vector3(1.5, 2.5, span), Color(0.3, 0.3, 0.33))
	_box(Vector3(h, 1.25, 0), Vector3(1.5, 2.5, span), Color(0.3, 0.3, 0.33))

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

func _flat(pos: Vector3, size: Vector2, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	q.material = mat
	mi.mesh = q
	mi.rotation.x = -PI / 2.0
	mi.position = pos
	add_child(mi)

func _tree(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.3
	cm.height = 2.6
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.32, 0.22, 0.14)
	cm.material = tm
	trunk.mesh = cm
	trunk.position.y = 1.3
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.3
	cs.height = 2.6
	col.shape = cs
	col.position.y = 1.3
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.7
	sm.height = 3.0
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.18, 0.42, 0.2)
	sm.material = gm
	crown.mesh = sm
	crown.position.y = 3.4
	body.add_child(trunk)
	body.add_child(col)
	body.add_child(crown)
	add_child(body)

func _ramp(pos: Vector3, size: Vector3, rot_x: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.x = rot_x
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.55, 0.2)
	bm.material = mat
	mi.mesh = bm
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	body.add_child(mi)
	body.add_child(col)
	add_child(body)