extends RefCounted
## Whole game model: world, creatures, ground items, turn order and rules.
## Player actions return true when they spend the player's turn; the caller
## then calls end_player_turn() so every enemy acts once.

const Tiles = preload("res://scripts/core/tile_types.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Templates = preload("res://scripts/entities/templates.gd")
const ItemData = preload("res://scripts/entities/item_data.gd")
const Combat = preload("res://scripts/game/combat.gd")
const ZombieAI = preload("res://scripts/ai/zombie_ai.gd")

const ZOMBIES_PER_LAYER := [140, 35]       # surface, sewers
const ITEMS_ON_MAP := {"consumable": 45, "weapon": 10, "armor": 10}
const MIN_SPAWN_DISTANCE := 12             # zombies never spawn this close to the player
const AGGRO_RADIUS := 30                   # zombies farther than this (in steps) stay idle
const MAX_MESSAGES := 60

const DIRS4 := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var world
var rng := RandomNumberGenerator.new()
var seed_value := 0
var player
var creatures: Array = []
var occupancy := {}    # Vector3i(x, y, layer) -> creature
var ground_items := {} # Vector3i(x, y, layer) -> item
var turn := 0
var game_over := false
var messages: Array[String] = []

var _distance_field := PackedInt32Array()
var _distance_layer := -1


func new_game(new_seed: int) -> void:
	seed_value = new_seed
	rng.seed = new_seed
	world = WorldGenerator.new().generate(new_seed)
	creatures.clear()
	occupancy.clear()
	ground_items.clear()
	turn = 0
	game_over = false
	messages.clear()
	_distance_field.resize(world.width * world.height)

	player = Templates.player()
	_place_creature(player, _random_free_tile_any_layer())
	player.add_item(Templates.consumable_template())

	for layer in world.layer_count():
		for i in ZOMBIES_PER_LAYER[layer]:
			var p = _random_free_tile(layer, true)
			if p != null:
				var z = Templates.zombie()
				z.layer = layer
				_place_creature(z, p)

	for kind in ITEMS_ON_MAP:
		for i in ITEMS_ON_MAP[kind]:
			var spot = _random_free_tile_any_layer()
			var item
			match kind:
				"weapon": item = Templates.weapon_template()
				"armor": item = Templates.armor_template()
				_: item = Templates.consumable_template()
			ground_items[_key(spot.z, Vector2i(spot.x, spot.y))] = item

	add_message("You wake up %s. Survive." % ("on the surface" if player.layer == 0 else "in the sewers"))
	add_message("WASD move | hold SPACE aim, release to fire | hold SHIFT inspect | 1-4 use/equip | CTRL+1-4 drop")
	_update_distance_field()


# ---------------------------------------------------------------- queries

func _key(layer: int, p: Vector2i) -> Vector3i:
	return Vector3i(p.x, p.y, layer)


func creature_at(layer: int, p: Vector2i):
	return occupancy.get(_key(layer, p))


func item_at(layer: int, p: Vector2i):
	return ground_items.get(_key(layer, p))


func is_free(layer: int, p: Vector2i) -> bool:
	return world.is_walkable(layer, p) and not occupancy.has(_key(layer, p))


func distance_to_player(p: Vector2i) -> int:
	if not world.in_bounds(p):
		return -1
	return _distance_field[world.index(p)]


func is_valid_attack_target(attacker, target: Vector2i) -> bool:
	return Combat.can_target(world, attacker.layer, attacker.pos, target, attacker.weapon.attack_range)


## Suggested aim when the attack key is pressed: nearest enemy in range,
## otherwise as far as possible in the facing direction.
func default_aim_target(attacker) -> Vector2i:
	var best = null
	var best_d := 1 << 30
	for c in creatures:
		if c == attacker or c.layer != attacker.layer:
			continue
		var d := Combat.manhattan(attacker.pos, c.pos)
		if d < best_d and is_valid_attack_target(attacker, c.pos):
			best = c
			best_d = d
	if best != null:
		return best.pos
	var target: Vector2i = attacker.pos
	for i in range(1, attacker.weapon.attack_range + 1):
		var p: Vector2i = attacker.pos + attacker.facing * i
		if world.is_opaque(attacker.layer, p):
			break
		target = p
	return target


# ---------------------------------------------------------------- player actions

func player_move(dir: Vector2i) -> bool:
	player.facing = dir
	var target: Vector2i = player.pos + dir
	if not world.is_walkable(player.layer, target):
		return false
	var blocker = creature_at(player.layer, target)
	if blocker != null:
		add_message("A %s blocks the way. Attack it with SPACE." % blocker.display_name.to_lower())
		return false
	move_creature(player, target)
	_try_use_stairs()
	_try_pick_up()
	return true


func player_attack(target: Vector2i) -> bool:
	if not is_valid_attack_target(player, target):
		add_message("Target out of range or not visible.")
		return false
	player.facing = (target - player.pos).sign()
	perform_attack(player, target)
	return true


## Consumables are used; weapons and armor are equipped (swapping the old one in).
func player_use_slot(slot: int) -> bool:
	if slot >= player.inventory_size:
		return false
	var item = player.inventory[slot]
	if item == null:
		add_message("Inventory slot %d is empty." % (slot + 1))
		return false
	match item.type:
		ItemData.Type.CONSUMABLE:
			var healed: int = player.heal(item.heal_amount)
			player.inventory[slot] = null
			add_message("You use the %s and recover %d HP." % [item.display_name, healed])
		ItemData.Type.WEAPON, ItemData.Type.ARMOR:
			player.equip_from_slot(slot)
			add_message("You equip the %s." % item.display_name)
	return true


func player_drop(slot: int) -> bool:
	if slot >= player.inventory_size or player.inventory[slot] == null:
		return false
	if item_at(player.layer, player.pos) != null:
		add_message("There is already an item on this tile.")
		return false
	var item = player.inventory[slot]
	player.inventory[slot] = null
	ground_items[_key(player.layer, player.pos)] = item
	add_message("You drop the %s." % item.display_name)
	return true


func end_player_turn() -> void:
	turn += 1
	_update_distance_field()
	for c in creatures.duplicate():
		if game_over:
			break
		if c.is_player or c.is_dead():
			continue
		match c.ai_behavior:
			"zombie":
				ZombieAI.take_turn(c, self)


# ---------------------------------------------------------------- shared rules

func move_creature(c, target: Vector2i) -> void:
	occupancy.erase(_key(c.layer, c.pos))
	c.pos = target
	occupancy[_key(c.layer, c.pos)] = c


## Weapon damage hits every creature (except the attacker) in the weapon area
## centered on the target tile; armor of the matching damage type reduces it.
func perform_attack(attacker, target: Vector2i) -> void:
	var weapon = attacker.weapon
	var hit_anything := false
	for tile in Combat.area_tiles(target, weapon.area):
		var victim = creature_at(attacker.layer, tile)
		if victim == null or victim == attacker:
			continue
		hit_anything = true
		var dealt: int = victim.receive_damage(weapon.damage, weapon.damage_type)
		if attacker.is_player:
			add_message("You hit the %s for %d (%d/%d HP)." % [victim.display_name.to_lower(), dealt, victim.hp, victim.max_hp])
		elif victim.is_player:
			if dealt > 0:
				add_message("The %s bites you for %d damage!" % [attacker.display_name.to_lower(), dealt])
			else:
				add_message("The %s attacks, but your armor absorbs it." % attacker.display_name.to_lower())
		if victim.is_dead():
			_kill(victim)
	if attacker.is_player and not hit_anything:
		add_message("Your attack hits nothing.")


func add_message(text: String) -> void:
	messages.append(text)
	if messages.size() > MAX_MESSAGES:
		messages.pop_front()


# ---------------------------------------------------------------- internals

func _kill(c) -> void:
	occupancy.erase(_key(c.layer, c.pos))
	creatures.erase(c)
	if c.is_player:
		game_over = true
		add_message("You died on turn %d. Press R to start a new world." % turn)
	else:
		add_message("The %s is destroyed." % c.display_name.to_lower())


func _place_creature(c, spot: Vector3i) -> void:
	c.layer = spot.z
	c.pos = Vector2i(spot.x, spot.y)
	creatures.append(c)
	occupancy[_key(c.layer, c.pos)] = c


func _try_use_stairs() -> void:
	var tile: int = world.get_tile(player.layer, player.pos)
	var dest_layer := -1
	var dest_tile := -1
	if tile == Tiles.STAIRS_DOWN and player.layer + 1 < world.layer_count():
		dest_layer = player.layer + 1
		dest_tile = Tiles.STAIRS_UP
	elif tile == Tiles.STAIRS_UP and player.layer > 0:
		dest_layer = player.layer - 1
		dest_tile = Tiles.STAIRS_DOWN
	if dest_layer < 0 or world.get_tile(dest_layer, player.pos) != dest_tile:
		return
	if creature_at(dest_layer, player.pos) != null:
		add_message("Something is blocking the other end of the stairs.")
		return
	occupancy.erase(_key(player.layer, player.pos))
	player.layer = dest_layer
	occupancy[_key(player.layer, player.pos)] = player
	add_message("You climb %s to the %s." % ["down" if dest_tile == Tiles.STAIRS_UP else "up", world.layer_names[dest_layer].to_lower()])


func _try_pick_up() -> void:
	var item = item_at(player.layer, player.pos)
	if item == null:
		return
	if player.add_item(item):
		ground_items.erase(_key(player.layer, player.pos))
		add_message("You pick up the %s." % item.display_name)
	else:
		add_message("A %s lies here, but your inventory is full." % item.display_name)


func _random_free_tile_any_layer() -> Vector3i:
	for _i in 100000:
		var layer := rng.randi_range(0, world.layer_count() - 1)
		var p := Vector2i(rng.randi_range(0, world.width - 1), rng.randi_range(0, world.height - 1))
		if _is_spawnable(layer, p, false):
			return Vector3i(p.x, p.y, layer)
	push_error("No free tile found")
	return Vector3i.ZERO


func _random_free_tile(layer: int, away_from_player: bool):
	for _i in 100000:
		var p := Vector2i(rng.randi_range(0, world.width - 1), rng.randi_range(0, world.height - 1))
		if _is_spawnable(layer, p, away_from_player):
			return Vector3i(p.x, p.y, layer)
	return null


func _is_spawnable(layer: int, p: Vector2i, away_from_player: bool) -> bool:
	if not is_free(layer, p) or Tiles.is_stairs(world.get_tile(layer, p)):
		return false
	if item_at(layer, p) != null:
		return false
	if away_from_player and player != null and player.layer == layer \
			and Combat.manhattan(player.pos, p) < MIN_SPAWN_DISTANCE:
		return false
	return true


## Breadth-first distances from the player (walkable tiles, same layer),
## limited to AGGRO_RADIUS. Used by the AI to step around obstacles.
func _update_distance_field() -> void:
	_distance_field.fill(-1)
	_distance_layer = player.layer
	var w: int = world.width
	var start: int = world.index(player.pos)
	_distance_field[start] = 0
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var d := _distance_field[i]
		if d >= AGGRO_RADIUS:
			continue
		var p := Vector2i(i % w, i / w)
		for dir in DIRS4:
			var np: Vector2i = p + dir
			if not world.is_walkable(player.layer, np):
				continue
			var j: int = world.index(np)
			if _distance_field[j] == -1:
				_distance_field[j] = d + 1
				queue.append(j)
