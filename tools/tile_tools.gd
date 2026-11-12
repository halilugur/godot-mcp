@tool
extends RefCounted
## TileMapLayer cells, terrain painting, TileSets, GridMaps, and MeshLibraries.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("get_tilemap_cells", "Used cells of a TileMapLayer and the sources of its TileSet.", {
		"node_path": node_path,
		"limit": {"type": "integer", "description": "Default 500"},
	}, ["node_path"], true)
	_reg("set_tilemap_cells", "Paint or erase cells on a TileMapLayer (undoable). cells: [{\"x\": 0, \"y\": 0, \"source_id\": 0, \"atlas_x\": 0, \"atlas_y\": 0, \"alternative\": 0}]; erase: [{\"x\": 1, \"y\": 0}].", {
		"node_path": node_path,
		"cells": {"type": "array", "items": {"type": "object"}},
		"erase": {"type": "array", "items": {"type": "object"}},
	}, ["node_path"])
	_reg("fill_tilemap_rect", "Fill or erase a rectangular region on a TileMapLayer in a single undoable action.", {
		"node_path": node_path,
		"from": {"type": "array", "items": {"type": "integer"}, "description": "[x, y] inclusive start cell"},
		"to": {"type": "array", "items": {"type": "integer"}, "description": "[x, y] inclusive end cell"},
		"erase": {"type": "boolean", "description": "If true, erase all cells in the rectangle. Default false."},
		"source_id": {"type": "integer", "description": "Default 0"},
		"atlas_x": {"type": "integer", "description": "Default 0"},
		"atlas_y": {"type": "integer", "description": "Default 0"},
		"alternative": {"type": "integer", "description": "Default 0"},
	}, ["node_path", "from", "to"], false, false)
	_reg("paint_tilemap_terrain", "Paint auto-tiled terrain cells on a TileMapLayer using set_cells_terrain_connect (undoable).", {
		"node_path": node_path,
		"cells": {"type": "array", "items": {"type": "object"}, "description": "Array of {\"x\": int, \"y\": int}"},
		"terrain_set": {"type": "integer", "description": "Default 0"},
		"terrain": {"type": "integer", "description": "Terrain index inside terrain_set (or -1 to clear). Default 0."},
		"ignore_empty_terrains": {"type": "boolean", "description": "Default true"},
	}, ["node_path", "cells"], false, false)
	_reg("get_tileset_info", "Inspect a TileMapLayer's TileSet or a .tres TileSet resource: tile_size, sources, physics/navigation/terrain layers.", {
		"node_path": {"type": "string", "description": "TileMapLayer node path"},
		"resource_path": {"type": "string", "description": "Or res:// path to a TileSet resource"},
	}, [], true, false)
	_reg("setup_tileset_source", "Create a TileSet with a TileSetAtlasSource sliced from a texture, assign it to a TileMapLayer and/or save as .tres.", {
		"texture_path": {"type": "string", "description": "res:// path to tile atlas texture"},
		"tile_size": {"type": "array", "items": {"type": "integer"}, "description": "[width, height], default [16, 16]"},
		"node_path": {"type": "string", "description": "Optional TileMapLayer node path to assign this TileSet"},
		"save_path": {"type": "string", "description": "Optional res:// path ending in .tres to save the TileSet"},
	}, ["texture_path"], false, false)
	_reg("get_gridmap_cells", "List used cells and MeshLibrary items of a GridMap node.", {
		"node_path": node_path,
		"limit": {"type": "integer", "description": "Default 500"},
	}, ["node_path"], true, false)
	_reg("set_gridmap_cells", "Place or erase cells on a GridMap node (undoable). cells: [{\"x\": 0, \"y\": 0, \"z\": 0, \"item\": 0, \"orientation\": 0}]. erase: [{\"x\": 1, \"y\": 0, \"z\": 0}].", {
		"node_path": node_path,
		"cells": {"type": "array", "items": {"type": "object"}},
		"erase": {"type": "array", "items": {"type": "object"}},
	}, ["node_path"], false, false)
	_reg("create_mesh_library", "Build a MeshLibrary .tres resource from MeshInstance3D children of a node (for GridMap).", {
		"root_path": {"type": "string", "description": "Node path whose MeshInstance3D children become library items. Default '.'"},
		"path": {"type": "string", "description": "Destination res:// path ending in .tres"},
	}, ["path"], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _tile_layer(path: Variant) -> Variant:
	var node: Variant = _host._find(path)
	if node == null:
		return _host._no_node(path)
	if not node.is_class("TileMapLayer"):
		return _host._err("%s is a %s, not a TileMapLayer." % [_host._path_of(node), node.get_class()])
	return node


func _record_cell_undo(ur: EditorUndoRedoManager, layer: Node, coords: Vector2i) -> void:
	var source: int = layer.call("get_cell_source_id", coords)
	if source == -1:
		ur.add_undo_method(layer, "erase_cell", coords)
	else:
		ur.add_undo_method(layer, "set_cell", coords, source, layer.call("get_cell_atlas_coords", coords), layer.call("get_cell_alternative_tile", coords))


func _tool_get_tilemap_cells(args: Dictionary) -> Variant:
	var layer: Variant = _tile_layer(args.get("node_path", ""))
	if layer is Dictionary:
		return layer
	var limit := clampi(_host._to_int(args.get("limit"), 500), 1, 20000)
	var used: Array = layer.call("get_used_cells")
	var cells := []
	for coords in used:
		if cells.size() >= limit:
			break
		var atlas: Vector2i = layer.call("get_cell_atlas_coords", coords)
		cells.append({"x": coords.x, "y": coords.y, "source_id": layer.call("get_cell_source_id", coords),
			"atlas_x": atlas.x, "atlas_y": atlas.y, "alternative": layer.call("get_cell_alternative_tile", coords)})
	var sources := []
	var tile_set: Variant = layer.get("tile_set")
	if tile_set is TileSet:
		for i in tile_set.get_source_count():
			var id: int = tile_set.get_source_id(i)
			var source: TileSetSource = tile_set.get_source(id)
			var info := {"source_id": id, "type": source.get_class(), "tiles": source.get_tiles_count()}
			if source is TileSetAtlasSource and source.texture != null:
				info["texture"] = source.texture.resource_path
			sources.append(info)
	var out := {"path": _host._path_of(layer), "used_cells": used.size(), "truncated": used.size() > cells.size(), "cells": cells, "sources": sources}
	if tile_set is TileSet:
		out["tile_size"] = Values.to_json(tile_set.tile_size)
	else:
		out["warning"] = "This TileMapLayer has no TileSet."
	return out


func _tool_set_tilemap_cells(args: Dictionary) -> Variant:
	var layer: Variant = _tile_layer(args.get("node_path", ""))
	if layer is Dictionary:
		return layer
	var cells: Variant = args.get("cells", [])
	var erase: Variant = args.get("erase", [])
	if not (cells is Array) or not (erase is Array) or (cells.is_empty() and erase.is_empty()):
		return _host._err("Give cells and/or erase as arrays.")
	for entry in cells + erase:
		if not (entry is Dictionary) or not entry.has("x") or not entry.has("y"):
			return _host._err("Every cell needs x and y.")
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Paint tiles on %s" % layer.name, UndoRedo.MERGE_DISABLE, layer)
	var count := 0
	for entry in cells:
		var coords := Vector2i(_host._to_int(entry["x"], 0), _host._to_int(entry["y"], 0))
		_record_cell_undo(ur, layer, coords)
		ur.add_do_method(layer, "set_cell", coords, _host._to_int(entry.get("source_id"), 0),
			Vector2i(_host._to_int(entry.get("atlas_x"), 0), _host._to_int(entry.get("atlas_y"), 0)), _host._to_int(entry.get("alternative"), 0))
		count += 1
	for entry in erase:
		var coords := Vector2i(_host._to_int(entry["x"], 0), _host._to_int(entry["y"], 0))
		_record_cell_undo(ur, layer, coords)
		ur.add_do_method(layer, "erase_cell", coords)
	ur.commit_action()
	return {"path": _host._path_of(layer), "painted": count, "erased": erase.size(), "used_cells": layer.call("get_used_cells").size()}


func _tool_fill_tilemap_rect(args: Dictionary) -> Variant:
	var layer: Variant = _tile_layer(args.get("node_path", ""))
	if layer is Dictionary:
		return layer
	var from_arr: Variant = args.get("from", [])
	var to_arr: Variant = args.get("to", [])
	if not (from_arr is Array) or not (to_arr is Array) or from_arr.size() < 2 or to_arr.size() < 2:
		return _host._err("from and to must be [x, y] arrays.")

	var x0 := mini(int(from_arr[0]), int(to_arr[0]))
	var x1 := maxi(int(from_arr[0]), int(to_arr[0]))
	var y0 := mini(int(from_arr[1]), int(to_arr[1]))
	var y1 := maxi(int(from_arr[1]), int(to_arr[1]))
	var count := (x1 - x0 + 1) * (y1 - y0 + 1)
	if count > 20000:
		return _host._err("Rectangle too large (%d cells, max 20000)." % count)

	var erase := bool(args.get("erase", false))
	var sid := int(_host._to_int(args.get("source_id"), 0))
	var atlas := Vector2i(_host._to_int(args.get("atlas_x"), 0), _host._to_int(args.get("atlas_y"), 0))
	var alt := int(_host._to_int(args.get("alternative"), 0))

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Fill TileMap rect on %s" % layer.name, UndoRedo.MERGE_DISABLE, layer)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var coords := Vector2i(x, y)
			_record_cell_undo(ur, layer, coords)
			if erase:
				ur.add_do_method(layer, "erase_cell", coords)
			else:
				ur.add_do_method(layer, "set_cell", coords, sid, atlas, alt)
	ur.commit_action()
	return {"path": _host._path_of(layer), "cells_affected": count, "erase": erase}


func _tool_paint_tilemap_terrain(args: Dictionary) -> Variant:
	var layer: Variant = _tile_layer(args.get("node_path", ""))
	if layer is Dictionary:
		return layer
	var raw_cells: Variant = args.get("cells", [])
	if not (raw_cells is Array) or raw_cells.is_empty():
		return _host._err("cells must be a non-empty array of {x, y}.")

	var coords_arr: Array[Vector2i] = []
	for entry in raw_cells:
		if not (entry is Dictionary) or not entry.has("x") or not entry.has("y"):
			return _host._err("Every cell needs x and y.")
		coords_arr.append(Vector2i(int(entry["x"]), int(entry["y"])))

	var terrain_set := int(_host._to_int(args.get("terrain_set"), 0))
	var terrain := int(_host._to_int(args.get("terrain"), 0))
	var ignore_empty := bool(args.get("ignore_empty_terrains", true))

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Paint terrain on %s" % layer.name, UndoRedo.MERGE_DISABLE, layer)
	for c in coords_arr:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				_record_cell_undo(ur, layer, c + Vector2i(dx, dy))
	ur.add_do_method(layer, "set_cells_terrain_connect", coords_arr, terrain_set, terrain, ignore_empty)
	ur.commit_action()
	return {"path": _host._path_of(layer), "painted": coords_arr.size(), "terrain_set": terrain_set, "terrain": terrain}


func _tool_get_tileset_info(args: Dictionary) -> Variant:
	var ts: TileSet = null
	if args.has("resource_path") and str(args["resource_path"]) != "":
		var rp: String = _host._res_path(args["resource_path"])
		if rp == "" or not ResourceLoader.exists(rp):
			return _host._err("TileSet not found: " + str(args["resource_path"]))
		ts = load(rp) as TileSet
	elif args.has("node_path") and str(args["node_path"]) != "":
		var node: Node = _host._find(args["node_path"])
		if node == null:
			return _host._no_node(args["node_path"])
		ts = node.get("tile_set") as TileSet
	else:
		return _host._err("Provide node_path or resource_path.")

	if ts == null:
		return _host._err("No TileSet found.")
	var sources := []
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid)
		var info := {"id": sid, "type": src.get_class(), "tiles": src.get_tiles_count()}
		if src is TileSetAtlasSource:
			info["texture"] = src.texture.resource_path if src.texture != null else ""
			info["texture_region_size"] = Values.to_json(src.texture_region_size)
			info["grid_size"] = Values.to_json(src.get_atlas_grid_size())
		sources.append(info)
	return {
		"resource_path": ts.resource_path,
		"tile_size": Values.to_json(ts.tile_size),
		"tile_shape": ts.tile_shape,
		"physics_layers": ts.get_physics_layers_count(),
		"navigation_layers": ts.get_navigation_layers_count(),
		"terrain_sets": ts.get_terrain_sets_count(),
		"sources": sources,
	}


