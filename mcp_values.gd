@tool
extends RefCounted
## Conversion between JSON values and Godot Variants. Shared by the editor tools and the in-game runtime.

static var _ansi: RegEx
static var _control: RegEx


## Removes ANSI colour codes and control characters that would produce invalid JSON.
static func clean_text(text: String) -> String:
	if _ansi == null:
		_ansi = RegEx.create_from_string("\\x1b\\[[0-9;]*[A-Za-z]")
		_control = RegEx.create_from_string("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f]")
	return _control.sub(_ansi.sub(text, "", true), "", true)


## Builds a new Resource from {"type": "RectangleShape2D", "properties": {"size": "Vector2(32, 32)"}}.
## Returns [ok, resource_or_message].
static func make_resource(spec: Dictionary) -> Array:
	var type_name := str(spec.get("type", ""))
	if not ClassDB.class_exists(type_name) or not ClassDB.is_parent_class(type_name, "Resource") or not ClassDB.can_instantiate(type_name):
		return [false, "'%s' is not a Resource class that can be created" % type_name]
	var res: Resource = ClassDB.instantiate(type_name)
	var props: Variant = spec.get("properties", {})
	if props is Dictionary:
		var r := apply_properties(res, props)
		if not r.is_empty():
			return [false, "%s: %s" % [type_name, "; ".join(r)]]
	return [true, res]


## Sets properties on an object with type coercion. Returns a list of error messages.
static func apply_properties(obj: Object, values: Dictionary) -> Array:
	var types := {}
	for p in obj.get_property_list():
		types[str(p["name"])] = p["type"]
	var errors := []
	for key_v in values:
		var key := str(key_v)
		var base := key.split(":")[0]
		if not types.has(base):
			errors.append("%s: no such property on %s" % [key, obj.get_class()])
			continue
		var indexed := key.contains(":")
		var type: int = typeof(obj.get_indexed(NodePath(key))) if indexed else int(types[key])
		var r := coerce(values[key_v], type)
		if not r[0]:
			errors.append("%s: %s" % [key, r[1]])
		elif indexed:
			obj.set_indexed(NodePath(key), r[1])
		else:
			obj.set(key, r[1])
	return errors


static func to_json(value: Variant, depth := 0) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return value if is_finite(value) else str(value)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_OBJECT:
			if not is_instance_valid(value):
				return null
			if value is Resource:
				if value.resource_path != "":
					return value.resource_path
				return "<%s>" % value.get_class()
			if value is Node:
				return "<Node %s>" % value.name
			return "<%s>" % value.get_class()
		TYPE_ARRAY:
			if depth > 6:
				return "<...>"
			var arr := []
			for item in value:
				arr.append(to_json(item, depth + 1))
			return arr
		TYPE_DICTIONARY:
			if depth > 6:
				return "<...>"
			var dict := {}
			for key in value:
				dict[str(key)] = to_json(value[key], depth + 1)
			return dict
	return var_to_str(value)


