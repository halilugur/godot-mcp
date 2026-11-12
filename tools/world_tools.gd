@tool
extends RefCounted
## 3D primitive meshes, CSG shapes, MultiMesh, paths, skeletons, and node arrangement.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("create_primitive_mesh", "Create a MeshInstance3D with a primitive mesh (box, sphere, capsule, cylinder, plane, torus, prism) and optional StandardMaterial3D (undoable).", {
		"parent_path": {"type": "string", "description": "Parent node path, default '.'"},
		"name": {"type": "string", "description": "Default MeshInstance3D"},
		"primitive": {"type": "string", "description": "box, sphere, capsule, cylinder, plane, torus, prism. Default box."},
		"size": {"type": "string", "description": "Optional Vector3/Vector2 size expression"},
		"position": {"type": "string", "description": "Optional Vector3 expression"},
		"albedo_color": {"type": "string", "description": "Optional Color expression for StandardMaterial3D"},
		"metallic": {"type": "number", "description": "Default 0.0"},
		"roughness": {"type": "number", "description": "Default 0.8"},
		"texture": {"type": "string", "description": "Optional res:// albedo texture path"},
	}, [], false, false)
	_reg("create_csg_shape", "Create a 3D CSG blockout node (CSGBox3D, CSGSphere3D, CSGCylinder3D, CSGTorus3D, CSGCombiner3D) with operation (union, intersection, subtraction) and collision (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"type": {"type": "string", "description": "CSGBox3D, CSGSphere3D, CSGCylinder3D, CSGTorus3D, CSGCombiner3D. Default CSGBox3D."},
		"name": s,
		"operation": {"type": "string", "description": "union, intersection, or subtraction. Default union."},
		"use_collision": {"type": "boolean", "description": "Default true"},
		"position": {"type": "string", "description": "Vector3 expression"},
		"size": {"type": "string", "description": "Vector3 expression for CSGBox3D"},
		"radius": {"type": "number", "description": "For CSGSphere3D / CSGCylinder3D"},
		"height": {"type": "number", "description": "For CSGCylinder3D"},
	}, [], false, false)
	_reg("populate_multimesh", "Populate a MultiMeshInstance3D with N scattered instances in a box/circle area (great for trees, grass, rocks) (undoable).", {
		"node_path": {"type": "string", "description": "Existing MultiMeshInstance3D, or parent path if creating"},
		"mesh_path": {"type": "string", "description": "res:// path to a Mesh resource, or primitive: box/sphere/capsule/cylinder"},
		"count": {"type": "integer", "description": "Number of instances (1..10000), default 100"},
		"area_size": {"type": "string", "description": "Scatter box Vector3 expression, default \"Vector3(20, 0, 20)\""},
		"random_yaw": {"type": "boolean", "description": "Default true"},
		"scale_min": {"type": "number", "description": "Default 0.8"},
		"scale_max": {"type": "number", "description": "Default 1.2"},
		"seed": {"type": "integer", "description": "Random seed, default 42"},
	}, ["mesh_path"], false, false)
	_reg("setup_path", "Create or update a Path2D or Path3D with a list of curve points and optional PathFollow2D/3D child (undoable).", {
		"node_path": {"type": "string", "description": "Existing Path2D/Path3D or parent node path, default '.'"},
		"name": {"type": "string", "description": "Default Path"},
		"is_3d": {"type": "boolean", "description": "Default false (2D)"},
		"points": {"type": "array", "items": {"type": "string"}, "description": "List of Vector2 or Vector3 expressions"},
		"closed": {"type": "boolean", "description": "Close the loop. Default false."},
		"add_follow": {"type": "boolean", "description": "Add a PathFollow2D/3D child. Default false."},
	}, ["points"], false, false)
	_reg("get_skeleton_bones", "List all bones (index, name, parent, rest position) of a Skeleton3D or Skeleton2D node.", {
		"node_path": node_path,
	}, ["node_path"], true, false)
	_reg("add_bone_attachment", "Add a BoneAttachment3D to a Skeleton3D bound to a specific bone (e.g. for attaching weapons/hats) (undoable).", {
		"skeleton_path": node_path,
		"bone_name": s,
		"name": {"type": "string", "description": "Default BoneAttachment3D"},
	}, ["skeleton_path", "bone_name"], false, false)
	_reg("arrange_nodes", "Arrange multiple nodes in a grid, line, or circle layout in 2D or 3D (undoable).", {
		"node_paths": string_list,
		"layout": {"type": "string", "description": "grid, line, or circle"},
		"origin": {"type": "string", "description": "Starting/center position as Vector2 or Vector3 expression. Default \"Vector2(0, 0)\""},
		"spacing": {"type": "string", "description": "Spacing as Vector2/Vector3 expression or number. Default \"Vector2(64, 64)\""},
		"columns": {"type": "integer", "description": "Columns for grid layout, default 4"},
		"radius": {"type": "number", "description": "Radius for circle layout, default 100"},
	}, ["node_paths", "layout"], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _make_primitive_mesh(prim: String, size_arg: Variant) -> Array:
	var mesh: PrimitiveMesh
	match prim.to_lower():
		"box":
			var m := BoxMesh.new()
			if size_arg != null:
				var c := Values.coerce(size_arg, TYPE_VECTOR3)
				if not c[0]: return [null, c[1]]
				m.size = c[1]
			mesh = m
		"sphere":
			mesh = SphereMesh.new()
		"capsule":
			mesh = CapsuleMesh.new()
		"cylinder":
			mesh = CylinderMesh.new()
		"plane":
			var mp := PlaneMesh.new()
			if size_arg != null:
				var c2 := Values.coerce(size_arg, TYPE_VECTOR2)
				if not c2[0]: return [null, c2[1]]
				mp.size = c2[1]
			mesh = mp
		"torus":
			mesh = TorusMesh.new()
		"prism":
			mesh = PrismMesh.new()
		_:
			return [null, "Unknown primitive: " + prim]
	return [mesh, ""]


func _tool_create_primitive_mesh(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null:
		return _host._no_node(args.get("parent_path", "."))

	var prim := str(args.get("primitive", "box"))
	var mr := _make_primitive_mesh(prim, args.get("size", null))
	if mr[0] == null:
		return _host._err(str(mr[1]))

	var mi := MeshInstance3D.new()
	mi.name = str(args.get("name", prim.capitalize() + "Mesh"))
	mi.mesh = mr[0]
	if args.has("position"):
		var cp := Values.coerce(args["position"], TYPE_VECTOR3)
		if not cp[0]:
			mi.free()
			return _host._err("position: " + str(cp[1]))
		mi.position = cp[1]

	if args.has("albedo_color") or args.has("metallic") or args.has("roughness") or args.has("texture"):
		var mat := StandardMaterial3D.new()
		if args.has("albedo_color"):
			var cc := Values.coerce(args["albedo_color"], TYPE_COLOR)
			if not cc[0]:
				mi.free()
				return _host._err("albedo_color: " + str(cc[1]))
			mat.albedo_color = cc[1]
		mat.metallic = float(args.get("metallic", 0.0))
		mat.roughness = float(args.get("roughness", 0.8))
		if args.has("texture") and str(args["texture"]) != "":
			var tp: String = _host._res_path(args["texture"])
			if tp != "" and ResourceLoader.exists(tp):
				mat.albedo_texture = load(tp) as Texture2D
		mi.material_override = mat

	_host._add_child_undo(parent, mi, "MCP: Create %s MeshInstance3D" % prim)
	return {"path": _host._path_of(mi), "primitive": prim}


func _tool_create_csg_shape(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))

	var ctype := str(args.get("type", "CSGBox3D"))
	if not ctype in ["CSGBox3D", "CSGSphere3D", "CSGCylinder3D", "CSGTorus3D", "CSGCombiner3D"]:
		return _host._err("Unsupported CSG type: " + ctype)
	var node: Node = ClassDB.instantiate(ctype)
	node.name = str(args.get("name", ctype))

	var op_map := {"union": CSGShape3D.OPERATION_UNION, "intersection": CSGShape3D.OPERATION_INTERSECTION, "subtraction": CSGShape3D.OPERATION_SUBTRACTION}
	var op_str := str(args.get("operation", "union")).to_lower()
	if op_map.has(op_str) and node is CSGShape3D:
		(node as CSGShape3D).operation = op_map[op_str]
	if node is CSGShape3D:
		(node as CSGShape3D).use_collision = bool(args.get("use_collision", true))

	if args.has("position"):
		var cp := Values.coerce(args["position"], TYPE_VECTOR3)
		if not cp[0]: node.free(); return _host._err("position: " + str(cp[1]))
		node.set("position", cp[1])
	if args.has("size") and node is CSGBox3D:
		var cs := Values.coerce(args["size"], TYPE_VECTOR3)
		if not cs[0]: node.free(); return _host._err("size: " + str(cs[1]))
		(node as CSGBox3D).size = cs[1]
	if args.has("radius") and "radius" in node:
		node.set("radius", float(args["radius"]))
	if args.has("height") and "height" in node:
		node.set("height", float(args["height"]))

	_host._host._add_child_undo(parent, node, "MCP: Create %s" % ctype)
	return {"path": _host._path_of(node), "type": ctype, "operation": op_str}


func _tool_populate_multimesh(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var target: Node = _host._find(args.get("node_path", "."))
	if target == null:
		return _host._no_node(args.get("node_path", "."))

	var mmi: MultiMeshInstance3D = target as MultiMeshInstance3D
	var created := false
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "MultiMeshInstance3D"
		created = true

	var mesh_arg := str(args.get("mesh_path", ""))
	var mesh: Mesh = null
	if mesh_arg in ["box", "sphere", "capsule", "cylinder", "plane", "torus", "prism"]:
		mesh = _make_primitive_mesh(mesh_arg, null)[0]
	else:
		var mp: String = _host._res_path(mesh_arg)
		if mp == "" or not ResourceLoader.exists(mp):
			if created: mmi.free()
			return _host._err("Mesh not found: " + mesh_arg)
		mesh = load(mp) as Mesh
	if mesh == null:
		if created: mmi.free()
		return _host._err("Could not load Mesh.")

	var count := clampi(int(args.get("count", 100)), 1, 10000)
	var area := Vector3(20, 0, 20)
	if args.has("area_size"):
		var ca := Values.coerce(args["area_size"], TYPE_VECTOR3)
		if not ca[0]:
			if created: mmi.free()
			return _host._err("area_size: " + str(ca[1]))
		area = ca[1]

	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.get("seed", 42))
	var rand_yaw := bool(args.get("random_yaw", true))
	var s_min := float(args.get("scale_min", 0.8))
	var s_max := float(args.get("scale_max", 1.2))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var pos := Vector3(
			rng.randf_range(-area.x * 0.5, area.x * 0.5),
			rng.randf_range(-area.y * 0.5, area.y * 0.5),
			rng.randf_range(-area.z * 0.5, area.z * 0.5)
		)
		var sc := rng.randf_range(s_min, s_max)
		var basis := Basis.IDENTITY.scaled(Vector3(sc, sc, sc))
		if rand_yaw:
			basis = basis.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		mm.set_instance_transform(i, Transform3D(basis, pos))

	if created:
		mmi.multimesh = mm
		_host._add_child_undo(target, mmi, "MCP: Populate MultiMesh")
	else:
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Populate MultiMesh")
		ur.add_do_property(mmi, "multimesh", mm)
		ur.add_undo_property(mmi, "multimesh", mmi.multimesh)
		ur.commit_action()
	return {"path": _host._path_of(mmi), "instance_count": count}


func _tool_setup_path(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var target: Node = _host._find(args.get("node_path", "."))
	if target == null:
		return _host._no_node(args.get("node_path", "."))
	var pts_raw: Variant = args.get("points", [])
	if not (pts_raw is Array) or pts_raw.size() < 2:
		return _host._err("points must have at least 2 points.")

	var is_3d := bool(args.get("is_3d", false))
	var path_node: Node = target if (target is Path2D or target is Path3D) else null
	var created := false
	if path_node == null:
		path_node = Path3D.new() if is_3d else Path2D.new()
		path_node.name = str(args.get("name", "Path3D" if is_3d else "Path2D"))
		created = true
	else:
		is_3d = path_node is Path3D

	if is_3d:
		var curve3 := Curve3D.new()
		for p in pts_raw:
			var c := Values.coerce(p, TYPE_VECTOR3)
			if not c[0]:
				if created: path_node.free()
				return _host._err("point: " + str(c[1]))
			curve3.add_point(c[1])
		if bool(args.get("closed", false)) and curve3.point_count >= 2:
			curve3.add_point(curve3.get_point_position(0))
		(path_node as Path3D).curve = curve3
	else:
		var curve2 := Curve2D.new()
		for p in pts_raw:
			var c := Values.coerce(p, TYPE_VECTOR2)
			if not c[0]:
				if created: path_node.free()
				return _host._err("point: " + str(c[1]))
			curve2.add_point(c[1])
		if bool(args.get("closed", false)) and curve2.point_count >= 2:
			curve2.add_point(curve2.get_point_position(0))
		(path_node as Path2D).curve = curve2

	if created:
		_host._add_child_undo(target, path_node, "MCP: Create %s" % path_node.get_class())
	if bool(args.get("add_follow", false)):
		var follow: Node = PathFollow3D.new() if is_3d else PathFollow2D.new()
		follow.name = "PathFollow3D" if is_3d else "PathFollow2D"
		_host._add_child_undo(path_node, follow, "MCP: Add PathFollow")
	return {"path": _host._path_of(path_node), "points": pts_raw.size(), "closed": bool(args.get("closed", false))}


func _tool_get_skeleton_bones(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	var bones := []
	if node is Skeleton3D:
		var sk := node as Skeleton3D
		for i in sk.get_bone_count():
			bones.append({
				"index": i,
				"name": sk.get_bone_name(i),
				"parent": sk.get_bone_parent(i),
				"rest_origin": Values.to_json(sk.get_bone_rest(i).origin),
			})
	elif node is Skeleton2D:
		var sk2 := node as Skeleton2D
		for i in sk2.get_bone_count():
			var b := sk2.get_bone(i)
			bones.append({"index": i, "name": str(b.name), "position": Values.to_json(b.position)})
	else:
		return _host._err("%s is %s, expected Skeleton3D or Skeleton2D." % [_host._path_of(node), node.get_class()])
	return {"path": _host._path_of(node), "bone_count": bones.size(), "bones": bones}


func _tool_add_bone_attachment(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("skeleton_path", ""))
	if node == null:
		return _host._no_node(args.get("skeleton_path", ""))
	if not (node is Skeleton3D):
		return _host._err("%s is %s, expected Skeleton3D." % [_host._path_of(node), node.get_class()])
	var bone := str(args.get("bone_name", ""))
	if (node as Skeleton3D).find_bone(bone) == -1:
		return _host._err("Bone '%s' not found on Skeleton3D." % bone)
	var att := BoneAttachment3D.new()
	att.name = str(args.get("name", "BoneAttachment_" + bone))
	att.bone_name = bone
	_host._add_child_undo(node, att, "MCP: Add BoneAttachment3D")
	return {"path": _host._path_of(att), "bone_name": bone}


func _tool_arrange_nodes(args: Dictionary) -> Variant:
	var paths: Variant = args.get("node_paths", [])
	if not (paths is Array) or paths.is_empty():
		return _host._err("node_paths must be a non-empty array.")
	var nodes := []
	for p in paths:
		var n: Node = _host._find(p)
		if n == null:
			return _host._no_node(p)
		nodes.append(n)

	var is_3d := nodes[0] is Node3D
	var layout := str(args.get("layout", "grid")).to_lower()
	var origin_v := Vector3.ZERO
	if args.has("origin"):
		var co := Values.coerce(args["origin"], TYPE_VECTOR3 if is_3d else TYPE_VECTOR2)
		if not co[0]:
			return _host._err("origin: " + str(co[1]))
		origin_v = co[1] if is_3d else Vector3(co[1].x, co[1].y, 0)

	var spacing_v := Vector3(2, 0, 2) if is_3d else Vector3(64, 64, 0)
	if args.has("spacing"):
		var sv: Variant = args["spacing"]
		if sv is float or sv is int:
			spacing_v = Vector3(float(sv), float(sv), float(sv))
		else:
			var cs := Values.coerce(sv, TYPE_VECTOR3 if is_3d else TYPE_VECTOR2)
			if not cs[0]:
				return _host._err("spacing: " + str(cs[1]))
			spacing_v = cs[1] if is_3d else Vector3(cs[1].x, cs[1].y, 0)

	var columns := maxi(1, int(_host._to_int(args.get("columns"), 4)))
	var radius := float(args.get("radius", 100.0))

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Arrange %d nodes (%s)" % [nodes.size(), layout])
	var positions := []
	for i in nodes.size():
		var n: Node = nodes[i]
		var target := origin_v
		match layout:
			"grid":
				var col := i % columns
				var row := i / columns
				target += Vector3(col * spacing_v.x, 0 if is_3d else row * spacing_v.y, row * spacing_v.z if is_3d else 0)
			"line":
				target += Vector3(i * spacing_v.x, 0 if is_3d else i * spacing_v.y, i * spacing_v.z if is_3d else 0)
			"circle":
				var angle := TAU * float(i) / float(nodes.size())
				target += Vector3(cos(angle) * radius, 0 if is_3d else sin(angle) * radius, sin(angle) * radius if is_3d else 0)
			_:
				return _host._err("Unknown layout '%s'. Use grid, line, or circle." % layout)

		if is_3d and n is Node3D:
			ur.add_do_property(n, "position", target)
			ur.add_undo_property(n, "position", n.position)
			positions.append({"path": _host._path_of(n), "position": Values.to_json(target)})
		elif not is_3d and (n is Node2D or n is Control):
			var p2 := Vector2(target.x, target.y)
			ur.add_do_property(n, "position", p2)
			ur.add_undo_property(n, "position", n.position)
			positions.append({"path": _host._path_of(n), "position": Values.to_json(p2)})
	ur.commit_action()
	return {"layout": layout, "arranged": positions.size(), "positions": positions}
