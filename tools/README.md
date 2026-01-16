# Sprite Atlas Generator

A local tool to generate sprite atlases from FableForge prefab JSON files using the same Replicate API (Flux models) used for character sprite generation.

## Overview

This tool reads prefab JSON files (animals.json, items.json, enemies.json, etc.) and:
1. Extracts all unique tile IDs from the `tileGrid` fields in each prefab
2. Generates images for each unique tile ID using Replicate API with Flux models
3. Creates a sprite atlas (single PNG) with all generated tiles arranged in a grid
4. Outputs metadata JSON file with tile positions for easy integration

## Installation

1. Install Python 3.8 or later
2. Install dependencies:
```bash
cd tools
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Or install directly:
```bash
pip install Pillow requests
```

3. Set up your Replicate API key:
```bash
export REPLICATE_API_KEY="your_api_key_here"
```

Or pass it via command line:
```bash
python generate_sprite_atlas.py --api-key "your_api_key_here"
```

## Quick Start

**Easy way (using wrapper script):**
```bash
./tools/generate_atlas.sh --prefab-file "FableForge Shared/Prefabs/Maps/prefabs_grassland.json" --atlas-png "generated_assets/grasslands_atlas.png"
```
```bash
./tools/generate_atlas.sh --prefab-file "FableForge Shared/Prefabs/Maps/prefabs_grassland.json" --atlas-png "generated_assets/grasslands_atlas.png"
```

```bash
./tools/generate_atlas.sh --prefab-file "FableForge Shared/Prefabs/Maps/prefabs_grassland.json" --atlas-png "FableForge Shared/Assets.xcassets/grasslands_atlas.imageset/grasslands_atlas.png"
```

**Manual way (activate venv first):**
```bash
source tools/venv/bin/activate
python3 tools/generate_sprite_atlas.py --prefab-file "FableForge Shared/Prefabs/items.json" --atlas-png "generated_assets/sprite_atlas.png"
```

## Usage

### Interactive Mode (Default)

The tool runs in interactive mode by default, showing each generated image for approval:

```bash
python generate_sprite_atlas.py
```

This will:
- Read prefab files from `FableForge Shared/Prefabs`
- Generate one tile at a time
- Display each image for your approval
- If you approve (y/yes): removes background and adds to atlas
- If you reject (n/no): regenerates a new image
- Continues until all tiles are approved or skipped

### Non-Interactive Mode

To auto-approve all generated images (useful for batch processing):

```bash
python generate_sprite_atlas.py --no-interactive
```

### Custom Options

```bash
python generate_sprite_atlas.py \
  --prefab-dir "FableForge Shared/Prefabs" \
  --output-dir "generated_assets" \
  --atlas-name "my_atlas.png" \
  --tile-size 32 \
  --limit 10
```

### Generate from Prefab File (New Workflow)

Generate tiles for entities marked with `"tileGrid": [["generate"]]` and automatically update the prefab file:

```bash
python generate_sprite_atlas.py \
  --prefab-file "FableForge Shared/Prefabs/items.json" \
  --atlas-png "generated_assets/sprite_atlas.png"
```

This will:
1. Find all entities with `"tileGrid": [["generate"]]` in the specified prefab file
2. Generate images for each (with approval if interactive)
3. Remove backgrounds
4. Add tiles to the specified atlas PNG
5. Update the prefab JSON file with the generated tile ID (e.g., `"exterior-3000"`)

### Test Parsing (Dry Run)

Test parsing without generating images:

```bash
python generate_sprite_atlas.py --dry-run
```

Or test the prefab file workflow:

```bash
python generate_sprite_atlas.py \
  --prefab-file "FableForge Shared/Prefabs/items.json" \
  --atlas-png "generated_assets/sprite_atlas.png" \
  --dry-run
