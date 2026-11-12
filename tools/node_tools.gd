@tool
extends RefCounted
## Node creation, batch operations, hierarchy, properties, groups, signals, and timers.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("add_node", "Add a node to the edited scene (undoable). Give either type (a class name, built-in or class_name) or scene_path (to instance a scene).", {
		"parent_path": {"type": "string", "description": "Parent node path, default '.'"},
		"type": {"type": "string", "description": "Node class, e.g. Sprite2D"},
		"scene_path": {"type": "string", "description": "res:// scene to instance instead of type"},
		"name": s,
		"properties": {"type": "object", "description": "Initial properties, same value rules as set_node_properties"},
		"index": {"type": "integer", "description": "Position among siblings, default last"},
	})
	_reg("batch_add_nodes", "Add a hierarchy of nodes to the edited scene in a single undoable operation. Each item in 'nodes' can have: name, type (or scene_path), parent (relative to root_parent, default '.'), properties, script, groups, unique_name, children (nested array with same schema).", {
		"root_parent": {"type": "string", "description": "Parent node path in the edited scene, default '.'"},
		"nodes": {"type": "array", "items": {"type": "object"}},
	}, ["nodes"], false, false)
	_reg("delete_node", "Delete a node and its children from the edited scene (undoable).", {"node_path": node_path}, ["node_path"])
	_reg("move_node", "Rename, reparent and/or reorder a node (undoable).", {
		"node_path": node_path,
		"new_name": s,
		"new_parent_path": {"type": "string", "description": "New parent node path"},
		"index": {"type": "integer", "description": "New position among siblings"},
	}, ["node_path"])
	_reg("duplicate_node", "Duplicate a node with its children (undoable).", {
		"node_path": node_path,
		"new_name": s,
		"parent_path": {"type": "string", "description": "Parent for the copy. Default: same parent."},
	}, ["node_path"])
	_reg("replace_node_type", "Change a node's class while preserving its name, children, groups, and matching properties (undoable). Cannot replace the scene root.", {
		"node_path": node_path,
		"new_type": {"type": "string", "description": "New Node class name, e.g. AnimatedSprite2D, CharacterBody2D"},
	}, ["node_path", "new_type"], false, false)
	_reg("find_nodes", "Find nodes in the edited scene by name pattern, class, group or script.", {
		"name": {"type": "string", "description": "Glob pattern, case-insensitive, e.g. \"Enemy*\""},
		"type": {"type": "string", "description": "Class name; subclasses match too"},
		"group": s,
		"script": {"type": "string", "description": "res:// script path"},
	}, [], true)
	_reg("get_node_properties", "Properties, script, groups and signal connections of a node.", {
		"node_path": node_path,
		"properties": {"type": "array", "items": s, "description": "Only these properties. Default: all editor-visible properties."},
	}, ["node_path"], true)
	_reg("set_node_properties", "Set properties on a node (undoable). Values: JSON for bool/number/string; Godot expression strings for the rest, e.g. \"Vector2(10, 20)\", \"Color(1, 0, 0)\"; res:// paths for resources (use property 'script' to attach a script); null to clear. Sub-properties work as 'position:x'.", {
		"node_path": node_path,
		"properties": {"type": "object", "description": "Property name -> value"},
	}, ["node_path", "properties"])
	_reg("batch_set_properties", "Set properties on multiple nodes in a single undoable operation. items: [{\"node_path\": \"Player\", \"properties\": {\"speed\": 200}}].", {
		"items": {"type": "array", "items": {"type": "object"}},
	}, ["items"], false, false)
	_reg("set_node_groups", "Add a node to groups and/or remove it from groups; saved with the scene (undoable).", {
		"node_path": node_path,
		"add": string_list,
		"remove": string_list,
	}, ["node_path"])
	_reg("set_node_unique_name", "Enable or disable scene-unique name (%NodeName) on a node (undoable).", {
		"node_path": node_path,
		"unique": {"type": "boolean"},
	}, ["node_path", "unique"], false, false)
	_reg("connect_signal", "Connect (or disconnect) a node's signal to a method on another node; saved with the scene.", {
		"node_path": node_path,
		"signal": s,
		"target_path": {"type": "string", "description": "Node that has the method"},
		"method": s,
		"disconnect": {"type": "boolean", "description": "Remove the connection instead. Default false."},
	}, ["node_path", "signal", "target_path", "method"])
	_reg("batch_connect_signals", "Connect multiple signals between nodes in a single undoable action. connections: [{\"from\": \"Btn\", \"signal\": \"pressed\", \"to\": \".\", \"method\": \"_on_btn_pressed\"}].", {
		"connections": {"type": "array", "items": {"type": "object"}},
	}, ["connections"], false, false)
	_reg("get_node_signals", "List all signals of a node, their arguments, and current connections.", {
		"node_path": node_path,
		"include_inherited": {"type": "boolean", "description": "Include built-in class signals. Default true."},
	}, ["node_path"], true, false)
	_reg("setup_timer", "Create a Timer node with wait_time, one_shot, autostart, and optional timeout signal connection (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"name": {"type": "string", "description": "Default Timer"},
		"wait_time": {"type": "number", "description": "Default 1.0"},
		"one_shot": {"type": "boolean", "description": "Default false"},
		"autostart": {"type": "boolean", "description": "Default false"},
		"target_node": {"type": "string", "description": "Optional node path to connect 'timeout' signal to"},
		"target_method": {"type": "string", "description": "Method name on target_node"},
	}, [], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _build_node_specs(specs: Array, parent: Node, root: Node, out: Array, warnings: Array) -> String:
	for item in specs:
		if not (item is Dictionary):
			return "Each entry in nodes must be an object."
		var node: Node = null
		var scene_path := str(item.get("scene_path", ""))
		var type_name := str(item.get("type", ""))
		if scene_path != "":
			var res_p: String = _host._res_path(scene_path)
			if res_p == "" or not ResourceLoader.exists(res_p):
				return "Scene not found: " + scene_path
			var packed := load(res_p)
			if not (packed is PackedScene):
				return "Not a PackedScene: " + res_p
			node = packed.instantiate()
		elif type_name != "":
			node = _host._instantiate(type_name)
			if node == null:
				return "Cannot instantiate Node type: " + type_name
		else:
			return "Each node spec requires 'type' or 'scene_path'."

		var desired_name := str(item.get("name", ""))
		if desired_name != "":
			node.name = desired_name

		var script_path := str(item.get("script", ""))
		if script_path != "":
			var sp: String = _host._res_path(script_path)
			if sp == "" or not ResourceLoader.exists(sp):
				node.free()
				return "Script not found: " + script_path
			node.set_script(load(sp))

		var props: Variant = item.get("properties", {})
		if props is Dictionary and not props.is_empty():
			var errs := Values.apply_properties(node, props)
			for e in errs:
				warnings.append("%s: %s" % [node.name, e])

		var groups: Variant = item.get("groups", [])
		if groups is Array:
			for g in groups:
				node.add_to_group(StringName(str(g)), true)

		if bool(item.get("unique_name", false)):
			node.unique_name_in_owner = true

		out.append({"node": node, "parent": parent})

		var children: Variant = item.get("children", [])
		if children is Array and not children.is_empty():
			var err := _build_node_specs(children, node, root, out, warnings)
			if err != "":
				return err
	return ""


