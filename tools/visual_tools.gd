@tool
extends RefCounted
## Shaders, lighting, cameras, world environment, particles, sprite frames, parallax, and viewports.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("create_shader", "Create a .gdshader file (canvas_item, spatial, particles, sky, or fog) and optionally assign it to a node via ShaderMaterial.", {
		"path": {"type": "string", "description": "res:// path ending in .gdshader"},
		"shader_type": {"type": "string", "description": "canvas_item, spatial, particles, sky, or fog. Default canvas_item."},
		"code": {"type": "string", "description": "Optional full .gdshader source. If omitted, a clean starter template is generated."},
		"attach_to": {"type": "string", "description": "Optional node path to assign a new ShaderMaterial using this shader"},
	}, ["path"], false, false)
	_reg("get_shader_params", "Read all shader uniform parameters and current values from a node's ShaderMaterial or a .tres/.res ShaderMaterial file.", {
		"node_path": {"type": "string", "description": "Node with material / material_override"},
		"resource_path": {"type": "string", "description": "Or res:// path to a ShaderMaterial resource"},
	}, [], true, false)
	_reg("set_shader_params", "Set shader uniform parameters on a node's ShaderMaterial (undoable) or a .tres/.res ShaderMaterial file.", {
		"node_path": {"type": "string", "description": "Node with material / material_override"},
		"resource_path": {"type": "string", "description": "Or res:// path to a ShaderMaterial resource"},
		"params": {"type": "object", "description": "Map of uniform name -> value (JSON or Godot expression like \"Color(1,0,0,1)\", \"res://tex.png\")"},
	}, ["params"], false, false)
	_reg("setup_world_environment", "Create or update a WorldEnvironment (+ Environment + optional ProceduralSkyMaterial & DirectionalLight3D) in the edited scene.", {
		"node_path": {"type": "string", "description": "Existing WorldEnvironment path, or '.' to find/create one under root"},
		"preset": {"type": "string", "description": "Optional preset: sky_3d, dark_3d, canvas_glow"},
		"properties": {"type": "object", "description": "Environment properties (e.g. glow_enabled, fog_enabled, background_mode, tonemap_mode, ssao_enabled)"},
		"add_sun": {"type": "boolean", "description": "For 3D sky preset, also add a DirectionalLight3D if missing. Default false."},
	}, [], false, false)
	_reg("create_particle_system", "Create and configure a GPUParticles2D or GPUParticles3D with a ParticleProcessMaterial (undoable).", {
		"parent_path": {"type": "string", "description": "Parent node path, default '.'"},
		"name": {"type": "string", "description": "Default Particles"},
		"is_3d": {"type": "boolean", "description": "Default false (2D)"},
		"amount": {"type": "integer", "description": "Default 32"},
		"lifetime": {"type": "number", "description": "Default 1.0"},
		"one_shot": {"type": "boolean", "description": "Default false"},
		"explosiveness": {"type": "number", "description": "Default 0.0"},
		"process_properties": {"type": "object", "description": "ParticleProcessMaterial properties (gravity, initial_velocity_min, initial_velocity_max, spread, direction, color, scale_min, scale_max, emission_shape)"},
		"texture": {"type": "string", "description": "Optional res:// texture path (2D)"},
	}, [], false, false)
	_reg("get_sprite_frames", "List animations, FPS, loop flags, and frame counts on an AnimatedSprite2D or AnimatedSprite3D.", {
		"node_path": node_path,
	}, ["node_path"], true, false)
	_reg("set_sprite_frames", "Create or update an animation in an AnimatedSprite2D/3D's SpriteFrames. Supports either 'textures' (list of res:// paths) or sprite-sheet slicing via 'sheet_path', 'hframes', 'vframes', and optional 'frames' (0-based indices).", {
		"node_path": node_path,
		"animation": {"type": "string", "description": "Animation name, e.g. walk, idle"},
		"fps": {"type": "number", "description": "Default 10.0"},
		"loop": {"type": "boolean", "description": "Default true"},
		"textures": {"type": "array", "items": s, "description": "List of res:// texture paths"},
		"sheet_path": {"type": "string", "description": "Sprite sheet res:// path"},
		"hframes": {"type": "integer", "description": "Columns in sprite sheet"},
		"vframes": {"type": "integer", "description": "Rows in sprite sheet"},
		"frames": {"type": "array", "items": {"type": "integer"}, "description": "0-based frame indices from the sheet (default: all frames)"},
		"set_current": {"type": "boolean", "description": "Play/select this animation on the node. Default true."},
	}, ["node_path", "animation"], false, false)
	_reg("setup_camera", "Create or configure a Camera2D or Camera3D (position, zoom/fov, look_at, current) (undoable).", {
		"parent_path": {"type": "string", "description": "Parent node path if creating, or existing Camera node path. Default '.'"},
		"name": {"type": "string", "description": "Default Camera2D / Camera3D"},
		"is_3d": {"type": "boolean", "description": "Default false (2D)"},
		"position": {"type": "string", "description": "Vector2 or Vector3 expression"},
		"look_at": {"type": "string", "description": "3D target Vector3 expression"},
		"zoom": {"type": "string", "description": "2D zoom Vector2 expression, e.g. \"Vector2(2, 2)\""},
		"fov": {"type": "number", "description": "3D field of view in degrees, default 75"},
		"current": {"type": "boolean", "description": "Make current camera, default true"},
	}, [], false, false)
	_reg("setup_light", "Create or configure a DirectionalLight3D, OmniLight3D, SpotLight3D, or PointLight2D (undoable).", {
		"parent_path": {"type": "string", "description": "Parent node path, default '.'"},
		"type": {"type": "string", "description": "DirectionalLight3D, OmniLight3D, SpotLight3D, or PointLight2D. Default DirectionalLight3D."},
		"name": s,
		"position": {"type": "string", "description": "Vector2 or Vector3 expression"},
		"look_at": {"type": "string", "description": "3D target Vector3 expression"},
		"color": {"type": "string", "description": "Color expression"},
		"energy": {"type": "number", "description": "Default 1.0"},
		"range": {"type": "number", "description": "Omni/Spot light range"},
		"shadow_enabled": {"type": "boolean", "description": "Default true"},
	}, [], false, false)
	_reg("setup_2d_vector_node", "Create or update a Line2D, Polygon2D, CollisionPolygon2D, or LightOccluder2D with a 2D point array (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"type": {"type": "string", "description": "Line2D, Polygon2D, CollisionPolygon2D, or LightOccluder2D. Default Line2D."},
		"name": s,
		"points": {"type": "array", "items": {"type": "string"}, "description": "Array of Vector2 expressions"},
		"color": {"type": "string", "description": "Color expression for Line2D/Polygon2D"},
		"width": {"type": "number", "description": "Line2D width, default 4.0"},
		"closed": {"type": "boolean", "description": "Line2D/Occluder closed loop, default false"},
	}, ["points"], false, false)
	_reg("setup_3d_fx_node", "Create a 3D environmental FX node: Decal, ReflectionProbe, or FogVolume (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"type": {"type": "string", "description": "Decal, ReflectionProbe, or FogVolume"},
		"name": s,
		"position": {"type": "string", "description": "Vector3 expression"},
		"size": {"type": "string", "description": "Vector3 size/extents expression"},
		"properties": {"type": "object", "description": "Additional properties (e.g. texture_albedo, density, albedo)"},
	}, ["type"], false, false)
	_reg("setup_parallax", "Create and configure a Parallax2D node (scroll_scale, repeat_size, autoscroll) with an optional Sprite2D texture (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"name": {"type": "string", "description": "Default Parallax2D"},
		"scroll_scale": {"type": "string", "description": "Vector2 expression, e.g. \"Vector2(0.5, 0.5)\""},
		"repeat_size": {"type": "string", "description": "Vector2 expression, e.g. \"Vector2(1280, 0)\""},
		"autoscroll": {"type": "string", "description": "Vector2 expression"},
		"texture": {"type": "string", "description": "Optional res:// texture to add as a child Sprite2D"},
	}, [], false, false)
	_reg("setup_subviewport", "Create a SubViewportContainer + SubViewport pair for minimaps, 3D-in-2D, or offscreen rendering (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"name": {"type": "string", "description": "Default SubViewportContainer"},
		"width": {"type": "integer", "description": "Default 256"},
		"height": {"type": "integer", "description": "Default 256"},
		"transparent_bg": {"type": "boolean", "description": "Default true"},
	}, [], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _resolve_shader_material(args: Dictionary) -> Array:
	if args.has("resource_path") and str(args["resource_path"]) != "":
		var rp: String = _host._res_path(args["resource_path"])
		if rp == "" or not ResourceLoader.exists(rp):
			return [null, null, "", _host._err("Resource not found: " + str(args["resource_path"]))]
		var res := load(rp)
		if not (res is ShaderMaterial):
			return [null, null, "", _host._err("Resource is %s, not a ShaderMaterial." % res.get_class())]
		return [res, null, rp, null]
	if args.has("node_path") and str(args["node_path"]) != "":
		var node: Node = _host._find(args["node_path"])
		if node == null:
			return [null, null, "", _host._no_node(args["node_path"])]
		var mat: Variant = node.get("material_override") if node is GeometryInstance3D else node.get("material")
		if mat == null and node is GeometryInstance3D:
			mat = node.get("material_overlay")
		if not (mat is ShaderMaterial):
			return [null, null, "", _host._err("%s does not have a ShaderMaterial assigned." % _host._path_of(node))]
		return [mat, node, "", null]
	return [null, null, "", _host._err("Provide node_path or resource_path.")]


