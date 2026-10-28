extends RefCounted
## One hull source shared by combat, previews and the hangar. Future designs stay hidden.
const RANKS := [3, 6, 10, 16, 24, 45, 55, 70, 90, 120]
const HULLS := [
	preload("res://assets/player-ship.png"),
	preload("res://assets/evolutions/ship-01.svg"),
	preload("res://assets/evolutions/ship-02.svg"),
	preload("res://assets/evolutions/ship-03.svg"),
	preload("res://assets/evolutions/ship-04.svg"),
	preload("res://assets/evolutions/ship-05.svg"),
	preload("res://assets/evolutions/ship-06.svg"),
	preload("res://assets/evolutions/ship-07.svg"),
	preload("res://assets/evolutions/ship-08.svg"),
	preload("res://assets/evolutions/ship-09.svg"),
	preload("res://assets/evolutions/ship-10.svg"),
]
static func stage(rank: int) -> int:
	var result := 0
	for required in RANKS:
		if rank >= required: result += 1
	return result

static func texture(rank: int) -> Texture2D:
	return HULLS[stage(rank)]

static func next_rank(rank: int) -> int:
	for required in RANKS:
		if rank < required: return required
	return 0
