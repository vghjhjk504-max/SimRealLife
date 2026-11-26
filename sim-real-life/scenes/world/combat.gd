extends Node3D
# Combat: сервер — судья района. Урон, патроны, смерть, респавн. Клиенты шлют запросы, сервер решает.

@onready var world: Node = get_parent()
@onready var players: Node3D = $"../Players"

var _mags := {}
var _last_fire := {}
var _dead := {}
var _kills := {}
var _deaths := {}
var _reloading := {}
var _last_ram := {}

func register(id: int) -> void:
	if not multiplayer.is_server():
		return
	_mags[id] = _fresh_mags()
	_kills[id] = 0
	_deaths[id] = 0
	_dead[id] = false
	rpc_id(id, &"ammo_full", _mags[id])
	rpc_id(id, &"stats_full", _kills, _deaths)

func unregister(id: int) -> void:
	_last_ram.erase(id)
	_mags.erase(id)
	_last_fire.erase(id)
	_dead.erase(id)
	_kills.erase(id)
	_deaths.erase(id)
	for key in _reloading.keys():
		if key.begins_with(str(id) + ":"):
			_reloading.erase(key)

func _fresh_mags() -> Dictionary:
	return {
		Weapons.ID.PISTOL: Weapons.DATA[Weapons.ID.PISTOL].mag,
		Weapons.ID.RIFLE: Weapons.DATA[Weapons.ID.RIFLE].mag,
	}

# ---------- запросы от клиентов ----------

@rpc("any_peer", "call_local", "reliable")
func request_fire(w: int, origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var p := players.get_node_or_null(str(id)) as Player
	if p == null or _dead.get(id, true) or not Weapons.DATA.has(w):
		return
	var wd: Dictionary = Weapons.DATA[w]
	var now := Time.get_ticks_msec()
	if now - int(_last_fire.get(id, 0)) < int(wd.rate * 900.0):
		return
	_last_fire[id] = now
	dir = dir.normalized()
	if dir.length_squared() < 0.5:
		return
	var head := p.global_position + Vector3(0, 1.6, 0)
	if origin.distance_to(head) > 6.5:
		origin = head
	if not wd.melee:
		var mag: int = _mags[id].get(w, 0)
		if mag <= 0:
			return
		_mags[id][w] = mag - 1
		rpc_id(id, &"ammo_state", w, mag - 1)
	var end: Vector3 = origin + dir * wd.range
	var hit_pos := end
	var victim := 0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, end, 7, [p.get_rid()])
	var res := space.intersect_ray(q)
	if res.is_empty() and wd.melee:
		# кулаку даём поблажку — сфера вместо тонкого луча
		var sq := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.55
		sq.shape = sph
		sq.transform = Transform3D(Basis.IDENTITY, origin + dir * 1.5)
		sq.collision_mask = 2
		sq.exclude = [p.get_rid()]
		for h in space.intersect_shape(sq, 4):
			if h.collider is CharacterBody3D and h.collider.get_parent() == players:
				res = {"collider": h.collider, "position": h.collider.global_position + Vector3(0, 1.2, 0)}
				break
	if not res.is_empty():
		hit_pos = res.position
		end = res.position
		var col = res.collider
		if col is CharacterBody3D and col.get_parent() == players:
			var vid := int(col.name)
			if not _dead.get(vid, false):
				victim = vid
				_apply_damage(id, vid, wd.dmg, w)
	rpc(&"combat_fx", id, w, origin, end, victim, hit_pos)

