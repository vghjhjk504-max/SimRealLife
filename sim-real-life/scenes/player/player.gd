class_name Player
extends CharacterBody3D
# Человек v0.2: кулаки, стволы, HP, смерть и респавн. Authority рулит, сервер судит.

signal weapon_changed(id: int)

const WALK := 5.0
const SPRINT := 9.0
const ACCEL := 14.0
const JUMP := 5.5
const GRAVITY := 18.0
const SENS := 0.0022
const MAX_HP := 100

var nick := "Бро"
var wheel_open := false
var wheel_vec := Vector2.ZERO

var car_id := 0:
	set(v):
		car_id = v
		if not is_node_ready():
			return
		var in_car := v != 0
		wheel_open = false
		body_mesh.visible = not in_car
		_socket.visible = not in_car and not _dead
		collider.set_deferred("disabled", in_car or _dead)
		_update_overhead()
		if _mine:
			_car_look = 0.0
			_look_idle = 0.0
			rig.rotation.y = 0.0
			arm.spring_length = 6.5 if in_car else 4.0
			Sound.play(&"door", -5.0)

var _car_look := 0.0
var _look_idle := 0.0

var weapon_id: int = Weapons.ID.FISTS:
	set(v):
		weapon_id = v
		if is_node_ready():
			_apply_weapon()

var hp: int = MAX_HP:
	set(v):
		var old := hp
		hp = clampi(v, 0, MAX_HP)
		if not is_node_ready():
			return
		_update_overhead()
		if old > 0 and hp <= 0:
			_die()
		elif old <= 0 and hp > 0:
			_revive()

var _pitch := -0.25
var _mine := false
var _dead := false
var _cooldown := 0.0
var _reloading := 0.0
var _reload_total := 1.0
var _recoil := 0.0
var _shake := 0.0
var _mags := {}
var _socket: Node3D
var _weapon_nodes := {}
var _muzzle: Node3D
var _muzzle_offsets := {}
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_tween: Tween
var _punch_tween: Tween
var _body_tween: Tween
var _hit_tween: Tween
var _body_mat: StandardMaterial3D
var _hp_bg: MeshInstance3D
var _hp_fg: MeshInstance3D
var _hp_fg_mat: StandardMaterial3D

@onready var arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var cam: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var rig: Node3D = $CameraRig
@onready var label: Label3D = $Nick
@onready var collider: CollisionShape3D = $Collider
@onready var body_mesh: MeshInstance3D = $Body
@onready var combat: Node = get_node("/root/World/Combat")
@onready var traffic: Traffic = get_node("/root/World/Traffic")

func _ready() -> void:
	add_to_group(&"player")
	_mine = is_multiplayer_authority()
	$ServerSync.set_multiplayer_authority(1)
	_mags = {
		Weapons.ID.PISTOL: Weapons.DATA[Weapons.ID.PISTOL].mag,
		Weapons.ID.RIFLE: Weapons.DATA[Weapons.ID.RIFLE].mag,
	}
	label.text = nick
	label.visible = not _mine
	arm.rotation.x = _pitch
	arm.add_excluded_object(get_rid())
	cam.current = _mine
	_body_mat = (body_mesh.mesh.material as StandardMaterial3D).duplicate()
	body_mesh.material_override = _body_mat
	_build_overhead()
	_build_weapons()
	_apply_weapon()
	if _mine:
		add_to_group(&"local_player")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		arm.process_mode = Node.PROCESS_MODE_DISABLED

# ---------- HP-бар над башкой (виден только у чужих) ----------

func _build_overhead() -> void:
	_hp_bg = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 0.09)
	var bgm := StandardMaterial3D.new()
	bgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bgm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bgm.albedo_color = Color(0.05, 0.05, 0.08, 0.85)
	q.material = bgm
	_hp_bg.mesh = q
	_hp_bg.position = Vector3(0, 2.05, 0)
	_hp_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hp_bg)
	_hp_fg = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(1.02, 0.05)
	_hp_fg_mat = StandardMaterial3D.new()
	_hp_fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_fg_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_hp_fg_mat.render_priority = 1
	_hp_fg_mat.albedo_color = Color(0.3, 1.0, 0.45)
	q2.material = _hp_fg_mat
	_hp_fg.mesh = q2
	_hp_fg.position = Vector3(0, 2.05, 0)
	_hp_fg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hp_fg)
	if _mine:
		_hp_bg.hide()
		_hp_fg.hide()

