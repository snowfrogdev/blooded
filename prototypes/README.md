# Prototypes Folder

This folder contains experimental features, mechanics testing, and asset evaluation for the Blooded game project.

## Purpose

Prototypes are self-contained experiments that live separately from the main game. Use this space to:
- Test new gameplay mechanics and features
- Experiment with different approaches to problems
- Evaluate third-party addons and assets
- Rapidly iterate on ideas without affecting production code

## Organization Philosophy: Feature-Based

This project follows **feature-based organization**, not layer-based. Each prototype is a self-contained feature folder with its own scenes, scripts, and assets.

**Good** (Feature-based):
```
prototypes/
├── combat_system/
│   ├── combat_test.tscn
│   ├── player_combat.gd
│   └── assets/
│       └── sprites/
│           └── sword.png
```

**Bad** (Layer-based):
```
prototypes/
├── scenes/
│   └── combat_test.tscn
├── scripts/
│   └── player_combat.gd
└── assets/
    └── sprites/
        └── sword.png
```

**Why?** Feature-based organization keeps related files together and makes it easy to delete experiments cleanly.

## The Deletion Test

A well-organized prototype should pass this test:

> **"If I delete this prototype folder, does anything else break?"**

The answer should always be **NO**. If deleting a prototype breaks other prototypes or the main game, something is wrong with the organization.

## Folder Structure

```
prototypes/
├── README.md                    # This file
├── common/                      # Shared assets (created when needed)
│   ├── audio/                   # Only for assets used by 3+ prototypes
│   ├── sprites/
│   └── shaders/
├── [feature_name]/              # Your prototype experiments
│   ├── [feature].tscn          # Main scene
│   ├── [feature].gd            # Scripts
│   └── assets/                  # Assets specific to this prototype
│       ├── sprites/
│       ├── audio/
│       └── textures/
└── docs/                        # Notes and documentation
    ├── .gdignore                # Prevents Godot from importing docs
    └── [your_notes].md
```

## The "Rule of Three" for Shared Assets

Don't prematurely move assets to `common/`. Follow this progression:

1. **First use**: Asset stays in the feature folder where it's created
   - Example: `prototypes/combat_system/assets/audio/sword_swing.wav`

2. **Second use**: Asset still lives in the "primary owner" folder
   - The second prototype just references it: `res://prototypes/combat_system/assets/audio/sword_swing.wav`
   - Why? Two uses might be coincidental

3. **Third use**: NOW move to `common/` since it's genuinely shared
   - Move to: `prototypes/common/audio/sword_swing.wav`
   - Update all references in the three prototypes

**Why wait?** Premature abstraction creates unnecessary complexity. It's better to have slight duplication than premature generalization.

## Naming Conventions

Follow Godot's snake_case convention for all files and folders:

- **Folders**: `snake_case` (e.g., `combat_system`, `inventory_prototype`, `ai_experiment`)
- **Scenes**: `snake_case.tscn` (e.g., `combat_test.tscn`, `player_movement.tscn`)
- **Scripts**: `snake_case.gd` (e.g., `enemy_ai.gd`, `inventory_manager.gd`)
- **Assets**: `snake_case.png/wav/etc` (e.g., `player_sprite.png`, `sword_swing.wav`)

**No prefixes needed** - the `prototypes/` folder itself provides the context that these are experiments.

## Keeping Prototypes Isolated

### Path Rules
- ✅ **DO** use paths within prototypes: `res://prototypes/combat_system/assets/sprite.png`
- ✅ **DO** reference other prototypes if needed: `res://prototypes/other_prototype/script.gd`
- ❌ **DON'T** reference main project files from prototypes
- ❌ **DON'T** reference prototype files from main project

### Why Isolation Matters
Prototypes are experiments. They should be easy to delete, modify, or abandon without affecting the main game. If prototypes become dependencies, they cease to be experiments.

## Evaluating Third-Party Addons

**Important**: Godot only recognizes plugins at `res://addons/`. You cannot put addons in `prototypes/addons/` and have them work.

### Workflow for Addon Evaluation

1. **Install to root addons folder**
   - Place addon in `res://addons/` as normal
   - Enable in Project → Project Settings → Plugins

