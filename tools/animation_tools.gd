@tool
extends RefCounted
## AnimationPlayer tracks, AnimationTree playback, state machines, and blend spaces.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("get_animations", "Animations of an AnimationPlayer. Pass name for the full tracks and keys of one animation.", {
		"node_path": node_path,
		"name": s,
	}, ["node_path"], true)
	_reg("set_animation", "Create or replace an animation on an AnimationPlayer (undoable). tracks: [{\"path\": \"Sprite2D:position\", \"keys\": [{\"time\": 0, \"value\": \"Vector2(0, 0)\"}, {\"time\": 1, \"value\": \"Vector2(100, 0)\"}], \"interpolation\": \"linear\"}]. Track paths are relative to the player's root node (normally its parent). For method tracks use {\"type\": \"method\", \"path\": \"Enemy\", \"keys\": [{\"time\": 0.5, \"method\": \"shoot\", \"args\": []}]}.", {
		"node_path": node_path,
		"name": s,
		"length": {"type": "number", "description": "Seconds. Default: time of the last key."},
		"loop": {"type": "boolean", "description": "Default false"},
		"tracks": {"type": "array", "items": {"type": "object"}},
		"autoplay": {"type": "boolean", "description": "Play this animation when the scene starts"},
	}, ["node_path", "name", "tracks"])
	_reg("remove_animation", "Remove an animation from an AnimationPlayer (undoable).", {"node_path": node_path, "name": s}, ["node_path", "name"])
	_reg("get_animation_tree", "Inspect an AnimationTree node: active state, root node class, parameters, and StateMachine current/travel state.", {
		"node_path": node_path,
	}, ["node_path"], true, false)
	_reg("control_animation_tree", "Set parameters on an AnimationTree and/or trigger a StateMachine travel/start transition.", {
		"node_path": node_path,
		"active": {"type": "boolean"},
		"params": {"type": "object", "description": "Map of parameter name (without 'parameters/' prefix or with it) -> value"},
		"travel": {"type": "string", "description": "StateMachine state name to travel() to"},
		"start": {"type": "string", "description": "StateMachine state name to start() immediately"},
		"playback_path": {"type": "string", "description": "Default \"parameters/playback\""},
	}, ["node_path"], false, false)
	_reg("build_animation_state_machine", "Build an AnimationNodeStateMachine on an AnimationTree with states and transitions (undoable).", {
		"node_path": node_path,
		"states": {"type": "array", "items": {"type": "object"}, "description": "[{\"name\": \"idle\", \"animation\": \"idle\"}, {\"name\": \"run\", \"animation\": \"run\"}]"},
		"transitions": {"type": "array", "items": {"type": "object"}, "description": "[{\"from\": \"Start\", \"to\": \"idle\", \"xfade_time\": 0.1, \"switch_mode\": \"immediate\"}]"},
		"activate": {"type": "boolean", "description": "Set AnimationTree active=true. Default true."},
	}, ["node_path", "states"], false, false)
	_reg("setup_blend_space", "Create an AnimationNodeBlendSpace1D or 2D on an AnimationTree (or inside its StateMachine) with animation blend points.", {
		"node_path": node_path,
		"is_2d": {"type": "boolean", "description": "Default false (1D)"},
		"state_name": {"type": "string", "description": "Optional StateMachine state name to add this BlendSpace into (if omitted, sets tree_root)"},
		"points": {"type": "array", "items": {"type": "object"}, "description": "1D: [{\"pos\": 0.0, \"animation\": \"idle\"}]. 2D: [{\"pos\": [0, 1], \"animation\": \"walk_up\"}]"},
		"min_space": {"type": "number", "description": "Default -1.0"},
		"max_space": {"type": "number", "description": "Default 1.0"},
	}, ["node_path", "points"], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _player(path: Variant) -> Variant:
	var node: Variant = _host._find(path)
	if node == null:
		return _host._no_node(path)
	if not (node is AnimationPlayer):
		return _host._err("%s is a %s, not an AnimationPlayer." % [_host._path_of(node), node.get_class()])
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
			return _host._err("No animation named '%s'. Animations: %s" % [wanted, ", ".join(Array(player.get_animation_list()))])
		var anim: Animation = player.get_animation(wanted)
		var tracks := []
		for i in anim.get_track_count():
			tracks.append(_track_summary(anim, i, true))
		return {"name": wanted, "length": anim.length, "loop": anim.loop_mode != Animation.LOOP_NONE, "tracks": tracks}
	var list := []
	for name in player.get_animation_list():
		var anim: Animation = player.get_animation(name)
		list.append({"name": str(name), "length": anim.length, "loop": anim.loop_mode != Animation.LOOP_NONE, "tracks": anim.get_track_count()})
	return {"path": _host._path_of(player), "autoplay": str(player.autoplay), "animations": list}


func _tool_set_animation(args: Dictionary) -> Variant:
	var player: Variant = _player(args.get("node_path", ""))
	if player is Dictionary:
		return player
	var name := str(args.get("name", ""))
	if name == "" or name.contains("/"):
		return _host._err("name must be a plain animation name.")
	var specs: Variant = args.get("tracks", [])
	if not (specs is Array):
		return _host._err("tracks must be an array.")
	var base: Node = player.get_node_or_null(player.root_node)
	var anim := Animation.new()
	var last_time := 0.0
	var warnings := []
	for spec in specs:
		if not (spec is Dictionary) or str(spec.get("path", "")) == "":
			return _host._err("Each track needs a path, e.g. \"Sprite2D:position\".")
		var track_path := NodePath(str(spec["path"]))
		var keys: Variant = spec.get("keys", [])
		if not (keys is Array):
			return _host._err("Track %s: keys must be an array." % track_path)
		var is_method := str(spec.get("type", "value")) == "method"
		var index := anim.add_track(Animation.TYPE_METHOD if is_method else Animation.TYPE_VALUE)
		anim.track_set_path(index, track_path)
		var node_part := NodePath(str(track_path).split(":")[0])
		var target: Node = base.get_node_or_null(node_part) if base != null else null
		if target == null:
			warnings.append("Track %s: node not found relative to %s." % [track_path, _host._path_of(base) if base != null else "the player's root"])
		var value_type := TYPE_NIL
		if not is_method:
			var prop := str(track_path.get_concatenated_subnames())
			if prop == "":
				return _host._err("Track %s: a value track path needs a property, e.g. \"Sprite2D:position\"." % track_path)
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
				return _host._err("Track %s: every key needs a time." % track_path)
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
					return _host._err("Track %s, key at %s: %s" % [track_path, time, r[1]])
				anim.track_insert_key(index, time, r[1], float(key.get("transition", 1.0)))
	anim.length = maxf(float(args.get("length", last_time)), 0.001)
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE

	var ur: Variant = _host._plugin.get_undo_redo()
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
		return _host._err("No animation named '%s' in the player's default library." % name)
	var library: AnimationLibrary = player.get_animation_library("")
	var ur: Variant = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Remove animation %s" % name, UndoRedo.MERGE_DISABLE, player)
	ur.add_do_method(library, "remove_animation", name)
	ur.add_undo_method(library, "add_animation", name, library.get_animation(name))
	ur.commit_action()
	return {"removed": name}


func _tool_get_animation_tree(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not (node is AnimationTree):
		return _host._err("%s is %s, not an AnimationTree." % [_host._path_of(node), node.get_class()])
	var tree := node as AnimationTree
	var params := {}
	for p in tree.get_property_list():
		var pname := str(p["name"])
		if pname.begins_with("parameters/"):
			params[pname] = Values.to_json(tree.get(pname))
	var out := {
		"path": _host._path_of(tree),
		"active": tree.active,
		"anim_player": str(tree.anim_player),
		"tree_root": tree.tree_root.get_class() if tree.tree_root != null else null,
		"parameters": params,
	}
	var pb: Variant = tree.get("parameters/playback")
	if pb is AnimationNodeStateMachinePlayback:
		out["current_state"] = str(pb.get_current_node())
		out["travel_path"] = Array(pb.get_travel_path())
	return out


func _tool_control_animation_tree(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null:
		return _host._no_node(args.get("node_path", ""))
	if not (node is AnimationTree):
		return _host._err("%s is %s, not an AnimationTree." % [_host._path_of(node), node.get_class()])
	var tree := node as AnimationTree
	if args.has("active"):
		tree.active = bool(args["active"])

	var params: Variant = args.get("params", {})
	var updated := []
	if params is Dictionary:
		for k in params:
			var key := str(k)
			if not key.begins_with("parameters/"):
				key = "parameters/" + key
			var cur: Variant = tree.get(key)
			var c := Values.coerce(params[k], typeof(cur) if cur != null else TYPE_NIL)
			if not c[0]:
				return _host._err("%s: %s" % [key, c[1]])
			tree.set(key, c[1])
			updated.append(key)

	var pb_path := str(args.get("playback_path", "parameters/playback"))
	var pb: Variant = tree.get(pb_path)
	var state := ""
	if args.has("start") and str(args["start"]) != "":
		if not (pb is AnimationNodeStateMachinePlayback):
			return _host._err("No AnimationNodeStateMachinePlayback at '%s'." % pb_path)
		pb.start(StringName(str(args["start"])))
		state = str(args["start"])
	elif args.has("travel") and str(args["travel"]) != "":
		if not (pb is AnimationNodeStateMachinePlayback):
			return _host._err("No AnimationNodeStateMachinePlayback at '%s'." % pb_path)
		pb.travel(StringName(str(args["travel"])))
		state = str(args["travel"])

	return {"path": _host._path_of(tree), "active": tree.active, "updated_params": updated, "requested_state": state}


func _tool_build_animation_state_machine(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null: return _host._no_node(args.get("node_path", ""))
	if not (node is AnimationTree):
		return _host._err("%s is %s, not an AnimationTree." % [_host._path_of(node), node.get_class()])
	var states: Variant = args.get("states", [])
	if not (states is Array) or states.is_empty():
		return _host._err("states must be a non-empty array.")

	var sm := AnimationNodeStateMachine.new()
	for i in states.size():
		var st: Variant = states[i]
		if not (st is Dictionary): continue
		var sname := StringName(str(st.get("name", "")))
		var anim := StringName(str(st.get("animation", sname)))
		var anode := AnimationNodeAnimation.new()
		anode.animation = anim
		sm.add_node(sname, anode, Vector2(200 + i * 180, 100))

	var transitions: Variant = args.get("transitions", [])
	var tcount := 0
	if transitions is Array:
		for tr in transitions:
			if not (tr is Dictionary): continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = float(tr.get("xfade_time", 0.1))
			var sw := str(tr.get("switch_mode", "immediate")).to_lower()
			if sw == "sync": t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
			elif sw == "at_end": t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			else: t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			sm.add_transition(StringName(str(tr.get("from", "Start"))), StringName(str(tr.get("to", ""))), t)
			tcount += 1

	var tree := node as AnimationTree
	var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
	ur.create_action("MCP: Build AnimationNodeStateMachine on %s" % tree.name)
	ur.add_do_property(tree, "tree_root", sm)
	ur.add_undo_property(tree, "tree_root", tree.tree_root)
	if bool(args.get("activate", true)):
		ur.add_do_property(tree, "active", true)
		ur.add_undo_property(tree, "active", tree.active)
	ur.commit_action()
	return {"path": _host._path_of(tree), "states": states.size(), "transitions": tcount}


func _tool_setup_blend_space(args: Dictionary) -> Variant:
	var node: Node = _host._find(args.get("node_path", ""))
	if node == null: return _host._no_node(args.get("node_path", ""))
	if not (node is AnimationTree):
		return _host._err("%s is %s, not an AnimationTree." % [_host._path_of(node), node.get_class()])
	var pts: Variant = args.get("points", [])
	if not (pts is Array) or pts.is_empty():
		return _host._err("points must be a non-empty array.")

	var is_2d := bool(args.get("is_2d", false))
	var bs: AnimationRootNode
	if is_2d:
		var b2 := AnimationNodeBlendSpace2D.new()
		var mn := float(args.get("min_space", -1.0))
		var mx := float(args.get("max_space", 1.0))
		b2.min_space = Vector2(mn, mn)
		b2.max_space = Vector2(mx, mx)
		for p in pts:
			if not (p is Dictionary): continue
			var pos_v: Variant = p.get("pos", [0, 0])
			var v2 := Vector2(float(pos_v[0]), float(pos_v[1])) if pos_v is Array and pos_v.size() >= 2 else Vector2.ZERO
			var an := AnimationNodeAnimation.new()
			an.animation = StringName(str(p.get("animation", "")))
			b2.add_blend_point(an, v2)
		bs = b2
	else:
		var b1 := AnimationNodeBlendSpace1D.new()
		b1.min_space = float(args.get("min_space", -1.0))
		b1.max_space = float(args.get("max_space", 1.0))
		for p in pts:
			if not (p is Dictionary): continue
			var an := AnimationNodeAnimation.new()
			an.animation = StringName(str(p.get("animation", "")))
			b1.add_blend_point(an, float(p.get("pos", 0.0)))
		bs = b1

	var tree := node as AnimationTree
	var state_name := str(args.get("state_name", ""))
	if state_name != "" and tree.tree_root is AnimationNodeStateMachine:
		(tree.tree_root as AnimationNodeStateMachine).add_node(StringName(state_name), bs)
	else:
		var ur: EditorUndoRedoManager = _host._plugin.get_undo_redo()
		ur.create_action("MCP: Set BlendSpace on %s" % tree.name)
		ur.add_do_property(tree, "tree_root", bs)
		ur.add_undo_property(tree, "tree_root", tree.tree_root)
		ur.commit_action()
	return {"path": _host._path_of(tree), "type": bs.get_class(), "points": pts.size()}