func _tool_add_node(args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	if root == null:
		return _host._err("No scene is open in the editor. Use open_scene or create_scene first.")
	var parent: Variant = _host._find(args.get("parent_path", "."))
	if parent == null:
		return _host._no_node(args.get("parent_path"))
	var node: Node
	var scene_path := str(args.get("scene_path", ""))
	if scene_path != "":
		scene_path = _host._res_path(scene_path)
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			return _host._err("Scene not found: " + str(args.get("scene_path")))
		if scene_path == root.scene_file_path:
			return _host._err("A scene cannot instance itself.")
		var packed: Variant = load(scene_path)
		if not (packed is PackedScene):
			return _host._err("Not a scene: " + scene_path)
		node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	else:
		var type := str(args.get("type", ""))
		if type == "":
			return _host._err("Give either type or scene_path.")
		node = _host._instantiate(type)
		if node == null:
			return _host._err("'%s' is not a Node class that can be instantiated. Use get_class_info to check names." % type)
	if node == null:
		return _host._err("Could not create the node.")
	if str(args.get("name", "")) != "":
		node.name = str(args["name"])
	var values: Variant = args.get("properties")
	if values is Dictionary and not values.is_empty():
		var prepared: Variant = _host._prepare_properties(node, values)
		if not prepared[1].is_empty():
			node.free()
			return _host._err("Node was not added.\n" + "\n".join(prepared[1]))
		for change in prepared[0]:
			if change[1]:
				node.set_indexed(NodePath(change[0]), change[2])
			else:
				node.set(change[0], change[2])
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Add %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	if args.has("index"):
		ur.add_do_method(parent, "move_child", node, _host._to_int(args["index"], -1))
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	return {"path": _host._path_of(node), "name": str(node.name), "type": node.get_class()}


func _tool_batch_add_nodes(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var root_parent: Node = _host._find(args.get("root_parent", "."))
	if root_parent == null:
		return _host._no_node(args.get("root_parent", "."))
	var specs: Variant = args.get("nodes", [])
	if not (specs is Array) or specs.is_empty():
		return _host._err("nodes must be a non-empty array.")

	var created_entries := []
	var errors := []
	var build_err := _build_node_specs(specs, root_parent, root, created_entries, errors)
	if build_err != "":
		for entry in created_entries:
			var n: Node = entry["node"]
			if is_instance_valid(n) and n.get_parent() == null:
				n.free()
		return _host._err(build_err)

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Batch add %d node(s)" % created_entries.size())
	for entry in created_entries:
		var node: Node = entry["node"]
		var parent: Node = entry["parent"]
		ur.add_do_method(parent, "add_child", node, true)
		ur.add_do_method(_host, "_set_owner_recursive", node, root)
		ur.add_do_reference(node)
		ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()

	var paths := []
	for entry in created_entries:
		paths.append(_host._path_of(entry["node"]))
	var out := {"added_count": created_entries.size(), "paths": paths}
	if not errors.is_empty():
		out["property_warnings"] = errors
	return out


func _tool_delete_node(args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	if node == root:
		return _host._err("The scene root cannot be deleted.")
	var parent: Node = node.get_parent()
	var path: Variant = _host._path_of(node)
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Delete %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(parent, "remove_child", node)
	ur.add_undo_method(parent, "add_child", node, true)
	ur.add_undo_method(parent, "move_child", node, node.get_index())
	for pair in _host._owned_nodes(node):
		if pair[1] != null:
			ur.add_undo_method(pair[0], "set_owner", pair[1])
	ur.add_undo_reference(node)
	ur.commit_action()
	return {"deleted": path}


func _tool_move_node(args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	var old_parent: Node = node.get_parent()
	var new_parent: Node = old_parent
	if args.has("new_parent_path"):
		if node == root:
			return _host._err("The scene root cannot be reparented.")
		new_parent = _host._find(args["new_parent_path"])
		if new_parent == null:
			return _host._no_node(args["new_parent_path"])
		if new_parent == node or node.is_ancestor_of(new_parent):
			return _host._err("A node cannot be moved into itself or its own children.")
	var new_name := str(args.get("new_name", ""))
	if not args.has("new_parent_path") and new_name == "" and not args.has("index"):
		return _host._err("Give new_name, new_parent_path and/or index.")
	if args.has("index") and node == root:
		return _host._err("The scene root has no sibling index.")
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Move %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	if new_parent != old_parent:
		var owners: Variant = _host._owned_nodes(node)
		ur.add_do_method(old_parent, "remove_child", node)
		ur.add_do_method(new_parent, "add_child", node, true)
		ur.add_undo_method(new_parent, "remove_child", node)
		ur.add_undo_method(old_parent, "add_child", node, true)
		ur.add_undo_method(old_parent, "move_child", node, node.get_index())
		for pair in owners:
			if pair[1] != null:
				ur.add_do_method(pair[0], "set_owner", pair[1])
				ur.add_undo_method(pair[0], "set_owner", pair[1])
	if new_name != "":
		ur.add_do_property(node, "name", new_name)
		ur.add_undo_property(node, "name", str(node.name))
	if args.has("index"):
		ur.add_do_method(new_parent, "move_child", node, _host._to_int(args["index"], -1))
		if new_parent == old_parent:
			ur.add_undo_method(old_parent, "move_child", node, node.get_index())
	ur.commit_action()
	return {"path": _host._path_of(node), "name": str(node.name), "index": node.get_index() if node != root else 0}


func _tool_duplicate_node(args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	if node == root:
		return _host._err("The scene root cannot be duplicated.")
	var parent: Node = node.get_parent()
	if args.has("parent_path"):
		parent = _host._find(args["parent_path"])
		if parent == null:
			return _host._no_node(args["parent_path"])
	var copy: Node = node.duplicate()
	if copy == null:
		return _host._err("Could not duplicate the node.")
	if str(args.get("new_name", "")) != "":
		copy.name = str(args["new_name"])
	var owned := [copy]
	_host._collect_owned_copies(node, copy, root, owned)
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Duplicate %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(parent, "add_child", copy, true)
	for n in owned:
		ur.add_do_method(n, "set_owner", root)
	ur.add_do_reference(copy)
	ur.add_undo_method(parent, "remove_child", copy)
	ur.commit_action()
	return {"path": _host._path_of(copy), "name": str(copy.name), "type": copy.get_class()}


func _tool_replace_node_type(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if node == root:
		return _host._err("Cannot replace the scene root node type directly.")
	var new_type := str(args.get("new_type", ""))
	var replacement: Node = _host._instantiate(new_type)
	if replacement == null:
		return _host._err("Cannot instantiate Node type: " + new_type)

	replacement.name = node.name
	replacement.unique_name_in_owner = node.unique_name_in_owner
	for g in node.get_groups():
		if not str(g).begins_with("_"):
			replacement.add_to_group(g, true)

	# Copy matching stored properties
	var target_props := {}
	for p in replacement.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_STORAGE:
			target_props[str(p["name"])] = p["type"]
	for p in node.get_property_list():
		var pname := str(p["name"])
		if pname == "script":
			continue
		if (int(p["usage"]) & PROPERTY_USAGE_STORAGE) and target_props.has(pname):
			if int(target_props[pname]) == int(p["type"]):
				replacement.set(pname, node.get(pname))

	var parent := node.get_parent()
	var idx := node.get_index()
	var children := node.get_children()

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Replace %s with %s" % [node.name, new_type])
	ur.add_do_method(parent, "remove_child", node)
	ur.add_do_method(parent, "add_child", replacement, true)
	ur.add_do_method(parent, "move_child", replacement, idx)
	for c in children:
		ur.add_do_method(node, "remove_child", c)
		ur.add_do_method(replacement, "add_child", c, true)
		ur.add_do_method(_host, "_set_owner_recursive", c, root)
	ur.add_do_property(replacement, "owner", root)
	ur.add_do_reference(replacement)

	ur.add_undo_method(parent, "remove_child", replacement)
	for c in children:
		ur.add_undo_method(replacement, "remove_child", c)
		ur.add_undo_method(node, "add_child", c, true)
		ur.add_undo_method(_host, "_set_owner_recursive", c, root)
	ur.add_undo_method(parent, "add_child", node, true)
	ur.add_undo_method(parent, "move_child", node, idx)
	ur.add_undo_property(node, "owner", root)
	ur.add_undo_reference(node)
	ur.commit_action()

	return {"path": _host._path_of(replacement), "old_type": node.get_class(), "new_type": replacement.get_class(), "preserved_children": children.size()}


func _tool_find_nodes(args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	if root == null:
		return _host._err("No scene is open in the editor.")
	var pattern := str(args.get("name", ""))
	var type := str(args.get("type", ""))
	var group := str(args.get("group", ""))
	var script_path: Variant = _host._res_path(args.get("script", "")) if str(args.get("script", "")) != "" else ""
	if pattern == "" and type == "" and group == "" and script_path == "":
		return _host._err("Give at least one of name, type, group, script.")
	var all := []
	_host._scene_nodes(root, root, all)
	var matches := []
	for node in all:
		if pattern != "" and not str(node.name).matchn(pattern):
			continue
		if type != "" and not node.is_class(type):
			var script: Variant = node.get_script()
			if not (script is Script and str(script.get_global_name()) == type):
				continue
		if group != "" and not node.is_in_group(group):
			continue
		if script_path != "":
			var attached: Variant = node.get_script()
			if not (attached is Script and attached.resource_path == script_path):
				continue
		matches.append({"path": _host._path_of(node), "type": node.get_class()})
	return {"count": matches.size(), "nodes": matches}


func _tool_get_node_properties(args: Dictionary) -> Variant:
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	var wanted: Variant = args.get("properties")
	var props := {}
	if wanted is Array and not wanted.is_empty():
		for name in wanted:
			var key := str(name)
			var base := key.split(":")[0]
			if base in node:
				props[key] = Values.to_json(node.get_indexed(NodePath(key)) if key.contains(":") else node.get(key))
			else:
				props[key] = "<no such property>"
	else:
		for p in node.get_property_list():
			if (p["usage"] & PROPERTY_USAGE_EDITOR) == 0:
				continue
			if p["usage"] & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
				continue
			props[p["name"]] = Values.to_json(node.get(p["name"]))
	var connections := []
	for sig in node.get_signal_list():
		for conn in node.get_signal_connection_list(sig["name"]):
			if (conn["flags"] & CONNECT_PERSIST) == 0:
				continue
			var callable: Callable = conn["callable"]
			var target: Variant = callable.get_object()
			connections.append({
				"signal": str(sig["name"]),
				"target": _host._path_of(target) if target is Node else str(target),
				"method": str(callable.get_method()),
			})
	var groups := []
	for g in node.get_groups():
		if not str(g).begins_with("_"):
			groups.append(str(g))
	var out := {"path": _host._path_of(node), "type": node.get_class(), "properties": props}
	if not groups.is_empty():
		out["groups"] = groups
	if not connections.is_empty():
		out["connections"] = connections
	return out


func _tool_set_node_properties(args: Dictionary) -> Variant:
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	var values: Variant = args.get("properties")
	if not (values is Dictionary) or values.is_empty():
		return _host._err("properties must be a non-empty object.")
	var prepared: Variant = _host._prepare_properties(node, values)
	if not prepared[1].is_empty():
		return _host._err("Nothing was changed.\n" + "\n".join(prepared[1]))
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set properties on %s" % node.name, UndoRedo.MERGE_DISABLE, node)
	for change in prepared[0]:
		if change[1]:
			ur.add_do_method(node, "set_indexed", NodePath(change[0]), change[2])
			ur.add_undo_method(node, "set_indexed", NodePath(change[0]), change[3])
		else:
			ur.add_do_property(node, change[0], change[2])
			ur.add_undo_property(node, change[0], change[3])
	ur.commit_action()
	var now := {}
	for change in prepared[0]:
		now[change[0]] = Values.to_json(node.get_indexed(NodePath(change[0])) if change[1] else node.get(change[0]))
	return {"path": _host._path_of(node), "properties": now}


func _tool_batch_set_properties(args: Dictionary) -> Variant:
	var items: Variant = args.get("items", [])
	if not (items is Array) or items.is_empty():
		return _host._err("items must be a non-empty array.")

	var prepared := []
	for entry in items:
		if not (entry is Dictionary):
			return _host._err("Each item must be an object with node_path and properties.")
		var node: Node = _host._find(entry.get("node_path", ""))
		if node == null:
			return _host._no_node(entry.get("node_path", ""))
		var props: Variant = entry.get("properties", {})
		if not (props is Dictionary) or props.is_empty():
			continue
		var prep: Array = _host._prepare_properties(node, props)
		if not prep[1].is_empty():
			return _host._err("%s: %s" % [_host._path_of(node), "; ".join(prep[1])])
		prepared.append({"node": node, "changes": prep[0]})

	if prepared.is_empty():
		return _host._err("No properties to update.")

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Batch set properties on %d node(s)" % prepared.size())
	var updated := []
	for p in prepared:
		var node: Node = p["node"]
		for change in p["changes"]:
			var key: String = change[0]
			var new_val: Variant = change[1]
			var old_val: Variant = change[2]
			if key.contains(":"):
				ur.add_do_property(node, key, new_val)
				ur.add_undo_property(node, key, old_val)
			else:
				ur.add_do_property(node, key, new_val)
				ur.add_undo_property(node, key, old_val)
		updated.append(_host._path_of(node))
	ur.commit_action()
	return {"updated_nodes": updated, "count": updated.size()}


func _tool_set_node_groups(args: Dictionary) -> Variant:
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	var add: Variant = args.get("add", [])
	var remove: Variant = args.get("remove", [])
	if not (add is Array) or not (remove is Array) or (add.is_empty() and remove.is_empty()):
		return _host._err("Give add and/or remove as arrays of group names.")
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Change groups of %s" % node.name, UndoRedo.MERGE_DISABLE, node)
	for g in add:
		if not node.is_in_group(str(g)):
			ur.add_do_method(node, "add_to_group", str(g), true)
			ur.add_undo_method(node, "remove_from_group", str(g))
	for g in remove:
		if node.is_in_group(str(g)):
			ur.add_do_method(node, "remove_from_group", str(g))
			ur.add_undo_method(node, "add_to_group", str(g), true)
	ur.commit_action()
	var groups := []
	for g in node.get_groups():
		if not str(g).begins_with("_"):
			groups.append(str(g))
	return {"path": _host._path_of(node), "groups": groups}


func _tool_set_node_unique_name(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	var unique := bool(args.get("unique", true))
	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set unique name on %s" % node.name)
	ur.add_do_property(node, "unique_name_in_owner", unique)
	ur.add_undo_property(node, "unique_name_in_owner", node.unique_name_in_owner)
	ur.commit_action()
	return {"path": _host._path_of(node), "unique_name_in_owner": node.unique_name_in_owner, "access_syntax": "%" + str(node.name)}


func _tool_connect_signal(args: Dictionary) -> Variant:
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	var target: Variant = _host._find(args.get("target_path", ""))
	if target == null:
		return _host._no_node(args.get("target_path"))
	var signal_name := str(args.get("signal", ""))
	var method := str(args.get("method", ""))
	if not node.has_signal(signal_name):
		var names := []
		for sig in node.get_signal_list():
			names.append(str(sig["name"]))
		return _host._err("%s has no signal '%s'. Signals: %s" % [node.get_class(), signal_name, ", ".join(names)])
	if method == "":
		return _host._err("method is empty.")
	var callable := Callable(target, method)
	var connected: bool = node.is_connected(signal_name, callable)
	var remove := bool(args.get("disconnect", false))
	if remove and not connected:
		return _host._err("That connection does not exist.")
	if not remove and connected:
		return {"already_connected": true}
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: %s signal %s" % ["Disconnect" if remove else "Connect", signal_name], UndoRedo.MERGE_DISABLE, _host._root())
	if remove:
		ur.add_do_method(node, "disconnect", signal_name, callable)
		ur.add_undo_method(node, "connect", signal_name, callable, CONNECT_PERSIST)
	else:
		ur.add_do_method(node, "connect", signal_name, callable, CONNECT_PERSIST)
		ur.add_undo_method(node, "disconnect", signal_name, callable)
	ur.commit_action()
	var out := {"signal": signal_name, "from": _host._path_of(node), "to": _host._path_of(target), "method": method, "connected": not remove}
	var script: Variant = target.get_script()
	if not remove and not target.has_method(method) and not (script is Script and method in _host._script_methods(script)):
		out["warning"] = "Target has no method '%s' yet. Add it to the target's script." % method
	return out


func _tool_batch_connect_signals(args: Dictionary) -> Variant:
	var conns: Variant = args.get("connections", [])
	if not (conns is Array) or conns.is_empty():
		return _host._err("connections must be a non-empty array.")
	var prepared := []
	for c in conns:
		if not (c is Dictionary): return _host._err("Each connection must be an object.")
		var from_n: Node = _host._find(c.get("from", ""))
		var to_n: Node = _host._find(c.get("to", ""))
		if from_n == null: return _host._no_node(c.get("from", ""))
		if to_n == null: return _host._no_node(c.get("to", ""))
		var sig := StringName(str(c.get("signal", "")))
		var meth := StringName(str(c.get("method", "")))
		if not from_n.has_signal(sig):
			return _host._err("%s has no signal '%s'." % [_host._path_of(from_n), sig])
		prepared.append([from_n, sig, Callable(to_n, meth)])

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Batch connect %d signal(s)" % prepared.size())
	for p in prepared:
		var fn: Node = p[0]
		var sname: StringName = p[1]
		var cb: Callable = p[2]
		if not fn.is_connected(sname, cb):
			ur.add_do_method(fn, "connect", sname, cb, CONNECT_PERSIST)
			ur.add_undo_method(fn, "disconnect", sname, cb)
	ur.commit_action()
	return {"connected": prepared.size()}


func _tool_get_node_signals(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	var include_inherited := bool(args.get("include_inherited", true))
	var script_sig_names := {}
	var scr: Variant = node.get_script()
	if scr is Script:
		for s in scr.get_script_signal_list():
			script_sig_names[str(s["name"])] = true

	var signals := []
	for sig in node.get_signal_list():
		var sname := str(sig["name"])
		if not include_inherited and not script_sig_names.has(sname):
			continue
		var sig_args := []
		for a in sig["args"]:
			sig_args.append({"name": str(a["name"]), "type": type_string(int(a["type"]))})
		var conns := []
		for c in node.get_signal_connection_list(sname):
			var target: Variant = c["callable"].get_object()
			conns.append({
				"target": _host._path_of(target) if target is Node else str(target),
				"method": str(c["callable"].get_method()),
				"flags": int(c["flags"]),
			})
		signals.append({"name": sname, "args": sig_args, "connections": conns})
	return {"path": _host._path_of(node), "count": signals.size(), "signals": signals}


func _tool_setup_timer(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var t := Timer.new()
	t.name = str(args.get("name", "Timer"))
	t.wait_time = maxf(0.01, float(args.get("wait_time", 1.0)))
	t.one_shot = bool(args.get("one_shot", false))
	t.autostart = bool(args.get("autostart", false))
	_host._add_child_undo(parent, t, "MCP: Add Timer")

	var connected := false
	if args.has("target_node") and args.has("target_method"):
		var target: Node = _host._find(args["target_node"])
		if target != null:
			t.connect(&"timeout", Callable(target, StringName(str(args["target_method"]))), CONNECT_PERSIST)
			connected = true
	return {"path": _host._path_of(t), "wait_time": t.wait_time, "connected_timeout": connected}
