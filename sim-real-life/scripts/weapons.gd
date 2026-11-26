class_name Weapons
extends RefCounted
# Единая база стволов: клиент и сервер читают одни цифры — рассинхрона нет.

enum ID { FISTS, PISTOL, RIFLE }

const RESPAWN_TIME := 3.0

const DATA := {
	ID.FISTS: {
		"name": "КУЛАКИ", "dmg": 25, "rate": 0.45, "range": 2.6,
		"mag": 0, "reload": 0.0, "spread": 0.0, "auto": false, "melee": true,
		"color": Color(0.95, 0.75, 0.3),
	},
	ID.PISTOL: {
		"name": "ПИСТОЛЕТ", "dmg": 26, "rate": 0.26, "range": 90.0,
		"mag": 12, "reload": 1.25, "spread": 0.012, "auto": false, "melee": false,
		"color": Color(0.35, 0.8, 1.0),
	},
	ID.RIFLE: {
		"name": "АВТОМАТ", "dmg": 16, "rate": 0.095, "range": 130.0,
		"mag": 30, "reload": 1.8, "spread": 0.028, "auto": true, "melee": false,
		"color": Color(1.0, 0.35, 0.55),
	},
}

const WHEEL_ANGLES := {
	ID.FISTS: -PI / 2.0,
	ID.PISTOL: PI / 6.0,
	ID.RIFLE: PI * 5.0 / 6.0,
}

static func get_data(id: int) -> Dictionary:
	return DATA.get(id, DATA[ID.FISTS])

static func wheel_pick(vec: Vector2, current: int) -> int:
	if vec.length() < 24.0:
		return current
	var ang := vec.angle()
	var best := current
	var best_d := 100.0
	for id in WHEEL_ANGLES:
		var d := absf(angle_difference(ang, WHEEL_ANGLES[id]))
		if d < best_d:
			best_d = d
			best = id
	return best

# Иконки рисуем кодом — ноль ассетов, чистый вектор-свэг.
static func draw_icon(ci: CanvasItem, id: int, pos: Vector2, s: float, color: Color) -> void:
	match id:
		ID.FISTS:
			ci.draw_rect(Rect2(pos + Vector2(0.14, 0.38) * s, Vector2(0.72, 0.42) * s), color)
			for i in 4:
				ci.draw_rect(Rect2(pos + Vector2(0.14 + i * 0.19, 0.2) * s, Vector2(0.15, 0.22) * s), color)
			ci.draw_rect(Rect2(pos + Vector2(0.02, 0.46) * s, Vector2(0.14, 0.24) * s), color)
		ID.PISTOL:
			ci.draw_colored_polygon(_pts(pos, s, [[0.06,0.26],[0.94,0.26],[0.94,0.46],[0.46,0.46],[0.38,0.84],[0.16,0.84],[0.24,0.46],[0.06,0.46]]), color)
			ci.draw_rect(Rect2(pos + Vector2(0.5, 0.46) * s, Vector2(0.16, 0.1) * s), color)
		ID.RIFLE:
			ci.draw_rect(Rect2(pos + Vector2(0.04, 0.3) * s, Vector2(0.92, 0.14) * s), color)
			ci.draw_colored_polygon(_pts(pos, s, [[0.04,0.3],[0.16,0.3],[0.14,0.56],[0.02,0.56]]), color)
			ci.draw_colored_polygon(_pts(pos, s, [[0.48,0.44],[0.62,0.44],[0.58,0.78],[0.44,0.78]]), color)
			ci.draw_colored_polygon(_pts(pos, s, [[0.72,0.44],[0.82,0.44],[0.78,0.66],[0.7,0.66]]), color)
			ci.draw_rect(Rect2(pos + Vector2(0.58, 0.22) * s, Vector2(0.1, 0.08) * s), color)

static func _pts(pos: Vector2, s: float, arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(pos + Vector2(p[0], p[1]) * s)
	return out