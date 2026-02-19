class_name QuadTree
extends RefCounted

## Adaptive spatial subdivision for pathfinding grids.
## Leaf cells become AStar3D points; internal cells are structural only.

# Child index convention (XZ plane):
# 0 = NW (-x, +z)    1 = NE (+x, +z)
# 2 = SW (-x, -z)    3 = SE (+x, -z)
enum { NW, NE, SW, SE }

## Cardinal + diagonal directions for neighbor finding.
enum Direction { N, S, E, W, NE, NW, SE, SW }

class Cell:
	var center: Vector3					# World-space center (includes terrain Y)
	var half_size: float				# Half the cell's width in XZ
	var parent: Cell					# null for root (creates RefCounted cycle - intentional, tree is never freed mid-session)
	var children: Array					# [NW, NE, SW, SE] for internal
	var is_blocked: bool = false		# Only meaningful for leaves
	var astar_id: int = -1			    # AStar3D point ID, only set for free leaves

	func is_leaf() -> bool:
		return children.is_empty()

	func is_free_leaf() -> bool:
		return is_leaf() and not is_blocked



## Recursively build the quadtree. Returns the root cell.
## [param height_provider] supplies ground elevation at cell centers.
## [param cell_checker] is called as cell_checker.call(center: Vector3, half_size: float) -> bool
## and should return true if the cell is free (no obstacles).
static func build(
	center_xz: Vector2, 
	half_size: float, 
	min_cell_size: float,
	height_provider: HeightProvider,
	cell_checker: Callable
) -> Cell:
	var cell := Cell.new()
	var y := height_provider.get_height(Vector3(center_xz.x, 0.0, center_xz.y))
	cell.center = Vector3(center_xz.x, y, center_xz.y)
	cell.half_size = half_size

	var is_free: bool = cell_checker.call(cell.center, half_size)

	if is_free:
		return cell # Entirely free - leaf

	if half_size <= min_cell_size:
		cell.is_blocked = true # At min size - conservatively block
		return cell

	# Not free and above min size - subdivide
	var q := half_size * 0.5
	var offsets: Array[Vector2] = [
		Vector2(-q, +q), # NW
		Vector2(+q, +q), # NE
		Vector2(-q, -q), # SW
		Vector2(+q, -q)  # SE
	]
	cell.children.resize(4)
	for i in 4:
		var child_center := center_xz + offsets[i]
		var child := build(child_center, q, min_cell_size, height_provider, cell_checker)
		child.parent = cell
		cell.children[i] = child
	return cell


## Walk the tree to find the leaf cell containing [param pos] (XZ containment).
## Returns null if the position is outside the root cell.
static func find_leaf_at(root: Cell, pos: Vector3) -> Cell:
	var cell := root
	while not cell.is_leaf():
		var cx := cell.center.x
		var cz := cell.center.z
		var idx: int
		if pos.x < cx:
			idx = NW if pos.z >= cz else SW
		else:
			idx = NE if pos.z >= cz else SE
		cell = cell.children[idx]
	return cell


static func get_free_leaves(root: Cell) -> Array[Cell]:
	var result: Array[Cell] = []
	_collect_free_leaves(root, result)
	return result

static func _collect_free_leaves(cell: Cell, result: Array[Cell]) -> void:
	if cell.is_free_leaf():
		result.append(cell)
	for child in cell.children:
		_collect_free_leaves(child, result)

## Find all free leaf neighbors of [param cell] in [param direction].
## Cardinal directions use Samet's algorithm directly. Diagonal directions
## compose two cardinal lookups (e.g., NW = N-neighbor's W-neighbor).
static func find_neighbors(cell: Cell, direction: int) -> Array[Cell]:
	var candidate: Cell
	if direction >= Direction.NE:
		var components := _decompose(direction)
		var edge_neighbor := _find_neighbor_geq(cell, components[0])
		if edge_neighbor != null:
			candidate = _find_neighbor_geq(edge_neighbor, components[1])
	else:
		candidate = _find_neighbor_geq(cell, direction)
	if candidate == null:
		return []
	var result: Array[Cell] = []
	_collect_adjacent_leaves(candidate, direction, result)
	return result

## Split a diagonal direction into its two cardinal components.
static func _decompose(direction: int) -> Array[int]:
	match direction:
		Direction.NE: return [Direction.N, Direction.E]
		Direction.NW: return [Direction.N, Direction.W]
		Direction.SE: return [Direction.S, Direction.E]
		Direction.SW: return [Direction.S, Direction.W]
	return []

## Walk up until the cell is no longer adjacent to [param direction],
## then walk down picking opposite-side children.
static func _find_neighbor_geq(cell: Cell, direction: int) -> Cell:
	if cell.parent == null:
		return null # Root - no neighbor in this direction
	var child_idx := _child_index(cell)
	if _is_adjacent(child_idx, direction):
		# Cell is on the side facing the query direction - must go higher
		var parent_neighbor := _find_neighbor_geq(cell.parent, direction)
		if parent_neighbor == null or parent_neighbor.is_leaf():
			return parent_neighbor
		return parent_neighbor.children[_reflect(child_idx, direction)]
	else:
		# Cell is on the opposite side - neighbor is a sibling
		return cell.parent.children[_reflect(child_idx, direction)]

## Return the index (0-3) of [param child] within its parent's children array.
static func _child_index(child: Cell) -> int:
	for i in 4:
		if child.parent.children[i] == child:
			return i
	return -1 # Should never happen

## True if child at [param idx] is on the border facing [param direction].
## NW(0) borders N,W,NW. NE(1) borders N,E,NE. SW(2) borders S,W,SW. SE(3) borders S,E,SE.
static func _is_adjacent(idx: int, direction: int) -> bool:
	match direction:
		Direction.N: return idx == NW or idx == NE
		Direction.S: return idx == SW or idx == SE
		Direction.W: return idx == NW or idx == SW
		Direction.E: return idx == NE or idx == SE
	return false

## Mirror [param idx] across the axis implied by [param direction].
## E.g., reflecting NW(0) across N gives SW(2); reflecting NW across W gives NE(1).
static func _reflect(idx: int, direction: int) -> int:
	match direction:
		Direction.N, Direction.S:
			# Flip N<->S: NW<->SW, NE<->SE
			match idx:
				NW: return SW
				NE: return SE
				SW: return NW
				SE: return NE
		Direction.E, Direction.W:
			# Flip E<->W: NW<->NE, SW<->SE
			match idx:
				NW: return NE
				NE: return NW
				SW: return SE
				SE: return SW
	return idx

## Descend into [param cell] collecting all free leaves facing [param direction].
static func _collect_adjacent_leaves(cell: Cell, direction: int, result: Array[Cell]) -> void:
	if cell.is_leaf():
		if cell.is_free_leaf():
			result.append(cell)
		return
	for child_idx in _children_facing(direction):
		_collect_adjacent_leaves(cell.children[child_idx], direction, result)

## Return child indices that face [param direction] (for descending into a neighbor subtree).
## When looking for cells facing NORTH, we want the SOUTH children (SW, SE).
static func _children_facing(direction: int) -> Array[int]:
	match direction:
		Direction.N: return [SW, SE] # South side of the neighbor faces us
		Direction.S: return [NW, NE]
		Direction.E: return [NW, SW] # West side of the neighbor faces us
		Direction.W: return [NE, SE]
		Direction.NW: return [SE]
		Direction.NE: return [SW]
		Direction.SW: return [NE]
		Direction.SE: return [NW]
	return []