extends RefCounted
## Procedurally builds the layered world:
##   Layer 0 - Surface: dense city center (tall buildings), sparse outskirts
##             (low buildings), streets with broken cars, surrounding forest.
##   Layer 1 - Sewers: small rooms joined by narrow corridors under the city.
## Stairs (manholes) connect both layers, and every walkable tile of every
## layer is guaranteed to be reachable.

const Tiles = preload("res://scripts/core/tile_types.gd")
const WorldMap = preload("res://scripts/world/world_map.gd")

const SURFACE := 0
const SEWERS := 1

const MAP_SIZE := 160
const BLOCK := 16            # city block period (street + sidewalk + lot)
const ROAD := 3              # street width in tiles
const CENTER_RADIUS := 34.0  # city center: tall, dense buildings
const CITY_RADIUS := 58.0    # outskirts end here; forest beyond
const EDGE_NOISE := 12.0     # makes zone borders ragged
const CAR_CHANCE := 0.04
const FOREST_TREE_CHANCE := 0.48
const FOREST_BUSH_CHANCE := 0.15
const STAIR_COUNT := 10
const STAIR_MIN_SPACING := 14
const EXTRA_SEWER_ROOMS := 28
const EXTRA_SEWER_LOOPS := 5

const DIRS4 := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

enum Zone { CENTER, OUTSKIRTS, FOREST }

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var world


func generate(seed_value: int):
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.04
	world = WorldMap.new(MAP_SIZE, MAP_SIZE, PackedStringArray(["Surface", "Sewers"]))
	_build_surface()
	_build_sewers()
	return world


func zone_at(x: int, y: int) -> int:
	var c := MAP_SIZE / 2.0
	var d := Vector2(x, y).distance_to(Vector2(c, c)) + noise.get_noise_2d(x, y) * EDGE_NOISE
	if d < CENTER_RADIUS:
		return Zone.CENTER
	if d < CITY_RADIUS:
		return Zone.OUTSKIRTS
	return Zone.FOREST


# ---------------------------------------------------------------- surface

func _build_surface() -> void:
	world.fill(SURFACE, Tiles.FOREST_FLOOR)
	var blocks := MAP_SIZE / BLOCK
	for by in blocks:
		for bx in blocks:
			var zone := zone_at(bx * BLOCK + BLOCK / 2, by * BLOCK + BLOCK / 2)
			if zone != Zone.FOREST:
				_build_block(bx, by, zone)
	_grow_forest()
	_scatter_cars()
	_add_border(SURFACE, Tiles.TREE)
	connect_regions(SURFACE)


func _build_block(bx: int, by: int, zone: int) -> void:
	var x0 := bx * BLOCK
	var y0 := by * BLOCK
	var lot_fill := Tiles.SIDEWALK if zone == Zone.CENTER else Tiles.DIRT
	for ly in BLOCK:
		for lx in BLOCK:
			var t: int
			if lx < ROAD or ly < ROAD:
				t = Tiles.STREET
			elif lx == ROAD or ly == ROAD or lx == BLOCK - 1 or ly == BLOCK - 1:
				t = Tiles.SIDEWALK
			else:
				t = lot_fill
			world.set_tile(SURFACE, Vector2i(x0 + lx, y0 + ly), t)
	var lot := Rect2i(x0 + ROAD + 1, y0 + ROAD + 1, BLOCK - ROAD - 2, BLOCK - ROAD - 2)
	if zone == Zone.CENTER:
		_fill_center_lot(lot)
	else:
		_fill_outskirts_lot(lot)


## City center: the lot is (almost) fully covered by one or two tall buildings.
func _fill_center_lot(lot: Rect2i) -> void:
	var layout := rng.randi_range(0, 3)
	if layout == 0:
		_fill_rect(SURFACE, lot, Tiles.BUILDING_TALL)
	elif layout == 1:  # two buildings split by a vertical alley
		var cut := rng.randi_range(lot.position.x + 3, lot.end.x - 4)
		_fill_rect(SURFACE, Rect2i(lot.position.x, lot.position.y, cut - lot.position.x, lot.size.y), Tiles.BUILDING_TALL)
		_fill_rect(SURFACE, Rect2i(cut + 1, lot.position.y, lot.end.x - cut - 1, lot.size.y), Tiles.BUILDING_TALL)
	elif layout == 2:  # two buildings split by a horizontal alley
		var cut := rng.randi_range(lot.position.y + 3, lot.end.y - 4)
		_fill_rect(SURFACE, Rect2i(lot.position.x, lot.position.y, lot.size.x, cut - lot.position.y), Tiles.BUILDING_TALL)
		_fill_rect(SURFACE, Rect2i(lot.position.x, cut + 1, lot.size.x, lot.end.y - cut - 1), Tiles.BUILDING_TALL)
	else:  # partially collapsed tower: smaller core surrounded by rubble
		_fill_rect(SURFACE, lot, Tiles.RUBBLE)
		_fill_rect(SURFACE, lot.grow(-2), Tiles.BUILDING_TALL)