func _tool_create_shader(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".gdshader"):
		return _host._err("path must be a res:// path ending in .gdshader.")
	var stype := str(args.get("shader_type", "canvas_item"))
	var code := str(args.get("code", ""))
	if code.strip_edges() == "":
		match stype:
			"spatial":
				code = "shader_type spatial;\n\nuniform vec4 albedo_color : source_color = vec4(1.0);\n\nvoid fragment() {\n\tALBEDO = albedo_color.rgb;\n}\n"
			"particles":
				code = "shader_type particles;\n\nvoid start() {\n}\n\nvoid process() {\n}\n"
			"sky":
				code = "shader_type sky;\n\nvoid sky() {\n\tCOLOR = vec3(0.1, 0.2, 0.4);\n}\n"
			"fog":
				code = "shader_type fog;\n\nvoid fog() {\n\tALBEDO = vec3(0.5);\n\tDENSITY = 0.1;\n}\n"
			_:
				code = "shader_type canvas_item;\n\nuniform vec4 tint_color : source_color = vec4(1.0);\n\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, UV) * tint_color;\n}\n"

	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _host._err("Cannot write shader file: " + path)
	f.store_string(code)
	f.close()
	_host._scan()

	var shader := load(path) as Shader
	var attached := ""
	if args.has("attach_to") and str(args["attach_to"]) != "":
		var node: Node = _host._find(args["attach_to"])
		if node == null:
			return _host._no_node(args["attach_to"])
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var prop := "material_override" if node is GeometryInstance3D else "material"
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Attach shader to %s" % node.name)
		ur.add_do_property(node, prop, mat)
		ur.add_undo_property(node, prop, node.get(prop))
		ur.commit_action()
		attached = _host._path_of(node)

	var uniforms := []
	if shader != null:
		for u in shader.get_shader_uniform_list():
			uniforms.append({"name": str(u["name"]), "type": type_string(int(u["type"]))})
	return {"path": path, "shader_type": stype, "attached_to": attached, "uniforms": uniforms}


