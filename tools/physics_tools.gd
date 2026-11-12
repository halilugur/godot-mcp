@tool
extends RefCounted
## Collision shapes, mesh collision, physics joints, raycasts, layers, and navigation.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("setup_collision_shape", "Create and assign a Shape2D or Shape3D on a CollisionShape2D/CollisionShape3D (undoable). Set auto_fit=true to size it from a sibling Sprite2D, ColorRect, or MeshInstance3D.", {
		"node_path": node_path,
		"shape": {"type": "string", "description": "2D: rectangle, circle, capsule, segment. 3D: box, sphere, capsule, cylinder."},
		"size": {"type": "string", "description": "Optional Godot expression, e.g. \"Vector2(32, 48)\" or \"Vector3(1, 2, 1)\""},
		"radius": {"type": "number"},
		"height": {"type": "number"},
		"auto_fit": {"type": "boolean", "description": "Auto-size from sibling visual node when size/radius are omitted. Default true."},
	}, ["node_path"], false, false)
	_reg("generate_mesh_collision", "Generate a StaticBody3D with CollisionShape3D for a MeshInstance3D (trimesh or convex).", {
		"node_path": node_path,
		"mode": {"type": "string", "description": "trimesh or convex. Default convex."},
	}, ["node_path"], false, false)
	_reg("create_physics_joint", "Create a 2D or 3D Physics Joint (PinJoint2D, DampedSpringJoint2D, HingeJoint3D, PinJoint3D, SliderJoint3D, Generic6DOFJoint3D) connecting node_a and node_b (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"type": s,
		"name": s,
		"node_a": node_path,
		"node_b": node_path,
		"position": {"type": "string", "description": "Vector2 or Vector3 expression"},
		"properties": {"type": "object"},
	}, ["type", "node_a", "node_b"], false, false)
	_reg("setup_raycast", "Create a RayCast2D or RayCast3D node with target_position and collision settings (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"is_3d": {"type": "boolean", "description": "Default false"},
		"name": s,
		"target_position": {"type": "string", "description": "Vector2 or Vector3 expression"},
		"collide_with_areas": {"type": "boolean", "description": "Default false"},
		"collide_with_bodies": {"type": "boolean", "description": "Default true"},
		"collision_mask": {"type": "integer"},
	}, ["target_position"], false, false)
	_reg("physics_layers", "Read or rename 2D/3D physics/render/navigation layer names in Project Settings, and optionally set collision_layer / collision_mask on a node by layer numbers or names.", {
		"domain": {"type": "string", "description": "2d_physics, 3d_physics, 2d_render, 3d_render, 2d_navigation, 3d_navigation. Default 2d_physics."},
		"set_names": {"type": "object", "description": "Map of layer number (\"1\"..\"32\") to name"},
		"node_path": {"type": "string", "description": "Optional node to update collision_layer/collision_mask"},
		"collision_layer": {"type": "array", "items": {"type": "string"}, "description": "Layer numbers (\"1\") or names to enable on collision_layer"},
		"collision_mask": {"type": "array", "items": {"type": "string"}, "description": "Layer numbers (\"1\") or names to enable on collision_mask"},
	}, [], false, false)
	_reg("setup_navigation_node", "Create a NavigationAgent2D/3D, NavigationObstacle2D/3D, or NavigationLink2D/3D (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"type": {"type": "string", "description": "NavigationAgent2D, NavigationAgent3D, NavigationObstacle2D, NavigationObstacle3D, NavigationLink2D, NavigationLink3D"},
		"name": s,
		"properties": {"type": "object"},
	}, ["type"], false, false)
	_reg("bake_navigation_mesh", "Bake the NavigationPolygon on a NavigationRegion2D or NavigationMesh on a NavigationRegion3D.", {
		"node_path": node_path,
	}, ["node_path"], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _resolve_layer_mask(items: Array, name_to_bit: Dictionary) -> int:
	var mask := 0
	for item in items:
		var s := str(item).strip_edges()
		if s.is_valid_int():
			var b := int(s)
			if b >= 1 and b <= 32:
				mask |= (1 << (b - 1))
		elif name_to_bit.has(s.to_lower()):
			var b: int = name_to_bit[s.to_lower()]
			mask |= (1 << (b - 1))
	return mask


func _tool_setup_collision_shape(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	var is_2d := node is CollisionShape2D
	var is_3d := node is CollisionShape3D
	if not is_2d and not is_3d:
		return _host._err("%s is %s, expected CollisionShape2D or CollisionShape3D." % [_host._path_of(node), node.get_class()])

	var shape_kind := str(args.get("shape", "rectangle" if is_2d else "box")).to_lower()
	var auto_fit := bool(args.get("auto_fit", true))
	var fit_size: Vector3 = _host._estimate_sibling_size(node, is_2d) if auto_fit else Vector3.ZERO
	var shape: Resource

	if is_2d:
		var v2 := Vector2(32, 32)
		if fit_size.x > 0.0 and fit_size.y > 0.0:
			v2 = Vector2(fit_size.x, fit_size.y)
		if args.has("size"):
			var c := Values.coerce(args["size"], TYPE_VECTOR2)
			if not c[0]:
				return _host._err("size: " + str(c[1]))
			v2 = c[1]
		match shape_kind:
			"rectangle", "rect", "box":
				var r := RectangleShape2D.new()
				r.size = v2
				shape = r
			"circle", "sphere":
				var cs := CircleShape2D.new()
				cs.radius = float(args["radius"]) if args.has("radius") else maxf(v2.x, v2.y) * 0.5
				shape = cs
			"capsule":
				var cap := CapsuleShape2D.new()
				cap.radius = float(args["radius"]) if args.has("radius") else v2.x * 0.5
				cap.height = float(args["height"]) if args.has("height") else v2.y
				shape = cap
			"segment":
				var seg := SegmentShape2D.new()
				seg.a = Vector2(-v2.x * 0.5, 0)
				seg.b = Vector2(v2.x * 0.5, 0)
				shape = seg
			_:
				return _host._err("Unknown 2D shape '%s'. Use rectangle, circle, capsule, or segment." % shape_kind)
	else:
		var v3 := Vector3(1, 1, 1)
		if fit_size != Vector3.ZERO:
			v3 = fit_size
		if args.has("size"):
			var c := Values.coerce(args["size"], TYPE_VECTOR3)
			if not c[0]:
				return _host._err("size: " + str(c[1]))
			v3 = c[1]
		match shape_kind:
			"box", "rectangle":
				var b := BoxShape3D.new()
				b.size = v3
				shape = b
			"sphere", "circle":
				var sp := SphereShape3D.new()
				sp.radius = float(args["radius"]) if args.has("radius") else maxf(v3.x, maxf(v3.y, v3.z)) * 0.5
				shape = sp
			"capsule":
				var cap3 := CapsuleShape3D.new()
				cap3.radius = float(args["radius"]) if args.has("radius") else maxf(v3.x, v3.z) * 0.5
				cap3.height = float(args["height"]) if args.has("height") else v3.y
				shape = cap3
			"cylinder":
				var cyl := CylinderShape3D.new()
				cyl.radius = float(args["radius"]) if args.has("radius") else maxf(v3.x, v3.z) * 0.5
				cyl.height = float(args["height"]) if args.has("height") else v3.y
				shape = cyl
			_:
				return _host._err("Unknown 3D shape '%s'. Use box, sphere, capsule, or cylinder." % shape_kind)

	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Set collision shape on %s" % node.name)
	ur.add_do_property(node, "shape", shape)
	ur.add_undo_property(node, "shape", node.get("shape"))
	ur.commit_action()
	return {"path": _host._path_of(node), "shape_class": shape.get_class(), "auto_fitted": auto_fit and fit_size != Vector3.ZERO}


func _tool_generate_mesh_collision(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not (node is MeshInstance3D):
		return _host._err("%s is %s, expected MeshInstance3D." % [_host._path_of(node), node.get_class()])
	if node.mesh == null:
		return _host._err("MeshInstance3D has no mesh.")
	var mode := str(args.get("mode", "convex")).to_lower()
	if mode == "trimesh":
		node.create_trimesh_collision()
	elif mode == "convex":
		node.create_convex_collision()
	else:
		return _host._err("mode must be 'convex' or 'trimesh'.")
	var root: Node = _host._root()
	_host._set_owner_recursive(node, root)
	return {"path": _host._path_of(node), "mode": mode, "children": node.get_child_count()}


func _tool_create_physics_joint(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var jtype := str(args.get("type", ""))
	if not ClassDB.class_exists(jtype) or not (ClassDB.is_parent_class(jtype, "Joint2D") or ClassDB.is_parent_class(jtype, "Joint3D")):
		return _host._err("Invalid Joint2D/Joint3D class: " + jtype)
	var na: Node = _host._find(args.get("node_a", ""))
	var nb: Node = _host._find(args.get("node_b", ""))
	if na == null: return _host._no_node(args.get("node_a", ""))
	if nb == null: return _host._no_node(args.get("node_b", ""))

	var joint: Node = ClassDB.instantiate(jtype)
	joint.name = str(args.get("name", jtype))
	var is_3d := joint is Joint3D
	if args.has("position"):
		var cp := Values.coerce(args["position"], TYPE_VECTOR3 if is_3d else TYPE_VECTOR2)
		if not cp[0]: joint.free(); return _host._err("position: " + str(cp[1]))
		joint.set("position", cp[1])
	var props: Variant = args.get("properties", {})
	if props is Dictionary and not props.is_empty():
		Values.apply_properties(joint, props)

	_host._host._add_child_undo(parent, joint, "MCP: Create %s" % jtype)
	joint.set("node_a", joint.get_path_to(na))
	joint.set("node_b", joint.get_path_to(nb))
	return {"path": _host._path_of(joint), "type": jtype, "node_a": _host._path_of(na), "node_b": _host._path_of(nb)}


func _tool_setup_raycast(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var is_3d := bool(args.get("is_3d", false))
	var rc: Node = RayCast3D.new() if is_3d else RayCast2D.new()
	rc.name = str(args.get("name", "RayCast3D" if is_3d else "RayCast2D"))
	var ct := Values.coerce(args.get("target_position"), TYPE_VECTOR3 if is_3d else TYPE_VECTOR2)
	if not ct[0]: rc.free(); return _host._err("target_position: " + str(ct[1]))
	rc.set("target_position", ct[1])
	rc.set("collide_with_areas", bool(args.get("collide_with_areas", false)))
	rc.set("collide_with_bodies", bool(args.get("collide_with_bodies", true)))
	if args.has("collision_mask"):
		rc.set("collision_mask", int(args["collision_mask"]))
	_host._host._add_child_undo(parent, rc, "MCP: Add %s" % rc.get_class())
	return {"path": _host._path_of(rc), "type": rc.get_class()}


func _tool_physics_layers(args: Dictionary) -> Variant:
	var domain := str(args.get("domain", "2d_physics"))
	var prefix := "layer_names/" + domain + "/layer_"

	var set_names: Variant = args.get("set_names", null)
	if set_names is Dictionary and not set_names.is_empty():
		for k in set_names:
			var idx := int(str(k))
			if idx < 1 or idx > 32:
				return _host._err("Layer index must be 1..32, got: " + str(k))
			ProjectSettings.set_setting(prefix + str(idx), str(set_names[k]))
		ProjectSettings.save()

	var layers := {}
	var name_to_bit := {}
	for i in range(1, 33):
		var val := str(ProjectSettings.get_setting(prefix + str(i), ""))
		if val != "":
			layers[str(i)] = val
			name_to_bit[val.to_lower()] = i

	var out := {"domain": domain, "named_layers": layers}
	if args.has("node_path"):
		var node: Node = _host._find(args["node_path"])
		if node == null:
			return _host._no_node(args["node_path"])
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Set physics layers on %s" % node.name)
		if args.has("collision_layer") and args["collision_layer"] is Array:
			var mask_val := _resolve_layer_mask(args["collision_layer"], name_to_bit)
			ur.add_do_property(node, "collision_layer", mask_val)
			ur.add_undo_property(node, "collision_layer", node.get("collision_layer"))
			out["collision_layer"] = mask_val
		if args.has("collision_mask") and args["collision_mask"] is Array:
			var mask_val := _resolve_layer_mask(args["collision_mask"], name_to_bit)
			ur.add_do_property(node, "collision_mask", mask_val)
			ur.add_undo_property(node, "collision_mask", node.get("collision_mask"))
			out["collision_mask"] = mask_val
		ur.commit_action()
	return out


func _tool_setup_navigation_node(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var ntype := str(args.get("type", ""))
	if not ntype in ["NavigationAgent2D", "NavigationAgent3D", "NavigationObstacle2D", "NavigationObstacle3D", "NavigationLink2D", "NavigationLink3D"]:
		return _host._err("Unsupported navigation node type: " + ntype)
	var node: Node = ClassDB.instantiate(ntype)
	node.name = str(args.get("name", ntype))
	var props: Variant = args.get("properties", {})
	if props is Dictionary and not props.is_empty():
		var errs := Values.apply_properties(node, props)
		if not errs.is_empty():
			node.free()
			return _host._err("; ".join(errs))
	_host._host._add_child_undo(parent, node, "MCP: Add %s" % ntype)
	return {"path": _host._path_of(node), "type": ntype}


func _tool_bake_navigation_mesh(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if node is NavigationRegion2D:
		if node.navigation_polygon == null:
			node.navigation_polygon = NavigationPolygon.new()
		node.bake_navigation_polygon(false)
		return {"path": _host._path_of(node), "type": "NavigationRegion2D", "baked": true}
	if node is NavigationRegion3D:
		if node.navigation_mesh == null:
			node.navigation_mesh = NavigationMesh.new()
		node.bake_navigation_mesh(false)
		return {"path": _host._path_of(node), "type": "NavigationRegion3D", "baked": true}
	return _host._err("%s is %s, expected NavigationRegion2D or NavigationRegion3D." % [_host._path_of(node), node.get_class()])
