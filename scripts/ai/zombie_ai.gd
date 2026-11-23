extends RefCounted
## Zombie behavior: if the player is not in range, move one tile towards the
## player; otherwise attack the player.
## "Towards" follows the shortest walkable path (a distance field computed from
## the player every turn), so zombies walk around buildings and cars.

const Combat = preload("res://scripts/game/combat.gd")

const DIRS4 := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


static func take_turn(zombie, state) -> void:
	var player = state.player
	if player == null or player.is_dead() or zombie.layer != player.layer:
		return
	if Combat.can_target(state.world, zombie.layer, zombie.pos, player.pos, zombie.weapon.attack_range):
		zombie.facing = (player.pos - zombie.pos).sign()
		state.perform_attack(zombie, player.pos)
		return
	var current: int = state.distance_to_player(zombie.pos)
	if current < 0:
		return  # player too far away (outside the aggro radius): stay put
	var best := Vector2i.ZERO
	var best_d := current
	for d in DIRS4:
		var np: Vector2i = zombie.pos + d
		var nd: int = state.distance_to_player(np)
		if nd >= 0 and nd < best_d and state.is_free(zombie.layer, np):
			best = np
			best_d = nd
	if best_d < current:
		zombie.facing = best - zombie.pos
		state.move_creature(zombie, best)
