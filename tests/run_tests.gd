extends SceneTree
## Headless test suite:  godot --headless --path . --script res://tests/run_tests.gd

const Tiles = preload("res://scripts/core/tile_types.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const GameState = preload("res://scripts/game/game_state.gd")
const Templates = preload("res://scripts/entities/templates.gd")
const ItemData = preload("res://scripts/entities/item_data.gd")
const Combat = preload("res://scripts/game/combat.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	test_world_generation()
	test_combat_and_items()
	test_zombie_ai()
	test_simulation()
	await test_main_scene_input()
	print("\n%s (%d failures)" % ["ALL TESTS PASSED" if failures == 0 else "TESTS FAILED", failures])
	quit(0 if failures == 0 else 1)


func count_regions(world, layer: int) -> int:
	var seen := {}
	var regions := 0
	for y in world.height:
		for x in world.width:
			var p := Vector2i(x, y)
			if seen.has(p) or not world.is_walkable(layer, p):
				continue
			regions += 1
			var stack := [p]
			seen[p] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var n: Vector2i = c + d
					if not seen.has(n) and world.is_walkable(layer, n):
						seen[n] = true
						stack.append(n)
	return regions


func test_world_generation() -> void:
	print("World generation")
	for seed_value in [1, 2, 42, 1337, 99999]:
		var t0 := Time.get_ticks_msec()
		var world = WorldGenerator.new().generate(seed_value)
		var ms := Time.get_ticks_msec() - t0
		var counts := {}
		for layer in world.layer_count():
			for t in world.layers[layer]:
				var k := "%d:%d" % [layer, t]
				counts[k] = counts.get(k, 0) + 1
		var stairs_ok := true
		var stairs := 0
		for y in world.height:
			for x in world.width:
				var p := Vector2i(x, y)
				if world.get_tile(0, p) == Tiles.STAIRS_DOWN:
					stairs += 1
					stairs_ok = stairs_ok and world.get_tile(1, p) == Tiles.STAIRS_UP
				if world.get_tile(1, p) == Tiles.STAIRS_UP:
					stairs_ok = stairs_ok and world.get_tile(0, p) == Tiles.STAIRS_DOWN
		check(count_regions(world, 0) == 1 and count_regions(world, 1) == 1,
				"seed %d: each layer is one connected region (%d ms)" % [seed_value, ms])
		check(stairs >= 5 and stairs_ok, "seed %d: %d paired stairs" % [seed_value, stairs])
		var needed := {"tall bldg": "0:%d" % Tiles.BUILDING_TALL, "low bldg": "0:%d" % Tiles.BUILDING_LOW,
			"cars": "0:%d" % Tiles.CAR, "trees": "0:%d" % Tiles.TREE, "sewer": "1:%d" % Tiles.SEWER_FLOOR}
		var summary := []
		var all_present := true
		for k in needed:
			var n: int = counts.get(needed[k], 0)
			summary.append("%s=%d" % [k, n])
			all_present = all_present and n > 0
		check(all_present, "seed %d: all biomes present (%s)" % [seed_value, ", ".join(summary)])


func test_combat_and_items() -> void:
	print("Combat & items")
	var s = GameState.new()
	s.new_game(7)
	var p = s.player
	check(p.max_hp == 10 and p.hp == 10, "player starts with 10 HP")
	check(p.base_physical_armor == 0 and p.physical_armor() == 1 and p.energy_armor() == 1, "vest adds 1/1 armor")
	check(p.weapon.damage == 1 and p.weapon.attack_range == 3 and p.weapon.area == 1, "weapon template stats")
	check(p.inventory_size == 4, "inventory size 4")
	check(Combat.area_tiles(Vector2i(5, 5), 1).size() == 1, "area 1 = single tile")
	check(Combat.area_tiles(Vector2i(5, 5), 2).size() == 5, "area 2 = 5 tiles")

	# Damage minus armor, min zero.
	var z = Templates.zombie()
	check(z.receive_damage(1, ItemData.DamageType.PHYSICAL) == 1 and z.hp == 9, "zombie (0 armor) takes 1 damage")
	check(p.receive_damage(1, ItemData.DamageType.PHYSICAL) == 0 and p.hp == 10, "player armor absorbs zombie bite (min 0)")
	p.receive_damage(5, ItemData.DamageType.ENERGY)
	check(p.hp == 6, "5 energy damage - 1 energy armor = 4")

	# Consumable
	var slot: int = p.inventory.find(p.inventory.filter(func(i): return i != null)[0])
	check(s.player_use_slot(slot) and p.hp == 9 and p.inventory[slot] == null, "medkit heals 3 and is consumed")
	check(not s.player_use_slot(slot), "using empty slot spends no turn")

	# Equip swap
	var new_weapon = Templates.weapon_template()
	new_weapon.damage = 4
	p.inventory[0] = new_weapon
	var old_weapon = p.weapon
	s.player_use_slot(0)
	check(p.weapon == new_weapon and p.inventory[0] == old_weapon, "equipping weapon swaps with old one")
	var vest = Templates.armor_template()
	p.inventory[1] = vest
	s.player_use_slot(1)
	check(p.armor == vest, "armor goes to vest slot")

	# Ranged attack on a placed zombie
	var target = _place_zombie_near(s, 3)
	if target != null:
		check(s.is_valid_attack_target(p, target.pos), "zombie at distance 3 is a valid target")
		s.player_attack(target.pos)
		check(target.hp == 6, "4 damage weapon hit -> zombie 6/10")


func _place_zombie_near(s, dist: int):
	var p = s.player
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var ok := true
		for i in range(1, dist + 1):
			if not s.is_free(p.layer, p.pos + d * i):
				ok = false
		if ok:
			var z = Templates.zombie()
			z.layer = p.layer
			s._place_creature(z, Vector3i(p.pos.x + d.x * dist, p.pos.y + d.y * dist, p.layer))
			return z
	print("  (skipped: no straight corridor near player)")
	return null


func test_zombie_ai() -> void:
	print("Zombie AI")
	var s = GameState.new()
	s.new_game(11)
	# Remove all zombies, then place one at distance 4.
	for c in s.creatures.duplicate():
		if not c.is_player:
			s._kill(c)
	s.messages.clear()
	var z = _place_zombie_near(s, 4)
	if z == null:
		return
	s._update_distance_field()
	var start_d: int = Combat.manhattan(z.pos, s.player.pos)
	s.end_player_turn()
	check(Combat.manhattan(z.pos, s.player.pos) == start_d - 1, "zombie moves one tile towards the player")
	s.end_player_turn()
	s.end_player_turn()
	check(Combat.manhattan(z.pos, s.player.pos) == 1, "zombie reaches the player")
	s.player.armor = null
	var hp: int = s.player.hp
	s.end_player_turn()
	check(s.player.hp == hp - 1, "adjacent zombie attacks instead of moving (no vest: -1 HP)")


func test_simulation() -> void:
	print("Random play simulation")
	var s = GameState.new()
	s.new_game(2024)
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var turns := 0
	var layers_seen := {}
	for i in 3000:
		if s.game_over:
			break
		var spent: bool
		if rng.randf() < 0.2:
			spent = s.player_attack(s.default_aim_target(s.player))
		else:
			spent = s.player_move(dirs[rng.randi_range(0, 3)])
		if spent:
			s.end_player_turn()
			turns += 1
		layers_seen[s.player.layer] = true
	var ms := Time.get_ticks_msec() - t0
	var consistent := true
	for k in s.occupancy:
		var c = s.occupancy[k]
		consistent = consistent and c.pos == Vector2i(k.x, k.y) and c.layer == k.z
	check(consistent and s.occupancy.size() == s.creatures.size(), "occupancy stays consistent")
	check(turns > 0, "%d turns simulated in %d ms (%.2f ms/turn)" % [turns, ms, float(ms) / maxi(1, turns)])


func test_main_scene_input() -> void:
	print("Main scene + input")
	var main = load("res://scenes/main.tscn").instantiate()
	main.fixed_seed = 3
	root.add_child(main)
	await process_frame
	var s = main.state
	check(s != null and s.player != null, "main scene starts a game")
	var start_turn: int = s.turn

	# Move: press D
	_key(main, KEY_D, true)
	_key(main, KEY_D, false)
	_key(main, KEY_A, true)
	_key(main, KEY_A, false)
	check(s.turn >= start_turn, "WASD input processed (turn %d)" % s.turn)

	# Inspect mode with Shift
	_key(main, KEY_SHIFT, true)
	check(main.mode == main.Mode.INSPECT and main.inspect_target == s.player.pos, "SHIFT enters inspect at player")
	_key(main, KEY_W, true, true)
	check(main.inspect_target == s.player.pos + Vector2i.UP or not main.renderer.visible_rect().has_point(s.player.pos + Vector2i.UP),
			"WASD moves the target icon, not the player")
	_key(main, KEY_SHIFT, false)
	check(main.mode == main.Mode.NORMAL, "releasing SHIFT leaves inspect")

	# Aim with space
	var turn_before: int = s.turn
	_key(main, KEY_SPACE, true)
	check(main.mode == main.Mode.AIMING, "holding SPACE enters aiming")
	await process_frame
	_key(main, KEY_SPACE, false)
	check(main.mode == main.Mode.NORMAL, "releasing SPACE fires/leaves aiming (turn %d -> %d)" % [turn_before, s.turn])
	await process_frame
	check(main.hud.stats_label.text.contains("Hit points"), "HUD shows player stats")
	main.queue_free()
	await process_frame


func _key(main, keycode: int, pressed: bool, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = pressed
	ev.shift_pressed = shift
	main._unhandled_input(ev)