```

### Command-line Arguments

- `--prefab-dir`: Path to prefab directory (default: `FableForge Shared/Prefabs`)
- `--output-dir`: Output directory for atlas and tiles (default: `generated_assets`)
- `--atlas-name`: Name of output atlas PNG file (default: `sprite_atlas.png`)
- `--tile-size`: Tile size in pixels (default: `32`)
- `--api-key`: Replicate API key (default: reads from REPLICATE_API_KEY environment variable)

## Output

The tool generates:
1. **sprite_atlas.png**: Single PNG file containing all tiles arranged in a grid
2. **sprite_atlas.json**: Metadata file with tile positions, names, and descriptions
3. **tiles/**: Directory containing individual tile PNG files

### Atlas Metadata Format

The `sprite_atlas.json` file contains:
```json
{
  "tile_size": 32,
  "atlas_width": 640,
  "atlas_height": 480,
  "cols": 20,
  "rows": 15,
  "tiles": {
    "exterior-1200": {
      "x": 0,
      "y": 0,
      "width": 32,
      "height": 32,
      "col": 0,
      "row": 0,
      "name": "Wolf",
      "description": "A wild wolf...",
      "type": "animal"
    },
    ...
  }
}
```

## How It Works

1. **Tile Extraction**: Scans all prefab JSON files and extracts unique tile IDs from the `tileGrid` arrays in each prefab's `parts`
2. **Prompt Generation**: For each tile ID, creates a prompt using the prefab's `name` and `description` fields, tailored to the entity type (animal, item, enemy, etc.)
3. **Image Generation**: Uses Replicate API with Flux-dev model to generate images matching your game's tile style
4. **Interactive Approval**: (In interactive mode) Shows each generated image and waits for approval
5. **Background Removal**: For approved images, removes background using Replicate's rembg model (same as character sprites)
6. **Atlas Assembly**: Arranges all approved tiles in a grid and saves as a single PNG file
7. **Incremental Updates**: Can add new tiles to existing atlas without regenerating everything

## Notes

- The tool requires a Replicate API key set via the `REPLICATE_API_KEY` environment variable or `--api-key` argument
- Uses the same Replicate API and Flux models as your Swift `SpriteGenerationService`
- Background removal uses the same `cjwbw/rembg` model as character sprite generation
- Generated images are created at 128x128 pixels initially, then resized to the specified tile size for better quality
- Rate limiting: Includes delays between API calls to be respectful to the API
- Failed generations are skipped (you'll see error messages), but the atlas will still be created with successfully generated tiles
- The atlas is incremental: running the tool again will add new tiles to the existing atlas without regenerating approved ones
- In interactive mode, you can reject up to 10 attempts per tile before it's skipped

## Prefab Properties Reference

### Entity-Level Properties

- **`tileMap`** (string, optional): Specifies the layout for image generation. Format: comma-separated numbers like `"2,3,1"` meaning:
  - Row 1: 2 tiles wide
  - Row 2: 3 tiles wide
  - Row 3: 1 tile wide
  - The tool will generate an image matching this layout and automatically create the `parts` structure
  - If not provided, uses existing `parts` with `tileGrid` containing `"generate"`

- **`size`** (object): Overall entity size in pixels. Used for bounding box calculations and entity placement.

- **`collision`** (object): **This is for the collision box**, separate from visual rendering:
  - `type`: "rectangle", "circle", or "none"
  - `size`: Collision box dimensions (can be different from visual `size`)

- **`zPosition`** (number): Base z-position for rendering order (higher = rendered on top)

- **`zOffset`** (number): Additional z-offset applied to all parts

- **`tileSize`** (number): Default tile size for the entity (defaults to 16px if 0)

### Part-Level Properties (in `parts` array)

Each part represents a visual layer of the entity:

- **`layer`** (string): Rendering layer - `"low"` (rendered below player) or `"high"` (rendered above player)

- **`tileGrid`** (2D array): Grid of tile IDs referencing tiles in the atlas. Format: `[["tile-id-1", "tile-id-2"], ["tile-id-3", "tile-id-4"]]`
  - Each row is an array of tile IDs
  - Use `null` for empty spaces
  - Use `"generate"` to mark tiles that need generation (legacy method)
  - Tile IDs reference atlas frames like `"atlas_name-1"`, `"atlas_name-2"`, etc.

- **`offset`** (object): **Position offset for sprite rendering** (NOT collision):
  - `x`, `y`: Offset in pixels from entity center (for single-tile) or top-left corner (for multi-tile)
  - Used to position sprites correctly when rendering
  - Example: `{"x": -16, "y": 0}` shifts the sprite 16 pixels left

- **`size`** (object): **Visual rendering size** (NOT collision):
  - `width`, `height`: Size in pixels for sprite rendering
  - For single-tile parts: usually matches tile size (e.g., 16x16, 32x32)
  - For multi-tile parts: bounding box size (e.g., 64x64 for a 2x2 grid)
  - This determines how large the sprite appears on screen

- **`tileSize`** (number): Size of individual tiles in the grid in pixels
  - Defaults to 16px if 0
  - Used to calculate spacing between tiles in multi-tile grids
  - Example: For a 2x2 grid with `tileSize: 16`, tiles are spaced 16 pixels apart

- **`zOffset`** (number): Z-offset relative to the entity's base z-position
  - Allows fine-tuning rendering order within the same layer

- **`assetName`** (string, optional): Asset catalog name that overrides `tileGrid` GID if provided
  - If set, uses this asset instead of looking up tiles from atlas
  - Useful for special cases where you want to use a specific asset image

### Layer Splitting Rules

When using `tileMap`, the tool automatically splits into layers:
- **1-2 rows**: Single `"low"` layer
- **3+ rows**: First 2 rows = `"low"` layer, remaining rows = `"high"` layer

This ensures proper rendering order (base below player, top parts above player).

## Troubleshooting

- **No images generated**: Check your Replicate API key and account balance
- **Images don't match tile style**: The prompt might need adjustment - modify the `build_prompt_for_tile` method in the script
- **Missing tiles**: Some prefabs might reference tiles that don't exist yet - check console output for warnings
- **Wrong tile size**: Default is 16px. Use `--tile-size` to change it, or set `tileSize` in the prefab