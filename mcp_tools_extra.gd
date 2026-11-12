@tool
extends "mcp_tools.gd"
## Second half of the tool set: file management, resources, input map, autoloads,
## animation, tilemaps, editor state, undo/redo and tools that reach into the running game.

const RUNTIME_AUTOLOAD := "LocalMcpRuntime"
const BREAK_MESSAGE := "The game is stopped in the debugger (script error or breakpoint), so it cannot answer. Read the error with get_output source=game, then call game_resume to continue or stop_project to end the run."
const REFERENCE_EXTENSIONS := ["gd", "tscn", "tres", "cfg", "godot", "json", "gdshader", "cs"]

var _bridge: EditorDebuggerPlugin


func set_bridge(bridge: EditorDebuggerPlugin) -> void:
	_bridge = bridge


func _build_definitions() -> void:
	super()
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	# Files
	_add("edit_file", "Replace an exact piece of text in a project text file. Prefer this over write_file for small changes. old_text must match exactly, including tab indentation. GDScript files are compiled afterwards.", {
		"path": {"type": "string", "description": "res:// path"},
		"old_text": s,
		"new_text": s,
		"replace_all": {"type": "boolean", "description": "Replace every occurrence. Default false (old_text must then be unique)."},
	}, ["path", "old_text", "new_text"])
	_add("create_directory", "Create a directory in the project.", {"path": {"type": "string", "description": "res:// path"}}, ["path"])
	_add("move_file", "Move or rename a file or directory in the project and update res:// references to it in text files.", {
		"from": {"type": "string", "description": "res:// path"},
		"to": {"type": "string", "description": "res:// path"},
		"update_references": {"type": "boolean", "description": "Default true"},
	}, ["from", "to"])
	_add("delete_file", "Delete a file or directory from the project by moving it to the system trash.", {
		"path": {"type": "string", "description": "res:// path"},
		"permanent": {"type": "boolean", "description": "Delete permanently instead of using the trash (files and empty directories only). Default false."},
	}, ["path"], false, true)
	_add("rescan_filesystem", "Make the editor rescan the project files (after changes made outside these tools).")

	# Scripts
	_add("create_script", "Create a new GDScript file from a template and optionally attach it to a node.", {
		"path": {"type": "string", "description": "res:// path ending in .gd"},
		"extends": {"type": "string", "description": "Base class. Default: the class of attach_to, or Node."},
		"class_name": {"type": "string", "description": "Optional global class name"},
		"attach_to": {"type": "string", "description": "Node path to attach the script to"},
		"content": {"type": "string", "description": "Full script source instead of the template"},
	}, ["path"])
	_add("attach_script", "Attach a script to a node (undoable). An empty script_path detaches the current script.", {
		"node_path": node_path,
		"script_path": {"type": "string", "description": "res:// path to a script, or \"\""},
	}, ["node_path", "script_path"])

	# Nodes
	_add("duplicate_node", "Duplicate a node with its children (undoable).", {
		"node_path": node_path,
		"new_name": s,
		"parent_path": {"type": "string", "description": "Parent for the copy. Default: same parent."},
	}, ["node_path"])
	_add("find_nodes", "Find nodes in the edited scene by name pattern, class, group or script.", {
		"name": {"type": "string", "description": "Glob pattern, case-insensitive, e.g. \"Enemy*\""},
		"type": {"type": "string", "description": "Class name; subclasses match too"},
		"group": s,
		"script": {"type": "string", "description": "res:// script path"},
	}, [], true)
	_add("set_node_groups", "Add a node to groups and/or remove it from groups; saved with the scene (undoable).", {
		"node_path": node_path,
		"add": string_list,
		"remove": string_list,
	}, ["node_path"])
	_add("get_selection", "Nodes currently selected in the editor.", {}, [], true)
	_add("select_nodes", "Select nodes in the editor's scene tree.", {"node_paths": string_list}, ["node_paths"])
	_add("open_in_editor", "Show a script, scene or resource in the editor for the user.", {
		"path": {"type": "string", "description": "res:// path"},
		"line": {"type": "integer", "description": "Line for scripts"},
	}, ["path"])
	_add("undo", "Undo the last change in the edited scene.")
	_add("redo", "Redo the last undone change in the edited scene.")

	# Resources
	_add("create_resource", "Create a resource file (.tres), e.g. a material, shape, theme, gradient or custom Resource.", {
		"type": {"type": "string", "description": "Resource class, e.g. StandardMaterial3D, RectangleShape2D"},
		"path": {"type": "string", "description": "res:// path ending in .tres"},
		"properties": {"type": "object", "description": "Same value rules as set_node_properties"},
	}, ["type", "path"])
	_add("get_resource_properties", "Read the properties of a resource file.", {
		"path": {"type": "string", "description": "res:// path"},
		"properties": string_list,
	}, ["path"], true)
	_add("set_resource_properties", "Change properties of a .tres/.res resource file and save it.", {
		"path": {"type": "string", "description": "res:// path"},
		"properties": {"type": "object"},
	}, ["path", "properties"])

	# Project
	_add("list_input_actions", "Input actions defined in the project's Input Map.", {
		"include_builtin": {"type": "boolean", "description": "Include built-in ui_* actions. Default false."},
	}, [], true)
	_add("add_input_action", "Create or replace an input action. Events: {\"key\": \"W\"}, {\"key\": \"Space\", \"shift\": true}, {\"mouse_button\": \"left\"}, {\"joypad_button\": 0}, {\"joypad_axis\": 0, \"axis_value\": -1}.", {
		"name": s,
		"events": {"type": "array", "items": {"type": "object"}},
		"deadzone": {"type": "number", "description": "Default 0.5"},
	}, ["name", "events"])
	_add("remove_input_action", "Remove an input action from the Input Map.", {"name": s}, ["name"])
	_add("add_autoload", "Register a script or scene as an autoload singleton.", {
		"name": s,
		"path": {"type": "string", "description": "res:// path to a script or scene"},
	}, ["name", "path"])
	_add("remove_autoload", "Remove an autoload singleton.", {"name": s}, ["name"])
	_add("search_classes", "Find Godot class names containing a text, e.g. \"Body2D\".", {"query": s}, ["query"], true)

	# Animation
	_add("get_animations", "Animations of an AnimationPlayer. Pass name for the full tracks and keys of one animation.", {
		"node_path": node_path,
		"name": s,
	}, ["node_path"], true)
	_add("set_animation", "Create or replace an animation on an AnimationPlayer (undoable). tracks: [{\"path\": \"Sprite2D:position\", \"keys\": [{\"time\": 0, \"value\": \"Vector2(0, 0)\"}, {\"time\": 1, \"value\": \"Vector2(100, 0)\"}], \"interpolation\": \"linear\"}]. Track paths are relative to the player's root node (normally its parent). For method tracks use {\"type\": \"method\", \"path\": \"Enemy\", \"keys\": [{\"time\": 0.5, \"method\": \"shoot\", \"args\": []}]}.", {
		"node_path": node_path,
		"name": s,
		"length": {"type": "number", "description": "Seconds. Default: time of the last key."},
		"loop": {"type": "boolean", "description": "Default false"},
		"tracks": {"type": "array", "items": {"type": "object"}},
		"autoplay": {"type": "boolean", "description": "Play this animation when the scene starts"},
	}, ["node_path", "name", "tracks"])
	_add("remove_animation", "Remove an animation from an AnimationPlayer (undoable).", {"node_path": node_path, "name": s}, ["node_path", "name"])

	# TileMap
	_add("get_tilemap_cells", "Used cells of a TileMapLayer and the sources of its TileSet.", {
		"node_path": node_path,
		"limit": {"type": "integer", "description": "Default 500"},
	}, ["node_path"], true)
	_add("set_tilemap_cells", "Paint or erase cells on a TileMapLayer (undoable). cells: [{\"x\": 0, \"y\": 0, \"source_id\": 0, \"atlas_x\": 0, \"atlas_y\": 0, \"alternative\": 0}]; erase: [{\"x\": 1, \"y\": 0}].", {
		"node_path": node_path,
		"cells": {"type": "array", "items": {"type": "object"}},
		"erase": {"type": "array", "items": {"type": "object"}},
	}, ["node_path"])

	# Running game
	_add("game_get_scene_tree", "Live node tree of the running game, with current scene, pause state and FPS. Requires run_project.", {
		"node_path": {"type": "string", "description": "Subtree root. Default: /root"},
		"max_depth": {"type": "integer", "description": "Default 8"},
	}, [], true)
	_add("game_get_node_properties", "Live property values of a node in the running game. Default: its script variables and common properties.", {
		"node_path": game_path,
		"properties": string_list,
	}, ["node_path"], true)
	_add("game_set_node_properties", "Change properties of a node in the running game (not saved to the scene).", {
		"node_path": game_path,
		"properties": {"type": "object"},
	}, ["node_path", "properties"])
	_add("game_call_method", "Call a method on a node in the running game and return its result.", {
		"node_path": game_path,
		"method": s,
		"args": {"type": "array", "description": "Arguments; Godot expression strings are converted"},
	}, ["node_path", "method"])
	_add("game_send_input", "Send input to the running game. Events run in order: {\"type\": \"action\", \"action\": \"jump\"}, {\"type\": \"key\", \"key\": \"Space\"}, {\"type\": \"mouse_button\", \"button\": 1, \"position\": [400, 300]}, {\"type\": \"mouse_motion\", \"position\": [10, 10]}. Without \"pressed\" an event is a tap: press, hold for \"hold\" seconds (default 0.1), release. With \"pressed\": true/false only that state is sent. \"wait\" pauses after the event.", {
		"events": {"type": "array", "items": {"type": "object"}},
	}, ["events"])
	_add("game_screenshot", "PNG screenshot of the running game.", {
		"max_width": {"type": "integer", "description": "Downscale to this width. Default 1280."},
	}, [], true)
	_add("game_resume", "Continue a game that is stopped in the debugger after a script error or breakpoint.")
	_add("game_execute_script", "Run GDScript inside the running game. The code is the body of `func run(tree: SceneTree, scene: Node)`; `return` a value to get it back. `await` is allowed (keep it under 15 seconds).", {
		"code": s,
	}, ["code"])


