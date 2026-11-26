class_name City
extends RefCounted
# Детерминированный генератор района: один seed — одинаковый город у всех пиров, ноль трафика.

const HALF := 156.0
const ROAD_LINES := [-147.0, -105.0, -63.0, -21.0, 21.0, 63.0, 105.0, 147.0]
const CENTERS := [-126.0, -84.0, -42.0, 0.0, 42.0, 84.0, 126.0]

static var _data: Dictionary = {}

static func layout() -> Dictionary:
	if not _data.is_empty():
		return _data
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261126
	var buildings: Array = []
	var trees: Array = []
	var parks: Array = []
	var cars: Array = []
	var palette := [
		Color(0.52, 0.48, 0.44), Color(0.38, 0.4, 0.48),
		Color(0.58, 0.53, 0.47), Color(0.32, 0.28, 0.3),
		Color(0.45, 0.5, 0.55), Color(0.5, 0.42, 0.36),
	]
	for bx in CENTERS:
		for bz in CENTERS:
			var center := Vector2(bx, bz)
			if center.length() < 30.0:
				continue  # центральная плаза — спавн-зона
			if rng.randf() < 0.15:
				parks.append(center)
				for t in 7:
					trees.append(Vector3(bx + rng.randf_range(-13.0, 13.0), 0.0, bz + rng.randf_range(-13.0, 13.0)))
				continue
			var dist := center.length()
			for cx in [-8.0, 8.0]:
				for cz in [-8.0, 8.0]:
					if rng.randf() < 0.16:
						continue
					var w := rng.randf_range(6.5, 12.0)
					var d := rng.randf_range(6.5, 12.0)
					var h := rng.randf_range(5.0, 14.0) * clampf(1.7 - dist / 200.0, 0.55, 1.7)
					var col: Color = palette[rng.randi_range(0, palette.size() - 1)]
					if rng.randf() < 0.08:
						col = Color(0.2, 0.45, 0.6)
					buildings.append({
						"pos": Vector3(bx + cx + rng.randf_range(-1.5, 1.5), h * 0.5, bz + cz + rng.randf_range(-1.5, 1.5)),
						"size": Vector3(w, h, d),
						"color": col,
					})
	# лендмарк-башня, чтоб не заблудиться
	buildings.append({"pos": Vector3(42.0, 27.5, -42.0), "size": Vector3(12.0, 55.0, 12.0), "color": Color(0.25, 0.5, 0.65)})
	var ramps := [
		{"pos": Vector3(0.0, 2.55, 18.0), "size": Vector3(9.0, 0.6, 16.0), "rot": -0.31},
		{"pos": Vector3(-63.0, 2.55, 0.0), "size": Vector3(9.0, 0.6, 16.0), "rot": -0.31},
		{"pos": Vector3(21.0, 2.55, 84.0), "size": Vector3(9.0, 0.6, 16.0), "rot": -0.31},
	]
	var car_cols := [
		Color(0.85, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.65, 0.15),
		Color(0.2, 0.75, 0.4), Color(0.85, 0.85, 0.9), Color(0.6, 0.2, 0.7),
		Color(0.15, 0.15, 0.18),
	]
	cars.append({"pos": Vector3(8.0, 0.4, 6.0), "rot": 0.4, "color": car_cols[0]})
	cars.append({"pos": Vector3(-8.0, 0.4, -6.0), "rot": -2.6, "color": car_cols[1]})
	var ci := 2
	for line in ROAD_LINES:
		if ci >= 14:
			break
		var along := rng.randf_range(-130.0, 130.0)
		cars.append({"pos": Vector3(line + 2.6, 0.4, along), "rot": 0.0, "color": car_cols[ci % car_cols.size()]})
		ci += 1
		if ci >= 14:
			break
		cars.append({"pos": Vector3(along, 0.4, line - 2.6), "rot": PI / 2.0, "color": car_cols[ci % car_cols.size()]})
		ci += 1
	_data = {"buildings": buildings, "trees": trees, "parks": parks, "ramps": ramps, "cars": cars}
	return _data