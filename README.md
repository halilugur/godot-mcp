# Local MCP (Godot 4.3+)

Godot editörünün içinde çalışan, tamamen yerel bir MCP sunucusu. Yapay zekâ asistanları
(Claude Code, Claude Desktop, Cursor, VS Code, yerel modeller...) bu sunucu üzerinden
editörünüzü ve çalışan oyununuzu kullanabilir.

- Saf GDScript. Node.js, Python veya ek bir süreç gerekmez.
- Yalnızca `127.0.0.1` adresini dinler. Dışarıya hiçbir bağlantı açmaz, telemetri yoktur.
- 61 araç: sahne/node düzenleme, script yazma ve derleme, kaynaklar, girdi haritası,
  animasyon, tilemap, geri al/yinele, oyunu çalıştırma, oyun içi ekran görüntüsü ve girdi.

## Kurulum

1. `addons/local_mcp` klasörünü projenizin `addons/` klasörüne kopyalayın.
2. Godot'ta **Project > Project Settings > Plugins** sekmesinde **Local MCP**'yi etkinleştirin.
3. Output panelinde şu satırı görmelisiniz:
   `[Local MCP] Listening on http://127.0.0.1:9777/mcp`

Adresi panoya kopyalamak için: **Project > Tools > Local MCP: Copy connection info**.

## Yapay zekâyı bağlama

Sunucu adresi: `http://127.0.0.1:9777/mcp` (Streamable HTTP). Godot açık ve proje yüklü olmalıdır.

**Claude Code**

    claude mcp add --transport http godot http://127.0.0.1:9777/mcp

**Cursor** (`.cursor/mcp.json`) ve HTTP destekleyen diğer istemciler

    {"mcpServers": {"godot": {"url": "http://127.0.0.1:9777/mcp"}}}

**VS Code** (`.vscode/mcp.json`)

    {"servers": {"godot": {"type": "http", "url": "http://127.0.0.1:9777/mcp"}}}

**Claude Desktop ve yalnızca komut (stdio) çalıştırabilen istemciler**

Pakete dahil köprü betiğini kullanın (yalnızca Python 3 standart kütüphanesi):

    {"mcpServers": {"godot": {
      "command": "python3",
      "args": ["/PROJE/YOLU/addons/local_mcp/bridge/stdio_bridge.py"]
    }}}

## Ayarlar (Project Settings > local_mcp)

| Ayar | Varsayılan | Açıklama |
| --- | --- | --- |
| `port` | 9777 | Doluysa sonraki 9 port denenir. `LOCAL_MCP_PORT` ortam değişkeni önceliklidir. |
| `auth_token` | boş | Doldurulursa her istekte `Authorization: Bearer <token>` istenir. |
| `enable_game_runtime` | açık | Oyun içi araçlar için `LocalMcpRuntime` autoload'ını ekler. |

## Araçlar

- **Proje ve dosyalar:** get_project_info, list_files, read_file, write_file, edit_file,
  search_files, create_directory, move_file, delete_file, rescan_filesystem
- **Scriptler:** create_script, attach_script, validate_script
- **Sahneler:** open_scene, create_scene, save_scene, get_scene_tree
- **Node'lar:** add_node, delete_node, move_node, duplicate_node, find_nodes,
  get_node_properties, set_node_properties, set_node_groups, connect_signal
- **Editör:** get_selection, select_nodes, open_in_editor, undo, redo, take_screenshot,
  get_output, execute_editor_script
- **Kaynaklar:** create_resource, get_resource_properties, set_resource_properties
- **Proje ayarları:** get_project_settings, set_project_setting, list_input_actions,
  add_input_action, remove_input_action, add_autoload, remove_autoload
- **API bilgisi:** get_class_info, search_classes
- **Animasyon:** get_animations, set_animation, remove_animation
- **TileMap:** get_tilemap_cells, set_tilemap_cells
- **Çalıştırma:** run_project, stop_project
- **Çalışan oyun:** game_get_scene_tree, game_get_node_properties, game_set_node_properties,
  game_call_method, game_send_input, game_screenshot, game_execute_script, game_resume

## Gizlilik ve güvenlik

- Eklenti yalnızca `127.0.0.1` üzerinde bir TCP dinleyicisi açar; `Host` ve `Origin`
  başlıklarını denetler (tarayıcıdan ve DNS rebinding ile erişim reddedilir).
- Oyun içi araçlar Godot'un kendi editör-oyun hata ayıklama kanalını kullanır; yeni bir
  soket açmaz. `LocalMcpRuntime`, hata ayıklayıcı bağlı değilse (dışa aktarılmış oyun)
  kendini kaldırır.
- `execute_editor_script` ve `game_execute_script` bağlanan yapay zekâya keyfî GDScript
  çalıştırma yetkisi verir. Güvenmediğiniz bir istemciyi bağlamayın; ortak kullanılan bir
  makinede `auth_token` belirleyin.
- Sunucu yerel olsa da, bulut tabanlı bir asistan (Claude, Cursor...) araçlardan okuduğu
  içeriği kendi sağlayıcısına gönderir. Hiçbir verinin çıkmaması için yerel bir model kullanın.

## Notlar

- Sahne değişiklikleri `save_scene` çağrılana kadar bellekte kalır ve Ctrl+Z ile geri alınabilir.
- Godot 4.5+ sürümlerinde script hataları Logger API'siyle, 4.3-4.4'te Output panelinden okunur.
- Oyun bir script hatasında hata ayıklayıcıda durursa oyun araçları bunu bildirir;
  `game_resume` ile devam ettirilebilir.
- TileMap araçları `TileMapLayer` içindir (eski `TileMap` node'u için `execute_editor_script`).