func _update_overhead() -> void:
	if _hp_fg == null:
		return
	var frac := hp / float(MAX_HP)
	(_hp_fg.mesh as QuadMesh).size = Vector2(1.02 * maxf(frac, 0.001), 0.05)
	_hp_fg_mat.albedo_color = Color(1, 0.25, 0.2).lerp(Color(0.3, 1, 0.45), frac)
	var show_bar := not _mine and not _dead and car_id == 0
	_hp_bg.visible = show_bar
	_hp_fg.visible = show_bar

# ---------- procedural стволы в руках ----------

func _build_weapons() -> void:
	_socket = Node3D.new()
	_socket.position = Vector3(0.32, 1.32, -0.28)
	add_child(_socket)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.13, 0.17)
	metal.metallic = 0.6
	metal.roughness = 0.4
	_weapon_nodes[Weapons.ID.FISTS] = _make_fists()
	_weapon_nodes[Weapons.ID.PISTOL] = _make_gun(metal, false)
	_weapon_nodes[Weapons.ID.RIFLE] = _make_gun(metal, true)
	for id in _weapon_nodes:
		_socket.add_child(_weapon_nodes[id])
	_muzzle = Node3D.new()
	_socket.add_child(_muzzle)
	_flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.85, 0.4)
	sm.material = fm
	_flash.mesh = sm
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1, 0.7, 0.3)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 6.0
	_muzzle.add_child(_flash_light)
	_muzzle_offsets = {
		Weapons.ID.FISTS: Vector3(0, 0, -0.25),
		Weapons.ID.PISTOL: Vector3(0, 0.02, -0.3),
		Weapons.ID.RIFLE: Vector3(0, 0.01, -0.7),
	}

func _make_fists() -> Node3D:
	var n := Node3D.new()
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.62, 0.45)
	for x in [0.0, -0.62]:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.09
		s.height = 0.18
		s.material = skin
		mi.mesh = s
		mi.position = Vector3(x, 0, 0)
		n.add_child(mi)
	return n

func _make_gun(metal: StandardMaterial3D, rifle: bool) -> Node3D:
	var n := Node3D.new()
	var accent := StandardMaterial3D.new()
	accent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	accent.albedo_color = Weapons.DATA[Weapons.ID.RIFLE if rifle else Weapons.ID.PISTOL].color
	if rifle:
		_part(n, metal, Vector3(0.07, 0.1, 0.7), Vector3(0, 0, -0.15))
		_part(n, metal, Vector3(0.05, 0.2, 0.09), Vector3(0, -0.14, -0.05))
		_part(n, metal, Vector3(0.06, 0.09, 0.22), Vector3(0, -0.01, 0.28))
		_part(n, metal, Vector3(0.035, 0.035, 0.2), Vector3(0, 0.01, -0.58))
		_part(n, accent, Vector3(0.02, 0.02, 0.02), Vector3(0, 0.07, -0.3))
	else:
		_part(n, metal, Vector3(0.06, 0.09, 0.34), Vector3(0, 0.02, -0.1))
		_part(n, metal, Vector3(0.05, 0.16, 0.07), Vector3(0, -0.1, 0.03))
		_part(n, accent, Vector3(0.015, 0.015, 0.015), Vector3(0, 0.075, -0.24))
	return n

func _part(parent: Node3D, mat: StandardMaterial3D, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)

func _apply_weapon() -> void:
	for id in _weapon_nodes:
		_weapon_nodes[id].visible = id == weapon_id
	_muzzle.position = _muzzle_offsets.get(weapon_id, Vector3.ZERO)
	weapon_changed.emit(weapon_id)
	if _mine and not _dead:
		Sound.play(&"switch", -6.0)

# ---------- input ----------

