extends RefCounted
## Pure combat geometry helpers (no game state).

## Area interpretation: area 1 hits only the target tile; each extra point of
## area grows the hit zone by one tile in every orthogonal direction
## (a diamond with radius area - 1). Change AREA_RADIUS_OFFSET to 0 if you want
## "area 1" to already hit the 4 tiles around the target.
const AREA_RADIUS_OFFSET := 1


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func area_tiles(center: Vector2i, area: int) -> Array[Vector2i]:
	var radius: int = maxi(0, area - AREA_RADIUS_OFFSET)
	var tiles: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if absi(dx) + absi(dy) <= radius:
				tiles.append(center + Vector2i(dx, dy))
	return tiles


## Bresenham line; only the tiles strictly between both ends must be see-through.
static func has_line_of_sight(world, layer: int, from: Vector2i, to: Vector2i) -> bool:
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx + dy
	var p := from
	while p != to:
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
		if p != to and world.is_opaque(layer, p):
			return false
	return true


## A tile can be targeted when it is within weapon range (Manhattan distance),
## is not a wall and is visible from the attacker.
static func can_target(world, layer: int, attacker_pos: Vector2i, target: Vector2i, attack_range: int) -> bool:
	var d := manhattan(attacker_pos, target)
	if d < 1 or d > attack_range:
		return false
	if not world.in_bounds(target) or world.is_opaque(layer, target):
		return false
	return has_line_of_sight(world, layer, attacker_pos, target)