# ---------------------------------------------------------------- pending (game) results

func poll_pending(ticket: int) -> Variant:
	if ticket < 0:
		return super(ticket)
	if _bridge == null:
		return format_result(_err("The game bridge is not available."))
	var taken: Array = _bridge.take(ticket)
	if not taken[0]:
		if _bridge.is_breaked():
			_bridge.cancel(ticket)
			return format_result(_err(BREAK_MESSAGE))
		return null
	var result: Variant = taken[1]
	if result is Dictionary and result.has("__image_path"):
		var bytes := FileAccess.get_file_as_bytes(str(result["__image_path"]))
		if bytes.is_empty():
			return format_result(_err("The game saved a screenshot but it could not be read."))
		return format_result({"__image": Marshalls.raw_to_base64(bytes)})
	return format_result(result if result != null else {"result": null})


func cancel_pending(ticket: int) -> void:
	if ticket < 0:
		super(ticket)
	elif _bridge != null:
		_bridge.cancel(ticket)


func _game(command: String, args: Dictionary) -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return _err("The game is not running. Call run_project first.")
	if _bridge == null:
		return _err("The game bridge is not available.")
	if _bridge.is_breaked():
		return _err(BREAK_MESSAGE)
	var ticket: int = _bridge.send(command, args)
	if ticket < 0:
		return _err("The game has not connected to the editor yet. Wait a second and try again.")
	return {"__pending": ticket}


