@tool
extends RefCounted
## Audio buses, audio stream players, and AudioStreamRandomizer resources.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("list_audio_buses", "List all AudioServer buses, volumes, mute/solo states, routing, and audio effects.", {}, [], true, false)
	_reg("configure_audio_bus", "Add, remove, or configure an AudioServer bus and optionally add an AudioEffect, then save default_bus_layout.tres.", {
		"action": {"type": "string", "description": "set (create if missing), remove, or add_effect. Default set."},
		"name": s,
		"volume_db": {"type": "number"},
		"mute": {"type": "boolean"},
		"solo": {"type": "boolean"},
		"bypass_fx": {"type": "boolean"},
		"send": {"type": "string", "description": "Target bus name, e.g. Master"},
		"effect_type": {"type": "string", "description": "AudioEffect class for add_effect, e.g. AudioEffectReverb, AudioEffectLowPassFilter"},
		"effect_properties": {"type": "object"},
		"save": {"type": "boolean", "description": "Save res://default_bus_layout.tres. Default true."},
	}, ["name"], false, false)
	_reg("setup_audio_player", "Create or configure an AudioStreamPlayer, AudioStreamPlayer2D, or AudioStreamPlayer3D (undoable).", {
		"parent_path": {"type": "string", "description": "Parent node path, default '.'"},
		"type": {"type": "string", "description": "AudioStreamPlayer, AudioStreamPlayer2D, or AudioStreamPlayer3D. Default AudioStreamPlayer."},
		"name": s,
		"stream": {"type": "string", "description": "res:// path to an audio file (.wav, .ogg, .mp3)"},
		"bus": {"type": "string", "description": "Audio bus name, default Master"},
		"volume_db": {"type": "number", "description": "Default 0.0"},
		"autoplay": {"type": "boolean", "description": "Default false"},
	}, [], false, false)
	_reg("create_audio_randomizer", "Create an AudioStreamRandomizer .tres resource from multiple audio files with random pitch/volume variation.", {
		"path": {"type": "string", "description": "res:// path ending in .tres"},
		"streams": {"type": "array", "items": s, "description": "List of res:// audio paths (.wav, .ogg, .mp3)"},
		"random_pitch": {"type": "number", "description": "Pitch variation >= 1.0, default 1.1"},
		"random_volume_offset_db": {"type": "number", "description": "Volume variation in dB, default 1.5"},
	}, ["path", "streams"], false, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _tool_list_audio_buses(_args: Dictionary) -> Variant:
	var buses := []
	for i in AudioServer.bus_count:
		var effects := []
		for e in AudioServer.get_bus_effect_count(i):
			var fx := AudioServer.get_bus_effect(i, e)
			effects.append({
				"index": e,
				"type": fx.get_class(),
				"enabled": AudioServer.is_bus_effect_enabled(i, e),
			})
		buses.append({
			"index": i,
			"name": AudioServer.get_bus_name(i),
			"volume_db": AudioServer.get_bus_volume_db(i),
			"mute": AudioServer.is_bus_mute(i),
			"solo": AudioServer.is_bus_solo(i),
			"bypass_fx": AudioServer.is_bus_bypassing_effects(i),
			"send": AudioServer.get_bus_send(i),
			"effects": effects,
		})
	return {"count": buses.size(), "buses": buses}


func _tool_configure_audio_bus(args: Dictionary) -> Variant:
	var action := str(args.get("action", "set")).to_lower()
	var bus_name := str(args.get("name", ""))
	if bus_name == "":
		return _host._err("name is required.")
	var idx := AudioServer.get_bus_index(bus_name)

	if action == "remove":
		if idx <= 0:
			return _host._err("Cannot remove Master or non-existent bus '%s'." % bus_name)
		AudioServer.remove_bus(idx)
	else:
		if idx == -1:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
		if args.has("volume_db"):
			AudioServer.set_bus_volume_db(idx, float(args["volume_db"]))
		if args.has("mute"):
			AudioServer.set_bus_mute(idx, bool(args["mute"]))
		if args.has("solo"):
			AudioServer.set_bus_solo(idx, bool(args["solo"]))
		if args.has("bypass_fx"):
			AudioServer.set_bus_bypass_effects(idx, bool(args["bypass_fx"]))
		if args.has("send"):
			AudioServer.set_bus_send(idx, StringName(str(args["send"])))
		if action == "add_effect" or args.has("effect_type"):
			var etype := str(args.get("effect_type", ""))
			if not ClassDB.class_exists(etype) or not ClassDB.is_parent_class(etype, "AudioEffect"):
				return _host._err("Invalid AudioEffect class: " + etype)
			var fx: AudioEffect = ClassDB.instantiate(etype)
			var fx_props: Variant = args.get("effect_properties", {})
			if fx_props is Dictionary and not fx_props.is_empty():
				Values.apply_properties(fx, fx_props)
			AudioServer.add_bus_effect(idx, fx)

	var saved := false
	if bool(args.get("save", true)):
		var layout := AudioServer.generate_bus_layout()
		if ResourceSaver.save(layout, "res://default_bus_layout.tres") == OK:
			saved = true
			_host._scan()
	return {"bus": bus_name, "action": action, "saved_layout": saved}


func _tool_setup_audio_player(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null:
		return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null:
		return _host._no_node(args.get("parent_path", "."))
	var ptype := str(args.get("type", "AudioStreamPlayer"))
	if not ptype in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		return _host._err("Invalid audio player type: " + ptype)
	var player: Node = ClassDB.instantiate(ptype)
	player.name = str(args.get("name", ptype))
	if args.has("stream") and str(args["stream"]) != "":
		var sp: String = _host._res_path(args["stream"])
		if sp == "" or not ResourceLoader.exists(sp):
			player.free()
			return _host._err("Audio stream not found: " + str(args["stream"]))
		player.set("stream", load(sp))
	player.set("bus", StringName(str(args.get("bus", "Master"))))
	player.set("volume_db", float(args.get("volume_db", 0.0)))
	player.set("autoplay", bool(args.get("autoplay", false)))
	_host._add_child_undo(parent, player, "MCP: Add %s" % ptype)
	return {"path": _host._path_of(player), "type": ptype}


func _tool_create_audio_randomizer(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not path.ends_with(".tres"):
		return _host._err("path must be a res:// path ending in .tres.")
	var streams: Variant = args.get("streams", [])
	if not (streams is Array) or streams.is_empty():
		return _host._err("streams must be a non-empty array of audio res:// paths.")
	var rand := AudioStreamRandomizer.new()
	rand.random_pitch = maxf(1.0, float(args.get("random_pitch", 1.1)))
	rand.random_volume_offset_db = maxf(0.0, float(args.get("random_volume_offset_db", 1.5)))
	for i in streams.size():
		var sp: String = _host._res_path(streams[i])
		if sp == "" or not ResourceLoader.exists(sp):
			return _host._err("Audio stream not found: " + str(streams[i]))
		var st := load(sp) as AudioStream
		if st == null:
			return _host._err("Not an AudioStream: " + sp)
		rand.add_stream(i, st)
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir): DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(rand, path)
	if err != OK: return _host._err("Failed to save AudioStreamRandomizer: " + error_string(err))
	_host._scan()
	return {"path": path, "streams_count": rand.streams_count}
