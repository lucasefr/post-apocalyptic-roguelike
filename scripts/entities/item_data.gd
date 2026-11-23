extends RefCounted
## A single item instance. Its type decides which slot can hold it and
## which stats matter (weapon: damage/range/area, armor: armor values,
## consumable: instant effect).

enum Type { WEAPON, ARMOR, CONSUMABLE }
enum DamageType { PHYSICAL, ENERGY }

var id := ""
var display_name := ""
var type: int = Type.CONSUMABLE

# Weapon stats
var damage := 0
var damage_type: int = DamageType.PHYSICAL
var attack_range := 0
var area := 0

# Armor stats
var physical_armor := 0
var energy_armor := 0

# Consumable effect
var heal_amount := 0

# Presentation
var glyph := "?"
var color := Color.WHITE


func clone():
	var copy = get_script().new()
	for prop in ["id", "display_name", "type", "damage", "damage_type", "attack_range", "area",
			"physical_armor", "energy_armor", "heal_amount", "glyph", "color"]:
		copy.set(prop, get(prop))
	return copy


func describe() -> String:
	match type:
		Type.WEAPON:
			return "Weapon: %d %s dmg, range %d, area %d" % [
				damage, damage_type_name(damage_type), attack_range, area]
		Type.ARMOR:
			return "Armor: +%d physical, +%d energy" % [physical_armor, energy_armor]
		Type.CONSUMABLE:
			return "Consumable: heals %d HP" % heal_amount
	return ""


static func type_name(t: int) -> String:
	return ["Weapon", "Armor", "Consumable"][t]


static func damage_type_name(t: int) -> String:
	return ["Physical", "Energy"][t]
