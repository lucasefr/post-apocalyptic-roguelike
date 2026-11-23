extends Node2D
## Draws the visible part of the player's current layer (left 4/5 of the
## screen), plus items, creatures and the aim / inspect overlays.

const Tiles = preload("res://scripts/core/tile_types.gd")
const Combat = preload("res://scripts/game/combat.gd")

const TILE := 24
const MAP_WIDTH_FRACTION := 0.8
const GLYPH_SIZE := 20

var game  # main controller (scripts/main.gd)
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


func view_size_tiles() -> Vector2i:
	var vp := get_viewport_rect().size
	return Vector2i(ceili(vp.x * MAP_WIDTH_FRACTION / TILE), ceili(vp.y / TILE))


## Top-left map tile shown on screen (camera follows the player, clamped to the map).
func view_origin() -> Vector2i:
	var state = game.state
	var cols_rows := view_size_tiles()
	var origin: Vector2i = state.player.pos - cols_rows / 2
	origin.x = clampi(origin.x, 0, maxi(0, state.world.width - cols_rows.x))
	origin.y = clampi(origin.y, 0, maxi(0, state.world.height - cols_rows.y))
	return origin


func visible_rect() -> Rect2i:
	return Rect2i(view_origin(), view_size_tiles())


func _draw() -> void:
	if game == null or game.state == null:
		return
	var state = game.state
	var world = state.world
	var layer: int = state.player.layer
	var view := visible_rect()

	for y in view.size.y:
		for x in view.size.x:
			var p := view.position + Vector2i(x, y)
			if world.in_bounds(p):
				_draw_tile(world, layer, p, _screen_rect(p, view))

	for key in state.ground_items:
		var p := Vector2i(key.x, key.y)
		if key.z == layer and view.has_point(p):
			var item = state.ground_items[key]
			_draw_glyph(_screen_rect(p, view), item.glyph, item.color)

	for c in state.creatures:
		if c.layer == layer and view.has_point(c.pos):
			_draw_creature(c, _screen_rect(c.pos, view))

	match game.mode:
		game.Mode.AIMING:
			_draw_aim_overlay(state, view)
		game.Mode.INSPECT:
			_draw_target_icon(_screen_rect(game.inspect_target, view))


func _screen_rect(p: Vector2i, view: Rect2i) -> Rect2:
	return Rect2(Vector2(p - view.position) * TILE, Vector2(TILE, TILE))


func _draw_tile(world, layer: int, p: Vector2i, r: Rect2) -> void:
	var t: int = world.get_tile(layer, p)
	var info: Dictionary = Tiles.DATA[t]
	draw_rect(r, info["bg"])
	match info["shape"]:
		"building":
			# Light edge on every side that touches a different tile = readable outlines.
			var edge: Color = info["fg"]
			if world.get_tile(layer, p + Vector2i.UP) != t:
				draw_line(r.position, Vector2(r.end.x, r.position.y), edge, 2.0)
			if world.get_tile(layer, p + Vector2i.DOWN) != t:
				draw_line(Vector2(r.position.x, r.end.y - 1), Vector2(r.end.x, r.end.y - 1), edge, 2.0)
			if world.get_tile(layer, p + Vector2i.LEFT) != t:
				draw_line(r.position, Vector2(r.position.x, r.end.y), edge, 2.0)
			if world.get_tile(layer, p + Vector2i.RIGHT) != t:
				draw_line(Vector2(r.end.x - 1, r.position.y), Vector2(r.end.x - 1, r.end.y), edge, 2.0)
		"tree":
			draw_circle(r.get_center(), TILE * 0.45, info["fg"])
			draw_circle(r.get_center() + Vector2(-3, -3), TILE * 0.2, info["fg"].lightened(0.15))
		"bush":
			draw_circle(r.position + Vector2(8, 9), 5, info["fg"])
			draw_circle(r.position + Vector2(16, 14), 6, info["fg"])
			draw_circle(r.position + Vector2(9, 17), 4, info["fg"].darkened(0.1))
		"car":
			var body := r.grow(-3)
			draw_rect(body, info["fg"])
			draw_rect(Rect2(body.position + Vector2(3, 3), Vector2(body.size.x - 6, 5)), Color(0.15, 0.18, 0.2))
		"glyph":
			_draw_glyph(r, info["glyph"], info["fg"])


func _draw_creature(c, r: Rect2) -> void:
	draw_circle(r.get_center(), TILE * 0.46, Color(0, 0, 0, 0.55))
	_draw_glyph(r, c.glyph, c.color)
	if not c.is_player and c.hp < c.max_hp:
		var frac: float = float(c.hp) / c.max_hp
		draw_rect(Rect2(r.position + Vector2(2, TILE - 4), Vector2(TILE - 4, 3)), Color(0.3, 0, 0))
		draw_rect(Rect2(r.position + Vector2(2, TILE - 4), Vector2((TILE - 4) * frac, 3)), Color(0.9, 0.2, 0.2))


func _draw_glyph(r: Rect2, glyph: String, color: Color) -> void:
	if glyph == "":
		return
	draw_string(font, Vector2(r.position.x, r.position.y + TILE * 0.8), glyph,
			HORIZONTAL_ALIGNMENT_CENTER, TILE, GLYPH_SIZE, color)


func _draw_aim_overlay(state, view: Rect2i) -> void:
	var player = state.player
	var weapon = player.weapon
	var valid: bool = state.is_valid_attack_target(player, game.aim_target)
	# Faint tint on every tile within weapon range.
	for dy in range(-weapon.attack_range, weapon.attack_range + 1):
		for dx in range(-weapon.attack_range, weapon.attack_range + 1):
			var p: Vector2i = player.pos + Vector2i(dx, dy)
			var d := absi(dx) + absi(dy)
			if d >= 1 and d <= weapon.attack_range and view.has_point(p):
				draw_rect(_screen_rect(p, view), Color(1, 0.4, 0.4, 0.10))
	# Area of effect in red (grey when the target is not valid).
	var color := Color(1, 0.1, 0.1, 0.5) if valid else Color(0.6, 0.6, 0.6, 0.35)
	for p in Combat.area_tiles(game.aim_target, weapon.area):
		if view.has_point(p):
			draw_rect(_screen_rect(p, view), color)
	if view.has_point(game.aim_target):
		draw_rect(_screen_rect(game.aim_target, view), Color(1, 0.2, 0.2) if valid else Color(0.7, 0.7, 0.7), false, 2.0)


func _draw_target_icon(r: Rect2) -> void:
	var c := r.get_center()
	var col := Color(0.3, 0.9, 1.0)
	draw_arc(c, TILE * 0.42, 0, TAU, 24, col, 2.0)
	draw_line(c + Vector2(-TILE * 0.6, 0), c + Vector2(-TILE * 0.2, 0), col, 2.0)
	draw_line(c + Vector2(TILE * 0.2, 0), c + Vector2(TILE * 0.6, 0), col, 2.0)
	draw_line(c + Vector2(0, -TILE * 0.6), c + Vector2(0, -TILE * 0.2), col, 2.0)
	draw_line(c + Vector2(0, TILE * 0.2), c + Vector2(0, TILE * 0.6), col, 2.0)