func _tool_setup_tileset_source(args: Dictionary) -> Variant:
	var tp: String = _host._res_path(args.get("texture_path", ""))
	if tp == "" or not ResourceLoader.exists(tp):
		return _host._err("Texture not found: " + str(args.get("texture_path", "")))
	var tex := load(tp) as Texture2D
	if tex == null:
		return _host._err("Not a Texture2D: " + tp)

	var sz_arr: Variant = args.get("tile_size", [16, 16])
	var tsize := Vector2i(int(sz_arr[0]), int(sz_arr[1])) if sz_arr is Array and sz_arr.size() >= 2 else Vector2i(16, 16)

	var ts := TileSet.new()
	ts.tile_size = tsize
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = tsize
	ts.add_source(src)

	var cols := int(tex.get_width() / maxf(1, tsize.x))
	var rows := int(tex.get_height() / maxf(1, tsize.y))
	var created_tiles := 0
	for x in cols:
		for y in rows:
			src.create_tile(Vector2i(x, y))
			created_tiles += 1

	var saved_path := ""
	if args.has("save_path") and str(args["save_path"]) != "":
		var sp: String = _host._res_path(args["save_path"])
		if sp == "" or not sp.ends_with(".tres"):
			return _host._err("save_path must end in .tres.")
		var dir := sp.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir): DirAccess.make_dir_recursive_absolute(dir)
		ResourceSaver.save(ts, sp)
		_host._scan()
		saved_path = sp
		ts = load(sp) as TileSet

	var assigned := ""
	if args.has("node_path") and str(args["node_path"]) != "":
		var layer: Variant = _tile_layer(args["node_path"])
		if layer is Dictionary: return layer
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Assign TileSet to %s" % layer.name)
		ur.add_do_property(layer, "tile_set", ts)
		ur.add_undo_property(layer, "tile_set", layer.get("tile_set"))
		ur.commit_action()
		assigned = _host._path_of(layer)

	return {"tile_size": Values.to_json(tsize), "grid": [cols, rows], "tiles_created": created_tiles, "saved_path": saved_path, "assigned_to": assigned}


