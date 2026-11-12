@tool
extends RefCounted
## Editor selection, undo/redo, viewport camera, screenshots, editor scripts, and tool discovery.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("get_selection", "Nodes currently selected in the editor.", {}, [], true)
	_reg("select_nodes", "Select nodes in the editor's scene tree.", {"node_paths": string_list}, ["node_paths"])
	_reg("open_in_editor", "Show a script, scene or resource in the editor for the user.", {
		"path": {"type": "string", "description": "res:// path"},
		"line": {"type": "integer", "description": "Line for scripts"},
	}, ["path"])
	_reg("undo", "Undo the last change in the edited scene.")
	_reg("redo", "Redo the last undone change in the edited scene.")
	_reg("get_editor_state", "Current editor state: open scenes, open scripts, current script, selection count, and playing state.", {}, [], true, false)
	_reg("set_editor_screen", "Switch the Godot editor's main screen: 2D, 3D, Script, or AssetLib.", {
		"screen": {"type": "string", "description": "2D, 3D, Script, or AssetLib"},
	}, ["screen"], false, false)
	_reg("focus_editor_camera", "Select a node in the editor and focus/inspect it.", {
		"node_path": node_path,
	}, ["node_path"], false, false)
	_reg("take_screenshot", "PNG screenshot of the editor: the 2D viewport, the 3D viewport, or the whole editor window.", {
		"target": {"type": "string", "enum": ["2d", "3d", "editor"], "description": "Default editor"},
		"max_width": {"type": "integer", "description": "Downscale to this width. Default 1280."},
	}, [], true)
	_reg("execute_editor_script", "Run GDScript inside the editor for anything the other tools do not cover. The code is the body of `func run(plugin: EditorPlugin, scene: Node)`; use `return` to send back a value. EditorInterface is available. No `await`.", {
		"code": {"type": "string", "description": "Function body, e.g. \"return scene.get_child_count()\""},
	}, ["code"])
	_reg("discover_tools", "Search all registered MCP tools by keyword, category, or read-only status, returning matching tool names, categories, and descriptions.", {
		"query": {"type": "string", "description": "Substring to match in tool name or description (omit to list all names)"},
		"category": {"type": "string", "description": "Optional category filter: project, filesystem, scene, node, script, editor, resource, visual, ui, animation, audio, tilemap_world, physics_nav, runtime, toolkit, custom"},
		"read_only_only": {"type": "boolean", "description": "Only return read-only tools. Default false."},
		"include_schema": {"type": "boolean", "description": "Include full inputSchema. Default false."},
	}, [], true, false)
	_reg("reload_custom_tools", "Scan res://mcp_tools/*.gd for project-specific custom MCP tool extensions and hot-reload them.", {}, [], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _tool_get_selection(_args: Dictionary) -> Variant:
	var paths := []
	for node in EditorInterface.get_selection().get_selected_nodes():
		paths.append({"path": _host._path_of(node), "type": node.get_class()})
	return {"selected": paths}


func _tool_select_nodes(args: Dictionary) -> Variant:
	var wanted: Variant = args.get("node_paths", [])
	if not (wanted is Array):
		return _host._err("node_paths must be an array.")
	var nodes := []
	for p in wanted:
		var node: Variant = _host._find(p)
		if node == null:
			return _host._no_node(p)
		nodes.append(node)
	var selection := EditorInterface.get_selection()
	selection.clear()
	for node in nodes:
		selection.add_node(node)
	return {"selected": nodes.size()}


func _tool_open_in_editor(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _host._err("Not found: " + str(args.get("path", "")))
	if path.get_extension().to_lower() in ["tscn", "scn"]:
		return _host._modules[0]._tool_open_scene({"path": path})
	var res: Variant = load(path)
	if res is Script:
		EditorInterface.edit_script(res, _host._to_int(args.get("line"), -1))
		EditorInterface.set_main_screen_editor("Script")
	elif res is Resource:
		EditorInterface.edit_resource(res)
	else:
		return _host._err("Could not load " + path)
	return {"opened": path}


func _tool_undo(_args: Dictionary) -> Variant:
	var history: UndoRedo = _host._scene_history()
	if history == null or not history.has_undo():
		return _host._err("Nothing to undo in this scene.")
	var action: String = history.get_current_action_name()
	history.undo()
	return {"undone": action}


func _tool_redo(_args: Dictionary) -> Variant:
	var history: UndoRedo = _host._scene_history()
	if history == null or not history.has_redo():
		return _host._err("Nothing to redo in this scene.")
	history.redo()
	return {"redone": history.get_current_action_name()}


func _tool_get_editor_state(_args: Dictionary) -> Variant:
	var se := EditorInterface.get_script_editor()
	var open_scripts := []
	var current_script := ""
	if se != null:
		var cur := se.get_current_script()
		if cur != null:
			current_script = cur.resource_path
		for s in se.get_open_scripts():
			if s != null and s.resource_path != "":
				open_scripts.append(s.resource_path)
	var sel := []
	for n in EditorInterface.get_selection().get_selected_nodes():
		sel.append(_host._path_of(n))
	var root: Node = _host._root()
	return {
		"edited_scene": root.scene_file_path if root != null else null,
		"open_scenes": Array(EditorInterface.get_open_scenes()),
		"current_script": current_script,
		"open_scripts": open_scripts,
		"selected_nodes": sel,
		"is_playing": EditorInterface.is_playing_scene(),
		"playing_scene": EditorInterface.get_playing_scene(),
	}


func _tool_set_editor_screen(args: Dictionary) -> Variant:
	var screen := str(args.get("screen", ""))
	if not screen in ["2D", "3D", "Script", "AssetLib"]:
		return _host._err("screen must be 2D, 3D, Script, or AssetLib.")
	EditorInterface.set_main_screen_editor(screen)
	return {"screen": screen}


func _tool_focus_editor_camera(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)
	EditorInterface.edit_node(node)
	return {"focused": _host._path_of(node)}


func _tool_take_screenshot(args: Dictionary) -> Variant:
	var target := str(args.get("target", "editor"))
	if not (target in ["2d", "3d", "editor"]):
		return _host._err("target must be 2d, 3d or editor.")
	if DisplayServer.get_name() == "headless":
		return _host._err("No rendered viewport is available (the editor is running headless).")
	# The 2D/3D viewports only render while their workspace is shown, so switch to it and
	# capture a few frames later.
	if target == "2d":
		EditorInterface.set_main_screen_editor("2D")
	elif target == "3d":
		EditorInterface.set_main_screen_editor("3D")
	var ticket: Variant = _host._next_shot
	_host._next_shot -= 1
	_host._shots[ticket] = {"target": target, "frames": 4, "max_width": clampi(_host._to_int(args.get("max_width"), 1280), 64, 4096)}
	return {"__pending": ticket}


func _tool_execute_editor_script(args: Dictionary) -> Variant:
	var code := str(args.get("code", ""))
	if code.strip_edges() == "":
		return _host._err("code is empty.")
	var body := ""
	for line in code.split("\n"):
		body += "\t" + line + "\n"
	var script := GDScript.new()
	script.source_code = "@tool\nextends RefCounted\n\nfunc run(plugin: EditorPlugin, scene: Node) -> Variant:\n" + body + "\treturn null\n"
	var marker: int = _host._capture.mark()
	var err := script.reload()
	if err != OK:
		var problems: Variant = _host._error_lines(_host._capture.since(marker))
		return _host._err("The code did not compile (line numbers are offset by 4).\n" + ("\n".join(problems) if not problems.is_empty() else "See get_output source=editor."))
	var runner: Variant = script.new()
	var result: Variant = runner.run(_host._plugin, _host._root())
	var out := {}
	if result is Object and result.get_class() == "GDScriptFunctionState":
		out["result"] = "<coroutine: `await` is not supported here; the code kept running in the background>"
	else:
		out["result"] = Values.to_json(result)
	var logged: PackedStringArray = _host._capture.since(marker)
	if not logged.is_empty():
		out["output"] = "\n".join(logged.slice(maxi(logged.size() - 200, 0)))
	return out


func _tool_discover_tools(args: Dictionary) -> Variant:
	var query := str(args.get("query", "")).to_lower()
	var category := str(args.get("category", "")).strip_edges().to_lower()
	var ro_only := bool(args.get("read_only_only", false))
	var with_schema := bool(args.get("include_schema", false))
	var matches := []
	for def in _host.all_tool_definitions():
		var name := str(def["name"])
		var desc := str(def["description"])
		var cat: String = _host.get_tool_category(name)
		var is_ro := bool(def.get("annotations", {}).get("readOnlyHint", false))
		if ro_only and not is_ro:
			continue
		if category != "" and cat != category:
			continue
		if query != "" and not name.to_lower().contains(query) and not desc.to_lower().contains(query):
			continue
		var item := {"name": name, "category": cat, "description": desc, "read_only": is_ro}
		if with_schema:
			item["inputSchema"] = def["inputSchema"]
		matches.append(item)
	return {"count": matches.size(), "categories": _host.get_category_summary(), "tools": matches}


func _tool_reload_custom_tools(_args: Dictionary) -> Variant:
	return _host.load_custom_extensions()
