extends CanvasLayer
# HUD района: HP, стволы, колесо оружия как в GTA, киллфид, хитмаркеры, смерть.

class Overlay extends Control:
	var hud: Node
	func _draw() -> void:
		hud._paint(self)

var player: Player = null
@onready var traffic: Traffic = get_node_or_null("/root/World/Traffic")
var _overlay: Overlay
var _vignette: TextureRect
var _feed: VBoxContainer
var _stats: Label
var _mute: Button
var _death_panel: Control
var _killer_lbl: Label
var _countdown: Label
var _hp_display := 100.0
var _hitmarker_t := 0.0
var _hitmarker_kill := false
var _toast_t := 0.0
var _toast_text := ""
var _vignette_a := 0.0
var _death := false
var _death_t := 0.0
var _kills := 0
var _deaths := 0

func _ready() -> void:
	add_to_group(&"hud")
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.42, 1.0])
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 256
	gt.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate = Color(0.75, 0.02, 0.02, 0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(_vignette)
	add_child(_vignette)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -400
	_feed.offset_top = 64
	_feed.offset_right = -16
	_feed.offset_bottom = 300
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	_stats = Label.new()
	_stats.position = Vector2(20, 14)
	_stats.add_theme_font_size_override("font_size", 15)
	_stats.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	add_child(_stats)

	_mute = Button.new()
	_mute.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mute.offset_left = -196
	_mute.offset_top = 14
	_mute.offset_right = -16
	_mute.offset_bottom = 50
	_mute.focus_mode = Control.FOCUS_NONE
	_mute.pressed.connect(func(): Sound.toggle_mute())
	add_child(_mute)

	_overlay = Overlay.new()
	_overlay.hud = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(_overlay)
	add_child(_overlay)

	_death_panel = Control.new()
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(_death_panel)
	var scrim := ColorRect.new()
	scrim.color = Color(0.1, 0.0, 0.0, 0.55)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(scrim)
	_death_panel.add_child(scrim)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "ТЫ ПОГИБ"
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(1, 0.25, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_killer_lbl = Label.new()
	_killer_lbl.add_theme_font_size_override("font_size", 19)
	_killer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown = Label.new()
	_countdown.add_theme_font_size_override("font_size", 42)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	vb.add_child(_killer_lbl)
	vb.add_child(_countdown)
	cc.add_child(vb)
	_death_panel.add_child(cc)
	_death_panel.hide()
	add_child(_death_panel)

	Sound.mute_changed.connect(_on_mute_changed)
	_on_mute_changed(Sound.muted)

func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if player == null:
		var arr := get_tree().get_nodes_in_group(&"local_player")
		if arr.size() > 0:
			player = arr[0] as Player
			player.weapon_changed.connect(_on_weapon_changed)
	_hitmarker_t = maxf(0.0, _hitmarker_t - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	_vignette_a = maxf(0.0, _vignette_a - delta * 1.4)
	if player:
		_hp_display = lerpf(_hp_display, float(player.hp), 1.0 - exp(-3.0 * delta))
		var va := _vignette_a
		if player.hp > 0 and player.hp < 30:
			va += 0.10 + 0.07 * sin(Time.get_ticks_msec() * 0.006)
		_vignette.modulate = Color(0.75, 0.02, 0.02, clampf(va, 0.0, 0.7))
		_stats.text = "БОЙЦОВ В ЭФИРЕ: %d    K %d · D %d" % [get_tree().get_nodes_in_group(&"player").size(), _kills, _deaths]
	if _death:
		_death_t = maxf(0.0, _death_t - delta)
		_countdown.text = str(maxi(1, ceili(_death_t)))
	_overlay.queue_redraw()

# ---------- события от Combat ----------

func on_hurt(_dmg: int) -> void:
	_vignette_a = minf(0.6, _vignette_a + 0.32)
	Sound.play(&"hurt", -4.0)

func hitmarker(kill: bool) -> void:
	_hitmarker_kill = kill
	_hitmarker_t = 0.3 if kill else 0.16
	if not kill:
		Sound.play(&"hit", -3.0)

func add_kill(killer: String, victim: String, w: int, mine_kill: bool, mine_death: bool) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	var a := Label.new()
	a.text = killer
	a.add_theme_font_size_override("font_size", 15)
	a.add_theme_color_override("font_color", Color(0.4, 1, 0.55) if mine_kill else Color(1, 1, 1, 0.9))
	var wl := Label.new()
	wl.text = "[ %s ]" % Weapons.name_of(w)
	wl.add_theme_font_size_override("font_size", 13)
	wl.add_theme_color_override("font_color", Weapons.DATA[w].color)
	var b := Label.new()
	b.text = victim
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if mine_death else Color(0.8, 0.8, 0.85))
	row.add_child(a)
	row.add_child(wl)
	row.add_child(b)
	_feed.add_child(row)
	if _feed.get_child_count() > 5:
		_feed.get_child(0).queue_free()
	var tw := row.create_tween()
	tw.tween_interval(3.6)
	tw.tween_property(row, "modulate:a", 0.0, 0.6)
	tw.tween_callback(row.queue_free)

func show_death(killer: String) -> void:
	_death = true
	_death_t = Weapons.RESPAWN_TIME
	_killer_lbl.text = "тебя уложил: " + killer
	_death_panel.show()

func hide_death() -> void:
	_death = false
	_death_panel.hide()

func set_stats(kills: Dictionary, deaths: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	_kills = kills.get(me, 0)
	_deaths = deaths.get(me, 0)

func _on_weapon_changed(id: int) -> void:
	_toast_text = Weapons.DATA[id].name
	_toast_t = 1.1

func _on_mute_changed(m: bool) -> void:
	_mute.text = "ЗВУК: ВЫКЛ · M" if m else "ЗВУК: ВКЛ · M"

# ---------- вся векторная отрисовка за один проход ----------

func _paint(ci: Control) -> void:
	if player == null:
		return
	var s := ci.size
	var font := ThemeDB.fallback_font
	var c := s * 0.5
	var in_car := player.car_id != 0
	var car: Car = null
	if in_car:
		car = get_node_or_null("/root/World/Cars/" + str(player.car_id)) as Car
	var wd := Weapons.get_data(player.weapon_id)

	if not player.is_dead() and not in_car:
		var gap := 7.0 + player.get_bloom() * 46.0
		var col := Color(1, 1, 1, 0.9)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			ci.draw_line(c + d * gap, c + d * (gap + 9.0), col, 2.0)
		ci.draw_circle(c, 1.6, col)
	if _hitmarker_t > 0.0:
		var hc := Color(1, 0.3, 0.25) if _hitmarker_kill else Color(1, 1, 1)
		hc.a = minf(1.0, _hitmarker_t * 8.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			ci.draw_line(c + d * 6.0, c + d * 15.0, hc, 2.5)

	var frac := player.hp / 100.0
	var disp := _hp_display / 100.0
	var bar := Rect2(28, s.y - 58, 264, 20)
	ci.draw_rect(bar.grow(3), Color(0.02, 0.02, 0.05, 0.75))
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * disp, bar.size.y)), Color(0.9, 0.3, 0.25, 0.8))
	var hcol := Color(1, 0.25, 0.2).lerp(Color(1, 0.75, 0.2), frac * 2.0) if frac < 0.5 else Color(1, 0.75, 0.2).lerp(Color(0.3, 1, 0.45), (frac - 0.5) * 2.0)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), hcol)
	for i in range(1, 4):
		var x := bar.position.x + bar.size.x * i / 4.0
		ci.draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.4), 1.0)
	ci.draw_rect(bar, Color(1, 1, 1, 0.25), false, 1.5)
	ci.draw_string(font, bar.position + Vector2(0, -8), "ЗДОРОВЬЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	ci.draw_string(font, Vector2(bar.end.x + 12, bar.end.y - 1), str(player.hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, hcol)

	if in_car and car:
		_speedo(ci, s, font, car)
	else:
		var panel := Rect2(s.x - 300, s.y - 118, 272, 90)
		ci.draw_rect(panel, Color(0.03, 0.03, 0.07, 0.72))
		var bc: Color = wd.color
		bc.a = 0.6
		ci.draw_rect(panel, bc, false, 1.5)
		Weapons.draw_icon(ci, player.weapon_id, panel.position + Vector2(14, 18), 54.0, wd.color)
		ci.draw_string(font, panel.position + Vector2(84, 30), wd.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
		if wd.melee:
			ci.draw_string(font, panel.position + Vector2(84, 66), "БЛИЖНИЙ БОЙ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.5))
		else:
			var mag := player.get_mag(player.weapon_id)
			ci.draw_string(font, panel.position + Vector2(84, 74), str(mag), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1) if mag > 0 else Color(1, 0.3, 0.25))
			ci.draw_string(font, panel.position + Vector2(140, 74), "ЗАПАС НЕ ОГРАНИЧЕН", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
			var rf := player.get_reload_frac()
			if rf > 0.0:
				ci.draw_rect(Rect2(panel.position.x, panel.end.y + 5, panel.size.x * rf, 5), wd.color)
				ci.draw_string(font, Vector2(panel.position.x, panel.end.y + 24), "ПЕРЕЗАРЯДКА...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, wd.color)
		for i in 3:
			var slot := Rect2(s.x - 300 + i * 62, s.y - 172, 56, 46)
			var active: bool = player.weapon_id == i
			var sc: Color = Weapons.DATA[i].color
			ci.draw_rect(slot, Color(0.03, 0.03, 0.07, 0.72))
			sc.a = 0.9 if active else 0.25
			ci.draw_rect(slot, sc, false, 2.0 if active else 1.0)
			Weapons.draw_icon(ci, i, slot.position + Vector2(13, 6), 30.0, Weapons.DATA[i].color if active else Color(1, 1, 1, 0.4))
			ci.draw_string(font, slot.position + Vector2(44, 40), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))

	if player.wheel_open:
		var wc := c
		var radius := 190.0
		ci.draw_circle(wc, radius + 26, Color(0.02, 0.02, 0.06, 0.66))
		var sel := Weapons.wheel_pick(player.wheel_vec, player.weapon_id)
		for id in Weapons.WHEEL_ANGLES:
			var a: float = Weapons.WHEEL_ANGLES[id]
			var wd2: Dictionary = Weapons.DATA[id]
			var pts := PackedVector2Array([wc])
			for k in range(17):
				var ang := a - deg_to_rad(54.0) + deg_to_rad(108.0) * k / 16.0
				pts.append(wc + Vector2.from_angle(ang) * radius)
			var fill: Color = wd2.color
			fill.a = 0.30 if id == sel else 0.10
			ci.draw_colored_polygon(pts, fill)
			var ip := wc + Vector2.from_angle(a) * (radius * 0.62)
			Weapons.draw_icon(ci, id, ip - Vector2(24, 24), 48.0, wd2.color if id == sel else Color(1, 1, 1, 0.75))
			ci.draw_string(font, ip + Vector2(-60, 44), wd2.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(1, 1, 1, 0.85))
		ci.draw_circle(wc, 34.0, Color(0.05, 0.05, 0.1, 0.9))
		ci.draw_string(font, wc + Vector2(-60, 5), "ОРУЖИЕ", HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(1, 1, 1, 0.8))

	_minimap(ci, font)
	_prompt(ci, s, font)
	if _toast_t > 0.0:
		ci.draw_string(font, Vector2(0, s.y - 240), _toast_text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(1, 0.9, 0.5, minf(1.0, _toast_t * 2.0)))

func _speedo(ci: Control, s: Vector2, font: Font, car: Car) -> void:
	var panel := Rect2(s.x - 300, s.y - 150, 272, 122)
	ci.draw_rect(panel, Color(0.03, 0.03, 0.07, 0.72))
	ci.draw_rect(panel, Color(0.95, 0.65, 0.15, 0.6), false, 1.5)
	var kmh := int(absf(car.forward_speed) * 3.6)
	var t := clampf(absf(car.forward_speed) / Car.MAX_SPEED, 0.0, 1.0)
	var center := panel.position + Vector2(70, 66)
	ci.draw_arc(center, 46.0, PI * 0.75, PI * 2.25, 40, Color(1, 1, 1, 0.15), 6.0, true)
	ci.draw_arc(center, 46.0, PI * 0.75, PI * 0.75 + PI * 1.5 * t, 40, Color(0.95, 0.65, 0.15).lerp(Color(1, 0.25, 0.2), t), 6.0, true)
	ci.draw_string(font, center + Vector2(-30, 8), str(kmh), HORIZONTAL_ALIGNMENT_CENTER, 60, 26, Color.WHITE)
	ci.draw_string(font, center + Vector2(-30, 26), "КМ/Ч", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(1, 1, 1, 0.5))
	ci.draw_string(font, panel.position + Vector2(140, 40), "ТАЧКА #" + str(car.car_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.75, 0.3))
	ci.draw_string(font, panel.position + Vector2(140, 64), "SPACE — РУЧНИК", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	ci.draw_string(font, panel.position + Vector2(140, 84), "E — ВЫЙТИ · H — СИГНАЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	if car.forward_speed < -0.5:
		ci.draw_string(font, panel.position + Vector2(140, 108), "R — ЗАДНИЙ ХОД", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.4, 0.3))

func _minimap(ci: Control, font: Font) -> void:
	var m := Rect2(20, 44, 170, 170)
	var span := 120.0
	var k := m.size.x / span
	var px := player.global_position
	var mc := m.position + m.size * 0.5
	ci.draw_rect(m.grow(2), Color(0.02, 0.02, 0.05, 0.85))
	ci.draw_rect(m, Color(0.07, 0.08, 0.1, 0.95))
	var L := City.layout()
	for line in City.ROAD_LINES:
		var rx := m.position.x + (line - px.x + span * 0.5) * k
		var rz := m.position.y + (line - px.z + span * 0.5) * k
		var rw := 8.0 * k
		var rv := Rect2(rx - rw * 0.5, m.position.y, rw, m.size.y).intersection(m)
		var rh := Rect2(m.position.x, rz - rw * 0.5, m.size.x, rw).intersection(m)
		if rv.size.x > 0.0:
			ci.draw_rect(rv, Color(0.16, 0.17, 0.2))
		if rh.size.y > 0.0:
			ci.draw_rect(rh, Color(0.16, 0.17, 0.2))
	for b in L.buildings:
		var bp: Vector3 = b.pos
		var bs: Vector3 = b.size
		var r := Rect2(m.position.x + (bp.x - bs.x * 0.5 - px.x + span * 0.5) * k, m.position.y + (bp.z - bs.z * 0.5 - px.z + span * 0.5) * k, bs.x * k, bs.z * k)
		var clipped := r.intersection(m)
		if clipped.size.x > 0.5 and clipped.size.y > 0.5:
			ci.draw_rect(clipped, Color(0.4, 0.42, 0.48, 0.9))
	for n in get_tree().get_nodes_in_group(&"car"):
		var car := n as Car
		var d := Vector2(car.global_position.x - px.x, car.global_position.z - px.z)
		if absf(d.x) < span * 0.5 and absf(d.y) < span * 0.5:
			ci.draw_circle(mc + d * k, 2.5, Color(0.95, 0.65, 0.15) if car.driver_id == 0 else Color(1, 0.4, 0.2))
	for n in get_tree().get_nodes_in_group(&"player"):
		var pl := n as Player
		if pl == player or pl.car_id != 0:
			continue
		var d := Vector2(pl.global_position.x - px.x, pl.global_position.z - px.z)
		if absf(d.x) < span * 0.5 and absf(d.y) < span * 0.5:
			ci.draw_circle(mc + d * k, 3.0, Color(1, 0.3, 0.3))
	var yaw := player.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	ci.draw_colored_polygon(PackedVector2Array([mc + fwd * 7.0, mc - fwd * 4.0 + side * 4.0, mc - fwd * 4.0 - side * 4.0]), Color(0.3, 1, 0.5))
	ci.draw_rect(m, Color(0.95, 0.65, 0.15, 0.5), false, 1.5)
	ci.draw_string(font, m.position + Vector2(m.size.x * 0.5 - 4, 13), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))

func _prompt(ci: Control, s: Vector2, font: Font) -> void:
	var text := ""
	if player.car_id != 0:
		text = "[E] ВЫЙТИ ИЗ ТАЧКИ · [H] СИГНАЛ"
	elif traffic and traffic.nearest_free_car(player.global_position) != null:
		text = "[E] ЗАЛЕТАЙ В ТАЧКУ"
	if text == "":
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var r := Rect2(s.x * 0.5 - w * 0.5 - 14, s.y - 208, w + 28, 30)
	ci.draw_rect(r, Color(0.03, 0.03, 0.07, 0.78))
	ci.draw_rect(r, Color(0.95, 0.65, 0.15, 0.7), false, 1.5)
	ci.draw_string(font, Vector2(r.position.x + 14, r.position.y + 21), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 0.9, 0.6))