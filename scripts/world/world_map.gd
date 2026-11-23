extends RefCounted
## Layered 2D grid. All layers share the same size so stairs line up:
## a staircase at (x, y) on one layer leads to (x, y) on the adjacent layer.

const Tiles = preload("res://scripts/core/tile_types.gd")

var width := 0
var height := 0
var layer_names: PackedStringArray = []
var layers: Array[PackedByteArray] = []


func _init(w: int, h: int, names: PackedStringArray) -> void:
	width = w
	height = h
	layer_names = names
	for i in names.size():
		var grid := PackedByteArray()
		grid.resize(w * h)
		grid.fill(Tiles.VOID)
		layers.append(grid)


func layer_count() -> int:
	return layers.size()


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func index(p: Vector2i) -> int:
	return p.y * width + p.x


func get_tile(layer: int, p: Vector2i) -> int:
	if not in_bounds(p):
		return Tiles.VOID
	return layers[layer][p.y * width + p.x]


func set_tile(layer: int, p: Vector2i, tile: int) -> void:
	if in_bounds(p):
		layers[layer][p.y * width + p.x] = tile


func fill(layer: int, tile: int) -> void:
	layers[layer].fill(tile)


func is_walkable(layer: int, p: Vector2i) -> bool:
	return in_bounds(p) and Tiles.is_walkable(get_tile(layer, p))


func is_opaque(layer: int, p: Vector2i) -> bool:
	return not in_bounds(p) or Tiles.is_opaque(get_tile(layer, p))