2. **Document in prototypes/docs/**
   - Create `prototypes/docs/addons_evaluated.md`
   - Track which addons you're testing
   - Note which prototypes use which addons
   - Record your evaluation (keeping, removing, undecided)

3. **Enable/disable as needed**
   - Use Project Settings → Plugins to toggle addons on/off
   - Disable unused addons to keep the editor clean

4. **Clean up after evaluation**
   - Remove unsuccessful addons from `res://addons/`
   - Update your documentation

5. **Consider .gitignore for temporary addons**
   - If testing many addons, add specific paths to `.gitignore`
   - Example: `addons/experimental_plugin/`

**Why can't addons live in prototypes/?** Godot's plugin system only scans `res://addons/` for `plugin.cfg` files at startup. This is a Godot limitation, not a choice.

## Creating a New Prototype

1. **Create a feature folder**
   ```bash
   prototypes/my_new_feature/
   ```

2. **Add your main scene**
   ```bash
   prototypes/my_new_feature/my_new_feature.tscn
   ```

3. **Add scripts as needed**
   ```bash
   prototypes/my_new_feature/player_controller.gd
   prototypes/my_new_feature/enemy_spawner.gd
   ```

4. **Create an assets folder for feature-specific assets**
   ```bash
   prototypes/my_new_feature/assets/
   prototypes/my_new_feature/assets/sprites/
   prototypes/my_new_feature/assets/audio/
   ```

5. **Document your experiment** (optional but recommended)
   ```bash
   prototypes/docs/my_new_feature_notes.md
   ```

## Graduating Prototypes to Production

When a prototype succeeds and you're ready to move it to the main game:

### 1. Create Main Project Structure (if needed)

If this is your first graduated prototype, consider this structure for the main game:

```
project_root/
├── common/              # Shared assets (music, UI sounds, fonts, shaders)
├── autoloads/           # Singleton managers (GameManager, AudioManager)
├── player/              # Everything player-related
├── enemies/             # Enemy types and AI
├── levels/              # Level scenes and level-specific assets
├── ui/                  # UI scenes and components
└── prototypes/          # Experimental features (this folder)
```

This mirrors the feature-based approach you're already using in prototypes.

### 2. Review and Refactor

Before moving code to production:
- Remove debug/test code
- Add proper error handling
- Follow production naming conventions
- Add documentation comments where logic isn't self-evident
- Ensure code quality is production-ready

### 3. Move Files to Appropriate Locations

- **Scenes** → Relevant feature folder or `levels/`
- **Scripts** → With their scenes (feature-based) or `autoloads/` if global
- **Assets** → With their scenes, or `common/` if used by 3+ features

### 4. Update All Resource Paths

Search and replace paths in your scenes and scripts:
- **From**: `res://prototypes/combat_system/assets/sword.png`
- **To**: `res://player/weapons/sword.png`

Use Godot's "Find in Files" (Ctrl+Shift+F) to find all references.

### 5. Test Thoroughly

After moving files:
- Run the game and test the feature
- Check for missing resource errors in the console
- Verify all paths are updated correctly

### 6. Delete the Prototype Folder

Once you've confirmed everything works:
- Delete the prototype folder: `prototypes/combat_system/`
- Run `git status` to see the changes
- Commit with a message like: "Graduate combat system from prototype to production"

### 7. Document in Main Project

Add documentation about the new feature to your main project docs (if you have them).

## Example Prototype Structure

Here's what a mature prototypes folder might look like:

```
prototypes/
├── README.md
├── common/                          # Only created when genuinely needed
│   ├── audio/
│   │   └── ui_click.wav            # Used by 3+ UI prototypes
│   └── sprites/
│       └── placeholder_32x32.png   # Generic test sprite
├── combat_system/
│   ├── combat_test.tscn
│   ├── player_combat.gd
│   ├── enemy_ai.gd
│   └── assets/
│       ├── sprites/
│       │   ├── sword.png
│       │   └── enemy_goblin.png
│       └── audio/
│           └── sword_swing.wav
├── inventory_prototype/
│   ├── inventory.tscn
│   ├── inventory_ui.gd
│   ├── item.gd
│   └── assets/
│       └── sprites/
│           ├── item_potion.png
│           ├── item_sword.png
│           └── inventory_bg.png
├── dialogue_system/
│   ├── dialogue_test.tscn
│   ├── dialogue_manager.gd
│   ├── dialogue_box.gd
│   └── assets/
│       └── fonts/
│           └── dialogue_font.ttf
└── docs/
    ├── .gdignore
    ├── combat_notes.md
    ├── inventory_decisions.md
    ├── dialogue_research.md
    └── addons_evaluated.md
```

## Best Practices Summary

1. ✅ **One prototype = one folder** - Keep experiments self-contained
2. ✅ **Assets with scenes** - Keep assets close to the code that uses them
3. ✅ **Apply deletion test** - Can you delete the folder without breaking anything?
4. ✅ **Use snake_case** - Follow Godot naming conventions
5. ✅ **Rule of Three** - Wait until 3+ uses before promoting to `common/`
6. ✅ **Isolate prototypes** - Don't reference main project from prototypes
7. ✅ **Document experiments** - Write notes in `prototypes/docs/`
8. ✅ **Graduate successful prototypes** - Move proven features to main project
9. ✅ **Delete failed experiments** - Don't be afraid to delete what doesn't work
10. ✅ **Keep common/ small** - Resist premature abstraction

## Questions?

If you're unsure whether something belongs in `prototypes/` vs the main project:

- **Prototypes**: Experiments, untested ideas, temporary code, evaluation of addons
- **Main Project**: Production-ready code, proven features, stable implementations

When in doubt, start in prototypes. It's easier to graduate a prototype than to demote production code.

## Future Recommendations

As the project grows, consider:
- **Archive old prototypes**: Create `prototypes/archive/2026-01/` for abandoned experiments
- **Template scenes**: Create `prototypes/_templates/` with boilerplate scenes and scripts
- **Documentation index**: Maintain `prototypes/docs/INDEX.md` listing all active prototypes

---

Happy prototyping! 🎮
