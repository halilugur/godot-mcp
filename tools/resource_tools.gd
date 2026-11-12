@tool
extends RefCounted
## Resource creation, inspection, duplication, gradients, noise textures, curves, and translations.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("create_resource", "Create a resource file (.tres), e.g. a material, shape, theme, gradient or custom Resource.", {
		"type": {"type": "string", "description": "Resource class, e.g. StandardMaterial3D, RectangleShape2D"},
		"path": {"type": "string", "description": "res:// path ending in .tres"},
		"properties": {"type": "object", "description": "Same value rules as set_node_properties"},
	}, ["type", "path"])
	_reg("get_resource_properties", "Read the properties of a resource file.", {
		"path": {"type": "string", "description": "res:// path"},
		"properties": string_list,
	}, ["path"], true)
	_reg("set_resource_properties", "Change properties of a .tres/.res resource file and save it.", {
		"path": {"type": "string", "description": "res:// path"},
		"properties": {"type": "object"},
	}, ["path", "properties"])
	_reg("duplicate_resource", "Duplicate an existing .tres/.res/.tscn file to a new path and optionally override properties on the copy.", {
		"from": {"type": "string", "description": "Source res:// path"},
		"to": {"type": "string", "description": "Destination res:// path"},
		"properties": {"type": "object", "description": "Optional properties to override (for Resource files)"},
	}, ["from", "to"], false, false)
	_reg("create_gradient", "Create a GradientTexture1D or GradientTexture2D resource (.tres) from color stops.", {
		"path": {"type": "string", "description": "res:// path ending in .tres"},
		"stops": {"type": "array", "items": {"type": "object"}, "description": "Array of {\"offset\": 0.0..1.0, \"color\": \"Color(...)\"}"},
		"is_2d": {"type": "boolean", "description": "Default false (GradientTexture1D)"},
		"width": {"type": "integer", "description": "Default 256"},
		"height": {"type": "integer", "description": "For 2D, default 256"},
	}, ["path", "stops"], false, false)
	_reg("create_noise_texture", "Create a NoiseTexture2D + FastNoiseLite .tres resource (for procedural terrain, clouds, water).", {
		"path": {"type": "string", "description": "res:// path ending in .tres"},
		"width": {"type": "integer", "description": "Default 256"},
		"height": {"type": "integer", "description": "Default 256"},
		"noise_type": {"type": "string", "description": "simplex, perlin, cellular, value. Default simplex."},
		"frequency": {"type": "number", "description": "Default 0.02"},
		"seamless": {"type": "boolean", "description": "Default true"},
		"seed": {"type": "integer", "description": "Default 0"},
	}, ["path"], false, false)
	_reg("create_curve_resource", "Create a Curve .tres resource from [[x, y], ...] control points (for easing, falloff, animations).", {
		"path": {"type": "string", "description": "res:// path ending in .tres"},
		"points": {"type": "array", "items": {"type": "array"}, "description": "List of [x, y] pairs, x in 0..1"},
		"min_value": {"type": "number", "description": "Default 0.0"},
		"max_value": {"type": "number", "description": "Default 1.0"},
	}, ["path", "points"], false, false)
	_reg("list_translations", "List translation resources configured in Project Settings, loaded locales, and keys in CSV translation files.", {}, [], true, false)
	_reg("set_translation_entries", "Create or update a Godot CSV translation file (keys x locales) and optionally register it in Project Settings.", {
		"path": {"type": "string", "description": "res:// path ending in .csv, e.g. res://localization/strings.csv"},
		"entries": {"type": "object", "description": "Map of KEY -> {\"en\": \"...\", \"tr\": \"...\"}"},
		"register": {"type": "boolean", "description": "Reimport and register generated .translation files in ProjectSettings. Default true."},
	}, ["path", "entries"], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


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
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not (path.get_extension().to_lower() in ["tres", "res"]):
		return _host._err("path must be a res:// path ending in .tres")
	if FileAccess.file_exists(path):
		return _host._err("File already exists: %s. Use set_resource_properties to change it." % path)
	var type := str(args.get("type", ""))
	var res: Resource = null
	if ClassDB.class_exists(type):
		var made := Values.make_resource({"type": type, "properties": args.get("properties", {})})
		if not made[0]:
			return _host._err(str(made[1]))
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
							return _host._err("\n".join(errors))
		if res == null:
			return _host._err("'%s' is not a Resource class that can be created." % type)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return _host._err("Could not save: " + error_string(err))
	_host._filesystem_changed(path, true)
	return {"created": path, "type": res.get_class()}


func _tool_get_resource_properties(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _host._err("Resource not found: " + str(args.get("path", "")))
	var res: Variant = load(path)
	if not (res is Resource):
		return _host._err("Could not load " + path)
	return {"path": path, "type": res.get_class(), "properties": _resource_properties(res, args.get("properties"))}


func _tool_set_resource_properties(args: Dictionary) -> Variant:
	var path: Variant = _host._res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _host._err("Resource not found: " + str(args.get("path", "")))
	if not (path.get_extension().to_lower() in ["tres", "res"]):
		return _host._err("Only .tres/.res files can be changed this way. For imported assets, edit their import settings instead.")
	var values: Variant = args.get("properties")
	if not (values is Dictionary) or values.is_empty():
		return _host._err("properties must be a non-empty object.")
	var res: Variant = load(path)
	if not (res is Resource):
		return _host._err("Could not load " + path)
	var errors := Values.apply_properties(res, values)
	if not errors.is_empty():
		return _host._err("\n".join(errors))
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return _host._err("Could not save: " + error_string(err))
	var keys := []
	for k in values:
		keys.append(str(k))
	return {"path": path, "properties": _resource_properties(res, keys)}


func _tool_duplicate_resource(args: Dictionary) -> Variant:
	var src: String = _host._res_path(args.get("from", ""))
	var dst: String = _host._res_path(args.get("to", ""))
	if src == "" or dst == "" or not FileAccess.file_exists(src):
		return _host._err("Invalid source or destination res:// path.")
	var dir := dst.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var props: Variant = args.get("properties", {})
	if props is Dictionary and not props.is_empty() and ResourceLoader.exists(src):
		var res := ResourceLoader.load(src)
		if res != null:
			var dup := res.duplicate(true)
			var errs := Values.apply_properties(dup, props)
			if not errs.is_empty():
				return _host._err("; ".join(errs))
			var serr := ResourceSaver.save(dup, dst)
			if serr != OK:
				return _host._err("Failed to save duplicated resource: " + error_string(serr))
			_host._scan()
			return {"from": src, "to": dst, "modified_properties": props.keys()}

	var bytes := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return _host._err("Cannot write destination: " + dst)
	f.store_buffer(bytes)
	f.close()
	_host._scan()
	return {"from": src, "to": dst, "copied_bytes": bytes.size()}


func _tool_create_gradient(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".tres"):
		return _host._err("path must be a res:// path ending in .tres.")
	var stops: Variant = args.get("stops", [])
	if not (stops is Array) or stops.is_empty():
		return _host._err("stops must be a non-empty array of {offset, color}.")

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for st in stops:
		if not (st is Dictionary):
			return _host._err("Each stop must be {offset, color}.")
		var cc := Values.coerce(st.get("color", "Color(1,1,1,1)"), TYPE_COLOR)
		if not cc[0]:
			return _host._err("color: " + str(cc[1]))
		grad.add_point(float(st.get("offset", 0.0)), cc[1])

	var tex: Resource
	if bool(args.get("is_2d", false)):
		var g2 := GradientTexture2D.new()
		g2.gradient = grad
		g2.width = maxi(1, int(args.get("width", 256)))
		g2.height = maxi(1, int(args.get("height", 256)))
		tex = g2
	else:
		var g1 := GradientTexture1D.new()
		g1.gradient = grad
		g1.width = maxi(1, int(args.get("width", 256)))
		tex = g1

	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(tex, path)
	if err != OK:
		return _host._err("Failed to save gradient: " + error_string(err))
	_host._scan()
	return {"path": path, "type": tex.get_class(), "stops": stops.size()}


func _tool_create_noise_texture(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".tres"):
		return _host._err("path must be a res:// path ending in .tres.")
	var noise := FastNoiseLite.new()
	var types := {"simplex": FastNoiseLite.TYPE_SIMPLEX, "perlin": FastNoiseLite.TYPE_PERLIN, "cellular": FastNoiseLite.TYPE_CELLULAR, "value": FastNoiseLite.TYPE_VALUE}
	noise.noise_type = types.get(str(args.get("noise_type", "simplex")).to_lower(), FastNoiseLite.TYPE_SIMPLEX)
	noise.frequency = float(args.get("frequency", 0.02))
	noise.seed = int(args.get("seed", 0))

	var tex := NoiseTexture2D.new()
	tex.width = maxi(1, int(args.get("width", 256)))
	tex.height = maxi(1, int(args.get("height", 256)))
	tex.seamless = bool(args.get("seamless", true))
	tex.noise = noise
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir): DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(tex, path)
	if err != OK: return _host._err("Failed to save NoiseTexture2D: " + error_string(err))
	_host._scan()
	return {"path": path, "width": tex.width, "height": tex.height}


func _tool_create_curve_resource(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".tres"):
		return _host._err("path must be a res:// path ending in .tres.")
	var pts: Variant = args.get("points", [])
	if not (pts is Array) or pts.is_empty():
		return _host._err("points must be a non-empty array of [x, y].")
	var curve := Curve.new()
	curve.min_value = float(args.get("min_value", 0.0))
	curve.max_value = float(args.get("max_value", 1.0))
	for p in pts:
		if not (p is Array) or p.size() < 2:
			return _host._err("Each point must be [x, y].")
		curve.add_point(Vector2(float(p[0]), float(p[1])))
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir): DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(curve, path)
	if err != OK: return _host._err("Failed to save Curve: " + error_string(err))
	_host._scan()
	return {"path": path, "point_count": curve.point_count}


