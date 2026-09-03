# Development workflow

This is a Godot 4 2D game.

Use the connected Godot MCP whenever inspecting or modifying
scene structure, node properties, signals, project settings,
resources, or other editor-owned state.

Prefer Godot MCP scene editing tools over manually editing
.tscn files.

Use normal filesystem editing for GDScript when appropriate.

Before changing an existing scene, inspect its current structure.

Do not launch or visually test the game unless explicitly asked.
The user normally tests gameplay manually.

Do not take screenshots unless explicitly requested.

When making scene changes, preserve existing nodes and user edits
unless the task explicitly requires replacing them.

After substantial GDScript changes, check for parse errors.

## Architecture

Gameplay input should be separated from gameplay commands.

The game is intended to support multiplayer later, so input code
should create semantic commands rather than directly mutate game
state.

Example:

Mouse input
→ PlayerController
→ MoveCommand
→ GameState
→ Units


## Godot MCP usage

The user performs visual and gameplay testing manually.

Do not:
- capture screenshots unless explicitly asked;
- simulate mouse/keyboard input unless explicitly asked;
- repeatedly run the game to visually inspect changes.

Do:
- inspect SceneTree through MCP;
- inspect node properties through MCP;
- create and modify nodes through MCP;
- connect signals through MCP;
- inspect Godot errors after changes when useful.