## Outskirts: few small, low buildings on vacant lots with some vegetation.
func _fill_outskirts_lot(lot: Rect2i) -> void:
	if rng.randf() < 0.75:
		for i in rng.randi_range(1, 2):
			var w := rng.randi_range(3, 6)
			var h := rng.randi_range(3, 6)
			var x := rng.randi_range(lot.position.x, lot.end.x - w)
			var y := rng.randi_range(lot.position.y, lot.end.y - h)
			_fill_rect(SURFACE, Rect2i(x, y, w, h), Tiles.BUILDING_LOW)
	for y in range(lot.position.y, lot.end.y):
		for x in range(lot.position.x, lot.end.x):
			var p := Vector2i(x, y)
			if world.get_tile(SURFACE, p) != Tiles.DIRT:
				continue
			var roll := rng.randf()
			if roll < 0.03:
				world.set_tile(SURFACE, p, Tiles.TREE)
			elif roll < 0.09:
				world.set_tile(SURFACE, p, Tiles.BUSH)


## Dense forest via cellular automata on every tile that is still forest floor.
func _grow_forest() -> void:
	var w: int = world.width
	var h: int = world.height
	var mask := PackedByteArray()
	mask.resize(w * h)
	var trees := PackedByteArray()
	trees.resize(w * h)
	for i in w * h:
		var is_forest: bool = world.layers[SURFACE][i] == Tiles.FOREST_FLOOR
		mask[i] = 1 if is_forest else 0
		trees[i] = 1 if is_forest and rng.randf() < FOREST_TREE_CHANCE else 0
	for _step in 4:
		var next := trees.duplicate()
		for y in h:
			for x in w:
				var i := y * w + x
				if mask[i] == 0:
					continue
				var count := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nx := x + dx
						var ny := y + dy
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							count += 1
						else:
							count += trees[ny * w + nx]
				if count >= 5:
					next[i] = 1
				elif count <= 3:
					next[i] = 0
		trees = next
	for i in w * h:
		if mask[i] == 0:
			continue
		if trees[i] == 1:
			world.layers[SURFACE][i] = Tiles.TREE
		elif rng.randf() < FOREST_BUSH_CHANCE:
			world.layers[SURFACE][i] = Tiles.BUSH


func _scatter_cars() -> void:
	var grid: PackedByteArray = world.layers[SURFACE]
	for i in grid.size():
		if grid[i] == Tiles.STREET and rng.randf() < CAR_CHANCE:
			grid[i] = Tiles.CAR
	world.layers[SURFACE] = grid


# ---------------------------------------------------------------- sewers

func _build_sewers() -> void:
	world.fill(SEWERS, Tiles.SEWER_WALL)
	var rooms: Array[Rect2i] = []
	var interior := Rect2i(1, 1, MAP_SIZE - 2, MAP_SIZE - 2)

	# 1. Pick manhole positions on surface streets, spread apart.
	var candidates: Array[Vector2i] = []
	for y in range(3, MAP_SIZE - 3):
		for x in range(3, MAP_SIZE - 3):
			if world.get_tile(SURFACE, Vector2i(x, y)) == Tiles.STREET:
				candidates.append(Vector2i(x, y))
	_shuffle(candidates)
	var stairs: Array[Vector2i] = []
	for c in candidates:
		if stairs.size() >= STAIR_COUNT:
			break
		var ok := true
		for s in stairs:
			if absi(s.x - c.x) + absi(s.y - c.y) < STAIR_MIN_SPACING:
				ok = false
				break
		if ok:
			stairs.append(c)

	# 2. Every manhole gets a small room right under it.
	for s in stairs:
		var w := rng.randi_range(3, 5)
		var h := rng.randi_range(3, 5)
		var room := Rect2i(s.x - rng.randi_range(0, w - 1), s.y - rng.randi_range(0, h - 1), w, h)
		rooms.append(room.intersection(interior))

	# 3. Extra rooms anywhere under the city.
	var tries := 0
	var added := 0
	var c := MAP_SIZE / 2
	var r := int(CITY_RADIUS)
	while added < EXTRA_SEWER_ROOMS and tries < 600:
		tries += 1
		var w := rng.randi_range(3, 6)
		var h := rng.randi_range(3, 6)
		var room := Rect2i(rng.randi_range(c - r, c + r - w), rng.randi_range(c - r, c + r - h), w, h)
		room = room.intersection(interior)
		if room.size.x < 3 or room.size.y < 3:
			continue
		var center := room.get_center()
		if zone_at(center.x, center.y) == Zone.FOREST:
			continue
		var overlaps := false
		for other in rooms:
			if other.grow(1).intersects(room):
				overlaps = true
				break
		if overlaps:
			continue
		rooms.append(room)
		added += 1

	for room in rooms:
		_fill_rect(SEWERS, room, Tiles.SEWER_FLOOR)
	_connect_rooms(rooms)

	for s in stairs:
		world.set_tile(SURFACE, s, Tiles.STAIRS_DOWN)
		world.set_tile(SEWERS, s, Tiles.STAIRS_UP)
	connect_regions(SEWERS)