func _tool_get_shader_params(args: Dictionary) -> Variant:
	var r := _resolve_shader_material(args)
	if r[3] != null:
		return r[3]
	var mat: ShaderMaterial = r[0]
	if mat.shader == null:
		return _host._err("ShaderMaterial has no shader assigned.")
	var params := {}
	for u in mat.shader.get_shader_uniform_list():
		var uname := str(u["name"])
		params[uname] = {
			"type": type_string(int(u["type"])),
			"value": Values.to_json(mat.get_shader_parameter(uname)),
		}
	return {"shader": mat.shader.resource_path, "params": params}


func _tool_set_shader_params(args: Dictionary) -> Variant:
	var r := _resolve_shader_material(args)
	if r[3] != null:
		return r[3]
	var mat: ShaderMaterial = r[0]
	var node: Variant = r[1]
	var res_path: String = r[2]
	if mat.shader == null:
		return _host._err("ShaderMaterial has no shader assigned.")
	var wanted: Variant = args.get("params", {})
	if not (wanted is Dictionary) or wanted.is_empty():
		return _host._err("params must be a non-empty object.")

	var uniform_types := {}
	for u in mat.shader.get_shader_uniform_list():
		uniform_types[str(u["name"])] = int(u["type"])

	var changes := []
	var errors := []
	for k in wanted:
		var uname := str(k)
		if not uniform_types.has(uname):
			errors.append("Unknown shader uniform: " + uname)
			continue
		var coerced := Values.coerce(wanted[k], uniform_types[uname])
		if not coerced[0]:
			errors.append("%s: %s" % [uname, coerced[1]])
			continue
		changes.append([uname, coerced[1], mat.get_shader_parameter(uname)])

	if not errors.is_empty():
		return _host._err("; ".join(errors))

	if node != null:
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Set shader params on %s" % node.name)
		for ch in changes:
			ur.add_do_method(mat, "set_shader_parameter", ch[0], ch[1])
			ur.add_undo_method(mat, "set_shader_parameter", ch[0], ch[2])
		ur.commit_action()
	else:
		for ch in changes:
			mat.set_shader_parameter(ch[0], ch[1])
		ResourceSaver.save(mat, res_path)
	return {"updated": changes.size(), "shader": mat.shader.resource_path}