func _tool_game_get_scene_tree(args: Dictionary) -> Variant:
	return _game("tree", args)


func _tool_game_get_node_properties(args: Dictionary) -> Variant:
	return _game("get", args)


func _tool_game_set_node_properties(args: Dictionary) -> Variant:
	return _game("set", args)


func _tool_game_call_method(args: Dictionary) -> Variant:
	return _game("call", args)


func _tool_game_send_input(args: Dictionary) -> Variant:
	return _game("input", args)


func _tool_game_screenshot(args: Dictionary) -> Variant:
	return _game("screenshot", args)


func _tool_game_execute_script(args: Dictionary) -> Variant:
	var code := str(args.get("code", ""))
	if code.strip_edges() == "":
		return _err("code is empty.")
	# Compile here first: a parse error inside the running game would stop it in the debugger.
	var body := ""
	for line in code.split("\n"):
		body += "\t" + line + "\n"
	var check := GDScript.new()
	check.source_code = "extends RefCounted\n\nfunc run(tree: SceneTree, scene: Node) -> Variant:\n" + body + "\treturn null\n"
	var marker: int = _capture.mark()
	if check.reload() != OK:
		var problems := _error_lines(_capture.since(marker))
		return _err("The code did not compile (line numbers are offset by 3).\n" + ("\n".join(problems) if not problems.is_empty() else "See get_output source=editor."))
	return _game("exec", args)


func _tool_game_resume(_args: Dictionary) -> Variant:
	if not EditorInterface.is_playing_scene():
		return _err("The game is not running.")
	if _bridge == null or not _bridge.resume():
		return {"resumed": false, "note": "The game was not stopped in the debugger."}
	return {"resumed": true}


# ---------------------------------------------------------------- files

func _is_own_path(path: String) -> bool:
	var own: String = get_script().resource_path.get_base_dir()
	return path == own or path.begins_with(own + "/")


func _scan() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null and not fs.is_scanning():
		fs.scan()