@rpc("any_peer", "call_local", "reliable")
func request_reload(w: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if _dead.get(id, true) or not Weapons.DATA.has(w):
		return
	var wd: Dictionary = Weapons.DATA[w]
	if wd.melee or _mags[id].get(w, 0) >= wd.mag:
		return
	var key := str(id) + ":" + str(w)
	if _reloading.has(key):
		return
	_reloading[key] = true
	get_tree().create_timer(wd.reload).timeout.connect(func():
		_reloading.erase(key)
		if multiplayer.is_server() and players.has_node(str(id)) and not _dead.get(id, false):
			_mags[id][w] = wd.mag
			rpc_id(id, &"ammo_state", w, wd.mag)
	)

func _apply_damage(killer: int, vid: int, dmg: int, w: int) -> void:
	var v := players.get_node(str(vid)) as Player
	v.hp = maxi(0, v.hp - dmg)
	rpc_id(vid, &"hurt_fx", dmg, killer)
	if v.hp <= 0:
		_dead[vid] = true
		_deaths[vid] = int(_deaths.get(vid, 0)) + 1
		_kills[killer] = int(_kills.get(killer, 0)) + 1
		rpc(&"killfeed", killer, vid, w)
		rpc(&"stats_full", _kills, _deaths)
		rpc_id(vid, &"you_died", killer)
		get_tree().create_timer(Weapons.RESPAWN_TIME).timeout.connect(func(): _respawn(vid))

func _respawn(id: int) -> void:
	if not multiplayer.is_server():
		return
	var p := players.get_node_or_null(str(id)) as Player
	if p == null:
		return
	_dead[id] = false
	p.hp = Weapons.get_data(0).get("hp", 100)
	_mags[id] = _fresh_mags()
	var a := randf() * TAU
	rpc_id(id, &"respawn", Vector3(cos(a) * 5.0, 1.0, sin(a) * 5.0))
	rpc_id(id, &"ammo_full", _mags[id])

# ---------- сервер → клиенты ----------

@rpc("authority", "call_local", "reliable")
func ammo_state(w: int, mag: int) -> void:
	var p := _local()
	if p:
		p.set_mag(w, mag)

@rpc("authority", "call_local", "reliable")
func ammo_full(mags: Dictionary) -> void:
	var p := _local()
	if p:
		p.set_mags(mags)

@rpc("authority", "call_local", "reliable")
func hurt_fx(dmg: int, _killer: int) -> void:
	var p := _local()
	if p:
		p.on_hurt(dmg)
	var h := _hud()
	if h:
		h.on_hurt(dmg)

@rpc("authority", "call_local", "reliable")
func you_died(killer: int) -> void:
	var h := _hud()
	if h:
		h.show_death(_nick(killer))

@rpc("authority", "call_local", "reliable")
func respawn(pos: Vector3) -> void:
	var p := _local()
	if p:
		p.do_respawn(pos)
	var h := _hud()
	if h:
		h.hide_death()

@rpc("authority", "call_local", "reliable")
func killfeed(killer: int, victim: int, w: int) -> void:
	var me := multiplayer.get_unique_id()
	var h := _hud()
	if h:
		h.add_kill(_nick(killer), _nick(victim), w, killer == me, victim == me)
		if killer == me:
			h.hitmarker(true)
	if killer == me:
		Sound.play(&"kill", -3.0)

@rpc("authority", "call_local", "reliable")
func stats_full(kills: Dictionary, deaths: Dictionary) -> void:
	var h := _hud()
	if h:
		h.set_stats(kills, deaths)

@rpc("authority", "call_local", "reliable")
func combat_fx(shooter: int, w: int, origin: Vector3, end: Vector3, victim: int, hit_pos: Vector3) -> void:
	var wd: Dictionary = Weapons.DATA.get(w, Weapons.DATA[Weapons.ID.FISTS])
	var sp := players.get_node_or_null(str(shooter)) as Player
	var me := multiplayer.get_unique_id()
	if sp and shooter != me:
		sp.remote_fire_fx(w)
	if wd.melee:
		if victim != 0:
			Sound.play3d(&"hit", self, hit_pos, -2.0)
			_burst(hit_pos, Color(0.9, 0.12, 0.12), 10)
		return
	var muzzle: Vector3 = sp.get_muzzle_pos() if sp else origin
	_tracer(muzzle, end, wd.color)
	if victim != 0:
		var v := players.get_node_or_null(str(victim)) as Player
		if v:
			v.flash_hit()
		_burst(hit_pos, Color(0.9, 0.12, 0.12), 8)
		_damage_number(hit_pos, wd.dmg)
		if shooter == me:
			var h := _hud()
			if h:
				h.hitmarker(false)
	else:
		_burst(hit_pos, Color(1.0, 0.75, 0.3), 6)

# ---------- визуальные эффекты (только визуал, урон уже решён) ----------

func _tracer(a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.3:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	var d := (b - a).normalized()
	mi.look_at(mi.global_position + d, Vector3.RIGHT if absf(d.dot(Vector3.UP)) > 0.98 else Vector3.UP)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(mi.queue_free)

func _burst(pos: Vector3, color: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.35
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.12
	p.color = color
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)

func _damage_number(pos: Vector3, dmg: int) -> void:
	var l := Label3D.new()
	l.text = str(dmg)
	l.font_size = 42
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(1, 0.85, 0.3)
	l.outline_size = 10
	add_child(l)
	l.global_position = pos + Vector3(0, 0.2, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)

func _nick(id: int) -> String:
	return world._nicks.get(id, "Бро")

func _local() -> Node:
	var a := get_tree().get_nodes_in_group(&"local_player")
	return (a[0] as Player) if a.size() > 0 else null

func _hud() -> Node:
	var a := get_tree().get_nodes_in_group(&"hud")
	return a[0] if a.size() > 0 else null

@rpc("any_peer", "call_local", "reliable")
func request_ram(vid: int, speed: float) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var p := players.get_node_or_null(str(id)) as Player
	var v := players.get_node_or_null(str(vid)) as Player
	if p == null or v == null or vid == id:
		return
	if p.car_id == 0 or _dead.get(id, true) or _dead.get(vid, false):
		return
	speed = clampf(speed, 0.0, 40.0)
	if speed < 6.0:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ram.get(id, 0)) < 600:
		return
	_last_ram[id] = now
	if p.global_position.distance_to(v.global_position) > 5.0:
		return
	_apply_damage(id, vid, clampi(int(speed * 3.2), 10, 120), Weapons.KILL_CAR)
	rpc(&"ram_fx", v.global_position + Vector3(0, 1.0, 0))

@rpc("authority", "call_local", "reliable")
func ram_fx(pos: Vector3, dmg: int) -> void:
	Sound.play3d(&"hit", self, pos, -1.0)
	_burst(pos, Color(0.9, 0.12, 0.12), 12)
	_damage_number(pos, dmg)