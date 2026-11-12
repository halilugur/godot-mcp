@tool
extends RefCounted
## Project filesystem (res://), save-data (user://), import settings, config files, and broken reference checks.

const Values := preload("../mcp_values.gd")
const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "cs", "gdshader", "gdshaderinc", "cfg", "json", "md", "txt", "godot", "csv", "xml", "yml", "yaml", "toml", "ini", "import"]
const MAX_READ_BYTES := 400 * 1024
const SKIP_DIRS := [".godot", ".git", ".import"]
const REFERENCE_EXTENSIONS := ["tscn", "tres", "gd", "godot", "import"]

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("list_files", "List project files under a res:// directory.", {
		"dir": {"type": "string", "description": "Directory, default res://"},
		"recursive": {"type": "boolean", "description": "Default true"},
		"extensions": {"type": "array", "items": s, "description": "Only these extensions, e.g. [\"gd\", \"tscn\"]"},
	}, [], true)
	_reg("read_file", "Read a text file (script, scene, resource, config) from the project.", {
		"path": {"type": "string", "description": "res:// path"},
		"start_line": {"type": "integer", "description": "1-based first line, default 1"},
		"max_lines": {"type": "integer", "description": "Default: whole file"},
	}, ["path"], true)
	_reg("write_file", "Create or overwrite a text file in the project. GDScript files are compiled afterwards and any errors are returned. Do not use this to edit a scene that is open in the editor; use the node tools instead.", {
		"path": {"type": "string", "description": "res:// path"},
		"content": s,
	}, ["path", "content"])
	_reg("edit_file", "Replace an exact piece of text in a project text file. Prefer this over write_file for small changes. old_text must match exactly, including tab indentation. GDScript files are compiled afterwards.", {
		"path": {"type": "string", "description": "res:// path"},
		"old_text": s,
		"new_text": s,
		"replace_all": {"type": "boolean", "description": "Replace every occurrence. Default false (old_text must then be unique)."},
	}, ["path", "old_text", "new_text"])
	_reg("create_directory", "Create a directory in the project.", {"path": {"type": "string", "description": "res:// path"}}, ["path"])
	_reg("move_file", "Move or rename a file or directory in the project and update res:// references to it in text files.", {
		"from": {"type": "string", "description": "res:// path"},
		"to": {"type": "string", "description": "res:// path"},
		"update_references": {"type": "boolean", "description": "Default true"},
	}, ["from", "to"])
	_reg("delete_file", "Delete a file or directory from the project by moving it to the system trash.", {
		"path": {"type": "string", "description": "res:// path"},
		"permanent": {"type": "boolean", "description": "Delete permanently instead of using the trash (files and empty directories only). Default false."},
	}, ["path"], false, true)
	_reg("search_files", "Case-insensitive text search across project text files.", {
		"query": s,
		"dir": {"type": "string", "description": "Default res://"},
		"extensions": {"type": "array", "items": s, "description": "Default: gd, tscn, tres, cs, gdshader, cfg, json, md, txt"},
		"max_results": {"type": "integer", "description": "Default 100"},
	}, ["query"], true)
	_reg("rescan_filesystem", "Make the editor rescan the project files (after changes made outside these tools).")
	_reg("set_import_settings", "Modify .import parameters (e.g. compress/mode, mipmaps/generate, process/fix_alpha_border) and reimport the asset.", {
		"path": {"type": "string", "description": "res:// path to the asset (not the .import file itself)"},
		"params": {"type": "object", "description": "Key-value pairs under [params], e.g. {\"compress/mode\": 0, \"mipmaps/generate\": false}"},
		"reimport": {"type": "boolean", "description": "Trigger EditorFileSystem.reimport_files(). Default true."},
	}, ["path", "params"], false, false)
	_reg("clean_orphan_imports", "Find (and optionally delete) orphaned .import files whose source asset no longer exists.", {
		"delete": {"type": "boolean", "description": "Delete orphaned .import files. Default false (dry-run)."},
	}, [], false, true)
	_reg("get_asset_info", "Inspect an asset (image, audio, font, mesh) for dimensions/duration/format and its .import settings.", {
		"path": {"type": "string", "description": "res:// path to the asset"},
	}, ["path"], true, false)
	_reg("edit_config_file", "Read or update keys in a Godot ConfigFile (.cfg, .ini, .godot) without rewriting the whole file.", {
		"path": {"type": "string", "description": "res:// path"},
		"section": s,
		"set": {"type": "object", "description": "Optional key->value map to write"},
	}, ["path"], false, false)
	_reg("find_broken_references", "Scan all .tscn and .tres files in the project for missing res:// dependencies.", {}, [], true, false)
	_reg("user_list_files", "List files and directories under user:// (game save data, configs, logs).", {
		"dir": {"type": "string", "description": "Directory under user://, default user://"},
		"recursive": {"type": "boolean", "description": "Default true"},
	}, [], true, false)
	_reg("user_read_file", "Read a text/JSON/cfg/log file from user://.", {
		"path": {"type": "string", "description": "user:// path"},
		"max_lines": {"type": "integer", "description": "Optional max lines"},
	}, ["path"], true, false)
	_reg("user_write_file", "Create or overwrite a text file under user:// (useful for seeding save states in tests).", {
		"path": {"type": "string", "description": "user:// path"},
		"content": s,
	}, ["path", "content"], false, false)
	_reg("user_delete_file", "Delete a file under user:// (e.g. reset a save file).", {
		"path": {"type": "string", "description": "user:// path"},
	}, ["path"], false, true)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _extensions_arg(value: Variant) -> Array:
	var out := []
	if value is Array:
		for e in value:
			out.append(str(e).trim_prefix(".").to_lower())
	return out


func _is_own_path(path: String) -> bool:
	var own: String = get_script().resource_path.get_base_dir()
	return path == own or path.begins_with(own + "/")


func _replace_references(old_path: String, new_path: String, is_dir: bool) -> Array:
	var changed := []
	var files := []
	_host._modules[0]._walk("res://", true, REFERENCE_EXTENSIONS, files, 20000)
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


func _user_path(path: Variant) -> String:
	var p := str(path).strip_edges().replace("\\", "/")
	if p == "" or p == "user://" or p == "user:/":
		return "user://"
	if not p.begins_with("user://"):
		if p.contains("://") or p.begins_with("/"):
			return ""
		p = "user://" + p
	p = p.simplify_path()
	if not p.begins_with("user://") or ".." in p.split("/"):
		return ""
	return p


func _walk_user(dir_path: String, recursive: bool, out: Array, limit: int) -> void:
	if out.size() >= limit:
		return
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "" and out.size() < limit:
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if da.current_is_dir():
				if recursive:
					_walk_user(full, true, out, limit)
				else:
					out.append(full + "/")
			else:
				out.append(full)
		entry = da.get_next()


func _tool_list_files(args: Dictionary) -> Variant:
	var dir: Variant = _host._res_path(args.get("dir", "res://"))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return _host._err("Directory not found: " + str(args.get("dir", "")))
	var files := []
	_host._walk(dir, bool(args.get("recursive", true)), _extensions_arg(args.get("extensions")), files, 2000)
	return {"dir": dir, "count": files.size(), "truncated": files.size() >= 2000, "files": files}


func _tool_read_file(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("File not found: " + str(args.get("path", "")))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _host._err("Cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
	if file.get_length() > MAX_READ_BYTES and not args.has("max_lines"):
		return _host._err("File is %d bytes. Read it in parts with start_line and max_lines." % file.get_length())
	var text := file.get_as_text()
	if not args.has("start_line") and not args.has("max_lines"):
		return text
	var lines := text.split("\n")
	var start := maxi(_host._to_int(args.get("start_line"), 1), 1) - 1
	var count: Variant = _host._to_int(args.get("max_lines"), lines.size())
	return "\n".join(lines.slice(start, start + maxi(count, 0)))


func _tool_write_file(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or path == "res://":
		return _host._err("Path must be inside the project (res://...).")
	if not (args.get("content") is String):
		return _host._err("content must be a string.")
	return _host._write_text(path, args["content"])


func _tool_edit_file(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("File not found: " + str(args.get("path", "")))
	var old_text := str(args.get("old_text", ""))
	var new_text := str(args.get("new_text", ""))
	if old_text == "":
		return _host._err("old_text is empty.")
	var text := FileAccess.get_file_as_string(path)
	var count := text.count(old_text)
	if count == 0:
		return _host._err("old_text was not found in %s. It must match exactly, including indentation (GDScript uses tabs). Use read_file to copy the current text." % path)
	var replace_all := bool(args.get("replace_all", false))
	if count > 1 and not replace_all:
		return _host._err("old_text matches %d places. Include more surrounding text to make it unique, or set replace_all." % count)
	if replace_all:
		text = text.replace(old_text, new_text)
	else:
		var at := text.find(old_text)
		text = text.substr(0, at) + new_text + text.substr(at + old_text.length())
	var out: Variant = _host._write_text(path, text)
	if not out.has("__error"):
		out["replacements"] = count if replace_all else 1
	return out


func _tool_create_directory(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or path == "res://":
		return _host._err("Path must be inside the project (res://...).")
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return _host._err("Cannot create directory: " + error_string(err))
	_host._scan()
	return {"created": path}


func _tool_move_file(args: Dictionary) -> Variant:
	var from: Variant = _host._res_path(args.get("from", ""))
	var to: Variant = _host._res_path(args.get("to", ""))
	if from == "" or from == "res://" or to == "" or to == "res://":
		return _host._err("Both paths must be inside the project (res://...).")
	if _is_own_path(from):
		return _host._err("The Local MCP addon cannot move itself.")
	var is_dir := DirAccess.dir_exists_absolute(from)
	if not is_dir and not FileAccess.file_exists(from):
		return _host._err("Not found: " + from)
	if FileAccess.file_exists(to) or DirAccess.dir_exists_absolute(to):
		return _host._err("Target already exists: " + to)
	if is_dir and to.begins_with(from + "/"):
		return _host._err("A directory cannot be moved into itself.")
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		return _host._err("Move failed: " + error_string(err))
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
	_host._scan()
	if not EditorInterface.get_open_scenes().is_empty():
		out["note"] = "Scenes that are open in the editor keep their old in-memory references until reopened with open_scene."
	return out


func _tool_delete_file(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or path == "res://":
		return _host._err("Path must be inside the project (res://...).")
	if _is_own_path(path) or path == "res://project.godot":
		return _host._err("This path is protected.")
	var is_dir := DirAccess.dir_exists_absolute(path)
	if not is_dir and not FileAccess.file_exists(path):
		return _host._err("Not found: " + path)
	var err: int
	var permanent := bool(args.get("permanent", false))
	if permanent:
		err = DirAccess.remove_absolute(path)
		if err != OK:
			return _host._err("Could not delete %s (%s). Directories must be empty for a permanent delete." % [path, error_string(err)])
	else:
		err = OS.move_to_trash(ProjectSettings.globalize_path(path))
		if err != OK:
			return _host._err("Could not move %s to the trash (%s). Pass permanent=true to delete it permanently." % [path, error_string(err)])
	if not is_dir:
		for suffix in [".import", ".uid"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	_host._scan()
	return {"deleted": path, "permanent": permanent}


func _tool_search_files(args: Dictionary) -> Variant:
	var query := str(args.get("query", "")).to_lower()
	if query == "":
		return _host._err("query is empty.")
	var dir: Variant = _host._res_path(args.get("dir", "res://"))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return _host._err("Directory not found: " + str(args.get("dir", "")))
	var extensions := _extensions_arg(args.get("extensions"))
	if extensions.is_empty():
		extensions = ["gd", "tscn", "tres", "cs", "gdshader", "cfg", "json", "md", "txt"]
	var limit := clampi(_host._to_int(args.get("max_results"), 100), 1, 1000)
	var files := []
	_host._walk(dir, true, extensions, files, 5000)
	var matches := []
	for path in files:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 2 * 1024 * 1024:
			continue
		var lines := file.get_as_text().split("\n")
		for i in lines.size():
			if lines[i].to_lower().contains(query):
				matches.append("%s:%d: %s" % [path, i + 1, lines[i].strip_edges().left(200)])
				if matches.size() >= limit:
					return {"count": matches.size(), "truncated": true, "matches": matches}
	return {"count": matches.size(), "truncated": false, "matches": matches}


func _tool_rescan_filesystem(_args: Dictionary) -> Variant:
	_host._scan()
	return {"scanning": true}


func _tool_set_import_settings(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("Asset not found: " + str(args.get("path", "")))
	var import_path := path + ".import"
	if not FileAccess.file_exists(import_path):
		return _host._err("No .import file found for: " + path)
	var params: Variant = args.get("params", {})
	if not (params is Dictionary) or params.is_empty():
		return _host._err("params must be a non-empty object.")

	var cfg := ConfigFile.new()
	var err := cfg.load(import_path)
	if err != OK:
		return _host._err("Failed to load .import: " + error_string(err))
	for k in params:
		cfg.set_value("params", str(k), params[k])
	err = cfg.save(import_path)
	if err != OK:
		return _host._err("Failed to save .import: " + error_string(err))

	var reimported := false
	if bool(args.get("reimport", true)):
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.reimport_files(PackedStringArray([path]))
			reimported = true
	return {"path": path, "updated_keys": params.keys(), "reimported": reimported}


func _tool_clean_orphan_imports(args: Dictionary) -> Variant:
	var do_delete := bool(args.get("delete", false))
	var imports := []
	_host._walk("res://", true, ["import"], imports, 3000)
	var orphans := []
	for imp in imports:
		var src := str(imp).trim_suffix(".import")
		if not FileAccess.file_exists(src):
			orphans.append(imp)
			if do_delete:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(imp))
	if do_delete and not orphans.is_empty():
		_host._scan()
	return {"orphans_found": orphans.size(), "deleted": do_delete, "files": orphans}


func _tool_get_asset_info(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("Asset not found: " + str(args.get("path", "")))

	var info := {
		"path": path,
		"extension": path.get_extension().to_lower(),
		"file_bytes": FileAccess.get_file_as_bytes(path).size(),
	}

	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res != null:
			info["resource_class"] = res.get_class()
			if res is Texture2D:
				info["width"] = res.get_width()
				info["height"] = res.get_height()
			elif res is AudioStream:
				info["length_seconds"] = res.get_length()
			elif res is Font:
				info["font_name"] = res.get_font_name()
			elif res is Mesh:
				info["surface_count"] = res.get_surface_count()
				info["aabb"] = Values.to_json(res.get_aabb())

	var import_path := path + ".import"
	if FileAccess.file_exists(import_path):
		var cfg := ConfigFile.new()
		if cfg.load(import_path) == OK:
			var import_data := {}
			for sec in cfg.get_sections():
				var sec_dict := {}
				for k in cfg.get_section_keys(sec):
					sec_dict[k] = Values.to_json(cfg.get_value(sec, k))
				import_data[sec] = sec_dict
			info["import"] = import_data
	return info


func _tool_edit_config_file(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "":
		return _host._err("Invalid res:// path.")
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path):
		var err := cfg.load(path)
		if err != OK:
			return _host._err("Failed to parse ConfigFile: " + error_string(err))

	var sec := str(args.get("section", ""))
	var to_set: Variant = args.get("set", null)
	if to_set is Dictionary and not to_set.is_empty():
		if sec == "":
			return _host._err("section is required when setting values.")
		for k in to_set:
			cfg.set_value(sec, str(k), to_set[k])
		var serr := cfg.save(path)
		if serr != OK:
			return _host._err("Failed to save ConfigFile: " + error_string(serr))

	if sec != "":
		var keys := {}
		if cfg.has_section(sec):
			for k in cfg.get_section_keys(sec):
				keys[k] = Values.to_json(cfg.get_value(sec, k))
		return {"path": path, "section": sec, "values": keys}
	var all_sections := {}
	for sname in cfg.get_sections():
		all_sections[sname] = Array(cfg.get_section_keys(sname))
	return {"path": path, "sections": all_sections}


func _tool_find_broken_references(_args: Dictionary) -> Variant:
	var files := []
	_host._walk("res://", true, ["tscn", "tres"], files, 3000)
	var broken := []
	for f in files:
		for dep in ResourceLoader.get_dependencies(f):
			var parts := dep.split("::")
			var dep_path := parts[2] if parts.size() >= 3 else dep
			if dep_path.begins_with("res://") and not ResourceLoader.exists(dep_path) and not FileAccess.file_exists(dep_path):
				broken.append({"file": f, "missing": dep_path})
	return {"scanned_files": files.size(), "broken_count": broken.size(), "broken": broken}


func _tool_user_list_files(args: Dictionary) -> Variant:
	var dir_path := _user_path(args.get("dir", "user://"))
	if dir_path == "":
		return _host._err("Invalid user:// path.")
	var recursive := bool(args.get("recursive", true))
	var files := []
	_walk_user(dir_path, recursive, files, 500)
	return {"dir": dir_path, "global_dir": ProjectSettings.globalize_path(dir_path), "count": files.size(), "files": files}


func _tool_user_read_file(args: Dictionary) -> Variant:
	var path := _user_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("File not found: " + str(args.get("path", "")))
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_READ_BYTES:
		return _host._err("File too large (%d bytes, max %d)." % [bytes.size(), MAX_READ_BYTES])
	var text := bytes.get_string_from_utf8()
	if args.has("max_lines"):
		var lines := text.split("\n")
		var limit := clampi(int(args["max_lines"]), 1, lines.size())
		text = "\n".join(lines.slice(0, limit))
	return {"path": path, "bytes": bytes.size(), "content": text}


func _tool_user_write_file(args: Dictionary) -> Variant:
	var path := _user_path(args.get("path", ""))
	if path == "" or path == "user://":
		return _host._err("Invalid user:// file path.")
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _host._err("Cannot open for write: " + path)
	var content := str(args.get("content", ""))
	f.store_string(content)
	f.close()
	return {"path": path, "bytes": content.to_utf8_buffer().size()}


func _tool_user_delete_file(args: Dictionary) -> Variant:
	var path := _user_path(args.get("path", ""))
	if path == "" or path == "user://" or not FileAccess.file_exists(path):
		return _host._err("File not found: " + str(args.get("path", "")))
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		return _host._err("Failed to delete file: " + error_string(err))
	return {"deleted": path}
