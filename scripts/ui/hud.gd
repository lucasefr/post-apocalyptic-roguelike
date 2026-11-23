extends CanvasLayer
## Right-hand column (1/5 of the screen): player stats, inventory, content of
## the inspected tile (while SHIFT is held) and the message log.

const Tiles = preload("res://scripts/core/tile_types.gd")
const ItemData = preload("res://scripts/entities/item_data.gd")
const Templates = preload("res://scripts/entities/templates.gd")
const Combat = preload("res://scripts/game/combat.gd")

const FONT_SIZE := 13

var stats_label: RichTextLabel
var inventory_label: RichTextLabel
var target_label: RichTextLabel
var log_label: RichTextLabel


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.8
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.085, 0.10)
	style.border_color = Color(0.25, 0.27, 0.31)
	style.border_width_left = 2
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	stats_label = _make_label(box, false)
	inventory_label = _make_label(box, false)
	target_label = _make_label(box, false)
	log_label = _make_label(box, true)


func _make_label(parent: Control, expand: bool) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	label.add_theme_font_size_override("bold_font_size", FONT_SIZE + 1)
	if expand:
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.scroll_following = true
	else:
		label.fit_content = true
		label.scroll_active = false
	parent.add_child(label)
	return label


func refresh(game) -> void:
	var state = game.state
	if state == null:
		return
	stats_label.text = _stats_text(state)
	inventory_label.text = _inventory_text(state)
	target_label.text = _target_text(game)
	log_label.text = "[b][color=#9aa4b2]LOG[/color][/b]\n" + "\n".join(state.messages.slice(-14))


func _stats_text(state) -> String:
	var p = state.player
	var hp_color := "#7ddc6a" if p.hp > p.max_hp * 0.5 else ("#e8c547" if p.hp > p.max_hp * 0.25 else "#ff5a5a")
	var w = p.weapon
	var lines := [
		"[b][color=#9aa4b2]PLAYER[/color][/b]",
		"Hit points: [color=%s]%d / %d[/color]" % [hp_color, p.hp, p.max_hp],
		"Physical armor: %d" % p.physical_armor(),
		"Energy armor: %d" % p.energy_armor(),
		"Damage: %d %s" % [w.damage, ItemData.damage_type_name(w.damage_type)],
		"Range: %d   Area: %d" % [w.attack_range, w.area],
		"Layer: %s   Turn: %d" % [state.world.layer_names[p.layer], state.turn],
	]
	if state.game_over:
		lines.append("[color=#ff5a5a][b]YOU DIED[/b] - press R[/color]")
	return "\n".join(lines)


func _inventory_text(state) -> String:
	var p = state.player
	var lines := ["[b][color=#9aa4b2]INVENTORY[/color][/b] (%d/%d)" % [p.used_slots(), p.inventory_size]]
	for i in p.inventory_size:
		var item = p.inventory[i]
		lines.append("[%d] %s" % [i + 1, _item_name(item) if item != null else "[color=#555b66]empty[/color]"])
	lines.append("Weapon: %s" % (_item_name(p.weapon) if p.weapon != null else "-"))
	lines.append("Vest: %s" % (_item_name(p.armor) if p.armor != null else "-"))
	return "\n".join(lines)


func _item_name(item) -> String:
	return "[color=#%s]%s[/color]" % [item.color.to_html(false), item.display_name]


func _target_text(game) -> String:
	var state = game.state
	if game.mode == game.Mode.AIMING:
		var valid: bool = state.is_valid_attack_target(state.player, game.aim_target)
		return "[b][color=#9aa4b2]AIMING[/color][/b]\n%s\nWASD move aim, release SPACE to fire, ESC cancels." % (
			"[color=#ff6a6a]Target locked[/color]" if valid else "[color=#888888]Out of range / blocked[/color]")
	if game.mode != game.Mode.INSPECT:
		return "[b][color=#9aa4b2]TARGET[/color][/b]\n[color=#555b66]Hold SHIFT to inspect a tile.[/color]"

	var p: Vector2i = game.inspect_target
	var layer: int = state.player.layer
	var lines := ["[b][color=#9aa4b2]TARGET[/color][/b] (%d, %d)" % [p.x, p.y]]
	lines.append("Tile: %s" % Tiles.DATA[state.world.get_tile(layer, p)]["name"])
	var c = state.creature_at(layer, p)
	if c != null:
		var w = c.weapon
		lines.append("[color=#%s][b]%s[/b][/color]" % [c.color.to_html(false), c.display_name])
		lines.append("HP %d/%d   Armor P%d / E%d" % [c.hp, c.max_hp, c.physical_armor(), c.energy_armor()])
		if w != null:
			lines.append("Damage %d %s   Range %d   Area %d" % [
				w.damage, ItemData.damage_type_name(w.damage_type), w.attack_range, w.area])
		if not c.is_player:
			lines.append("AI: %s" % Templates.ai_description(c.ai_behavior))
	var item = state.item_at(layer, p)
	if item != null:
		lines.append("Item: %s" % _item_name(item))
		lines.append(item.describe())
	return "\n".join(lines)
