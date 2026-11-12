@tool
extends RefCounted
## Scene lifecycle, scene tree inspection, metrics, dependencies, warnings, and branch saving.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("open_scene", "Open a scene in the editor and make it the edited scene.", {"path": {"type": "string", "description": "res:// path to a .tscn/.scn"}}, ["path"])
	_reg("create_scene", "Create a new scene file with a root node and open it.", {
		"path": {"type": "string", "description": "res:// path ending in .tscn"},
		"root_type": {"type": "string", "description": "Node class for the root, e.g. Node2D, Node3D, Control, CharacterBody2D"},
		"root_name": {"type": "string", "description": "Default: file name"},
	}, ["path", "root_type"])
	_reg("save_scene", "Save the edited scene. Pass path to save as a new file.", {"path": {"type": "string", "description": "Optional res:// path for 'save as'"}})
	_reg("reload_scene", "Reload a scene from disk in the editor (useful if a .tscn was modified externally).", {
		"path": {"type": "string", "description": "Optional res:// path. Default: currently edited scene."},
	}, [], false, false)
	_reg("get_open_scenes", "List all scenes currently open in the editor and which one is active.", {}, [], true, false)
	_reg("get_scene_tree", "Node tree of the edited scene: names, types, scripts, instanced scenes.", {
		"node_path": {"type": "string", "description": "Subtree root, default '.'"},
		"max_depth": {"type": "integer", "description": "Default 8"},
	}, [], true)
	_reg("get_scene_metrics", "Analyze the currently edited scene: total node count, class breakdown, script count, instanced scenes, collision shapes, lights, and meshes.", {}, [], true, false)
	_reg("list_scene_dependencies", "List all resource dependencies (scripts, textures, sub-scenes, materials) of a scene or resource.", {
		"path": {"type": "string", "description": "res:// path to a .tscn, .scn, or .tres"},
	}, ["path"], true, false)
	_reg("check_scene_warnings", "Run Godot's get_configuration_warnings() across every node in the edited scene to find missing shapes, streams, textures, or setup issues.", {}, [], true, false)
	_reg("save_branch_as_scene", "Save a node and its subtree as a new .tscn scene file. Optionally replace the branch in the current scene with an instance of the new scene.", {
		"node_path": node_path,
		"path": {"type": "string", "description": "Destination res:// path ending in .tscn"},
		"replace_with_instance": {"type": "boolean", "description": "Default true"},
	}, ["node_path", "path"], false, false)
	_reg("set_editable_children", "Enable or disable 'Editable Children' on an instanced scene node (undoable).", {
		"node_path": node_path,
		"editable": {"type": "boolean"},
	}, ["node_path", "editable"], false, false)
	_reg("find_resource_usages", "Find all scenes, resources, scripts, and project.godot entries referencing a given res:// path.", {
		"path": {"type": "string", "description": "res:// path to search for"},
	}, ["path"], true, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _collect_metrics(node: Node, root: Node, classes: Dictionary, stats: Dictionary) -> void:
	stats["total_nodes"] += 1
	var cls := node.get_class()
	classes[cls] = int(classes.get(cls, 0)) + 1
	if node.get_script() != null:
		stats["scripted_nodes"] += 1
	if node != root and node.scene_file_path != "":
		stats["instanced_scenes"] += 1
	if node is CollisionShape2D or node is CollisionShape3D or node is CollisionPolygon2D or node is CollisionPolygon3D:
		stats["collision_shapes"] += 1
	if node is Light2D or node is Light3D:
		stats["lights"] += 1
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		stats["meshes"] += 1
	if node is Sprite2D or node is AnimatedSprite2D or node is Sprite3D or node is AnimatedSprite3D:
		stats["sprites"] += 1
	if node is Control:
		stats["controls"] += 1
	for c in node.get_children():
		_collect_metrics(c, root, classes, stats)


func _collect_warnings(node: Node, out: Array) -> void:
	var w: PackedStringArray = node.get_configuration_warnings()
	if not w.is_empty():
		out.append({"path": _host._path_of(node), "type": node.get_class(), "warnings": Array(w)})
	for c in node.get_children():
		_collect_warnings(c, out)


func _tool_open_scene(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _host._err("Scene not found: " + str(args.get("path", "")))
	if path in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(path)
	EditorInterface.open_scene_from_path(path)
	var root: Variant = _host._root()
	if root == null or root.scene_file_path != path:
		return _host._err("The editor did not open %s. Check get_output for errors." % path)
	return {"opened": path, "root": "%s (%s)" % [root.name, root.get_class()]}


func _tool_create_scene(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not (path.get_extension().to_lower() in ["tscn", "scn"]):
		return _host._err("path must be a res:// path ending in .tscn")
	if FileAccess.file_exists(path):
		return _host._err("File already exists: %s. Use open_scene, or pick another path." % path)
	var root: Variant = _host._instantiate(str(args.get("root_type", "")))
	if root == null:
		return _host._err("'%s' is not a Node class that can be instantiated." % str(args.get("root_type", "")))
	var root_name := str(args.get("root_name", ""))
	root.name = root_name if root_name != "" else path.get_file().get_basename().to_pascal_case()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		return _host._err("Could not save scene: " + error_string(err))
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(path)
	EditorInterface.open_scene_from_path(path)
	return {"created": path, "opened": _host._root() != null and _host._root().scene_file_path == path}


func _tool_save_scene(args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	if root == null:
		return _host._err("No scene is open.")
	if args.has("path") and str(args["path"]) != "":
		var path: Variant = _host._res_path(args["path"])
		if path == "" or not (path.get_extension().to_lower() in ["tscn", "scn"]):
			return _host._err("path must be a res:// path ending in .tscn")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		EditorInterface.save_scene_as(path)
		return {"saved": path}
	if root.scene_file_path == "":
		return _host._err("This scene has never been saved. Pass path.")
	var err := EditorInterface.save_scene()
	if err != OK:
		return _host._err("Save failed: " + error_string(err))
	return {"saved": root.scene_file_path}


func _tool_reload_scene(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "":
		var root: Node = _host._root()
		if root == null or root.scene_file_path == "":
			return _host._err("No saved scene is currently open.")
		path = root.scene_file_path
	EditorInterface.reload_scene_from_path(path)
	return {"reloaded": path}


func _tool_get_open_scenes(_args: Dictionary) -> Variant:
	var active := EditorInterface.get_edited_scene_root()
	var active_path := active.scene_file_path if active != null else ""
	var scenes := []
	for p in EditorInterface.get_open_scenes():
		scenes.append({"path": p, "active": p == active_path})
	return {"active_scene": active_path, "count": scenes.size(), "scenes": scenes}


func _tool_get_scene_tree(args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	if root == null:
		return _host._err("No scene is open in the editor. Use open_scene or create_scene first.")
	var start: Variant = _host._find(args.get("node_path", "."))
	if start == null:
		return _host._no_node(args.get("node_path"))
	return {
		"scene": root.scene_file_path,
		"path": _host._path_of(start),
		"tree": _host._describe_node(start, root, 0, clampi(_host._to_int(args.get("max_depth"), 8), 0, 64)),
	}


func _tool_get_scene_metrics(_args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var classes := {}
	var stats := {
		"total_nodes": 0,
		"scripted_nodes": 0,
		"instanced_scenes": 0,
		"collision_shapes": 0,
		"lights": 0,
		"meshes": 0,
		"sprites": 0,
		"controls": 0,
	}
	_collect_metrics(root, root, classes, stats)
	return {
		"scene_path": root.scene_file_path,
		"root": str(root.name),
		"stats": stats,
		"classes": classes,
	}


func _tool_list_scene_dependencies(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _host._err("Resource not found: " + str(args.get("path", "")))
	var deps := ResourceLoader.get_dependencies(path)
	var parsed := []
	for d in deps:
		var parts := d.split("::")
		if parts.size() >= 3:
			parsed.append({"uid": parts[0], "type": parts[1], "path": parts[2]})
		else:
			parsed.append({"raw": d})
	return {"path": path, "count": parsed.size(), "dependencies": parsed}


func _tool_check_scene_warnings(_args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var warnings := []
	_collect_warnings(root, warnings)
	return {"scene": root.scene_file_path, "warning_count": warnings.size(), "warnings": warnings}


func _tool_save_branch_as_scene(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if node == root:
		return _host._err("Use save_scene to save the entire root scene.")
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".tscn"):
		return _host._err("path must be a res:// path ending in .tscn.")

	var copy := node.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	_host._set_owner_recursive(copy, copy)
	var packed := PackedScene.new()
	var pack_err := packed.pack(copy)
	copy.free()
	if pack_err != OK:
		return _host._err("Failed to pack branch: " + error_string(pack_err))

	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		return _host._err("Failed to save scene: " + error_string(save_err))
	_host._scan()

	var replaced := false
	if bool(args.get("replace_with_instance", true)):
		var inst_scene := load(path) as PackedScene
		if inst_scene != null:
			var inst := inst_scene.instantiate()
			inst.name = node.name
			var parent := node.get_parent()
			var idx := node.get_index()
			var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
			ur.create_action("MCP: Replace branch with scene %s" % path)
			ur.add_do_method(parent, "remove_child", node)
			ur.add_do_method(parent, "add_child", inst, true)
			ur.add_do_method(parent, "move_child", inst, idx)
			ur.add_do_property(inst, "owner", root)
			ur.add_do_reference(inst)
			ur.add_undo_method(parent, "remove_child", inst)
			ur.add_undo_method(parent, "add_child", node, true)
			ur.add_undo_method(parent, "move_child", node, idx)
			ur.add_undo_property(node, "owner", root)
			ur.add_undo_reference(node)
			ur.commit_action()
			replaced = true
	return {"saved_path": path, "replaced_with_instance": replaced}


func _tool_set_editable_children(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if node.scene_file_path == "":
		return _host._err("%s is not an instanced scene." % _host._path_of(node))
	var editable := bool(args.get("editable", true))
	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set editable children on %s" % node.name)
	ur.add_do_method(root, "set_editable_instance", node, editable)
	ur.add_undo_method(root, "set_editable_instance", node, root.is_editable_instance(node))
	ur.commit_action()
	return {"path": _host._path_of(node), "editable_children": root.is_editable_instance(node)}


func _tool_find_resource_usages(args: Dictionary) -> Variant:
	var target: String = _host._res_path(args.get("path", ""))
	if target == "":
		return _host._err("Invalid res:// path.")
	var uid_str := ""
	if ResourceLoader.exists(target):
		var uid_id := ResourceLoader.get_resource_uid(target)
		if uid_id != ResourceUID.INVALID_ID:
			uid_str = ResourceUID.id_to_text(uid_id)

	var files := []
	_host._walk("res://", true, ["tscn", "tres", "gd", "godot", "cfg", "gdshader"], files, 3000)
	var usages := []
	for f in files:
		if f == target:
			continue
		var txt := FileAccess.get_file_as_string(f)
		if txt.contains(target) or (uid_str != "" and txt.contains(uid_str)):
			usages.append(f)
	return {"target": target, "uid": uid_str, "count": usages.size(), "used_in": usages}