func _tool_edit_file(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _err("File not found: " + str(args.get("path", "")))
	var old_text := str(args.get("old_text", ""))
	var new_text := str(args.get("new_text", ""))
	if old_text == "":
		return _err("old_text is empty.")
	var text := FileAccess.get_file_as_string(path)
	var count := text.count(old_text)
	if count == 0:
		return _err("old_text was not found in %s. It must match exactly, including indentation (GDScript uses tabs). Use read_file to copy the current text." % path)
	var replace_all := bool(args.get("replace_all", false))
	if count > 1 and not replace_all:
		return _err("old_text matches %d places. Include more surrounding text to make it unique, or set replace_all." % count)
	if replace_all:
		text = text.replace(old_text, new_text)
	else:
		var at := text.find(old_text)
		text = text.substr(0, at) + new_text + text.substr(at + old_text.length())
	var out := _write_text(path, text)
	if not out.has("__error"):
		out["replacements"] = count if replace_all else 1
	return out


func _tool_create_directory(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or path == "res://":
		return _err("Path must be inside the project (res://...).")
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return _err("Cannot create directory: " + error_string(err))
	_scan()
	return {"created": path}


func _replace_references(old_path: String, new_path: String, is_dir: bool) -> Array:
	var changed := []
	var files := []
	_walk("res://", true, REFERENCE_EXTENSIONS, files, 20000)
	for file_path in files:
		if _is_own_path(file_path):
			continue
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null or file.get_length() > 8 * 1024 * 1024:
			continue
		var text := file.get_as_text()
		file.close()
		var updated := text
		if is_dir:
			updated = updated.replace(old_path + "/", new_path + "/")
		else:
			updated = updated.replace("\"" + old_path + "\"", "\"" + new_path + "\"").replace("'" + old_path + "'", "'" + new_path + "'")
		if updated != text:
			var out := FileAccess.open(file_path, FileAccess.WRITE)
			if out != null:
				out.store_string(updated)
				out.close()
				changed.append(file_path)
	return changed


func _tool_move_file(args: Dictionary) -> Variant:
	var from := _res_path(args.get("from", ""))
	var to := _res_path(args.get("to", ""))
	if from == "" or from == "res://" or to == "" or to == "res://":
		return _err("Both paths must be inside the project (res://...).")
	if _is_own_path(from):
		return _err("The Local MCP addon cannot move itself.")
	var is_dir := DirAccess.dir_exists_absolute(from)
	if not is_dir and not FileAccess.file_exists(from):
		return _err("Not found: " + from)
	if FileAccess.file_exists(to) or DirAccess.dir_exists_absolute(to):
		return _err("Target already exists: " + to)
	if is_dir and to.begins_with(from + "/"):
		return _err("A directory cannot be moved into itself.")
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		return _err("Move failed: " + error_string(err))
	if not is_dir:
		for suffix in [".import", ".uid"]:
			if FileAccess.file_exists(from + suffix):
				DirAccess.rename_absolute(from + suffix, to + suffix)
	var out := {"moved": from, "to": to}
	if bool(args.get("update_references", true)):
		out["references_updated_in"] = _replace_references(from, to, is_dir)
		var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
		if main_scene == from or (is_dir and main_scene.begins_with(from + "/")):
			ProjectSettings.set_setting("application/run/main_scene", to + main_scene.substr(from.length()))
			ProjectSettings.save()
	_scan()
	if not EditorInterface.get_open_scenes().is_empty():
		out["note"] = "Scenes that are open in the editor keep their old in-memory references until reopened with open_scene."
	return out


func _tool_delete_file(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or path == "res://":
		return _err("Path must be inside the project (res://...).")
	if _is_own_path(path) or path == "res://project.godot":
		return _err("This path is protected.")
	var is_dir := DirAccess.dir_exists_absolute(path)
	if not is_dir and not FileAccess.file_exists(path):
		return _err("Not found: " + path)
	var err: int
	var permanent := bool(args.get("permanent", false))
	if permanent:
		err = DirAccess.remove_absolute(path)
		if err != OK:
			return _err("Could not delete %s (%s). Directories must be empty for a permanent delete." % [path, error_string(err)])
	else:
		err = OS.move_to_trash(ProjectSettings.globalize_path(path))
		if err != OK:
			return _err("Could not move %s to the trash (%s). Pass permanent=true to delete it permanently." % [path, error_string(err)])
	if not is_dir:
		for suffix in [".import", ".uid"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	_scan()
	return {"deleted": path, "permanent": permanent}


func _tool_rescan_filesystem(_args: Dictionary) -> Variant:
	_scan()
	return {"scanning": true}


# ---------------------------------------------------------------- scripts

func _set_script(node: Node, script: Variant) -> void:
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Set script on %s" % node.name, UndoRedo.MERGE_DISABLE, node)
	ur.add_do_property(node, "script", script)
	ur.add_undo_property(node, "script", node.get_script())
	ur.commit_action()


func _tool_create_script(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or path.get_extension().to_lower() != "gd":
		return _err("path must be a res:// path ending in .gd")
	if FileAccess.file_exists(path):
		return _err("File already exists: %s. Use edit_file or write_file to change it." % path)
	var node: Node = null
	if str(args.get("attach_to", "")) != "":
		node = _find(args["attach_to"])
		if node == null:
			return _no_node(args["attach_to"])
	var content := str(args.get("content", ""))
	if content == "":
		var base := str(args.get("extends", ""))
		if base == "":
			base = node.get_class() if node != null else "Node"
		var global_name := str(args.get("class_name", ""))
		if global_name != "":
			content += "class_name %s\n" % global_name
		content += "extends %s\n\n\nfunc _ready() -> void:\n\tpass\n" % base
	var out := _write_text(path, content)
	if out.has("__error"):
		return out
	if node != null:
		var script: Variant = load(path)
		if script is Script:
			_set_script(node, script)
			out["attached_to"] = _path_of(node)
		else:
			out["attach_error"] = "The script was written but could not be loaded."
	return out


func _tool_attach_script(args: Dictionary) -> Variant:
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var raw := str(args.get("script_path", ""))
	if raw == "":
		_set_script(node, null)
		return {"path": _path_of(node), "script": null}
	var path := _res_path(raw)
	if path == "" or not ResourceLoader.exists(path):
		return _err("Script not found: " + raw)
	var script: Variant = load(path)
	if not (script is Script):
		return _err("Not a script: " + path)
	_set_script(node, script)
	var out := {"path": _path_of(node), "script": path}
	var base := str(script.get_instance_base_type())
	if base != "" and not node.is_class(base):
		out["warning"] = "The script extends %s but the node is a %s." % [base, node.get_class()]
	return out


# ---------------------------------------------------------------- nodes

func _collect_owned_copies(original: Node, copy: Node, root: Node, out: Array) -> void:
	# Pairs the copy's descendants with the original's to find which ones belong to the scene.
	var a := original.get_children()
	var b := copy.get_children()
	for i in mini(a.size(), b.size()):
		if a[i].owner == root:
			out.append(b[i])
			_collect_owned_copies(a[i], b[i], root, out)


func _tool_duplicate_node(args: Dictionary) -> Variant:
	var root := _root()
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	if node == root:
		return _err("The scene root cannot be duplicated.")
	var parent := node.get_parent()
	if args.has("parent_path"):
		parent = _find(args["parent_path"])
		if parent == null:
			return _no_node(args["parent_path"])
	var copy := node.duplicate()
	if copy == null:
		return _err("Could not duplicate the node.")
	if str(args.get("new_name", "")) != "":
		copy.name = str(args["new_name"])
	var owned := [copy]
	_collect_owned_copies(node, copy, root, owned)
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Duplicate %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(parent, "add_child", copy, true)
	for n in owned:
		ur.add_do_method(n, "set_owner", root)
	ur.add_do_reference(copy)
	ur.add_undo_method(parent, "remove_child", copy)
	ur.commit_action()
	return {"path": _path_of(copy), "name": str(copy.name), "type": copy.get_class()}


func _scene_nodes(node: Node, root: Node, out: Array) -> void:
	out.append(node)
	for child in node.get_children():
		if child.owner == root:
			_scene_nodes(child, root, out)


func _tool_find_nodes(args: Dictionary) -> Variant:
	var root := _root()
	if root == null:
		return _err("No scene is open in the editor.")
	var pattern := str(args.get("name", ""))
	var type := str(args.get("type", ""))
	var group := str(args.get("group", ""))
	var script_path := _res_path(args.get("script", "")) if str(args.get("script", "")) != "" else ""
	if pattern == "" and type == "" and group == "" and script_path == "":
		return _err("Give at least one of name, type, group, script.")
	var all := []
	_scene_nodes(root, root, all)
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
		matches.append({"path": _path_of(node), "type": node.get_class()})
	return {"count": matches.size(), "nodes": matches}


func _tool_set_node_groups(args: Dictionary) -> Variant:
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var add: Variant = args.get("add", [])
	var remove: Variant = args.get("remove", [])
	if not (add is Array) or not (remove is Array) or (add.is_empty() and remove.is_empty()):
		return _err("Give add and/or remove as arrays of group names.")
	var ur := _plugin.get_undo_redo()
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
	return {"path": _path_of(node), "groups": groups}


func _tool_get_selection(_args: Dictionary) -> Variant:
	var paths := []
	for node in EditorInterface.get_selection().get_selected_nodes():
		paths.append({"path": _path_of(node), "type": node.get_class()})
	return {"selected": paths}


func _tool_select_nodes(args: Dictionary) -> Variant:
	var wanted: Variant = args.get("node_paths", [])
	if not (wanted is Array):
		return _err("node_paths must be an array.")
	var nodes := []
	for p in wanted:
		var node := _find(p)
		if node == null:
			return _no_node(p)
		nodes.append(node)
	var selection := EditorInterface.get_selection()
	selection.clear()
	for node in nodes:
		selection.add_node(node)
	return {"selected": nodes.size()}


func _tool_open_in_editor(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _err("Not found: " + str(args.get("path", "")))
	if path.get_extension().to_lower() in ["tscn", "scn"]:
		return _tool_open_scene({"path": path})
	var res: Variant = load(path)
	if res is Script:
		EditorInterface.edit_script(res, _to_int(args.get("line"), -1))
		EditorInterface.set_main_screen_editor("Script")
	elif res is Resource:
		EditorInterface.edit_resource(res)
	else:
		return _err("Could not load " + path)
	return {"opened": path}


func _scene_history() -> UndoRedo:
	var root := _root()
	if root == null:
		return null
	var ur := _plugin.get_undo_redo()
	return ur.get_history_undo_redo(ur.get_object_history_id(root))


func _tool_undo(_args: Dictionary) -> Variant:
	var history := _scene_history()
	if history == null or not history.has_undo():
		return _err("Nothing to undo in this scene.")
	var action := history.get_current_action_name()
	history.undo()
	return {"undone": action}


func _tool_redo(_args: Dictionary) -> Variant:
	var history := _scene_history()
	if history == null or not history.has_redo():
		return _err("Nothing to redo in this scene.")
	history.redo()
	return {"redone": history.get_current_action_name()}


# ---------------------------------------------------------------- resources

func _resource_properties(res: Resource, wanted: Variant) -> Dictionary:
	var props := {}
	if wanted is Array and not wanted.is_empty():
		for name in wanted:
			var key := str(name)
			props[key] = Values.to_json(res.get_indexed(NodePath(key))) if key.split(":")[0] in res else "<no such property>"
		return props
	for p in res.get_property_list():
		if (p["usage"] & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if p["usage"] & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		if str(p["name"]) in ["resource_local_to_scene", "resource_path", "resource_name", "script"]:
			continue
		props[p["name"]] = Values.to_json(res.get(p["name"]))
	return props


func _tool_create_resource(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not (path.get_extension().to_lower() in ["tres", "res"]):
		return _err("path must be a res:// path ending in .tres")
	if FileAccess.file_exists(path):
		return _err("File already exists: %s. Use set_resource_properties to change it." % path)
	var type := str(args.get("type", ""))
	var res: Resource = null
	if ClassDB.class_exists(type):
		var made := Values.make_resource({"type": type, "properties": args.get("properties", {})})
		if not made[0]:
			return _err(str(made[1]))
		res = made[1]
	else:
		for info in ProjectSettings.get_global_class_list():
			if str(info["class"]) == type:
				var script: Variant = load(info["path"])
				var base := str(script.get_instance_base_type()) if script is Script else ""
				if base != "" and ClassDB.is_parent_class(base, "Resource") and ClassDB.can_instantiate(base):
					res = ClassDB.instantiate(base)
					res.set_script(script)
					if args.get("properties") is Dictionary:
						var errors := Values.apply_properties(res, args["properties"])
						if not errors.is_empty():
							return _err("\n".join(errors))
		if res == null:
			return _err("'%s' is not a Resource class that can be created." % type)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return _err("Could not save: " + error_string(err))
	_filesystem_changed(path, true)
	return {"created": path, "type": res.get_class()}


func _tool_get_resource_properties(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _err("Resource not found: " + str(args.get("path", "")))
	var res: Variant = load(path)
	if not (res is Resource):
		return _err("Could not load " + path)
	return {"path": path, "type": res.get_class(), "properties": _resource_properties(res, args.get("properties"))}


func _tool_set_resource_properties(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _err("Resource not found: " + str(args.get("path", "")))
	if not (path.get_extension().to_lower() in ["tres", "res"]):
		return _err("Only .tres/.res files can be changed this way. For imported assets, edit their import settings instead.")
	var values: Variant = args.get("properties")
	if not (values is Dictionary) or values.is_empty():
		return _err("properties must be a non-empty object.")
	var res: Variant = load(path)
	if not (res is Resource):
		return _err("Could not load " + path)
	var errors := Values.apply_properties(res, values)
	if not errors.is_empty():
		return _err("\n".join(errors))
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return _err("Could not save: " + error_string(err))
	var keys := []
	for k in values:
		keys.append(str(k))
	return {"path": path, "properties": _resource_properties(res, keys)}


# ---------------------------------------------------------------- input map and autoloads

func _make_input_event(spec: Variant) -> Variant:
	# Returns an InputEvent, or a String with the problem.
	if not (spec is Dictionary):
		return "each event must be an object"
	if spec.has("key"):
		var code := OS.find_keycode_from_string(str(spec["key"]))
		if code == KEY_NONE:
			return "unknown key '%s' (use names like W, Space, Enter, Escape, Left, Shift)" % str(spec["key"])
		var k := InputEventKey.new()
		if bool(spec.get("physical", true)):
			k.physical_keycode = code
		else:
			k.keycode = code
		k.shift_pressed = bool(spec.get("shift", false))
		k.ctrl_pressed = bool(spec.get("ctrl", false))
		k.alt_pressed = bool(spec.get("alt", false))
		k.meta_pressed = bool(spec.get("meta", false))
		k.device = -1
		return k
	if spec.has("mouse_button"):
		var names := {"left": 1, "right": 2, "middle": 3, "wheel_up": 4, "wheel_down": 5}
		var raw: Variant = spec["mouse_button"]
		var index: int = names.get(str(raw).to_lower(), _to_int(raw, 0))
		if index <= 0:
			return "unknown mouse button '%s' (use left, right, middle, wheel_up, wheel_down or a number)" % str(raw)
		var b := InputEventMouseButton.new()
		b.button_index = index as MouseButton
		b.device = -1
		return b
	if spec.has("joypad_button"):
		var j := InputEventJoypadButton.new()
		j.button_index = _to_int(spec["joypad_button"], 0) as JoyButton
		j.device = -1
		return j
	if spec.has("joypad_axis"):
		var m := InputEventJoypadMotion.new()
		m.axis = _to_int(spec["joypad_axis"], 0) as JoyAxis
		m.axis_value = float(spec.get("axis_value", 1.0))
		m.device = -1
		return m
	return "an event needs one of: key, mouse_button, joypad_button, joypad_axis"


func _tool_list_input_actions(args: Dictionary) -> Variant:
	var builtin := bool(args.get("include_builtin", false))
	var actions := {}
	for p in ProjectSettings.get_property_list():
		var n := str(p["name"])
		if not n.begins_with("input/"):
			continue
		var action := n.substr(6)
		if action.begins_with("ui_") and not builtin:
			continue
		var value: Variant = ProjectSettings.get_setting(n)
		if not (value is Dictionary):
			continue
		var events := []
		for ev in value.get("events", []):
			if ev is InputEvent:
				events.append(ev.as_text())
		actions[action] = {"deadzone": value.get("deadzone", 0.5), "events": events}
	return {"count": actions.size(), "actions": actions}


func _tool_add_input_action(args: Dictionary) -> Variant:
	var name := str(args.get("name", "")).strip_edges()
	if name == "" or name.contains("/") or name.contains(":"):
		return _err("name must be a plain action name such as \"jump\".")
	var specs: Variant = args.get("events", [])
	if not (specs is Array):
		return _err("events must be an array.")
	var events := []
	for spec in specs:
		var ev: Variant = _make_input_event(spec)
		if ev is String:
			return _err("Action was not saved: " + ev)
		events.append(ev)
	ProjectSettings.set_setting("input/" + name, {"deadzone": float(args.get("deadzone", 0.5)), "events": events})
	var err := ProjectSettings.save()
	if err != OK:
		return _err("Could not save project.godot: " + error_string(err))
	var texts := []
	for ev in events:
		texts.append(ev.as_text())
	return {"action": name, "events": texts}


func _tool_remove_input_action(args: Dictionary) -> Variant:
	var name := str(args.get("name", ""))
	if not ProjectSettings.has_setting("input/" + name):
		return _err("No such input action: " + name)
	ProjectSettings.set_setting("input/" + name, null)
	ProjectSettings.save()
	return {"removed": name}


func _tool_add_autoload(args: Dictionary) -> Variant:
	var name := str(args.get("name", "")).strip_edges()
	if not name.is_valid_identifier():
		return _err("name must be a valid identifier, e.g. \"GameState\".")
	var path := _res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _err("Not found: " + str(args.get("path", "")))
	_plugin.add_autoload_singleton(name, path)
	ProjectSettings.save()
	return {"autoload": name, "path": path}


func _tool_remove_autoload(args: Dictionary) -> Variant:
	var name := str(args.get("name", ""))
	if name == RUNTIME_AUTOLOAD:
		return _err("That autoload belongs to Local MCP. Turn it off with Project Settings > local_mcp/enable_game_runtime.")
	if not ProjectSettings.has_setting("autoload/" + name):
		return _err("No such autoload: " + name)
	_plugin.remove_autoload_singleton(name)
	ProjectSettings.save()
	return {"removed": name}


func _tool_search_classes(args: Dictionary) -> Variant:
	var query := str(args.get("query", "")).to_lower()
	if query == "":
		return _err("query is empty.")
	var found := []
	for c in ClassDB.get_class_list():
		if str(c).to_lower().contains(query):
			found.append(str(c))
	for info in ProjectSettings.get_global_class_list():
		if str(info["class"]).to_lower().contains(query):
			found.append("%s (script: %s)" % [info["class"], info["path"]])
	found.sort()
	return {"count": found.size(), "classes": found.slice(0, 200)}


# ---------------------------------------------------------------- animation

func _player(path: Variant) -> Variant:
	var node := _find(path)
	if node == null:
		return _no_node(path)
	if not (node is AnimationPlayer):
		return _err("%s is a %s, not an AnimationPlayer." % [_path_of(node), node.get_class()])
	return node


func _track_summary(anim: Animation, index: int, with_keys: bool) -> Dictionary:
	var kinds := {Animation.TYPE_VALUE: "value", Animation.TYPE_METHOD: "method", Animation.TYPE_POSITION_3D: "position_3d",
		Animation.TYPE_ROTATION_3D: "rotation_3d", Animation.TYPE_SCALE_3D: "scale_3d", Animation.TYPE_BLEND_SHAPE: "blend_shape",
		Animation.TYPE_BEZIER: "bezier", Animation.TYPE_AUDIO: "audio", Animation.TYPE_ANIMATION: "animation"}
	var info := {
		"path": str(anim.track_get_path(index)),
		"type": kinds.get(anim.track_get_type(index), "other"),
		"key_count": anim.track_get_key_count(index),
	}
	if with_keys:
		var keys := []
		for k in anim.track_get_key_count(index):
			keys.append({"time": anim.track_get_key_time(index, k), "value": Values.to_json(anim.track_get_key_value(index, k))})
		info["keys"] = keys
	return info


func _tool_get_animations(args: Dictionary) -> Variant:
	var player: Variant = _player(args.get("node_path", ""))
	if player is Dictionary:
		return player
	var wanted := str(args.get("name", ""))
	if wanted != "":
		if not player.has_animation(wanted):
			return _err("No animation named '%s'. Animations: %s" % [wanted, ", ".join(Array(player.get_animation_list()))])
		var anim: Animation = player.get_animation(wanted)
		var tracks := []
		for i in anim.get_track_count():
			tracks.append(_track_summary(anim, i, true))
		return {"name": wanted, "length": anim.length, "loop": anim.loop_mode != Animation.LOOP_NONE, "tracks": tracks}
	var list := []
	for name in player.get_animation_list():
		var anim: Animation = player.get_animation(name)
		list.append({"name": str(name), "length": anim.length, "loop": anim.loop_mode != Animation.LOOP_NONE, "tracks": anim.get_track_count()})
	return {"path": _path_of(player), "autoplay": str(player.autoplay), "animations": list}


func _tool_set_animation(args: Dictionary) -> Variant:
	var player: Variant = _player(args.get("node_path", ""))
	if player is Dictionary:
		return player
	var name := str(args.get("name", ""))
	if name == "" or name.contains("/"):
		return _err("name must be a plain animation name.")
	var specs: Variant = args.get("tracks", [])
	if not (specs is Array):
		return _err("tracks must be an array.")
	var base: Node = player.get_node_or_null(player.root_node)
	var anim := Animation.new()
	var last_time := 0.0
	var warnings := []
	for spec in specs:
		if not (spec is Dictionary) or str(spec.get("path", "")) == "":
			return _err("Each track needs a path, e.g. \"Sprite2D:position\".")
		var track_path := NodePath(str(spec["path"]))
		var keys: Variant = spec.get("keys", [])
		if not (keys is Array):
			return _err("Track %s: keys must be an array." % track_path)
		var is_method := str(spec.get("type", "value")) == "method"
		var index := anim.add_track(Animation.TYPE_METHOD if is_method else Animation.TYPE_VALUE)
		anim.track_set_path(index, track_path)
		var node_part := NodePath(str(track_path).split(":")[0])
		var target: Node = base.get_node_or_null(node_part) if base != null else null
		if target == null:
			warnings.append("Track %s: node not found relative to %s." % [track_path, _path_of(base) if base != null else "the player's root"])
		var value_type := TYPE_NIL
		if not is_method:
			var prop := str(track_path.get_concatenated_subnames())
			if prop == "":
				return _err("Track %s: a value track path needs a property, e.g. \"Sprite2D:position\"." % track_path)
			if target != null:
				if prop.split(":")[0] in target:
					value_type = typeof(target.get_indexed(NodePath(prop)))
				else:
					warnings.append("Track %s: %s has no property '%s'." % [track_path, target.get_class(), prop])
			match str(spec.get("interpolation", "linear")):
				"nearest":
					anim.track_set_interpolation_type(index, Animation.INTERPOLATION_NEAREST)
				"cubic":
					anim.track_set_interpolation_type(index, Animation.INTERPOLATION_CUBIC)
			if bool(spec.get("discrete", false)) or value_type in [TYPE_BOOL, TYPE_STRING, TYPE_OBJECT, TYPE_INT]:
				anim.value_track_set_update_mode(index, Animation.UPDATE_DISCRETE)
		for key in keys:
			if not (key is Dictionary) or not key.has("time"):
				return _err("Track %s: every key needs a time." % track_path)
			var time := float(key["time"])
			last_time = maxf(last_time, time)
			if is_method:
				var call_args := []
				if key.get("args") is Array:
					for a in key["args"]:
						call_args.append(Values.coerce(a, TYPE_NIL)[1])
				anim.track_insert_key(index, time, {"method": StringName(str(key.get("method", ""))), "args": call_args})
			else:
				var r := Values.coerce(key.get("value"), value_type)
				if not r[0]:
					return _err("Track %s, key at %s: %s" % [track_path, time, r[1]])
				anim.track_insert_key(index, time, r[1], float(key.get("transition", 1.0)))
	anim.length = maxf(float(args.get("length", last_time)), 0.001)
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE

	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Set animation %s" % name, UndoRedo.MERGE_DISABLE, player)
	var library: AnimationLibrary
	if player.has_animation_library(""):
		library = player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		ur.add_do_method(player, "add_animation_library", "", library)
		ur.add_undo_method(player, "remove_animation_library", "")
	if library.has_animation(name):
		var previous: Animation = library.get_animation(name)
		ur.add_do_method(library, "remove_animation", name)
		ur.add_do_method(library, "add_animation", name, anim)
		ur.add_undo_method(library, "remove_animation", name)
		ur.add_undo_method(library, "add_animation", name, previous)
	else:
		ur.add_do_method(library, "add_animation", name, anim)
		ur.add_undo_method(library, "remove_animation", name)
	if args.has("autoplay"):
		ur.add_do_property(player, "autoplay", name if bool(args["autoplay"]) else "")
		ur.add_undo_property(player, "autoplay", player.autoplay)
	ur.commit_action()
	var out := {"animation": name, "length": anim.length, "tracks": anim.get_track_count()}
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


func _tool_remove_animation(args: Dictionary) -> Variant:
	var player: Variant = _player(args.get("node_path", ""))
	if player is Dictionary:
		return player
	var name := str(args.get("name", ""))
	if not player.has_animation_library("") or not player.get_animation_library("").has_animation(name):
		return _err("No animation named '%s' in the player's default library." % name)
	var library: AnimationLibrary = player.get_animation_library("")
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Remove animation %s" % name, UndoRedo.MERGE_DISABLE, player)
	ur.add_do_method(library, "remove_animation", name)
	ur.add_undo_method(library, "add_animation", name, library.get_animation(name))
	ur.commit_action()
	return {"removed": name}


# ---------------------------------------------------------------- tilemap

func _tile_layer(path: Variant) -> Variant:
	var node := _find(path)
	if node == null:
		return _no_node(path)
	if not node.is_class("TileMapLayer"):
		return _err("%s is a %s, not a TileMapLayer." % [_path_of(node), node.get_class()])
	return node


func _tool_get_tilemap_cells(args: Dictionary) -> Variant:
	var layer: Variant = _tile_layer(args.get("node_path", ""))
	if layer is Dictionary:
		return layer
	var limit := clampi(_to_int(args.get("limit"), 500), 1, 20000)
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
	var out := {"path": _path_of(layer), "used_cells": used.size(), "truncated": used.size() > cells.size(), "cells": cells, "sources": sources}
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
		return _err("Give cells and/or erase as arrays.")
	for entry in cells + erase:
		if not (entry is Dictionary) or not entry.has("x") or not entry.has("y"):
			return _err("Every cell needs x and y.")
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Paint tiles on %s" % layer.name, UndoRedo.MERGE_DISABLE, layer)
	var count := 0
	for entry in cells:
		var coords := Vector2i(_to_int(entry["x"], 0), _to_int(entry["y"], 0))
		_record_cell_undo(ur, layer, coords)
		ur.add_do_method(layer, "set_cell", coords, _to_int(entry.get("source_id"), 0),
			Vector2i(_to_int(entry.get("atlas_x"), 0), _to_int(entry.get("atlas_y"), 0)), _to_int(entry.get("alternative"), 0))
		count += 1
	for entry in erase:
		var coords := Vector2i(_to_int(entry["x"], 0), _to_int(entry["y"], 0))
		_record_cell_undo(ur, layer, coords)
		ur.add_do_method(layer, "erase_cell", coords)
	ur.commit_action()
	return {"path": _path_of(layer), "painted": count, "erased": erase.size(), "used_cells": layer.call("get_used_cells").size()}


func _record_cell_undo(ur: EditorUndoRedoManager, layer: Node, coords: Vector2i) -> void:
	var source: int = layer.call("get_cell_source_id", coords)
	if source == -1:
		ur.add_undo_method(layer, "erase_cell", coords)
	else:
		ur.add_undo_method(layer, "set_cell", coords, source, layer.call("get_cell_atlas_coords", coords), layer.call("get_cell_alternative_tile", coords))