## Converts a JSON value to the wanted Variant type. Returns [ok, value_or_message].
static func coerce(value: Variant, type: int) -> Array:
	if value == null:
		return [true, null]
	var vt := typeof(value)
	match type:
		TYPE_NIL:
			if vt == TYPE_STRING:
				var parsed: Variant = _parse_expression(value)
				if parsed != null:
					return [true, parsed]
			return [true, value]
		TYPE_BOOL:
			if vt == TYPE_STRING:
				return [true, value.to_lower() == "true"]
			return [true, bool(value)]
		TYPE_INT:
			if vt == TYPE_STRING and not value.is_valid_int():
				return [false, "expected an integer, got \"%s\"" % value]
			return [true, int(value)]
		TYPE_FLOAT:
			if vt == TYPE_STRING and not value.is_valid_float():
				return [false, "expected a number, got \"%s\"" % value]
			return [true, float(value)]
		TYPE_STRING:
			return [true, str(value)]
		TYPE_STRING_NAME:
			return [true, StringName(str(value))]
		TYPE_NODE_PATH:
			return [true, NodePath(str(value))]
		TYPE_OBJECT:
			if vt == TYPE_DICTIONARY and value.has("type"):
				return make_resource(value)
			if vt != TYPE_STRING:
				return [false, "expected a res:// path, null, or {\"type\": \"ClassName\", \"properties\": {...}} for a new built-in resource"]
			if value == "":
				return [true, null]
			if value.begins_with("res://") or value.begins_with("uid://"):
				if not ResourceLoader.exists(value):
					return [false, "resource not found: " + value]
				return [true, load(value)]
			var obj: Variant = _parse_expression(value)
			if obj is Object:
				return [true, obj]
			return [false, "expected a res:// path, got \"%s\"" % value]

	if vt == TYPE_STRING:
		var parsed: Variant = _parse_expression(value)
		if typeof(parsed) == type:
			return [true, parsed]
		if type == TYPE_COLOR and (Color.html_is_valid(value) or Color.from_string(value, Color(0, 0, 0, 0)) != Color(0, 0, 0, 0)):
			return [true, Color.from_string(value, Color.BLACK)]
		if parsed != null:
			var converted: Variant = type_convert(parsed, type)
			if typeof(converted) == type and type in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_RECT2, TYPE_RECT2I]:
				return [true, converted]
		return [false, "expected %s, e.g. \"%s\"" % [type_string(type), _example(type)]]
	if vt == TYPE_DICTIONARY and type != TYPE_DICTIONARY:
		var parts := []
		for keys in [["x", "y", "z", "w"], ["r", "g", "b", "a"]]:
			if value.has(keys[0]):
				for k in keys:
					if value.has(k):
						parts.append(value[k])
				break
		if not parts.is_empty():
			value = parts
			vt = TYPE_ARRAY
	if vt == TYPE_ARRAY and type != TYPE_ARRAY:
		var all_numbers := true
		for item in value:
			if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
				all_numbers = false
		if all_numbers and type < TYPE_PACKED_BYTE_ARRAY:
			var texts := PackedStringArray()
			for item in value:
				texts.append(str(item))
			var built: Variant = str_to_var("%s(%s)" % [type_string(type), ", ".join(texts)])
			if typeof(built) == type:
				return [true, built]
	var converted: Variant = type_convert(value, type)
	if typeof(converted) == type and (vt == TYPE_ARRAY or vt == TYPE_DICTIONARY or vt == type):
		return [true, converted]
	return [false, "expected %s, e.g. \"%s\"" % [type_string(type), _example(type)]]


static func _example(type: int) -> String:
	match type:
		TYPE_VECTOR2: return "Vector2(10, 20)"
		TYPE_VECTOR2I: return "Vector2i(10, 20)"
		TYPE_VECTOR3: return "Vector3(1, 2, 3)"
		TYPE_VECTOR3I: return "Vector3i(1, 2, 3)"
		TYPE_COLOR: return "Color(1, 0, 0, 1)"
		TYPE_RECT2: return "Rect2(0, 0, 100, 50)"
		TYPE_TRANSFORM2D: return "Transform2D(1, 0, 0, 1, 0, 0)"
		TYPE_QUATERNION: return "Quaternion(0, 0, 0, 1)"
	return type_string(type) + "(...)"


static func _parse_expression(text: String) -> Variant:
	# Accept only "TypeName(...)" / "[...]" / "{...}" / "&..." / "^..." shapes so plain strings stay strings.
	var t := text.strip_edges()
	if t == "":
		return null
	var looks_typed := t.ends_with(")") and t.find("(") > 0 and t.substr(0, t.find("(")).is_valid_identifier()
	if not (looks_typed or t.begins_with("[") or t.begins_with("{") or t.begins_with("&\"") or t.begins_with("^\"")):
		return null
	return str_to_var(t)
