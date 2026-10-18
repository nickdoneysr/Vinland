class_name Crew
extends RefCounted
## Named crew and their roles (Backlog F23). Roles decide who can stand a watch, take a verb, or sail home:
## the skipper holds the helm, the pilot reads the sky, the shipwright repairs, the smith makes hooks,
## the healer shortens sickness, the householder runs the dairy, the hunter finds caribou.
## Women are roles, not passengers (plan sheet Content). Losses are counts in the voyage and camp rules;
## this roster says who they were.

const ROLE_NAMES := {"skipper": "Skipper", "pilot": "Pilot", "shipwright": "Shipwright", "smith": "Smith", "healer": "Healer",
	"householder": "Householder", "hunter": "Hunter", "hand": "Hand"}
const KEY_ROLES := ["skipper", "pilot", "shipwright", "smith", "healer", "householder", "hunter"]
## The order roles are dropped in when the party is smaller than the outfit's roster.
const DROP_ORDER := ["hand", "hunter", "householder", "healer", "smith", "shipwright", "pilot", "skipper"]
const MEN := ["Thorvald", "Ketil", "Hrafn", "Grim", "Asbjorn", "Bard", "Einar", "Gunnar", "Halldor", "Kolbein", "Orm", "Snorri",
	"Sveinn", "Thorgeir", "Ulf", "Vermund", "Arnor", "Bersi", "Eyvind", "Finnbogi", "Geir", "Hauk", "Ljot", "Starkad", "Tind", "Atli"]
const WOMEN := ["Asa", "Bergthora", "Dalla", "Freydis", "Groa", "Hallgerd", "Ingunn", "Jorunn", "Ragnhild", "Signy", "Thordis",
	"Thorgerd", "Ulfrun", "Vigdis", "Yngvild", "Alfdis", "Geirny", "Halla", "Oddny", "Thurid", "Arnbjorg", "Gyda", "Hild", "Sigrid"]

var members: Array = []      # {name, role, female: bool, alive: bool}

## Build the roster for a party of this size from an outfit's roles and leaders.
func build(outfit: Dictionary, people: int, rng: RandomNumberGenerator) -> void:
	members.clear()
	var used := {}
	for l in outfit.get("lead", []):
		members.append({"name": l[0], "role": l[1], "female": l[2] == "f", "alive": true})
		used[l[0]] = true
	var want: Dictionary = outfit.get("roles", {}).duplicate()
	for m in members:
		if want.has(m.role):
			want[m.role] = maxi(0, int(want[m.role]) - 1)
	var roles: Array = []
	for r in KEY_ROLES:
		for i in int(want.get(r, 0)):
			roles.append(r)
	var men: Array = MEN.duplicate(); var women: Array = WOMEN.duplicate()
	_shuffle(men, rng); _shuffle(women, rng)
	var i := 0
	var target := maxi(people, members.size() + roles.size())
	while members.size() < target:
		var role: String = roles[i] if i < roles.size() else "hand"
		i += 1
		var female := (members.size() % 5) in [1, 3]          # about two in five of the company are women
		var pool: Array = women if female else men
		var nm: String = pool.pop_back() if not pool.is_empty() else "%s %d" % ["Thord" if not female else "Thora", members.size()]
		members.append({"name": nm, "role": role, "female": female, "alive": true})
	# trim to the party size, dropping hands first
	for r in DROP_ORDER:
		var k := members.size() - 1
		while members.size() > people and k >= 2:
			if members[k].role == r:
				members.remove_at(k)
			k -= 1

func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]; a[i] = a[j]; a[j] = t

func alive() -> Array:
	return members.filter(func(m): return m.alive)

func count() -> int:
	return alive().size()

func has_role(role: String) -> bool:
	for m in members:
		if m.alive and m.role == role:
			return true
	return false

func holders(role: String) -> Array:
	return members.filter(func(m): return m.alive and m.role == role)

## Someone dies: picked at random among the living. Returns "Name the Role" lines.
func lose(n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in n:
		var living := alive()
		if living.is_empty():
			break
		var m: Dictionary = living[rng.randi_range(0, living.size() - 1)]
		m.alive = false
		out.append(title(m))
	return out

## A recruit joins (relief ships, births): a hand unless a role is given.
func add(name: String, role: String, female: bool) -> void:
	members.append({"name": name, "role": role, "female": female, "alive": true})

## New people join (recruits for the relief): hands with names not already in the company.
func recruit(count: int, rng: RandomNumberGenerator) -> void:
	var used := {}
	for m in members:
		used[m.name] = true
	var men: Array = MEN.filter(func(x): return not used.has(x))
	var women: Array = WOMEN.filter(func(x): return not used.has(x))
	_shuffle(men, rng); _shuffle(women, rng)
	for i in count:
		var female := (members.size() % 5) in [1, 3]
		var pool: Array = women if female else men
		var nm: String = pool.pop_back() if not pool.is_empty() else "%s %d" % ["Thora" if female else "Thord", members.size()]
		members.append({"name": nm, "role": "hand", "female": female, "alive": true})

func title(m: Dictionary) -> String:
	return m.name if m.role == "hand" else "%s, the %s" % [m.name, str(ROLE_NAMES[m.role]).to_lower()]

## Who the party has in each key role, for screens.
func roles_line() -> String:
	var parts: Array = []
	for r in KEY_ROLES:
		var h := holders(r)
		if h.is_empty():
			parts.append("no %s" % str(ROLE_NAMES[r]).to_lower())
		else:
			parts.append("%s %s" % [ROLE_NAMES[r], " and ".join(h.map(func(m): return str(m.name).split(" ")[0]))])
	return " · ".join(parts)

## Who could sail a knarr home: a skipper or a pilot, and enough hands for the watches.
func can_sail_home(min_crew: int) -> bool:
	return (has_role("skipper") or has_role("pilot")) and count() >= min_crew

## Keep the roster in step with a head count kept elsewhere (the rules count people; this names them).
func sync_to(people: int, rng: RandomNumberGenerator) -> Array:
	var lines: Array = []
	if count() > people:
		lines = lose(count() - people, rng)
	return lines

func to_array() -> Array:
	return members.duplicate(true)

func from_array(a: Array) -> void:
	members.clear()
	for m in a:
		members.append({"name": str(m.name), "role": str(m.role), "female": bool(m.female), "alive": bool(m.alive)})
