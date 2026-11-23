extends Node2D
## Main controller: owns the game state, translates input into player actions
## and keeps renderer + HUD in sync.

const GameState = preload("res://scripts/game/game_state.gd")
const WorldRenderer = preload("res://scripts/ui/world_renderer.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const Combat = preload("res://scripts/game/combat.gd")

enum Mode { NORMAL, AIMING, INSPECT }

const DIRECTION_ACTIONS := {
	"move_up": Vector2i.UP,
	"move_down": Vector2i.DOWN,
	"move_left": Vector2i.LEFT,
	"move_right": Vector2i.RIGHT,
}

## Set to a number >= 0 to always generate the same world (useful for debugging).
@export var fixed_seed := -1

var state
var renderer
var hud
var mode: int = Mode.NORMAL
var aim_target := Vector2i.ZERO
var inspect_target := Vector2i.ZERO


func _ready() -> void:
	InputSetup.ensure_actions()
	RenderingServer.set_default_clear_color(Color.BLACK)
	renderer = WorldRenderer.new()
	renderer.game = self
	add_child(renderer)
	hud = Hud.new()
	add_child(hud)
	get_viewport().size_changed.connect(refresh)
	start_new_game(fixed_seed)


func start_new_game(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi()
	state = GameState.new()
	state.new_game(seed_value)
	mode = Mode.NORMAL
	refresh()


func refresh() -> void:
	renderer.queue_redraw()
	hud.refresh(self)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if state.game_over:
		if event.is_action_pressed("restart"):
			start_new_game()
		return
	match mode:
		Mode.NORMAL:
			_handle_normal(event)
		Mode.AIMING:
			_handle_aiming(event)
		Mode.INSPECT:
			_handle_inspect(event)
	refresh()


func _handle_normal(event: InputEventKey) -> void:
	if event.is_action_pressed("inspect"):
		mode = Mode.INSPECT
		inspect_target = state.player.pos
		return
	if event.is_action_pressed("attack"):
		mode = Mode.AIMING
		aim_target = state.default_aim_target(state.player)
		return
	var dir := _direction_from(event)
	if dir != Vector2i.ZERO:
		_finish_action(state.player_move(dir))
		return
	for i in 4:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			if event.ctrl_pressed:
				_finish_action(state.player_drop(i))
			else:
				_finish_action(state.player_use_slot(i))
			return


func _handle_aiming(event: InputEventKey) -> void:
	if event.is_action_released("attack"):
		mode = Mode.NORMAL
		_finish_action(state.player_attack(aim_target))
		return
	if event.is_action_pressed("cancel"):
		mode = Mode.NORMAL
		return
	var dir := _direction_from(event)
	if dir != Vector2i.ZERO:
		var next: Vector2i = aim_target + dir
		var weapon_range: int = state.player.weapon.attack_range
		if state.world.in_bounds(next) and Combat.manhattan(state.player.pos, next) <= weapon_range:
			aim_target = next


func _handle_inspect(event: InputEventKey) -> void:
	if event.is_action_released("inspect"):
		mode = Mode.NORMAL
		return
	var dir := _direction_from(event)
	if dir != Vector2i.ZERO:
		var view: Rect2i = renderer.visible_rect()
		var next: Vector2i = inspect_target + dir
		if view.has_point(next) and state.world.in_bounds(next):
			inspect_target = next


func _direction_from(event: InputEventKey) -> Vector2i:
	for action in DIRECTION_ACTIONS:
		if event.is_action_pressed(action, true):
			return DIRECTION_ACTIONS[action]
	return Vector2i.ZERO


## Every action that spends the player's turn lets all enemies act once.
func _finish_action(turn_spent: bool) -> void:
	if turn_spent:
		state.end_player_turn()