func _tool_setup_world_environment(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var we: WorldEnvironment = null
	if args.has("node_path") and str(args["node_path"]) != "" and str(args["node_path"]) != ".":
		var found: Node = _host._find(args["node_path"])
		if found == null:
			return _host._no_node(args["node_path"])
		if not (found is WorldEnvironment):
			return _host._err("%s is not a WorldEnvironment." % _host._path_of(found))
		we = found
	else:
		for c in root.get_children():
			if c is WorldEnvironment:
				we = c
				break

	var created := false
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		created = true

	var env: Environment = we.environment if we.environment != null else Environment.new()
	var preset := str(args.get("preset", "")).to_lower()
	match preset:
		"sky_3d":
			var sky := Sky.new()
			sky.sky_material = ProceduralSkyMaterial.new()
			env.background_mode = Environment.BG_SKY
			env.sky = sky
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
			env.glow_enabled = true
		"dark_3d":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.03, 0.03, 0.05)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.15, 0.17, 0.25)
			env.glow_enabled = true
		"canvas_glow":
			env.background_mode = Environment.BG_CANVAS
			env.glow_enabled = true
			env.glow_intensity = 0.8
			env.glow_bloom = 0.2

	var props: Variant = args.get("properties", {})
	if props is Dictionary and not props.is_empty():
		var errs := Values.apply_properties(env, props)
		if not errs.is_empty():
			if created:
				we.free()
			return _host._err("; ".join(errs))

	we.environment = env
	if created:
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Add WorldEnvironment")
		ur.add_do_method(root, "add_child", we, true)
		ur.add_do_property(we, "owner", root)
		ur.add_do_reference(we)
		ur.add_undo_method(root, "remove_child", we)
		ur.commit_action()

	var sun_added := false
	if bool(args.get("add_sun", false)):
		var has_sun := false
		for c in root.get_children():
			if c is DirectionalLight3D:
				has_sun = true
				break
		if not has_sun:
			var sun := DirectionalLight3D.new()
			sun.name = "DirectionalLight3D"
			sun.rotation_degrees = Vector3(-45, 30, 0)
			sun.shadow_enabled = true
			var ur2: EditorUndoRedoManager = _host._plugin.get_undo_redo()
			ur2.create_action("MCP: Add DirectionalLight3D")
			ur2.add_do_method(root, "add_child", sun, true)
			ur2.add_do_property(sun, "owner", root)
			ur2.add_do_reference(sun)
			ur2.add_undo_method(root, "remove_child", sun)
			ur2.commit_action()
			sun_added = true

	return {"path": _host._path_of(we), "created": created, "preset": preset, "sun_added": sun_added}


