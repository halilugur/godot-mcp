@tool
extends RefCounted
## Project settings, statistics, input map, autoloads, export presets, plugins, and git status.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("get_project_info", "Project name, Godot version, main scene, open scenes, autoloads and run state. Call this first.", {}, [], true)
	_reg("get_project_settings", "Read project settings by name, or list the names under a prefix.", {
		"names": {"type": "array", "items": s, "description": "e.g. [\"application/run/main_scene\"]"},
		"prefix": {"type": "string", "description": "List settings starting with this, e.g. \"input/\""},
	}, [], true)
	_reg("set_project_setting", "Set a project setting and save project.godot. Same value rules as set_node_properties.", {
		"name": s,
		"value": {"description": "New value; null removes an override"},
	}, ["name", "value"])
	_reg("get_project_statistics", "Summarize project size and composition: file counts by extension, total GDScript lines, scene count, and resource count.", {}, [], true, false)
	_reg("list_input_actions", "Input actions defined in the project's Input Map.", {
		"include_builtin": {"type": "boolean", "description": "Include built-in ui_* actions. Default false."},
	}, [], true)
	_reg("add_input_action", "Create or replace an input action. Events: {\"key\": \"W\"}, {\"key\": \"Space\", \"shift\": true}, {\"mouse_button\": \"left\"}, {\"joypad_button\": 0}, {\"joypad_axis\": 0, \"axis_value\": -1}.", {
		"name": s,
		"events": {"type": "array", "items": {"type": "object"}},
		"deadzone": {"type": "number", "description": "Default 0.5"},
	}, ["name", "events"])
	_reg("remove_input_action", "Remove an input action from the Input Map.", {"name": s}, ["name"])
	_reg("add_standard_input_preset", "Register a standard InputMap preset: 'wasd_2d' (move_left/right/up/down + jump + interact) or 'ui_gamepad'.", {
		"preset": {"type": "string", "description": "wasd_2d or platformer_2d. Default wasd_2d."},
	}, [], false, false)
	_reg("add_autoload", "Register a script or scene as an autoload singleton.", {
		"name": s,
		"path": {"type": "string", "description": "res:// path to a script or scene"},
	}, ["name", "path"])
	_reg("remove_autoload", "Remove an autoload singleton.", {"name": s}, ["name"])
	_reg("get_autoload_info", "List all autoload singletons with their paths, base classes, and script symbols.", {}, [], true, false)
	_reg("list_export_presets", "Read export presets configured in res://export_presets.cfg.", {}, [], true, false)
	_reg("export_project", "Export the project headlessly using a preset from export_presets.cfg (release, debug, or pack).", {
		"preset": {"type": "string", "description": "Exact preset name from export_presets.cfg"},
		"output_path": {"type": "string", "description": "Optional destination file path (defaults to preset's export_path)"},
		"mode": {"type": "string", "description": "release, debug, or pack. Default debug."},
	}, ["preset"], false, false)
	_reg("manage_editor_plugins", "List installed addons/*/plugin.cfg plugins and optionally enable or disable one.", {
		"plugin": {"type": "string", "description": "Addon folder name (e.g. 'my_plugin') to toggle"},
		"enabled": {"type": "boolean", "description": "Enable (true) or disable (false) the specified plugin"},
	}, [], false, false)
	_reg("git_status", "Run 'git status --short' and optional 'git diff --stat' in the project root to inspect pending changes.", {
		"include_diff_stat": {"type": "boolean", "description": "Default true"},
	}, [], true, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _tool_get_project_info(_args: Dictionary) -> Variant:
	var root: Variant = _host._root()
	var autoloads := {}
	for prop in ProjectSettings.get_property_list():
		var n := str(prop["name"])
		if n.begins_with("autoload/"):
			autoloads[n.substr(9)] = str(ProjectSettings.get_setting(n)).trim_prefix("*")
	return {
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"godot_version": Engine.get_version_info()["string"],
		"project_dir": ProjectSettings.globalize_path("res://"),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"edited_scene": root.scene_file_path if root != null else null,
		"edited_scene_root": ("%s (%s)" % [root.name, root.get_class()]) if root != null else null,
		"open_scenes": Array(EditorInterface.get_open_scenes()).filter(func(p): return p != ""),
		"autoloads": autoloads,
		"is_playing": EditorInterface.is_playing_scene(),
	}


func _tool_get_project_settings(args: Dictionary) -> Variant:
	var out := {}
	var names: Variant = args.get("names")
	if names is Array:
		for n in names:
			out[str(n)] = Values.to_json(ProjectSettings.get_setting(str(n))) if ProjectSettings.has_setting(str(n)) else "<not set>"
	var prefix := str(args.get("prefix", ""))
	if prefix != "":
		for p in ProjectSettings.get_property_list():
			var n := str(p["name"])
			if n.begins_with(prefix) and out.size() < 300:
				out[n] = Values.to_json(ProjectSettings.get_setting(n))
	if out.is_empty():
		return _host._err("Give names and/or prefix (e.g. prefix \"application/\").")
	return out


func _tool_set_project_setting(args: Dictionary) -> Variant:
	var name := str(args.get("name", ""))
	if name == "" or not name.contains("/"):
		return _host._err("name must look like \"section/key\", e.g. \"application/run/main_scene\".")
	var value: Variant = args.get("value")
	var type := TYPE_NIL
	if ProjectSettings.has_setting(name):
		type = typeof(ProjectSettings.get_setting(name))
	if type == TYPE_OBJECT:
		type = TYPE_NIL
	var r := Values.coerce(value, type)
	if not r[0]:
		return _host._err("%s: %s" % [name, r[1]])
	ProjectSettings.set_setting(name, r[1])
	var err := ProjectSettings.save()
	if err != OK:
		return _host._err("Could not save project.godot: " + error_string(err))
	return {"name": name, "value": Values.to_json(ProjectSettings.get_setting(name)) if ProjectSettings.has_setting(name) else null}


func _tool_get_project_statistics(_args: Dictionary) -> Variant:
	var files := []
	_host._walk("res://", true, [], files, 5000)
	var by_ext := {}
	var gd_lines := 0
	var total_bytes := 0
	for f in files:
		var p := str(f)
		if p.begins_with("res://addons/local_mcp"):
			continue
		var ext := p.get_extension().to_lower()
		if ext == "": ext = "<none>"
		by_ext[ext] = int(by_ext.get(ext, 0)) + 1
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa != null:
			total_bytes += fa.get_length()
			if ext == "gd":
				gd_lines += fa.get_as_text().split("\n").size()
	return {
		"total_files": files.size(),
		"total_size_mb": snappedf(total_bytes / 1048576.0, 0.01),
		"gdscript_lines": gd_lines,
		"by_extension": by_ext,
	}


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
		return _host._err("name must be a plain action name such as \"jump\".")
	var specs: Variant = args.get("events", [])
	if not (specs is Array):
		return _host._err("events must be an array.")
	var events := []
	for spec in specs:
		var ev: Variant = _host._make_input_event(spec)
		if ev is String:
			return _host._err("Action was not saved: " + ev)
		events.append(ev)
	ProjectSettings.set_setting("input/" + name, {"deadzone": float(args.get("deadzone", 0.5)), "events": events})
	var err := ProjectSettings.save()
	if err != OK:
		return _host._err("Could not save project.godot: " + error_string(err))
	var texts := []
	for ev in events:
		texts.append(ev.as_text())
	return {"action": name, "events": texts}


func _tool_remove_input_action(args: Dictionary) -> Variant:
	var name := str(args.get("name", ""))
	if not ProjectSettings.has_setting("input/" + name):
		return _host._err("No such input action: " + name)
	ProjectSettings.set_setting("input/" + name, null)
	ProjectSettings.save()
	return {"removed": name}


func _tool_add_standard_input_preset(args: Dictionary) -> Variant:
	var preset := str(args.get("preset", "wasd_2d")).to_lower()
	var actions := {
		"move_left": [{"key": "A"}, {"key": "Left"}],
		"move_right": [{"key": "D"}, {"key": "Right"}],
		"move_up": [{"key": "W"}, {"key": "Up"}],
		"move_down": [{"key": "S"}, {"key": "Down"}],
		"jump": [{"key": "Space"}],
		"interact": [{"key": "E"}],
	}
	if preset == "platformer_2d":
		actions.erase("move_up")
		actions.erase("move_down")
	var added := []
	for aname in actions:
		_tool_add_input_action({"name": aname, "events": actions[aname]})
		added.append(aname)
	return {"preset": preset, "actions": added}


func _tool_add_autoload(args: Dictionary) -> Variant:
	var name := str(args.get("name", "")).strip_edges()
	if not name.is_valid_identifier():
		return _host._err("name must be a valid identifier, e.g. \"GameState\".")
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _host._err("Not found: " + str(args.get("path", "")))
	_host._plugin.add_autoload_singleton(name, path)
	ProjectSettings.save()
	return {"autoload": name, "path": path}


func _tool_remove_autoload(args: Dictionary) -> Variant:
	var name := str(args.get("name", ""))
	if name == _host.RUNTIME_AUTOLOAD:
		return _host._err("That autoload belongs to Local MCP. Turn it off with Project Settings > local_mcp/enable_game_runtime.")
	if not ProjectSettings.has_setting("autoload/" + name):
		return _host._err("No such autoload: " + name)
	_host._plugin.remove_autoload_singleton(name)
	ProjectSettings.save()
	return {"removed": name}


func _tool_get_autoload_info(_args: Dictionary) -> Variant:
	var list := []
	for p in ProjectSettings.get_property_list():
		var pname := str(p["name"])
		if pname.begins_with("autoload/"):
			var aname := pname.substr(9)
			var raw := str(ProjectSettings.get_setting(pname))
			var enabled := raw.begins_with("*")
			var path := raw.substr(1) if enabled else raw
			list.append({"name": aname, "path": path, "enabled": enabled, "exists": FileAccess.file_exists(path)})
	return {"count": list.size(), "autoloads": list}


func _tool_list_export_presets(_args: Dictionary) -> Variant:
	var path := "res://export_presets.cfg"
	if not FileAccess.file_exists(path):
		return {"exists": false, "presets": []}
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return _host._err("Failed to parse export_presets.cfg: " + error_string(err))
	var presets := []
	for sec in cfg.get_sections():
		if sec.begins_with("preset.") and not sec.ends_with(".options"):
			presets.append({
				"section": sec,
				"name": cfg.get_value(sec, "name", ""),
				"platform": cfg.get_value(sec, "platform", ""),
				"runnable": cfg.get_value(sec, "runnable", false),
				"export_path": cfg.get_value(sec, "export_path", ""),
			})
	return {"exists": true, "count": presets.size(), "presets": presets}


func _tool_export_project(args: Dictionary) -> Variant:
	if not FileAccess.file_exists("res://export_presets.cfg"):
		return _host._err("res://export_presets.cfg not found.")
	var preset := str(args.get("preset", ""))
	if preset == "":
		return _host._err("preset name is required.")
	var mode := str(args.get("mode", "debug")).to_lower()
	var flag := "--export-debug"
	if mode == "release":
		flag = "--export-release"
	elif mode == "pack":
		flag = "--export-pack"

	var out_path := str(args.get("output_path", ""))
	if out_path == "":
		var cfg := ConfigFile.new()
		cfg.load("res://export_presets.cfg")
		for sec in cfg.get_sections():
			if sec.begins_with("preset.") and not sec.ends_with(".options"):
				if str(cfg.get_value(sec, "name", "")) == preset:
					out_path = str(cfg.get_value(sec, "export_path", ""))
					break
	if out_path == "":
		return _host._err("No output_path given and preset has no export_path.")

	var proj_dir := ProjectSettings.globalize_path("res://")
	var cmd := PackedStringArray(["--headless", "--path", proj_dir, flag, preset, out_path])
	var output := []
	var rc := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	if text.length() > 12000:
		text = text.substr(text.length() - 12000)
	return {"preset": preset, "mode": mode, "output_path": out_path, "exit_code": rc, "ok": rc == 0, "output": text}


func _tool_manage_editor_plugins(args: Dictionary) -> Variant:
	if args.has("plugin") and str(args["plugin"]) != "":
		var target := str(args["plugin"]).strip_edges()
		var enable := bool(args.get("enabled", true))
		if target == "local_mcp" and not enable:
			return _host._err("Refusing to disable local_mcp from inside itself.")
		if not DirAccess.dir_exists_absolute("res://addons/" + target):
			return _host._err("Addon directory not found: res://addons/" + target)
		EditorInterface.set_plugin_enabled(target, enable)

	var plugins := []
	var da := DirAccess.open("res://addons")
	if da != null:
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if da.current_is_dir() and not entry.begins_with("."):
				var cfg_path := "res://addons/%s/plugin.cfg" % entry
				if FileAccess.file_exists(cfg_path):
					var cfg := ConfigFile.new()
					cfg.load(cfg_path)
					plugins.append({
						"id": entry,
						"name": str(cfg.get_value("plugin", "name", entry)),
						"version": str(cfg.get_value("plugin", "version", "")),
						"author": str(cfg.get_value("plugin", "author", "")),
						"enabled": EditorInterface.is_plugin_enabled(entry),
					})
			entry = da.get_next()
	return {"count": plugins.size(), "plugins": plugins}


func _tool_git_status(args: Dictionary) -> Variant:
	var proj_dir := ProjectSettings.globalize_path("res://")
	var st_out := []
	var rc := OS.execute("git", PackedStringArray(["-C", proj_dir, "status", "--short"]), st_out, true)
	if rc != 0:
		return _host._err("git status failed (is this a git repository?): " + "\n".join(st_out))
	var out := {"status": "\n".join(st_out).strip_edges()}
	if bool(args.get("include_diff_stat", true)):
		var diff_out := []
		OS.execute("git", PackedStringArray(["-C", proj_dir, "diff", "--stat"]), diff_out, true)
		out["diff_stat"] = "\n".join(diff_out).strip_edges()
	return out
