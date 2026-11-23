extends RefCounted
## Catalogue of every tile type: display name, colors, how it is drawn,
## and whether creatures can walk on it / see through it.

enum {
	VOID,
	STREET,
	SIDEWALK,
	BUILDING_TALL,
	BUILDING_LOW,
	CAR,
	DIRT,
	FOREST_FLOOR,
	BUSH,
	TREE,
	RUBBLE,
	SEWER_FLOOR,
	SEWER_WALL,
	STAIRS_DOWN,
	STAIRS_UP,
}

## shape: how the renderer draws the tile ("flat", "building", "tree", "bush", "car", "glyph").
const DATA := {
	VOID: {"name": "Solid rock", "walkable": false, "opaque": true,
		"bg": Color(0.04, 0.04, 0.05), "fg": Color(0.04, 0.04, 0.05), "shape": "flat", "glyph": ""},
	STREET: {"name": "Street", "walkable": true, "opaque": false,
		"bg": Color(0.17, 0.17, 0.18), "fg": Color(0.25, 0.25, 0.26), "shape": "flat", "glyph": ""},
	SIDEWALK: {"name": "Sidewalk", "walkable": true, "opaque": false,
		"bg": Color(0.30, 0.29, 0.27), "fg": Color(0.36, 0.35, 0.33), "shape": "flat", "glyph": ""},
	BUILDING_TALL: {"name": "Tall building (city center)", "walkable": false, "opaque": true,
		"bg": Color(0.11, 0.15, 0.21), "fg": Color(0.28, 0.38, 0.50), "shape": "building", "glyph": ""},
	BUILDING_LOW: {"name": "Low building (outskirts)", "walkable": false, "opaque": true,
		"bg": Color(0.25, 0.19, 0.16), "fg": Color(0.45, 0.35, 0.28), "shape": "building", "glyph": ""},
	CAR: {"name": "Broken car", "walkable": false, "opaque": false,
		"bg": Color(0.17, 0.17, 0.18), "fg": Color(0.55, 0.27, 0.20), "shape": "car", "glyph": ""},
	DIRT: {"name": "Vacant lot", "walkable": true, "opaque": false,
		"bg": Color(0.24, 0.21, 0.15), "fg": Color(0.28, 0.25, 0.18), "shape": "flat", "glyph": ""},
	FOREST_FLOOR: {"name": "Forest floor", "walkable": true, "opaque": false,
		"bg": Color(0.12, 0.18, 0.10), "fg": Color(0.15, 0.22, 0.12), "shape": "flat", "glyph": ""},
	BUSH: {"name": "Dense undergrowth", "walkable": true, "opaque": true,
		"bg": Color(0.12, 0.18, 0.10), "fg": Color(0.27, 0.43, 0.20), "shape": "bush", "glyph": ""},
	TREE: {"name": "Tree", "walkable": false, "opaque": true,
		"bg": Color(0.09, 0.13, 0.06), "fg": Color(0.18, 0.35, 0.14), "shape": "tree", "glyph": ""},
	RUBBLE: {"name": "Rubble", "walkable": true, "opaque": false,
		"bg": Color(0.23, 0.21, 0.20), "fg": Color(0.42, 0.38, 0.35), "shape": "glyph", "glyph": ","},
	SEWER_FLOOR: {"name": "Sewer floor", "walkable": true, "opaque": false,
		"bg": Color(0.15, 0.19, 0.16), "fg": Color(0.19, 0.24, 0.20), "shape": "flat", "glyph": ""},
	SEWER_WALL: {"name": "Sewer wall", "walkable": false, "opaque": true,
		"bg": Color(0.07, 0.06, 0.05), "fg": Color(0.20, 0.18, 0.15), "shape": "building", "glyph": ""},
	STAIRS_DOWN: {"name": "Stairs down (manhole to sewers)", "walkable": true, "opaque": false,
		"bg": Color(0.17, 0.17, 0.18), "fg": Color(0.91, 0.77, 0.28), "shape": "glyph", "glyph": ">"},
	STAIRS_UP: {"name": "Stairs up (to surface)", "walkable": true, "opaque": false,
		"bg": Color(0.15, 0.19, 0.16), "fg": Color(0.91, 0.77, 0.28), "shape": "glyph", "glyph": "<"},
}


static func info(tile: int) -> Dictionary:
	return DATA[tile]


static func is_walkable(tile: int) -> bool:
	return DATA[tile]["walkable"]


static func is_opaque(tile: int) -> bool:
	return DATA[tile]["opaque"]


static func is_stairs(tile: int) -> bool:
	return tile == STAIRS_DOWN or tile == STAIRS_UP
