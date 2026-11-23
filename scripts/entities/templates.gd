extends RefCounted
## Item and creature templates. Every stat that defines balance lives here,
## so tuning the game means editing only this file.

const ItemData = preload("res://scripts/entities/item_data.gd")
const Creature = preload("res://scripts/entities/creature.gd")

const PLAYER_SHEET := {
	"hit_points": 10,
	"physical_armor": 0,
	"energy_armor": 0,
	"inventory_size": 4,
}


static func weapon_template():
	var item = ItemData.new()
	item.id = "weapon_template"
	item.display_name = "Scrap Rifle"
	item.type = ItemData.Type.WEAPON
	item.damage = 1
	item.damage_type = ItemData.DamageType.PHYSICAL
	item.attack_range = 3
	item.area = 1
	item.glyph = "/"
	item.color = Color(0.75, 0.75, 0.80)
	return item


static func armor_template():
	var item = ItemData.new()
	item.id = "armor_template"
	item.display_name = "Padded Vest"
	item.type = ItemData.Type.ARMOR
	item.physical_armor = 1
	item.energy_armor = 1
	item.glyph = "["
	item.color = Color(0.40, 0.65, 0.95)
	return item


static func consumable_template():
	var item = ItemData.new()
	item.id = "consumable_template"
	item.display_name = "Medkit"
	item.type = ItemData.Type.CONSUMABLE
	item.heal_amount = 3
	item.glyph = "!"
	item.color = Color(0.95, 0.35, 0.40)
	return item


static func all_item_templates() -> Array:
	return [weapon_template(), armor_template(), consumable_template()]


static func player():
	var c = Creature.new()
	c.display_name = "You"
	c.glyph = "@"
	c.color = Color(1.0, 0.95, 0.55)
	c.is_player = true
	c.max_hp = PLAYER_SHEET["hit_points"]
	c.hp = c.max_hp
	c.base_physical_armor = PLAYER_SHEET["physical_armor"]
	c.base_energy_armor = PLAYER_SHEET["energy_armor"]
	c.setup_inventory(PLAYER_SHEET["inventory_size"])
	c.weapon = weapon_template()
	c.armor = armor_template()
	return c


## Enemies share the player's base sheet; attack stats come from a natural weapon.
static func zombie():
	var c = Creature.new()
	c.display_name = "Zombie"
	c.glyph = "Z"
	c.color = Color(0.55, 0.85, 0.35)
	c.ai_behavior = "zombie"
	c.max_hp = PLAYER_SHEET["hit_points"]
	c.hp = c.max_hp
	c.base_physical_armor = PLAYER_SHEET["physical_armor"]
	c.base_energy_armor = PLAYER_SHEET["energy_armor"]
	c.setup_inventory(PLAYER_SHEET["inventory_size"])
	var bite = ItemData.new()
	bite.id = "zombie_bite"
	bite.display_name = "Bite"
	bite.type = ItemData.Type.WEAPON
	bite.damage = 1
	bite.damage_type = ItemData.DamageType.PHYSICAL
	bite.attack_range = 1
	bite.area = 1
	c.weapon = bite
	return c


static func ai_description(behavior: String) -> String:
	match behavior:
		"zombie":
			return "If player not in range, moves a tile towards the player; otherwise attacks."
	return "Controlled by the player"
