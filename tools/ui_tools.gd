@tool
extends RefCounted
## UI themes, StyleBoxes, overrides, anchors, containers, and LabelSettings.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("create_stylebox", "Create a StyleBoxFlat and optionally save it to a .tres file and/or apply it as a theme override on a Control node (undoable).", {
		"bg_color": {"type": "string", "description": "Color expression, e.g. \"Color(0.15, 0.15, 0.2, 1)\""},
		"border_color": {"type": "string", "description": "Optional border Color expression"},
		"border_width": {"type": "integer", "description": "Uniform border width in px, default 0"},
		"corner_radius": {"type": "integer", "description": "Uniform corner radius in px, default 0"},
		"content_margin": {"type": "number", "description": "Uniform content margin in px, default -1 (unset)"},
		"shadow_size": {"type": "integer", "description": "Default 0"},
		"save_path": {"type": "string", "description": "Optional res:// path ending in .tres"},
		"node_path": {"type": "string", "description": "Optional Control node to apply add_theme_stylebox_override"},
		"theme_type": {"type": "string", "description": "Stylebox slot name on Control, e.g. panel, normal, hover, pressed. Default panel."},
	}, ["bg_color"], false, false)
	_reg("configure_theme", "Create or update a .tres Theme resource (default_font_size, colors, font_sizes, constants, styleboxes).", {
		"path": {"type": "string", "description": "res:// path ending in .tres"},
		"default_font_size": {"type": "integer"},
		"colors": {"type": "object", "description": "Map of \"ThemeType/name\" (or \"name\" for Control) -> Color expression"},
		"font_sizes": {"type": "object", "description": "Map of \"ThemeType/name\" -> int"},
		"constants": {"type": "object", "description": "Map of \"ThemeType/name\" -> int"},
		"styleboxes": {"type": "object", "description": "Map of \"ThemeType/name\" -> res:// path to a StyleBox .tres"},
	}, ["path"], false, false)
	_reg("set_theme_overrides", "Apply theme overrides (colors, font_sizes, constants, fonts) on a Control node (undoable).", {
		"node_path": node_path,
		"colors": {"type": "object", "description": "e.g. {\"font_color\": \"Color(1, 1, 0)\"}"},
		"font_sizes": {"type": "object", "description": "e.g. {\"font_size\": 24}"},
		"constants": {"type": "object", "description": "e.g. {\"separation\": 12}"},
		"fonts": {"type": "object", "description": "e.g. {\"font\": \"res://fonts/main.ttf\"}"},
	}, ["node_path"], false, false)
	_reg("set_ui_anchors_preset", "Apply a layout anchor preset to a Control node (undoable): full_rect, center, top_left, top_right, bottom_left, bottom_right, center_left, center_right, center_top, center_bottom, top_wide, bottom_wide, left_wide, right_wide, hcenter_wide, vcenter_wide.", {
		"node_path": node_path,
		"preset": s,
		"keep_offsets": {"type": "boolean", "description": "Default false"},
	}, ["node_path", "preset"], false, false)
	_reg("setup_ui_container", "Create and configure a UI Container (VBoxContainer, HBoxContainer, GridContainer, MarginContainer, PanelContainer, ScrollContainer, TabContainer) (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"type": {"type": "string", "description": "Container class name, default VBoxContainer"},
		"name": s,
		"columns": {"type": "integer", "description": "For GridContainer"},
		"separation": {"type": "integer", "description": "Theme constant separation for Box/Grid containers"},
		"margin": {"type": "integer", "description": "Uniform margin for MarginContainer"},
		"full_rect": {"type": "boolean", "description": "Apply PRESET_FULL_RECT anchors. Default false."},
	}, [], false, false)
	_reg("setup_label_settings", "Create a LabelSettings resource (font, font_size, color, outline, shadow) and apply it to a Label or save as .tres.", {
		"node_path": {"type": "string", "description": "Optional Label node path"},
		"save_path": {"type": "string", "description": "Optional res:// path ending in .tres"},
		"font_path": {"type": "string", "description": "Optional res:// font path"},
		"font_size": {"type": "integer", "description": "Default 16"},
		"font_color": {"type": "string", "description": "Color expression"},
		"outline_size": {"type": "integer", "description": "Default 0"},
		"outline_color": {"type": "string", "description": "Color expression"},
		"shadow_size": {"type": "integer", "description": "Default 0"},
		"shadow_color": {"type": "string", "description": "Color expression"},
	}, [], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _split_theme_key(key: String) -> Array:
	if key.contains("/"):
		var idx := key.find("/")
		return [StringName(key.substr(0, idx)), StringName(key.substr(idx + 1))]
	return [&"Control", StringName(key)]


func _tool_create_stylebox(args: Dictionary) -> Variant:
	var sb := StyleBoxFlat.new()
	var bg := Values.coerce(args.get("bg_color", "Color(0.2, 0.2, 0.25, 1)"), TYPE_COLOR)
	if not bg[0]:
		return _host._err("bg_color: " + str(bg[1]))
	sb.bg_color = bg[1]

	if args.has("border_color"):
		var bc := Values.coerce(args["border_color"], TYPE_COLOR)
		if not bc[0]:
			return _host._err("border_color: " + str(bc[1]))
		sb.border_color = bc[1]
	var bw := int(_host._to_int(args.get("border_width"), 0))
	if bw > 0:
		sb.set_border_width_all(bw)
	var cr := int(_host._to_int(args.get("corner_radius"), 0))
	if cr > 0:
		sb.set_corner_radius_all(cr)
	var cm := float(args.get("content_margin", -1.0))
	if cm >= 0.0:
		sb.set_content_margin_all(cm)
	sb.shadow_size = int(_host._to_int(args.get("shadow_size"), 0))

	var saved_path := ""
	if args.has("save_path") and str(args["save_path"]) != "":
		var sp: String = _host._res_path(args["save_path"])
		if sp == "" or not sp.ends_with(".tres"):
			return _host._err("save_path must end in .tres.")
		var dir := sp.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		var err := ResourceSaver.save(sb, sp)
		if err != OK:
			return _host._err("Failed to save StyleBoxFlat: " + error_string(err))
		_host._scan()
		saved_path = sp
		sb = load(sp) as StyleBoxFlat

	var applied_to := ""
	if args.has("node_path") and str(args["node_path"]) != "":
		var node: Node = _host._find(args["node_path"])
		if node == null:
			return _host._no_node(args["node_path"])
		if not (node is Control):
			return _host._err("%s is %s, not a Control." % [_host._path_of(node), node.get_class()])
		var slot := StringName(str(args.get("theme_type", "panel")))
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Apply StyleBoxFlat to %s" % node.name)
		ur.add_do_method(node, "add_theme_stylebox_override", slot, sb)
		ur.commit_action()
		applied_to = _host._path_of(node)

	return {"saved_path": saved_path, "applied_to": applied_to}


func _tool_configure_theme(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".tres"):
		return _host._err("path must be a res:// path ending in .tres.")
	var theme: Theme = load(path) as Theme if ResourceLoader.exists(path) else Theme.new()
	if theme == null:
		return _host._err("Existing resource is not a Theme: " + path)

	if args.has("default_font_size"):
		theme.default_font_size = int(args["default_font_size"])

	var colors: Variant = args.get("colors", {})
	if colors is Dictionary:
		for k in colors:
			var parts := _split_theme_key(str(k))
			var c := Values.coerce(colors[k], TYPE_COLOR)
			if not c[0]:
				return _host._err("color %s: %s" % [k, c[1]])
			theme.set_color(parts[1], parts[0], c[1])

	var fsizes: Variant = args.get("font_sizes", {})
	if fsizes is Dictionary:
		for k in fsizes:
			var parts := _split_theme_key(str(k))
			theme.set_font_size(parts[1], parts[0], int(fsizes[k]))

	var constants: Variant = args.get("constants", {})
	if constants is Dictionary:
		for k in constants:
			var parts := _split_theme_key(str(k))
			theme.set_constant(parts[1], parts[0], int(constants[k]))

	var sboxes: Variant = args.get("styleboxes", {})
	if sboxes is Dictionary:
		for k in sboxes:
			var parts := _split_theme_key(str(k))
			var sp: String = _host._res_path(sboxes[k])
			if sp == "" or not ResourceLoader.exists(sp):
				return _host._err("StyleBox not found: " + str(sboxes[k]))
			var sb := load(sp) as StyleBox
			if sb == null:
				return _host._err("Not a StyleBox: " + sp)
			theme.set_stylebox(parts[1], parts[0], sb)

	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(theme, path)
	if err != OK:
		return _host._err("Failed to save Theme: " + error_string(err))
	_host._scan()
	return {"path": path, "saved": true, "type_list": Array(theme.get_type_list())}


func _tool_set_theme_overrides(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not (node is Control):
		return _host._err("%s is %s, not a Control." % [_host._path_of(node), node.get_class()])
	var ctrl := node as Control
	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set theme overrides on %s" % ctrl.name)
	var count := 0

	var colors: Variant = args.get("colors", {})
	if colors is Dictionary:
		for k in colors:
			var c := Values.coerce(colors[k], TYPE_COLOR)
			if not c[0]:
				return _host._err("color %s: %s" % [k, c[1]])
			ur.add_do_method(ctrl, "add_theme_color_override", StringName(str(k)), c[1])
			count += 1

	var font_sizes: Variant = args.get("font_sizes", {})
	if font_sizes is Dictionary:
		for k in font_sizes:
			ur.add_do_method(ctrl, "add_theme_font_size_override", StringName(str(k)), int(font_sizes[k]))
			count += 1

	var constants: Variant = args.get("constants", {})
	if constants is Dictionary:
		for k in constants:
			ur.add_do_method(ctrl, "add_theme_constant_override", StringName(str(k)), int(constants[k]))
			count += 1

	var fonts: Variant = args.get("fonts", {})
	if fonts is Dictionary:
		for k in fonts:
			var fp: String = _host._res_path(fonts[k])
			if fp == "" or not ResourceLoader.exists(fp):
				return _host._err("Font not found: " + str(fonts[k]))
			ur.add_do_method(ctrl, "add_theme_font_override", StringName(str(k)), load(fp))
			count += 1

	if count == 0:
		return _host._err("No overrides provided.")
	ur.commit_action()
	return {"path": _host._path_of(ctrl), "applied": count}


func _tool_set_ui_anchors_preset(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not (node is Control):
		return _host._err("%s is %s, not a Control." % [_host._path_of(node), node.get_class()])
	var presets := {
		"top_left": Control.PRESET_TOP_LEFT,
		"top_right": Control.PRESET_TOP_RIGHT,
		"bottom_left": Control.PRESET_BOTTOM_LEFT,
		"bottom_right": Control.PRESET_BOTTOM_RIGHT,
		"center_left": Control.PRESET_CENTER_LEFT,
		"center_top": Control.PRESET_CENTER_TOP,
		"center_right": Control.PRESET_CENTER_RIGHT,
		"center_bottom": Control.PRESET_CENTER_BOTTOM,
		"center": Control.PRESET_CENTER,
		"left_wide": Control.PRESET_LEFT_WIDE,
		"top_wide": Control.PRESET_TOP_WIDE,
		"right_wide": Control.PRESET_RIGHT_WIDE,
		"bottom_wide": Control.PRESET_BOTTOM_WIDE,
		"vcenter_wide": Control.PRESET_VCENTER_WIDE,
		"hcenter_wide": Control.PRESET_HCENTER_WIDE,
		"full_rect": Control.PRESET_FULL_RECT,
	}
	var key := str(args.get("preset", "")).to_lower()
	if not presets.has(key):
		return _host._err("Unknown preset '%s'. Valid: %s" % [key, ", ".join(presets.keys())])
	var keep := bool(args.get("keep_offsets", false))
	var mode := Control.PRESET_MODE_KEEP_SIZE if keep else Control.PRESET_MODE_MINSIZE

	var ctrl := node as Control
	var old_state := [ctrl.anchor_left, ctrl.anchor_top, ctrl.anchor_right, ctrl.anchor_bottom,
		ctrl.offset_left, ctrl.offset_top, ctrl.offset_right, ctrl.offset_bottom]
	ctrl.set_anchors_and_offsets_preset(presets[key], mode)
	var new_state := [ctrl.anchor_left, ctrl.anchor_top, ctrl.anchor_right, ctrl.anchor_bottom,
		ctrl.offset_left, ctrl.offset_top, ctrl.offset_right, ctrl.offset_bottom]

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set anchors preset %s on %s" % [key, ctrl.name])
	var props := ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom"]
	for i in props.size():
		ur.add_do_property(ctrl, props[i], new_state[i])
		ur.add_undo_property(ctrl, props[i], old_state[i])
	ur.commit_action()
	return {"path": _host._path_of(ctrl), "preset": key}


func _tool_setup_ui_container(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var ctype := str(args.get("type", "VBoxContainer"))
	if not ClassDB.class_exists(ctype) or not ClassDB.is_parent_class(ctype, "Container"):
		return _host._err("Invalid Container class: " + ctype)
	var c: Container = ClassDB.instantiate(ctype)
	c.name = str(args.get("name", ctype))
	if args.has("columns") and c is GridContainer:
		(c as GridContainer).columns = maxi(1, int(args["columns"]))
	if args.has("separation"):
		c.add_theme_constant_override(&"separation", int(args["separation"]))
	if args.has("margin") and c is MarginContainer:
		var m := int(args["margin"])
		for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
			c.add_theme_constant_override(side, m)
	if bool(args.get("full_rect", false)):
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host._host._add_child_undo(parent, c, "MCP: Add %s" % ctype)
	return {"path": _host._path_of(c), "type": ctype}


func _tool_setup_label_settings(args: Dictionary) -> Variant:
	var ls := LabelSettings.new()
	ls.font_size = int(args.get("font_size", 16))
	ls.outline_size = int(args.get("outline_size", 0))
	ls.shadow_size = int(args.get("shadow_size", 0))
	if args.has("font_path") and str(args["font_path"]) != "":
		var fp: String = _host._res_path(args["font_path"])
		if fp == "" or not ResourceLoader.exists(fp):
			return _host._err("Font not found: " + str(args["font_path"]))
		ls.font = load(fp) as Font
	for cprop in ["font_color", "outline_color", "shadow_color"]:
		if args.has(cprop):
			var cc := Values.coerce(args[cprop], TYPE_COLOR)
			if not cc[0]: return _host._err("%s: %s" % [cprop, cc[1]])
			ls.set(cprop, cc[1])

	var saved := ""
	if args.has("save_path") and str(args["save_path"]) != "":
		var sp: String = _host._res_path(args["save_path"])
		if sp == "" or not sp.ends_with(".tres"):
			return _host._err("save_path must end in .tres.")
		ResourceSaver.save(ls, sp)
		_host._scan()
		saved = sp
		ls = load(sp) as LabelSettings

	var applied := ""
	if args.has("node_path") and str(args["node_path"]) != "":
		var node: Node = _host._find(args["node_path"])
		if node == null: return _host._no_node(args["node_path"])
		if not (node is Label):
			return _host._err("%s is %s, not a Label." % [_host._path_of(node), node.get_class()])
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Set LabelSettings on %s" % node.name)
		ur.add_do_property(node, "label_settings", ls)
		ur.add_undo_property(node, "label_settings", node.get("label_settings"))
		ur.commit_action()
		applied = _host._path_of(node)
	return {"saved_path": saved, "applied_to": applied}
