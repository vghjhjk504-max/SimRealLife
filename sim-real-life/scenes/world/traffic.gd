class_name Traffic
extends Node3D
# Диспетчер тачек: спавн, вход/выход (сервер решает), сигнал, краш-FX.

const CAR_SCENE := preload("res://scenes/vehicles/car.tscn")

@onready var spawner: MultiplayerSpawner = $"../CarSpawner"
@onready var cars: Node3D = $"../Cars"
@onready var players: Node3D = $"../Players"

func _ready() -> void:
	spawner.spawn_function = _spawn_car
	if multiplayer.is_server():
		var L := City.layout()
		for i in L.cars.size():
			var d: Dictionary = L.cars[i]
			spawner.spawn({"id": i, "pos": d.pos, "rot": d.rot, "color": d.color})

func _spawn_car(data: Dictionary) -> Node:
	var c := CAR_SCENE.instantiate() as Car
	c.name = str(data.id)
	c.car_id = data.id
	c.paint = data.color
	c.position = data.pos
	c.rotation.y = data.rot
	return c

func nearest_free_car(pos: Vector3, max_dist := 4.5) -> Car:
	var best: Car = null
	var bd := max_dist
	for n in cars.get_children():
		var c := n as Car
		if c and c.driver_id == 0:
			var d := pos.distance_to(c.global_position)
			if d < bd:
				bd = d
				best = c
	return best

func release_driver(id: int) -> void:
	if not multiplayer.is_server():
		return
	for n in cars.get_children():
		var c := n as Car
		if c and c.driver_id == id:
			c.driver_id = 0
			c.forward_speed = 0.0

@rpc("any_peer", "call_local", "reliable")
func request_enter(cid: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var p := players.get_node_or_null(str(id)) as Player
	var c := cars.get_node_or_null(str(cid)) as Car
	if p == null or c == null:
		return
	if p.car_id != 0 or c.driver_id != 0 or p.is_dead():
		return
	if p.global_position.distance_to(c.global_position) > 4.5:
		return
	c.driver_id = id
	p.car_id = cid
	Sound.play3d(&"door", self, c.global_position, -4.0)

@rpc("any_peer", "call_local", "reliable")
func request_exit() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var p := players.get_node_or_null(str(id)) as Player
	if p == null or p.car_id == 0:
		return
	var c := cars.get_node_or_null(str(p.car_id)) as Car
	var pos := p.global_position + Vector3(2.5, 1.0, 0)
	if c:
		pos = _exit_pos(c)
		c.driver_id = 0
		c.forward_speed = 0.0
	p.car_id = 0
	rpc_id(id, &"exit_place", pos)
	if c:
		Sound.play3d(&"door", self, c.global_position, -4.0)

@rpc("authority", "call_local", "reliable")
func exit_place(pos: Vector3) -> void:
	var a := get_tree().get_nodes_in_group(&"local_player")
	if a.size() > 0:
		(a[0] as Player).place_at(pos)

@rpc("any_peer", "call_local", "reliable")
func honk(cid: int) -> void:
	var c := cars.get_node_or_null(str(cid)) as Car
	if c:
		c.honk()

@rpc("any_peer", "call_local", "reliable")
func crash_fx(pos: Vector3) -> void:
	Sound.play3d(&"crash", self, pos, -2.0)
	var cb := get_node_or_null("../Combat")
	if cb:
		cb._burst(pos, Color(1.0, 0.8, 0.4), 8)

func _exit_pos(c: Car) -> Vector3:
	var space := get_world_3d().direct_space_state
	for off in [Vector3(-2.5, 0.7, 0), Vector3(2.5, 0.7, 0), Vector3(0, 0.7, 3.4), Vector3(0, 2.4, 0)]:
		var p := c.global_transform * off
		var q := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.45
		q.shape = s
		q.transform = Transform3D(Basis.IDENTITY, p)
		q.collision_mask = 5
		q.exclude = [c.get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return Vector3(p.x, p.y + 0.2, p.z)
	return c.global_position + Vector3(0, 2.5, 0)