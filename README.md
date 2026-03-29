# Huebound - Color-Mixing Idle Factory Game

## Overview

Huebound is an abstract geometric idle factory game built with Godot 4.x. Players place colored nodes on a grid, connect them with flowing lines, and discover 256 colors through mixing. No art assets - everything is procedural.

---

## Project Structure

```
idlegame/
├── .godot/                     # Godot configuration files
├── addons/                     # GodotSteam GDExtension
├── export/                     # Full game build output
├── export_demo/                # Demo build output (20 colors only)
├── fonts/                      # Custom font files
├── scenes/                     # Game scene files (.tscn)
│   ├── main_game.tscn         # Main game world
│   └── title_screen.tscn      # Title screen UI
├── shaders/                    # Custom shaders (colorblind filter)
├── scripts/                    # Godot GDScript code
│   ├── autoloads/             # Singletons (auto-loaded)
│   │   ├── color_palette.gd   # 256-color palette + discovery system
│   │   ├── demo_config.gd     # Demo mode flag (IS_DEMO)
│   │   ├── game_state.gd      # Save/load state management
│   │   ├── node_factory.gd    # Node type definitions
│   │   ├── sfx.gd             # Procedural sound effects
│   │   └── steam_manager.gd   # Steam integration
│   ├── connection_line.gd     # Connection wire rendering
│   ├── factory_node.gd        # Base node class (Producer/Processor/Seller/Splitter)
│   ├── grid_drawer.gd         # Background grid
│   ├── main_game.gd           # Main game logic
│   └── settings_ui.gd         # Settings panel
├── steam/                      # Steam integration files
│   ├── build/                 # SteamCMD build configs
│   ├── achievements.vdf       # Achievement definitions
│   └── README_STEAM.md        # Steam setup guide
├── devlog_[1-4].html          # Development logs
├── export_presets.cfg         # Export configuration
├── project.godot              # Godot project settings
└── steam_appid.txt            # Steam App ID: 4459040
```

---

## Core Systems

### 1. Node Types (`node_factory.gd`)

| Type | Shape | Function |
|------|-------|----------|
| **Source** (Blue/Red/Yellow) | Circle | Generates colored orbs |
| **Combiner** | Hexagon | Mixes exactly 2 input colors via recipes |
| **Seller** | Diamond | Sells orbs for currency (Light/$) |
| **Splitter** | Square | Splits one input into two outputs (halved value) |

### 2. Color System (`color_palette.gd`)

- **256 curated colors** across 6 tiers (0-5)
- **Recipe-driven mixing**: Combiner looks up recipes, not free-form mixing
- **Discovery system**: First sale of a new color gives 10x bonus
- **Tier values**: 1, 5, 20, 80, 300, 1000 Light per orb

### 3. Currency & Economy

- **Light ($)**: Primary currency (symbol shown as $ in UI)
- **Node costs**: Escalating via log curve (base * (1 + 0.3 * ln(1 + count)))
- **Sell refunds**: 50% of node cost returned on delete
- **Unlock costs**: Shop purchases to unlock Red/Yellow sources, Combiner, Splitter

### 4. Save System (`game_state.gd`)

- **Save file**: `user://huebound_save.json`
- **Autosave**: Every 30 seconds
- **Web export**: Explicit file.close() + FS.syncfs() for IndexedDB persistence
- **Data stored**: Currency, discovered colors, placed nodes, connections, upgrades

### 5. Demo Mode (`demo_config.gd`)

Controlled by `IS_DEMO` constant:
- **Full game** (`IS_DEMO = false`): All 256 colors, all node types
- **Demo** (`IS_DEMO = true`): Only 20 colors, no Splitter node

Demo colors: Blue, Red, Yellow, Purple, Orange, Green, Rose, Crimson, Vermillion, Amber, Teal, Wine, Rust, Olive, Maroon, Sienna, Ember, Auburn, Blackberry, Paprika

---

## Input Controls

| Action | Control |
|--------|---------|
| Place node | Left click (in place mode) |
| Connect nodes | Drag from output to input |
| Pan camera | Middle click drag / Right click drag |
| Zoom | Mouse wheel |
| Select node | Left click on node |
| Delete node | Select → Delete key |
| Cancel action | Escape |
| Box select | Shift + drag |

---

## Game Loop

1. **Start**: Blue Source available, 50 Light
2. **Unlock**: Buy Red/Yellow sources, Combiner, Splitter in shop
3. **Mix**: Connect sources to Combiner to create new colors
4. **Sell**: Connect output to Seller for currency
5. **Discover**: Each new color sold adds to collection (gallery shows 256-dot grid)
6. **Expand**: Buy more nodes, discover more colors, increase factory efficiency

---

## Steam Integration

- **App ID**: 4459040 (main), 4555340 (demo)
- **Achievements**: first_color, ten_colors, fifty_colors, hundred_colors, all_colors, tier_5, ten_nodes, rich
- **Cloud saves**: Via Steam Auto-Cloud
- **Rich presence**: Basic status

---

## Export Configuration

Single preset `"Steam Windows"` used for both builds:
- **Full game**: Export with `IS_DEMO = false` in `demo_config.gd`
- **Demo**: Toggle `IS_DEMO = true`, export to `export_demo/`

---

## Known Limitations

1. No undo system
2. Single save file
3. Web export: GodotSteam features disabled gracefully

---

## Credits

**Game**: Huebound  
**Engine**: Godot Engine 4.6.1  
**Platform**: Windows (Steam, itch.io), Web (HTML5)