func _tool_create_particle_system(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null:
		return _host._no_node(args.get("parent_path", "."))

	var is_3d := bool(args.get("is_3d", false))
	var p: Node = GPUParticles3D.new() if is_3d else GPUParticles2D.new()
	p.name = str(args.get("name", "Particles"))
	p.set("amount", maxi(1, int(_host._to_int(args.get("amount"), 32))))
	p.set("lifetime", maxf(0.01, float(args.get("lifetime", 1.0))))
	p.set("one_shot", bool(args.get("one_shot", false)))
	p.set("explosiveness", clampf(float(args.get("explosiveness", 0.0)), 0.0, 1.0))

	var mat := ParticleProcessMaterial.new()
	var proc_props: Variant = args.get("process_properties", {})
	if proc_props is Dictionary and not proc_props.is_empty():
		var errs := Values.apply_properties(mat, proc_props)
		if not errs.is_empty():
			p.free()
			return _host._err("; ".join(errs))
	p.set("process_material", mat)

	if not is_3d and args.has("texture") and str(args["texture"]) != "":
		var tp: String = _host._res_path(args["texture"])
		if tp == "" or not ResourceLoader.exists(tp):
			p.free()
			return _host._err("Texture not found: " + str(args["texture"]))
		p.set("texture", load(tp))

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Create %s" % p.get_class())
	ur.add_do_method(parent, "add_child", p, true)
	ur.add_do_property(p, "owner", root)
	ur.add_do_reference(p)
	ur.add_undo_method(parent, "remove_child", p)
	ur.commit_action()
	return {"path": _host._path_of(p), "type": p.get_class(), "amount": p.get("amount")}


func _tool_get_sprite_frames(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not (node is AnimatedSprite2D or node is AnimatedSprite3D):
		return _host._err("%s is %s, expected AnimatedSprite2D or AnimatedSprite3D." % [_host._path_of(node), node.get_class()])
	var sf: SpriteFrames = node.get("sprite_frames")
	if sf == null:
		return {"path": _host._path_of(node), "animations": []}
	var anims := []
	for anim_name in sf.get_animation_names():
		anims.append({
			"name": str(anim_name),
			"fps": sf.get_animation_speed(anim_name),
			"loop": sf.get_animation_loop(anim_name),
			"frame_count": sf.get_frame_count(anim_name),
		})
	return {"path": _host._path_of(node), "current": str(node.get("animation")), "animations": anims}


func _tool_set_sprite_frames(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not (node is AnimatedSprite2D or node is AnimatedSprite3D):
		return _host._err("%s is %s, expected AnimatedSprite2D or AnimatedSprite3D." % [_host._path_of(node), node.get_class()])

	var anim_name := StringName(str(args.get("animation", "")))
	if anim_name == &"":
		return _host._err("animation name is required.")

	var frame_textures := []
	if args.has("sheet_path") and str(args["sheet_path"]) != "":
		var sp: String = _host._res_path(args["sheet_path"])
		if sp == "" or not ResourceLoader.exists(sp):
			return _host._err("Sprite sheet not found: " + str(args["sheet_path"]))
		var sheet := load(sp) as Texture2D
		if sheet == null:
			return _host._err("Not a Texture2D: " + sp)
		var hf := maxi(1, int(_host._to_int(args.get("hframes"), 1)))
		var vf := maxi(1, int(_host._to_int(args.get("vframes"), 1)))
		var cell_w := sheet.get_width() / float(hf)
		var cell_h := sheet.get_height() / float(vf)
		var indices := []
		var raw_frames: Variant = args.get("frames", [])
		if raw_frames is Array and not raw_frames.is_empty():
			for f_idx in raw_frames:
				indices.append(int(f_idx))
		else:
			for i in range(hf * vf):
				indices.append(i)
		for idx in indices:
			if idx < 0 or idx >= hf * vf:
				return _host._err("Frame index %d out of range 0..%d." % [idx, hf * vf - 1])
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			var col: int = int(idx) % hf
			var row: int = int(idx) / hf
			atlas.region = Rect2(col * cell_w, row * cell_h, cell_w, cell_h)
			frame_textures.append(atlas)
	elif args.has("textures") and args["textures"] is Array:
		for t in args["textures"]:
			var tp: String = _host._res_path(t)
			if tp == "" or not ResourceLoader.exists(tp):
				return _host._err("Texture not found: " + str(t))
			var tex := load(tp) as Texture2D
			if tex == null:
				return _host._err("Not a Texture2D: " + tp)
			frame_textures.append(tex)
	else:
		return _host._err("Provide either 'textures' or 'sheet_path'.")

	var old_sf: SpriteFrames = node.get("sprite_frames")
	var new_sf: SpriteFrames = old_sf.duplicate() if old_sf != null else SpriteFrames.new()
	if not new_sf.has_animation(anim_name):
		new_sf.add_animation(anim_name)
	else:
		new_sf.clear(anim_name)
	new_sf.set_animation_speed(anim_name, float(args.get("fps", 10.0)))
	new_sf.set_animation_loop(anim_name, bool(args.get("loop", true)))
	for tex in frame_textures:
		new_sf.add_frame(anim_name, tex)

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set SpriteFrames '%s' on %s" % [anim_name, node.name])
	ur.add_do_property(node, "sprite_frames", new_sf)
	ur.add_undo_property(node, "sprite_frames", old_sf)
	if bool(args.get("set_current", true)):
		ur.add_do_property(node, "animation", anim_name)
		ur.add_undo_property(node, "animation", node.get("animation"))
	ur.commit_action()
	return {"path": _host._path_of(node), "animation": str(anim_name), "frames": frame_textures.size()}


func _tool_setup_camera(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var target: Node = _host._find(args.get("parent_path", "."))
	if target == null:
		return _host._no_node(args.get("parent_path", "."))

	var is_3d := bool(args.get("is_3d", false))
	var cam: Node = target if (target is Camera2D or target is Camera3D) else null
	var created := false
	if cam == null:
		cam = Camera3D.new() if is_3d else Camera2D.new()
		cam.name = str(args.get("name", "Camera3D" if is_3d else "Camera2D"))
		created = true
	else:
		is_3d = cam is Camera3D

	if args.has("position"):
		var c := Values.coerce(args["position"], TYPE_VECTOR3 if is_3d else TYPE_VECTOR2)
		if not c[0]:
			if created: cam.free()
			return _host._err("position: " + str(c[1]))
		cam.set("position", c[1])
	if is_3d and args.has("fov"):
		cam.set("fov", float(args["fov"]))
	if not is_3d and args.has("zoom"):
		var cz := Values.coerce(args["zoom"], TYPE_VECTOR2)
		if not cz[0]:
			if created: cam.free()
			return _host._err("zoom: " + str(cz[1]))
		cam.set("zoom", cz[1])
	if args.has("current"):
		cam.set("current" if is_3d else "enabled", bool(args["current"]))
	elif created:
		cam.set("current" if is_3d else "enabled", true)

	if created:
		_host._add_child_undo(target, cam, "MCP: Add %s" % cam.get_class())
	if is_3d and args.has("look_at"):
		var cl := Values.coerce(args["look_at"], TYPE_VECTOR3)
		if cl[0]:
			(cam as Camera3D).look_at(cl[1])
	return {"path": _host._path_of(cam), "type": cam.get_class(), "created": created}


func _tool_setup_light(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null:
		return _host._no_node(args.get("parent_path", "."))
	var ltype := str(args.get("type", "DirectionalLight3D"))
	if not ltype in ["DirectionalLight3D", "OmniLight3D", "SpotLight3D", "PointLight2D"]:
		return _host._err("Unsupported light type: " + ltype)
	var light: Node = ClassDB.instantiate(ltype)
	light.name = str(args.get("name", ltype))
	var is_3d := ltype != "PointLight2D"

	if args.has("position"):
		var c := Values.coerce(args["position"], TYPE_VECTOR3 if is_3d else TYPE_VECTOR2)
		if not c[0]:
			light.free()
			return _host._err("position: " + str(c[1]))
		light.set("position", c[1])
	if args.has("color"):
		var cc := Values.coerce(args["color"], TYPE_COLOR)
		if not cc[0]:
			light.free()
			return _host._err("color: " + str(cc[1]))
		light.set("color", cc[1])
	if args.has("energy"):
		light.set("light_energy" if is_3d else "energy", float(args["energy"]))
	if args.has("range") and (ltype == "OmniLight3D" or ltype == "SpotLight3D"):
		light.set("omni_range" if ltype == "OmniLight3D" else "spot_range", float(args["range"]))
	light.set("shadow_enabled", bool(args.get("shadow_enabled", true)))

	_host._add_child_undo(parent, light, "MCP: Add %s" % ltype)
	if is_3d and args.has("look_at"):
		var cl := Values.coerce(args["look_at"], TYPE_VECTOR3)
		if cl[0]:
			(light as Node3D).look_at(cl[1])
	return {"path": _host._path_of(light), "type": ltype}


func _tool_setup_2d_vector_node(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var pts_raw: Variant = args.get("points", [])
	if not (pts_raw is Array) or pts_raw.size() < 2:
		return _host._err("points must have at least 2 Vector2 expressions.")

	var pts := PackedVector2Array()
	for p in pts_raw:
		var c := Values.coerce(p, TYPE_VECTOR2)
		if not c[0]: return _host._err("point: " + str(c[1]))
		pts.append(c[1])

	var ntype := str(args.get("type", "Line2D"))
	var node: Node
	match ntype:
		"Line2D":
			var l := Line2D.new()
			l.points = pts
			l.width = float(args.get("width", 4.0))
			l.closed = bool(args.get("closed", false))
			if args.has("color"):
				var cc := Values.coerce(args["color"], TYPE_COLOR)
				if cc[0]: l.default_color = cc[1]
			node = l
		"Polygon2D":
			var poly := Polygon2D.new()
			poly.polygon = pts
			if args.has("color"):
				var cc := Values.coerce(args["color"], TYPE_COLOR)
				if cc[0]: poly.color = cc[1]
			node = poly
		"CollisionPolygon2D":
			var cp := CollisionPolygon2D.new()
			cp.polygon = pts
			node = cp
		"LightOccluder2D":
			var lo := LightOccluder2D.new()
			var op := OccluderPolygon2D.new()
			op.polygon = pts
			op.closed = bool(args.get("closed", true))
			lo.occluder = op
			node = lo
		_:
			return _host._err("Unsupported 2D vector node type: " + ntype)

	node.name = str(args.get("name", ntype))
	_host._host._add_child_undo(parent, node, "MCP: Create %s" % ntype)
	return {"path": _host._path_of(node), "type": ntype, "points": pts.size()}


func _tool_setup_3d_fx_node(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var ntype := str(args.get("type", ""))
	if not ntype in ["Decal", "ReflectionProbe", "FogVolume"]:
		return _host._err("type must be Decal, ReflectionProbe, or FogVolume.")
	var node: Node = ClassDB.instantiate(ntype)
	node.name = str(args.get("name", ntype))
	if args.has("position"):
		var cp := Values.coerce(args["position"], TYPE_VECTOR3)
		if not cp[0]: node.free(); return _host._err("position: " + str(cp[1]))
		node.set("position", cp[1])
	if args.has("size"):
		var cs := Values.coerce(args["size"], TYPE_VECTOR3)
		if not cs[0]: node.free(); return _host._err("size: " + str(cs[1]))
		node.set("size", cs[1])
	var props: Variant = args.get("properties", {})
	if props is Dictionary and not props.is_empty():
		var errs := Values.apply_properties(node, props)
		if not errs.is_empty():
			node.free()
			return _host._err("; ".join(errs))
	_host._host._add_child_undo(parent, node, "MCP: Create %s" % ntype)
	return {"path": _host._path_of(node), "type": ntype}


func _tool_setup_parallax(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null:
		return _host._no_node(args.get("parent_path", "."))

	var p2d := Parallax2D.new()
	p2d.name = str(args.get("name", "Parallax2D"))
	for prop in ["scroll_scale", "repeat_size", "autoscroll"]:
		if args.has(prop):
			var c := Values.coerce(args[prop], TYPE_VECTOR2)
			if not c[0]:
				p2d.free()
				return _host._err("%s: %s" % [prop, c[1]])
			p2d.set(prop, c[1])
	_host._add_child_undo(parent, p2d, "MCP: Create Parallax2D")

	if args.has("texture") and str(args["texture"]) != "":
		var tp: String = _host._res_path(args["texture"])
		if tp != "" and ResourceLoader.exists(tp):
			var sp := Sprite2D.new()
			sp.name = "Sprite2D"
			sp.texture = load(tp) as Texture2D
			sp.centered = false
			_host._add_child_undo(p2d, sp, "MCP: Add Parallax Sprite2D")
	return {"path": _host._path_of(p2d)}


func _tool_setup_subviewport(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var svc := SubViewportContainer.new()
	svc.name = str(args.get("name", "SubViewportContainer"))
	svc.stretch = true
	var sv := SubViewport.new()
	sv.name = "SubViewport"
	sv.size = Vector2i(maxi(1, int(args.get("width", 256))), maxi(1, int(args.get("height", 256))))
	sv.transparent_bg = bool(args.get("transparent_bg", true))
	svc.add_child(sv)
	_host._host._add_child_undo(parent, svc, "MCP: Add SubViewportContainer")
	sv.owner = root
	return {"container_path": _host._path_of(svc), "viewport_path": _host._path_of(sv), "size": Values.to_json(sv.size)}