func _tool_list_translations(_args: Dictionary) -> Variant:
	var configured: Variant = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	var csvs := []
	_host._walk("res://", true, ["csv"], csvs, 200)
	var csv_info := []
	for p in csvs:
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null:
			var header := f.get_csv_line()
			var key_count := 0
			while not f.eof_reached():
				var row := f.get_csv_line()
				if row.size() > 0 and row[0] != "":
					key_count += 1
			csv_info.append({"path": p, "columns": Array(header), "keys": key_count})
	return {
		"configured_translations": Array(configured) if configured is PackedStringArray or configured is Array else [],
		"loaded_locales": Array(TranslationServer.get_loaded_locales()),
		"current_locale": TranslationServer.get_locale(),
		"csv_files": csv_info,
	}


func _tool_set_translation_entries(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".csv"):
		return _host._err("path must be a res:// path ending in .csv.")
	var entries: Variant = args.get("entries", {})
	if not (entries is Dictionary) or entries.is_empty():
		return _host._err("entries must be a non-empty object.")

	var locales := []
	var rows := {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and not f.eof_reached():
			var header := f.get_csv_line()
			for i in range(1, header.size()):
				if header[i] != "":
					locales.append(header[i])
			while not f.eof_reached():
				var r := f.get_csv_line()
				if r.size() > 0 and r[0] != "":
					var map := {}
					for i in range(1, mini(r.size(), header.size())):
						map[header[i]] = r[i]
					rows[r[0]] = map

	for k in entries:
		var key := str(k)
		var val: Variant = entries[k]
		if not (val is Dictionary):
			return _host._err("Each entry must map locale -> translated string.")
		if not rows.has(key):
			rows[key] = {}
		for loc in val:
			var l := str(loc)
			if not (l in locales):
				locales.append(l)
			rows[key][l] = str(val[loc])

	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return _host._err("Cannot write CSV: " + path)
	var header_line := ["keys"] + locales
	out.store_csv_line(PackedStringArray(header_line))
	for key in rows:
		var line := [str(key)]
		for l in locales:
			line.append(str(rows[key].get(l, "")))
		out.store_csv_line(PackedStringArray(line))
	out.close()
	_host._scan()

	var registered := []
	if bool(args.get("register", true)):
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.reimport_files(PackedStringArray([path]))
		var base := path.get_basename()
		var existing: Variant = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
		var list := PackedStringArray(existing) if existing is PackedStringArray or existing is Array else PackedStringArray()
		for l in locales:
			var tr_path := "%s.%s.translation" % [base, l]
			if FileAccess.file_exists(tr_path) and not (tr_path in list):
				list.append(tr_path)
				registered.append(tr_path)
		if not registered.is_empty():
			ProjectSettings.set_setting("internationalization/locale/translations", list)
			ProjectSettings.save()

	return {"path": path, "locales": locales, "total_keys": rows.size(), "registered_translations": registered}
