class_name Car
extends CharacterBody3D
# Аркадная тачка: водитель — authority, пустая — сервер. Рулится как GTA, синкается как часы.

const MAX_SPEED := 30.0
const MAX_REVERSE := 9.0
const ACCEL := 16.0
const BRAKE := 30.0
const REVERSE_ACCEL := 9.0
const STEER := 2.4
const GRAVITY := 20.0
const WHEEL_R := 0.38

var paint := Color(0.8, 0.2, 0.2)
var car_id := 0
var forward_speed := 0.0
var steer_vis := 0.0
var driver_id := 0:
	set(v):
		driver_id = v
		if not is_node_ready():
			return
		set_multiplayer_authority(v if v != 0 else 1)
		$ServerSync.set_multiplayer_authority(1)
		_update_engine()

var _steer := 0.0
var _crash_cd := 0.0
var _spin_pivots: Array[Node3D] = []
var _front_pivots: Array[Node3D] = []
var _engine: AudioStreamPlayer3D

@onready var combat: Node = get_node("/root/World/Combat")
@onready var traffic: Traffic = get_node("/root/World/Traffic")

func _ready() -> void:
	add_to_group(&"car")
	set_multiplayer_authority(driver_id if driver_id != 0 else 1)
	$ServerSync.set_multiplayer_authority(1)
	_build_model()
	_build_engine()
	_update_engine()

func _physics_process(delta: float) -> void:
	_crash_cd = maxf(0.0, _crash_cd - delta)
	if not is_multiplayer_authority():
		return
	if driver_id != 0:
		_drive(delta)
	else:
		forward_speed = move_toward(forward_speed, 0.0, 20.0 * delta)
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = velocity.y - GRAVITY * delta if not is_on_floor() else -0.5
		move_and_slide()

func _process(delta: float) -> void:
	for p in _spin_pivots:
		p.rotate_x(-forward_speed * delta / WHEEL_R)
	for p in _front_pivots:
		p.rotation.y = -steer_vis * 0.45
	if _engine and driver_id != 0:
		var t := absf(forward_speed) / MAX_SPEED
		_engine.pitch_scale = 0.55 + t * 1.5
		_engine.volume_db = -16.0 + t * 8.0

func _drive(delta: float) -> void:
	var throttle := Input.is_action_pressed("move_forward")
	var brake := Input.is_action_pressed("move_back")
	var steer_in := Input.get_axis("move_left", "move_right")
	var hand := Input.is_action_pressed("jump")
	if throttle:
		forward_speed = minf(forward_speed + ACCEL * delta, MAX_SPEED)
	elif brake:
		if forward_speed > 0.5:
			forward_speed = maxf(forward_speed - BRAKE * delta, 0.0)
		else:
			forward_speed = maxf(forward_speed - REVERSE_ACCEL * delta, -MAX_REVERSE)
	else:
		forward_speed = move_toward(forward_speed, 0.0, (1.5 + absf(forward_speed) * 0.25) * delta)
	if hand:
		forward_speed = move_toward(forward_speed, 0.0, 22.0 * delta)
	var sf := clampf(absf(forward_speed) / 5.0, 0.0, 1.0) * (1.0 - absf(forward_speed) / (MAX_SPEED * 2.2))
	_steer = lerpf(_steer, steer_in, 1.0 - exp(-10.0 * delta))
	steer_vis = _steer
	rotate_y(-_steer * STEER * sf * (1.35 if hand else 1.0) * delta * signf(forward_speed))
	velocity.y = velocity.y - GRAVITY * delta if not is_on_floor() else -0.5
	var fwd := -transform.basis.z
	velocity.x = fwd.x * forward_speed
	velocity.z = fwd.z * forward_speed
	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body is Player and absf(forward_speed) > 6.0:
			combat.rpc_id(1, &"request_ram", int(body.name), absf(forward_speed))
			forward_speed *= 0.55
		elif body is StaticBody3D and absf(forward_speed) > 12.0 and _crash_cd <= 0.0:
			_crash_cd = 0.5
			forward_speed *= 0.35
			traffic.rpc(&"crash_fx", global_position + Vector3(0, 0.8, 0))

func honk() -> void:
	Sound.play3d(&"horn", get_parent(), global_position, -2.0)

func _update_engine() -> void:
	if _engine == null:
		return
	if driver_id != 0 and not _engine.playing:
		_engine.play()
	elif driver_id == 0 and _engine.playing:
		_engine.stop()

func _build_engine() -> void:
	var eng: AudioStreamWAV = Sound.streams.get(&"engine")
	if eng == null:
		return
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = eng
	_engine.unit_size = 10.0
	_engine.max_distance = 55.0
	_engine.volume_db = -16.0
	add_child(_engine)

func _build_model() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = paint
	body_mat.metallic = 0.5
	body_mat.roughness = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.16, 0.24)
	glass.metallic = 0.8
	glass.roughness = 0.15
	var head := StandardMaterial3D.new()
	head.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head.albedo_color = Color(1.0, 0.95, 0.75)
	var tail := StandardMaterial3D.new()
	tail.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tail.albedo_color = Color(1.0, 0.15, 0.1)
	_part(self, body_mat, Vector3(2.0, 0.55, 4.4), Vector3(0, 0.62, 0))
	_part(self, glass, Vector3(1.7, 0.5, 2.2), Vector3(0, 1.12, 0.1))
	_part(self, dark, Vector3(2.05, 0.2, 0.3), Vector3(0, 0.42, -2.15))
	_part(self, dark, Vector3(2.05, 0.2, 0.3), Vector3(0, 0.42, 2.15))
	_part(self, head, Vector3(0.35, 0.14, 0.06), Vector3(-0.6, 0.72, -2.21))
	_part(self, head, Vector3(0.35, 0.14, 0.06), Vector3(0.6, 0.72, -2.21))
	_part(self, tail, Vector3(0.35, 0.14, 0.06), Vector3(-0.6, 0.72, 2.21))
	_part(self, tail, Vector3(0.35, 0.14, 0.06), Vector3(0.6, 0.72, 2.21))
	var tyre := StandardMaterial3D.new()
	tyre.albedo_color = Color(0.06, 0.06, 0.07)
	for x in [-0.95, 0.95]:
		for z in [-1.45, 1.45]:
			var steer_pivot := Node3D.new()
			steer_pivot.position = Vector3(x, WHEEL_R, z)
			add_child(steer_pivot)
			var spin := Node3D.new()
			steer_pivot.add_child(spin)
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = WHEEL_R
			cyl.bottom_radius = WHEEL_R
			cyl.height = 0.3
			cyl.material = tyre
			mi.mesh = cyl
			mi.rotation.z = PI / 2.0
			spin.add_child(mi)
			_spin_pivots.append(spin)
			if z < 0.0:
				_front_pivots.append(steer_pivot)

func _part(parent: Node3D, mat: StandardMaterial3D, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)