func _tool_get_gridmap_cells(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not node.is_class("GridMap"):
		return _host._err("%s is %s, not a GridMap." % [_host._path_of(node), node.get_class()])
	var limit := clampi(_host._to_int(args.get("limit"), 500), 1, 20000)
	var used: Array = node.call("get_used_cells")
	var cells := []
	for coords in used:
		if cells.size() >= limit:
			break
		cells.append({
			"x": coords.x, "y": coords.y, "z": coords.z,
			"item": node.call("get_cell_item", coords),
			"orientation": node.call("get_cell_item_orientation", coords),
		})
	var lib: Variant = node.get("mesh_library")
	var items := []
	if lib is MeshLibrary:
		for id in lib.get_item_list():
			items.append({"id": id, "name": lib.get_item_name(id)})
	return {"path": _host._path_of(node), "used_cells": used.size(), "truncated": used.size() > cells.size(), "cells": cells, "mesh_library_items": items}


func _tool_set_gridmap_cells(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not node.is_class("GridMap"):
		return _host._err("%s is %s, not a GridMap." % [_host._path_of(node), node.get_class()])
	var cells: Variant = args.get("cells", [])
	var erase: Variant = args.get("erase", [])
	if not (cells is Array) or not (erase is Array) or (cells.is_empty() and erase.is_empty()):
		return _host._err("Provide cells and/or erase arrays.")

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Edit GridMap %s" % node.name)
	for entry in cells:
		if not (entry is Dictionary):
			continue
		var c := Vector3i(_host._to_int(entry.get("x"), 0), _host._to_int(entry.get("y"), 0), _host._to_int(entry.get("z"), 0))
		var old_item: int = node.call("get_cell_item", c)
		var old_ori: int = node.call("get_cell_item_orientation", c)
		ur.add_do_method(node, "set_cell_item", c, _host._to_int(entry.get("item"), 0), _host._to_int(entry.get("orientation"), 0))
		ur.add_undo_method(node, "set_cell_item", c, old_item, old_ori)
	for entry in erase:
		if not (entry is Dictionary):
			continue
		var c := Vector3i(_host._to_int(entry.get("x"), 0), _host._to_int(entry.get("y"), 0), _host._to_int(entry.get("z"), 0))
		var old_item: int = node.call("get_cell_item", c)
		var old_ori: int = node.call("get_cell_item_orientation", c)
		ur.add_do_method(node, "set_cell_item", c, -1, 0)
		ur.add_undo_method(node, "set_cell_item", c, old_item, old_ori)
	ur.commit_action()
	return {"path": _host._path_of(node), "placed": cells.size(), "erased": erase.size(), "used_cells": node.call("get_used_cells").size()}


func _tool_create_mesh_library(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".tres"):
		return _host._err("path must be a res:// path ending in .tres.")
	var root: Node = _host._find(args.get("root_path", "."))
	if root == null: return _host._no_node(args.get("root_path", "."))

	var lib := MeshLibrary.new()
	var id := 0
	for c in root.get_children():
		if c is MeshInstance3D and c.mesh != null:
			lib.create_item(id)
			lib.set_item_name(id, str(c.name))
			lib.set_item_mesh(id, c.mesh)
			id += 1
	if id == 0:
		return _host._err("No MeshInstance3D children with meshes found under %s." % _host._path_of(root))
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir): DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(lib, path)
	if err != OK: return _host._err("Failed to save MeshLibrary: " + error_string(err))
	_host._scan()
	return {"path": path, "items": id}