func _unhandled_input(event: InputEvent) -> void:
	if not _mine:
		return
	if event.is_action_pressed("ui_cancel"):
		wheel_open = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("mute"):
		Sound.toggle_mute()
		return
	if event.is_action_pressed("interact") and not _dead:
		if car_id != 0:
			traffic.rpc_id(1, &"request_exit")
		else:
			var c := traffic.nearest_free_car(global_position)
			if c:
				traffic.rpc_id(1, &"request_enter", c.car_id)
		return
	if event.is_action_pressed("horn") and car_id != 0:
		traffic.rpc(&"honk", car_id)
		return
	if _dead:
		return
	if event is InputEventMouseMotion:
		if wheel_open:
			wheel_vec += event.relative
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if car_id != 0:
				_car_look = clampf(_car_look - event.relative.x * SENS, -2.6, 2.6)
				_look_idle = 0.0
			else:
				rotate_y(-event.relative.x * SENS)
			_pitch = clampf(_pitch - event.relative.y * SENS, -1.2, 0.55)
			arm.rotation.x = _pitch
		return
	if car_id != 0:
		return
	if event.is_action_pressed("weapon_wheel"):
		wheel_open = true
		wheel_vec = Vector2.ZERO
	elif event.is_action_released("weapon_wheel"):
		if wheel_open:
			wheel_open = false
			_select(Weapons.wheel_pick(wheel_vec, weapon_id))
	elif event.is_action_pressed("weapon_1"):
		_select(Weapons.ID.FISTS)
	elif event.is_action_pressed("weapon_2"):
		_select(Weapons.ID.PISTOL)
	elif event.is_action_pressed("weapon_3"):
		_select(Weapons.ID.RIFLE)
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event is InputEventMouseButton and event.pressed and not wheel_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_reloading = maxf(0.0, _reloading - delta)
	_recoil = maxf(0.0, _recoil - delta * 0.35)
	_shake = maxf(0.0, _shake - delta * 2.2)
	if not _mine:
		return
	cam.h_offset = (randf() - 0.5) * _shake
	cam.v_offset = (randf() - 0.5) * _shake
	if car_id != 0:
		_follow_car(delta)
		return
	if _dead:
		rig.rotate_y(delta * 0.4)
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and not wheel_open:
		var wd := Weapons.get_data(weapon_id)
		var want := Input.is_action_pressed("fire") if wd.auto else Input.is_action_just_pressed("fire")
		if want and _cooldown <= 0.0 and _reloading <= 0.0:
			if wd.melee or get_mag(weapon_id) > 0:
				_fire()
			else:
				_cooldown = 0.3
				Sound.play(&"empty")
				_start_reload()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and captured:
		velocity.y = JUMP
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if captured else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT if Input.is_action_pressed("sprint") else WALK
	var k := 1.0 - exp(-ACCEL * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, k)
	velocity.z = lerpf(velocity.z, dir.z * speed, k)
	move_and_slide()

# ---------- бой ----------

func _fire() -> void:
	var wd := Weapons.get_data(weapon_id)
	_cooldown = wd.rate
	if wd.melee:
		_punch_anim()
		Sound.play(&"swing", -4.0)
	else:
		_mags[weapon_id] = maxi(0, get_mag(weapon_id) - 1)
		_muzzle_flash()
		_recoil = minf(_recoil + (0.03 if weapon_id == Weapons.ID.RIFLE else 0.06), 0.12)
		_pitch = clampf(_pitch + (0.006 if weapon_id == Weapons.ID.RIFLE else 0.012), -1.2, 0.55)
		arm.rotation.x = _pitch
		_shake = minf(_shake + 0.03, 0.2)
		Sound.play(&"rifle" if weapon_id == Weapons.ID.RIFLE else &"pistol", -5.0)
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	if wd.spread > 0.0:
		dir = (dir + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * wd.spread * 2.0).normalized()
	combat.rpc_id(1, &"request_fire", weapon_id, origin, dir)

func _muzzle_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.visible = true
	_flash.scale = Vector3.ONE * randf_range(0.7, 1.5)
	_flash_light.light_energy = 3.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_light, "light_energy", 0.0, 0.05)
	_flash_tween.tween_callback(func(): _flash.visible = false)

func _punch_anim() -> void:
	if _punch_tween and _punch_tween.is_valid():
		_punch_tween.kill()
	_socket.position.z = -0.28
	_punch_tween = create_tween()
	_punch_tween.tween_property(_socket, "position:z", -0.66, 0.08)
	_punch_tween.tween_property(_socket, "position:z", -0.28, 0.14)

