extends RefCounted

const MAX_HEALTH := 1000
const DAMAGE := 5


static func vitals(health_pool: int, combat_mode: int, armor_pool: int) -> Dictionary:
	if combat_mode == 0:
		return {"health": health_pool, "armor": 0}
	var health: int = {300: 100, 600: 200, 1000: 400}.get(armor_pool, 100)
	return {"health": health, "armor": armor_pool - health}


static func damage(health: int, armor: int, amount: int) -> Dictionary:
	var absorbed := mini(maxi(armor, 0), maxi(amount, 0)) if health > 0 else 0
	var lost := mini(maxi(health, 0), maxi(amount - absorbed, 0))
	return {"health": maxi(health - lost, 0), "armor": maxi(armor - absorbed, 0),
		"dealt": absorbed + lost, "health_damage": lost, "armor_damage": absorbed,
		"broken": armor > 0 and absorbed == armor}
