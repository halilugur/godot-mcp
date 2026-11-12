# godot-mcp Agent Guide

This guide helps any AI coding agent work reliably and efficiently with `godot-mcp` (180 tools across 15 categories).

## Core Workflow Rules

1. **Discover tools by category or keyword**: Call `discover_tools` with `category` (`project`, `filesystem`, `scene`, `node`, `script`, `editor`, `resource`, `visual`, `ui`, `animation`, `audio`, `tilemap_world`, `physics_nav`, `runtime`, `toolkit`) or `query` (e.g. `shader`, `collision`, `csg`, `tilemap`, `game_`) before assuming a capability is missing. This is especially important when `local_mcp/compact_mode` is enabled.
2. **Prefer batch operations**:
   - Use `batch_add_nodes` to create full node hierarchies in one undoable step.
   - Use `batch_set_properties` and `batch_connect_signals` for multi-node edits.
3. **Validate scripts before running**:
   - After creating or editing `.gd` files (`write_file`, `edit_file`, `create_script`), always call `validate_all_scripts` to catch parse or type-inference errors before launching the game.
   - In GDScript, explicitly type untyped node method returns (e.g. `var hit: KinematicCollision2D = $Ball.move_and_collide(...)`).
4. **Set `main_scene` after creating the scene**:
   - Do not write `application/run/main_scene` to `project.godot` before the `.tscn` file exists on disk; create and save the scene first, then call `set_project_setting`.
5. **Use exact parameter names**:
   - `create_shader`: `path`, `shader_type` (`canvas_item`, `spatial`, `particles`, `sky`, `fog`), `code`, `attach_to`
   - `setup_world_environment`: `node_path`, `preset` (`sky_3d`, `dark_3d`, `canvas_glow`), `properties`, `add_sun`
   - `setup_collision_shape`: `node_path`, `shape` (`rectangle`, `circle`, `capsule`, `box`, `sphere`, etc.), `size` / `radius` / `height`
   - `create_stylebox`: `node_path`, `theme_type` (`normal`, `hover`, `pressed`, `panel`), `bg_color`, `border_color`, `border_width`, `corner_radius`
   - `game_eval_expression`: `expression`

## Live Playtest Loop

1. Start the game with `run_project` (`mode: "main"` or `mode: "custom"` with `scene_path`).
2. Wait briefly for `LocalMcpRuntime` to connect, then query `game_get_ui_elements` (`interactive_only: true`) to get exact button `center` coordinates.
3. Drive gameplay via `game_send_input` (`action`, `key`, `mouse_button`, `mouse_motion`) and `game_step_frames`.
4. Inspect state with `game_get_scene_tree`, `game_get_node_properties`, `game_get_physics_info`, `game_get_performance_monitors`, and `game_screenshot`.
5. Read logs with `get_output` (`source: "game"`) and finish with `stop_project`.
