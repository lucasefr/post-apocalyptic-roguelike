extends RefCounted
## Character sheet shared by the player and every enemy.
## Enemies use the same sheet; their attack stats live in a "natural weapon"
## kept in the weapon slot, and they get an ai_behavior instead of player input.

const ItemData = preload("res://scripts/entities/item_data.gd")

var display_name := ""
var glyph := "?"
var color := Color.WHITE
var is_player := false
var ai_behavior := ""

var max_hp := 10
var hp := 10
var base_physical_armor := 0
var base_energy_armor := 0
var inventory_size := 4
var inventory: Array = []  # fixed size, null = empty slot

var weapon = null  # ItemData of type WEAPON
var armor = null   # ItemData of type ARMOR (vest slot)

var pos := Vector2i.ZERO
var layer := 0
var facing := Vector2i.RIGHT


func setup_inventory(size: int) -> void:
	inventory_size = size
	inventory.resize(size)
	inventory.fill(null)


func physical_armor() -> int:
	return base_physical_armor + (armor.physical_armor if armor != null else 0)


func energy_armor() -> int:
	return base_energy_armor + (armor.energy_armor if armor != null else 0)


func armor_against(damage_type: int) -> int:
	return physical_armor() if damage_type == ItemData.DamageType.PHYSICAL else energy_armor()


## Applies damage reduced by the matching armor (never below zero). Returns damage dealt.
func receive_damage(amount: int, damage_type: int) -> int:
	var dealt: int = maxi(0, amount - armor_against(damage_type))
	hp = maxi(0, hp - dealt)
	return dealt


func heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


func is_dead() -> bool:
	return hp <= 0


func free_slot() -> int:
	for i in inventory_size:
		if inventory[i] == null:
			return i
	return -1


func used_slots() -> int:
	var n := 0
	for item in inventory:
		if item != null:
			n += 1
	return n


func add_item(item) -> bool:
	var slot := free_slot()
	if slot < 0:
		return false
	inventory[slot] = item
	return true


## Equips the item in an inventory slot into its matching slot, swapping the old one back.
func equip_from_slot(slot: int) -> bool:
	var item = inventory[slot]
	if item == null:
		return false
	match item.type:
		ItemData.Type.WEAPON:
			inventory[slot] = weapon
			weapon = item
			return true
		ItemData.Type.ARMOR:
			inventory[slot] = armor
			armor = item
			return true
	return false