## Prim-style: link each room to the closest already-connected room, then add a few loops.
func _connect_rooms(rooms: Array[Rect2i]) -> void:
	if rooms.size() < 2:
		return
	var connected: Array[int] = [0]
	var remaining: Array[int] = []
	for i in range(1, rooms.size()):
		remaining.append(i)
	while not remaining.is_empty():
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a in connected:
			for b in remaining:
				var d := Vector2(rooms[a].get_center()).distance_squared_to(Vector2(rooms[b].get_center()))
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		_carve_corridor(rooms[best_a].get_center(), rooms[best_b].get_center())
		connected.append(best_b)
		remaining.erase(best_b)
	for _i in EXTRA_SEWER_LOOPS:
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b:
			_carve_corridor(rooms[a].get_center(), rooms[b].get_center())


## Narrow (1 tile) L-shaped corridor.
func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var corner := Vector2i(to.x, from.y) if rng.randf() < 0.5 else Vector2i(from.x, to.y)
	for segment in [[from, corner], [corner, to]]:
		var a: Vector2i = segment[0]
		var b: Vector2i = segment[1]
		var step := (b - a).sign()
		var p := a
		while true:
			if world.get_tile(SEWERS, p) == Tiles.SEWER_WALL:
				world.set_tile(SEWERS, p, Tiles.SEWER_FLOOR)
			if p == b:
				break
			p += step


# ---------------------------------------------------------------- helpers

## Guarantees one connected walkable region: every isolated pocket gets a
## tunnel carved (through trees, wrecks or walls) to the largest region.
func connect_regions(layer: int) -> void:
	var w: int = world.width
	var h: int = world.height
	var n := w * h
	var grid: PackedByteArray = world.layers[layer]
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(-1)
	var sizes: Array[int] = []
	for start in n:
		if labels[start] != -1 or not Tiles.is_walkable(grid[start]):
			continue
		var label := sizes.size()
		var count := 0
		var stack: Array[int] = [start]
		labels[start] = label
		while not stack.is_empty():
			var i: int = stack.pop_back()
			count += 1
			var x := i % w
			var y := i / w
			for d in DIRS4:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if labels[j] == -1 and Tiles.is_walkable(grid[j]):
					labels[j] = label
					stack.append(j)
		sizes.append(count)
	if sizes.size() <= 1:
		return
	var main := 0
	for r in sizes.size():
		if sizes[r] > sizes[main]:
			main = r

	# BFS from the main region over every interior tile (walls included).
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var queue := PackedInt32Array()
	for i in n:
		if labels[i] == main:
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % w
		var y := i / w
		for d in DIRS4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 1 or ny < 1 or nx >= w - 1 or ny >= h - 1:
				continue
			var j := ny * w + nx
			if dist[j] == -1:
				dist[j] = dist[i] + 1
				parent[j] = i
				queue.append(j)

	var closest := {}
	for i in n:
		var r := labels[i]
		if r < 0 or r == main or dist[i] < 0:
			continue
		if not closest.has(r) or dist[i] < dist[closest[r]]:
			closest[r] = i
	for r in closest:
		var i: int = closest[r]
		while i != -1 and dist[i] > 0:
			if not Tiles.is_walkable(grid[i]):
				grid[i] = _carved_tile(grid[i])
			i = parent[i]
	world.layers[layer] = grid


func _carved_tile(old: int) -> int:
	match old:
		Tiles.TREE, Tiles.BUSH:
			return Tiles.FOREST_FLOOR
		Tiles.CAR:
			return Tiles.STREET
		Tiles.SEWER_WALL, Tiles.VOID:
			return Tiles.SEWER_FLOOR
	return Tiles.RUBBLE


func _fill_rect(layer: int, rect: Rect2i, tile: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			world.set_tile(layer, Vector2i(x, y), tile)


func _add_border(layer: int, tile: int) -> void:
	for i in MAP_SIZE:
		world.set_tile(layer, Vector2i(i, 0), tile)
		world.set_tile(layer, Vector2i(i, MAP_SIZE - 1), tile)
		world.set_tile(layer, Vector2i(0, i), tile)
		world.set_tile(layer, Vector2i(MAP_SIZE - 1, i), tile)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
