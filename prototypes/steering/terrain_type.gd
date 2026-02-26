class_name TerrainType
extends RefCounted
## Central definition of terrain types and their movement properties.
##
## Enum values must match Terrain3D texture asset indices.
## [TerrainTypeCostCalculator], [TerrainDangerBehavior], and [ContextActuator]
## reference these constants as defaults.

## Terrain texture IDs — values must match Terrain3D texture asset indices.
enum Type {
	GRASS = 0,
	SAND = 1,
	WATER = 2,
}

## Pathfinding cost penalties per terrain type.
## 0.0 = no penalty, 0.5 = +50% cost, INF = impassable.
const PATH_COSTS: Dictionary = {
	Type.GRASS: 0.0,
	Type.SAND: 0.5,
	Type.WATER: INF,
}

## Runtime speed multipliers per terrain type.
## 1.0 = full speed, 0.6 = 60% speed, 0.0 = stopped.
const SPEED_FACTORS: Dictionary = {
	Type.GRASS: 1.0,
	Type.SAND: 0.6,
	Type.WATER: 0.0,
}