func _start_reload() -> void:
	if _dead or _reloading > 0.0:
		return
	var wd := Weapons.get_data(weapon_id)
	if wd.melee or get_mag(weapon_id) >= wd.mag:
		return
	_reloading = wd.reload
	_reload_total = wd.reload
	Sound.play(&"reload", -4.0)
	combat.rpc_id(1, &"request_reload", weapon_id)

func _select(id: int) -> void:
	if _dead or id == weapon_id or not Weapons.DATA.has(id):
		return
	_reloading = 0.0
	weapon_id = id

func _cycle(d: int) -> void:
	var ids := [Weapons.ID.FISTS, Weapons.ID.PISTOL, Weapons.ID.RIFLE]
	_select(ids[wrapi(ids.find(weapon_id) + d, 0, ids.size())])

# ---------- состояние для HUD / combat ----------

func set_mag(w: int, mag: int) -> void:
	_mags[w] = mag

func set_mags(m: Dictionary) -> void:
	for w in m:
		_mags[w] = m[w]

func get_mag(w: int) -> int:
	return _mags.get(w, 0)

func get_reload_frac() -> float:
	return 1.0 - _reloading / _reload_total if _reloading > 0.0 else 0.0

func get_bloom() -> float:
	return _recoil * 3.0 + Vector2(velocity.x, velocity.z).length() / SPRINT * 0.3

func is_dead() -> bool:
	return _dead

func get_muzzle_pos() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position + Vector3(0, 1.4, 0)

func on_hurt(_dmg: int) -> void:
	_shake = minf(_shake + 0.22, 0.5)

func flash_hit() -> void:
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1, 0.15, 0.1)
	_body_mat.emission_energy_multiplier = 2.5
	_hit_tween = create_tween()
	_hit_tween.tween_property(_body_mat, "emission_energy_multiplier", 0.0, 0.25)

func remote_fire_fx(w: int) -> void:
	if _dead:
		return
	if Weapons.get_data(w).melee:
		_punch_anim()
		Sound.play3d(&"swing", get_parent(), global_position, -4.0)
	else:
		_muzzle_flash()
		Sound.play3d(&"rifle" if w == Weapons.ID.RIFLE else &"pistol", get_parent(), get_muzzle_pos(), -5.0)

# ---------- смерть / респавн ----------

func _die() -> void:
	if _dead:
		return
	_dead = true
	wheel_open = false
	_reloading = 0.0
	collider.set_deferred("disabled", true)
	_socket.visible = false
	_update_overhead()
	Sound.play3d(&"death", get_parent(), global_position, -2.0)
	if _body_tween and _body_tween.is_valid():
		_body_tween.kill()
	_body_tween = create_tween()
	_body_tween.set_parallel(true)
	_body_tween.tween_property(body_mesh, "rotation:x", -PI / 2.0, 0.4).set_ease(Tween.EASE_IN)
	_body_tween.tween_property(body_mesh, "position:y", 0.36, 0.4)
	if _mine:
		arm.spring_length = 7.0
		_pitch = -0.85
		arm.rotation.x = _pitch

func _revive() -> void:
	if not _dead:
		return
	_dead = false
	collider.set_deferred("disabled", false)
	if _body_tween and _body_tween.is_valid():
		_body_tween.kill()
	body_mesh.rotation = Vector3.ZERO
	body_mesh.position = Vector3(0, 0.9, 0)
	_socket.visible = true
	_update_overhead()
	if _mine:
		rig.rotation = Vector3.ZERO
		arm.spring_length = 4.0
		_pitch = -0.25
		arm.rotation.x = _pitch

func do_respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_reloading = 0.0
	_cooldown = 0.0
	_revive()
	Sound.play(&"respawn", -4.0)

func _follow_car(delta: float) -> void:
	var c := get_node_or_null("/root/World/Cars/" + str(car_id)) as Car
	if c == null:
		return
	global_position = c.global_position
	rotation.y = c.rotation.y
	_look_idle += delta
	if _look_idle > 1.4:
		_car_look = lerpf(_car_look, 0.0, 1.0 - exp(-2.0 * delta))
	rig.rotation.y = _car_look
	velocity = Vector3.ZERO

func place_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO