@tool
extends RefCounted
## GDScript creation, attachment, validation, linting, symbol refactoring, and ClassDB inspection.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("create_script", "Create a new GDScript file from a template and optionally attach it to a node.", {
		"path": {"type": "string", "description": "res:// path ending in .gd"},
		"extends": {"type": "string", "description": "Base class. Default: the class of attach_to, or Node."},
		"class_name": {"type": "string", "description": "Optional global class name"},
		"attach_to": {"type": "string", "description": "Node path to attach the script to"},
		"content": {"type": "string", "description": "Full script source instead of the template"},
	}, ["path"])
	_reg("attach_script", "Attach a script to a node (undoable). An empty script_path detaches the current script.", {
		"node_path": node_path,
		"script_path": {"type": "string", "description": "res:// path to a script, or \"\""},
	}, ["node_path", "script_path"])
	_reg("validate_script", "Compile a GDScript file and return its errors.", {"path": {"type": "string", "description": "res:// path to a .gd file"}}, ["path"], true)
	_reg("validate_all_scripts", "Compile all .gd scripts in the project (or under a directory) and report any scripts with errors.", {
		"dir": {"type": "string", "description": "Directory to scan, default res://"},
	}, [], true, false)
	_reg("get_script_symbols", "Extract structural symbols (class_name, extends, signals, enums, constants, @export vars, functions with line numbers) from a GDScript file without reading the whole file.", {
		"path": {"type": "string", "description": "res:// path to a .gd file"},
	}, ["path"], true, false)
	_reg("add_script_member", "Append a signal, @export var, const, or func to a .gd script file and compile-check it.", {
		"path": {"type": "string", "description": "res:// path to a .gd file"},
		"kind": {"type": "string", "description": "signal, export, const, or func"},
		"code": {"type": "string", "description": "Full declaration or function block"},
	}, ["path", "kind", "code"], false, false)
	_reg("rename_symbol_in_project", "Find (and optionally replace) an exact identifier across all .gd files in the project.", {
		"old_name": s,
		"new_name": s,
		"dry_run": {"type": "boolean", "description": "Preview matches without modifying files. Default true."},
	}, ["old_name", "new_name"], false, false)
	_reg("lint_gdscript", "Check .gd scripts for mixed tabs/spaces indentation, trailing whitespace, and lines exceeding max_length.", {
		"path": {"type": "string", "description": "res:// file or directory, default res://"},
		"max_line_length": {"type": "integer", "description": "Default 120"},
	}, [], true, false)
	_reg("get_class_info", "Properties, methods and signals of a Godot class. Use it instead of guessing API names.", {
		"class_name": s,
		"include_inherited": {"type": "boolean", "description": "Default false"},
	}, ["class_name"], true)
	_reg("search_classes", "Find Godot class names containing a text, e.g. \"Body2D\".", {"query": s}, ["query"], true)
	_reg("search_class_members", "Search Godot ClassDB for subclasses of a base class, or find classes that define a specific method/signal/property.", {
		"base_class": {"type": "string", "description": "Optional base class to list subclasses of (e.g. 'Control', 'Node3D')"},
		"member_query": {"type": "string", "description": "Optional substring to match method/signal/property names"},
		"limit": {"type": "integer", "description": "Default 60"},
	}, [], true, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _set_script(node: Node, script: Variant) -> void:
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set script on %s" % node.name, UndoRedo.MERGE_DISABLE, node)
	ur.add_do_property(node, "script", script)
	ur.add_undo_property(node, "script", node.get_script())
	ur.commit_action()


func _type_name(info: Dictionary, is_return := false) -> String:
	if info["type"] == TYPE_OBJECT and str(info.get("class_name", "")) != "":
		return str(info["class_name"])
	if info["type"] == TYPE_NIL:
		return "void" if is_return and (info.get("usage", 0) & PROPERTY_USAGE_NIL_IS_VARIANT) == 0 else "Variant"
	return type_string(info["type"])


func _tool_create_script(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or path.get_extension().to_lower() != "gd":
		return _host._err("path must be a res:// path ending in .gd")
	if FileAccess.file_exists(path):
		return _host._err("File already exists: %s. Use edit_file or write_file to change it." % path)
	var node: Node = null
	if str(args.get("attach_to", "")) != "":
		node = _host._find(args["attach_to"])
		if node == null:
			return _host._no_node(args["attach_to"])
	var content := str(args.get("content", ""))
	if content == "":
		var base := str(args.get("extends", ""))
		if base == "":
			base = node.get_class() if node != null else "Node"
		var global_name := str(args.get("class_name", ""))
		if global_name != "":
			content += "class_name %s\n" % global_name
		content += "extends %s\n\n\nfunc _ready() -> void:\n\tpass\n" % base
	var out: Variant = _host._write_text(path, content)
	if out.has("__error"):
		return out
	if node != null:
		var script: Variant = load(path)
		if script is Script:
			_set_script(node, script)
			out["attached_to"] = _host._path_of(node)
		else:
			out["attach_error"] = "The script was written but could not be loaded."
	return out


func _tool_attach_script(args: Dictionary) -> Variant:
	var node: Variant = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path"))
	var raw := str(args.get("script_path", ""))
	if raw == "":
		_set_script(node, null)
		return {"path": _host._path_of(node), "script": null}
	var path: Variant = _host._res_path(raw)
	if path == "" or not ResourceLoader.exists(path):
		return _host._err("Script not found: " + raw)
	var script: Variant = load(path)
	if not (script is Script):
		return _host._err("Not a script: " + path)
	_set_script(node, script)
	var out := {"path": _host._path_of(node), "script": path}
	var base := str(script.get_instance_base_type())
	if base != "" and not node.is_class(base):
		out["warning"] = "The script extends %s but the node is a %s." % [base, node.get_class()]
	return out


func _tool_validate_script(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("File not found: " + str(args.get("path", "")))
	if path.get_extension().to_lower() != "gd":
		return _host._err("Only .gd files can be validated.")
	var result: Variant = _host._compile_script(path, FileAccess.get_file_as_string(path))
	result["path"] = path
	return result


func _tool_validate_all_scripts(args: Dictionary) -> Variant:
	var dir: String = _host._res_path(args.get("dir", "res://"))
	if dir == "":
		dir = "res://"
	var files := []
	_host._walk(dir, true, ["gd"], files, 2000)
	var failed := []
	var checked := 0
	for p in files:
		if str(p).begins_with("res://addons/local_mcp"):
			continue
		checked += 1
		var res: Dictionary = _host._compile_script(p)
		if not bool(res.get("ok", true)):
			failed.append({"path": p, "errors": res.get("errors", [])})
	return {"checked": checked, "failed_count": failed.size(), "ok": failed.is_empty(), "failed": failed}


func _tool_get_script_symbols(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("Script not found: " + str(args.get("path", "")))
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")

	var out := {
		"path": path,
		"line_count": lines.size(),
		"class_name": "",
		"extends": "",
		"signals": [],
		"enums": [],
		"constants": [],
		"exports": [],
		"functions": [],
	}

	var re_func := RegEx.create_from_string("^\\s*(?:static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(([^)]*)\\)(?:\\s*->\\s*([^:]+))?:")
	var re_sig := RegEx.create_from_string("^signal\\s+([A-Za-z_][A-Za-z0-9_]*.*)")
	var re_enum := RegEx.create_from_string("^enum\\s+([A-Za-z_][A-Za-z0-9_]*)?")
	var re_const := RegEx.create_from_string("^const\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var re_export := RegEx.create_from_string("^@export[^\\n]*\\s+var\\s+([A-Za-z_][A-Za-z0-9_]*[^:=#]*)")

	for i in lines.size():
		var line := lines[i].strip_edges(false, true)
		var stripped := line.strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		if stripped.begins_with("class_name "):
			out["class_name"] = stripped.substr(11).strip_edges()
		elif stripped.begins_with("extends "):
			out["extends"] = stripped.substr(8).strip_edges()
		elif not line.begins_with("\t") and not line.begins_with(" "):
			var m_sig := re_sig.search(stripped)
			if m_sig:
				out["signals"].append({"line": i + 1, "signature": m_sig.get_string(1).strip_edges()})
				continue
			var m_enum := re_enum.search(stripped)
			if m_enum:
				out["enums"].append({"line": i + 1, "name": m_enum.get_string(1) if m_enum.get_string(1) != "" else "<anonymous>"})
				continue
			var m_const := re_const.search(stripped)
			if m_const:
				out["constants"].append({"line": i + 1, "name": m_const.get_string(1)})
				continue
			var m_exp := re_export.search(stripped)
			if m_exp:
				out["exports"].append({"line": i + 1, "declaration": m_exp.get_string(1).strip_edges()})
				continue
		var m_func := re_func.search(line)
		if m_func:
			out["functions"].append({
				"line": i + 1,
				"name": m_func.get_string(1),
				"args": m_func.get_string(2).strip_edges(),
				"return_type": m_func.get_string(3).strip_edges(),
			})
	return out


func _tool_add_script_member(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("Script not found: " + str(args.get("path", "")))
	var kind := str(args.get("kind", "func")).to_lower()
	var code := str(args.get("code", "")).strip_edges(false, true)
	if code.strip_edges() == "":
		return _host._err("code is empty.")
	var existing := FileAccess.get_file_as_string(path)
	var updated := ""
	if kind == "func":
		updated = existing.rstrip("\n") + "\n\n\n" + code + "\n"
	else:
		var lines := existing.split("\n")
		var insert_at := 0
		for i in lines.size():
			var st := lines[i].strip_edges()
			if st.begins_with("extends ") or st.begins_with("class_name ") or st.begins_with("@tool") or st.begins_with("signal ") or st.begins_with("const "):
				insert_at = i + 1
		lines.insert(insert_at, code)
		updated = "\n".join(lines)
	return _host._write_text(path, updated)


func _tool_rename_symbol_in_project(args: Dictionary) -> Variant:
	var old_name := str(args.get("old_name", "")).strip_edges()
	var new_name := str(args.get("new_name", "")).strip_edges()
	if old_name == "" or new_name == "" or old_name == new_name:
		return _host._err("Provide distinct non-empty old_name and new_name.")
	var dry_run := bool(args.get("dry_run", true))
	var re := RegEx.create_from_string("\\b" + old_name + "\\b")
	var files := []
	_host._walk("res://", true, ["gd"], files, 2000)
	var changed := []
	for f in files:
		if str(f).begins_with("res://addons/local_mcp"):
			continue
		var txt := FileAccess.get_file_as_string(f)
		var hits := re.search_all(txt).size()
		if hits > 0:
			changed.append({"file": f, "occurrences": hits})
			if not dry_run:
				var next := re.sub(txt, new_name, true)
				var wf := FileAccess.open(f, FileAccess.WRITE)
				if wf != null:
					wf.store_string(next)
					wf.close()
	if not dry_run and not changed.is_empty():
		_host._scan()
	return {"old_name": old_name, "new_name": new_name, "dry_run": dry_run, "files_matched": changed.size(), "files": changed}


func _tool_lint_gdscript(args: Dictionary) -> Variant:
	var target: String = _host._res_path(args.get("path", "res://"))
	if target == "": target = "res://"
	var max_len := maxi(40, int(args.get("max_line_length", 120)))
	var files := []
	if target.ends_with(".gd") and FileAccess.file_exists(target):
		files.append(target)
	else:
		_host._walk(target, true, ["gd"], files, 1000)
	var issues := []
	for f in files:
		if str(f).begins_with("res://addons/"):
			continue
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var ln := lines[i]
			if ln.begins_with(" "):
				issues.append({"file": f, "line": i + 1, "issue": "space_indentation"})
			if ln.length() > max_len:
				issues.append({"file": f, "line": i + 1, "issue": "line_too_long", "length": ln.length()})
			if issues.size() >= 200:
				break
		if issues.size() >= 200:
			break
	return {"checked_files": files.size(), "issue_count": issues.size(), "issues": issues}


func _tool_get_class_info(args: Dictionary) -> Variant:
	var cls := str(args.get("class_name", ""))
	if not ClassDB.class_exists(cls):
		for info in ProjectSettings.get_global_class_list():
			if str(info["class"]) == cls:
				return {"class": cls, "script": info["path"], "inherits": str(info["base"]), "hint": "Script class: use read_file on the script, and get_class_info on the base class."}
		return _host._err("Unknown class: " + cls)
	var own := not bool(args.get("include_inherited", false))
	var properties := []
	for p in ClassDB.class_get_property_list(cls, own):
		if p["usage"] & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		properties.append("%s: %s" % [p["name"], _type_name(p)])
	var methods := []
	for m in ClassDB.class_get_method_list(cls, own):
		if str(m["name"]).begins_with("_"):
			continue
		var params := []
		for a in m["args"]:
			params.append("%s: %s" % [a["name"], _type_name(a)])
		methods.append("%s(%s) -> %s" % [m["name"], ", ".join(params), _type_name(m["return"], true)])
	var signals := []
	for sig in ClassDB.class_get_signal_list(cls, own):
		var params := []
		for a in sig["args"]:
			params.append("%s: %s" % [a["name"], _type_name(a)])
		signals.append("%s(%s)" % [sig["name"], ", ".join(params)])
	return {
		"class": cls,
		"inherits": str(ClassDB.get_parent_class(cls)),
		"can_instantiate": ClassDB.can_instantiate(cls),
		"properties": properties,
		"methods": methods,
		"signals": signals,
	}


func _tool_search_classes(args: Dictionary) -> Variant:
	var query := str(args.get("query", "")).to_lower()
	if query == "":
		return _host._err("query is empty.")
	var found := []
	for c in ClassDB.get_class_list():
		if str(c).to_lower().contains(query):
			found.append(str(c))
	for info in ProjectSettings.get_global_class_list():
		if str(info["class"]).to_lower().contains(query):
			found.append("%s (script: %s)" % [info["class"], info["path"]])
	found.sort()
	return {"count": found.size(), "classes": found.slice(0, 200)}


func _tool_search_class_members(args: Dictionary) -> Variant:
	var base := str(args.get("base_class", ""))
	var query := str(args.get("member_query", "")).to_lower()
	var limit := clampi(int(args.get("limit", 60)), 1, 300)

	if base != "" and not ClassDB.class_exists(base):
		return _host._err("Unknown Godot class: " + base)

	if base != "" and query == "":
		var subs := Array(ClassDB.get_inheriters_from_class(base))
		subs.sort()
		return {"base_class": base, "count": subs.size(), "subclasses": subs.slice(0, limit)}

	var classes := Array(ClassDB.get_inheriters_from_class(base)) if base != "" else Array(ClassDB.get_class_list())
	var hits := []
	for cls in classes:
		if hits.size() >= limit: break
		var cname := str(cls)
		var matched_methods := []
		for m in ClassDB.class_get_method_list(cname, true):
			var mn := str(m["name"])
			if query == "" or mn.to_lower().contains(query):
				matched_methods.append(mn)
		if not matched_methods.is_empty():
			hits.append({"class": cname, "methods": matched_methods.slice(0, 10)})
	return {"query": query, "count": hits.size(), "results": hits}
