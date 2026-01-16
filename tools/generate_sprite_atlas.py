#!/usr/bin/env python3
"""
Sprite Atlas Generator for FableForge
Generates sprite atlases from prefab JSON files using Replicate API (Flux models)
"""

import json
import os
import sys
import argparse
import time
import base64
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set
from collections import defaultdict
from PIL import Image, ImageDraw
import requests
from io import BytesIO
import tempfile
import subprocess

# Replicate API configuration
# API key is read from REPLICATE_API_KEY environment variable
# You can set it with: export REPLICATE_API_KEY="your_key_here"
REPLICATE_API_KEY = os.getenv("REPLICATE_API_KEY")
REPLICATE_BASE_URL = "https://api.replicate.com/v1"

# Default tile size (matches your game's tile size)
DEFAULT_TILE_SIZE = 16

# Model names
FLUX_DEV_MODEL = "black-forest-labs/flux-dev"
FLUX_2_PRO_MODEL = "black-forest-labs/flux-2-pro"


class SpriteAtlasGenerator:
    def __init__(self, api_key: str, tile_size: int = DEFAULT_TILE_SIZE):
        self.api_key = api_key
        self.tile_size = tile_size
        self.cached_model_versions = {}
        
    def get_model_version(self, model_name: str) -> Optional[str]:
        """Fetch the latest version hash for a model from Replicate API"""
        if model_name in self.cached_model_versions:
            return self.cached_model_versions[model_name]
        
        url = f"{REPLICATE_BASE_URL}/models/{model_name}"
        headers = {
            "Authorization": f"Token {self.api_key}",
            "Content-Type": "application/json"
        }
        
        try:
            response = requests.get(url, headers=headers, timeout=30)
            if response.status_code == 200:
                data = response.json()
                if isinstance(data.get("latest_version"), str):
                    version = data["latest_version"]
                elif isinstance(data.get("latest_version"), dict):
                    version = data["latest_version"].get("id")
                else:
                    print(f"❌ No latest_version found for {model_name}")
                    return None
                
                self.cached_model_versions[model_name] = version
                print(f"✅ Got version for {model_name}: {version}")
                return version
            else:
                print(f"❌ Failed to fetch model version for {model_name}: Status {response.status_code}")
                return None
        except Exception as e:
            print(f"❌ Error fetching model version for {model_name}: {e}")
            return None
    
    def generate_image_text_to_image(self, prompt: str, negative_prompt: str = "", size: int = 128, width: int = None, height: int = None) -> Optional[Image.Image]:
        """Generate image using Replicate's Flux-dev text-to-image API"""
        version_hash = self.get_model_version(FLUX_DEV_MODEL)
        if not version_hash:
            return None
        
        url = f"{REPLICATE_BASE_URL}/predictions"
        headers = {
            "Authorization": f"Token {self.api_key}",
            "Content-Type": "application/json"
        }
        
        # Prompt is already complete from build_prompt_for_tile
        full_prompt = prompt
        
        # Calculate resolution and aspect ratio based on dimensions
        if width and height:
            # Use actual dimensions for multi-tile sprites
            actual_width = width
            actual_height = height
        else:
            # Default to square for single tiles
            actual_width = size
            actual_height = size
        
        # Calculate resolution in megapixels (rough estimate)
        total_pixels = actual_width * actual_height
        if total_pixels >= 1000000:  # 1 MP or more
            resolution = f"{total_pixels / 1000000:.1f} MP"
        elif total_pixels >= 500000:  # 0.5 MP
            resolution = "0.5 MP"
        else:
            resolution = "1 MP"  # Minimum
        
        # Calculate aspect ratio
        gcd = self._gcd(actual_width, actual_height)
        aspect_w = actual_width // gcd
        aspect_h = actual_height // gcd
        # Limit aspect ratio to reasonable values (max 4:1 or 1:4)
        if aspect_w > 4 * aspect_h:
            aspect_w = 4
            aspect_h = 1
        elif aspect_h > 4 * aspect_w:
            aspect_w = 1
            aspect_h = 4
        aspect_ratio = f"{aspect_w}:{aspect_h}"
        
        input_params = {
            "prompt": full_prompt,
            "resolution": resolution,
            "aspect_ratio": aspect_ratio,
            "output_format": "png",
            "output_quality": 100,
            "seed": int(time.time()) % (2**31)
        }
        
        if negative_prompt:
            input_params["negative_prompt"] = negative_prompt
        
        request_body = {
            "version": version_hash,
            "input": input_params
        }
        
        try:
            # Create prediction
            response = requests.post(url, headers=headers, json=request_body, timeout=120)
            if response.status_code != 201:
                print(f"❌ Failed to create prediction: Status {response.status_code}")
                print(f"Response: {response.text[:500]}")
                return None
            
            prediction = response.json()
            prediction_id = prediction.get("id")
            if not prediction_id:
                print("❌ No prediction ID in response")
                return None
            
            print(f"✅ Prediction created: {prediction_id}")
            
            # Poll for completion
            return self.poll_prediction(prediction_id)
            
        except Exception as e:
            print(f"❌ Error generating image: {e}")
            return None
    
    def remove_background(self, image: Image.Image) -> Optional[Image.Image]:
        """Remove background from image using Replicate rembg model"""
        # Convert image to bytes
        img_bytes = BytesIO()
        image.save(img_bytes, format='PNG')
        img_bytes.seek(0)
        image_data = img_bytes.getvalue()
        
        # Convert to base64
        base64_image = base64.b64encode(image_data).decode('utf-8')
        image_data_uri = f"data:image/png;base64,{base64_image}"
        
        # Get model version
        model_name = "cjwbw/rembg"
        version_hash = self.get_model_version(model_name)
        if not version_hash:
            # Fallback to known working version
            version_hash = "fb8af171cfa1616dcf4f220882e77ab2a5bf03f29d7a49fd2919bc30e5e5d94b"
        
        url = f"{REPLICATE_BASE_URL}/predictions"
        headers = {
            "Authorization": f"Token {self.api_key}",
            "Content-Type": "application/json"
        }
        
        input_params = {
            "image": image_data_uri,
            "alpha_matting": True,
            "alpha_matting_foreground_threshold": 200,
            "alpha_matting_background_threshold": 20,
            "alpha_matting_erode_size": 15
        }
        
        request_body = {
            "version": version_hash,
            "input": input_params
        }
        
        try:
            # Create prediction
            response = requests.post(url, headers=headers, json=request_body, timeout=60)
            if response.status_code != 201:
                print(f"❌ Failed to create background removal prediction: Status {response.status_code}")
                return None
            
            prediction = response.json()
            prediction_id = prediction.get("id")
            if not prediction_id:
                print("❌ No prediction ID in background removal response")
                return None
            
            print("   🎨 Removing background...")
            
            # Poll for completion
            return self.poll_prediction(prediction_id, max_attempts=60, poll_interval=2)
            
        except Exception as e:
            print(f"❌ Error removing background: {e}")
            return None
    
    def show_image_for_approval(self, image: Image.Image, tile_id: str, tile_info: Dict) -> bool:
        """Display image and get user approval"""
        print(f"\n{'='*60}")
        print(f"Tile: {tile_id}")
        print(f"Name: {tile_info.get('name', 'Unknown')}")
        print(f"Type: {tile_info.get('type', 'unknown')}")
        print(f"Description: {tile_info.get('description', 'No description')[:100]}")
        print(f"{'='*60}")
        
        # Save to temp file and open it
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
            image.save(tmp.name)
            tmp_path = tmp.name
        
        try:
            # Try to open image with system default viewer
            if sys.platform == "darwin":  # macOS
                subprocess.run(["open", tmp_path])
            elif sys.platform == "linux":
                subprocess.run(["xdg-open", tmp_path])
            elif sys.platform == "win32":
                os.startfile(tmp_path)
            else:
                # Fallback: just save and tell user to view it
                print(f"   Image saved to: {tmp_path}")
        except Exception as e:
            print(f"   Could not open image automatically: {e}")
            print(f"   Image saved to: {tmp_path}")
        
        # Get user input
        while True:
            response = input("\nApprove this image? (y/n/yes/no): ").strip().lower()
            if response in ['y', 'yes']:
                # Clean up temp file
                try:
                    os.unlink(tmp_path)
                except:
                    pass
                return True
            elif response in ['n', 'no']:
                # Clean up temp file
                try:
                    os.unlink(tmp_path)
                except:
                    pass
                return False
            else:
                print("Please enter 'y'/'yes' to approve or 'n'/'no' to reject")
    
    def poll_prediction(self, prediction_id: str, max_attempts: int = 120, poll_interval: int = 2) -> Optional[Image.Image]:
        """Poll for prediction completion"""
        url = f"{REPLICATE_BASE_URL}/predictions/{prediction_id}"
        headers = {
            "Authorization": f"Token {self.api_key}",
            "Content-Type": "application/json"
        }
        
        for attempt in range(max_attempts):
            try:
                response = requests.get(url, headers=headers, timeout=30)
                if response.status_code != 200:
                    print(f"❌ Failed to poll prediction: Status {response.status_code}")
                    return None
                
                prediction = response.json()
                status = prediction.get("status")
                
                if status == "succeeded":
                    output_url = prediction.get("output")
                    if not output_url:
                        print("❌ No output URL in successful prediction")
                        return None
                    
                    # Download the image
                    if isinstance(output_url, list) and len(output_url) > 0:
                        output_url = output_url[0]
                    
                    print(f"✅ Prediction completed, downloading image from {output_url}")
                    img_response = requests.get(output_url, timeout=60)
                    if img_response.status_code == 200:
                        return Image.open(BytesIO(img_response.content))
                    else:
                        print(f"❌ Failed to download image: Status {img_response.status_code}")
                        return None
                
                elif status == "failed":
                    error = prediction.get("error", "Unknown error")
                    print(f"❌ Prediction failed: {error}")
                    return None
                
                elif status in ["starting", "processing"]:
                    print(f"⏳ Prediction {status}... (attempt {attempt + 1}/{max_attempts})")
                    time.sleep(poll_interval)
                else:
                    print(f"⚠️ Unknown prediction status: {status}")
                    time.sleep(poll_interval)
                    
            except Exception as e:
                print(f"❌ Error polling prediction: {e}")
                time.sleep(poll_interval)
        
        print(f"❌ Prediction timed out after {max_attempts * poll_interval} seconds")
        return None
    
    def parse_prefab_file(self, file_path: Path) -> List[Dict]:
        """Parse a prefab JSON file and extract entities"""
        with open(file_path, 'r') as f:
            data = json.load(f)
        
        entities = []
        # Handle different prefab file structures
        if "animals" in data:
            for animal in data["animals"]:
                entities.append({"type": "animal", **animal})
        elif "items" in data:
            for item in data["items"]:
                entities.append({"type": "item", **item})
        elif "enemies" in data:
            for enemy in data["enemies"]:
                entities.append({"type": "enemy", **enemy})
        elif "npcs" in data:
            for npc in data["npcs"]:
                entities.append({"type": "npc", **npc})
        else:
            # Try to find any array at the top level
            for key, value in data.items():
                if isinstance(value, list):
                    for entity in value:
                        entities.append({"type": key.rstrip('s'), **entity})
        
        return entities
    
    def find_entities_needing_generation(self, prefab_file: Path) -> List[Dict]:
        """Find entities in a prefab file that have 'generate' in their tileGrid"""
        entities_needing_gen = []
        
        with open(prefab_file, 'r') as f:
            data = json.load(f)
        
        # Handle different prefab file structures - support all entity types
        entity_list = []
        if "animals" in data:
            entity_list = [(data["animals"], "animal")]
        if "items" in data:
            entity_list.append((data["items"], "item"))
        if "enemies" in data:
            entity_list.append((data["enemies"], "enemy"))
        if "npcs" in data:
            entity_list.append((data["npcs"], "npc"))
        if "skills" in data:
            entity_list.append((data["skills"], "skill"))
        if "chests" in data:
            entity_list.append((data["chests"], "chest"))
        if "prefabs" in data:
            # Map JSON files have a "prefabs" array
            entity_list.append((data["prefabs"], "prefab"))
        
        # If no standard keys found, try to find any array at the top level
        if not entity_list:
            for key, value in data.items():
                if isinstance(value, list):
                    entity_list.append((value, key.rstrip('s')))
        
        if not entity_list:
            print(f"   ⚠️ No entity arrays found in {prefab_file.name}")
            return entities_needing_gen
        
        for entities, entity_type in entity_list:
            print(f"   🔍 Checking {len(entities)} {entity_type} entities...")
            for idx, entity in enumerate(entities):
                # Check if entity has "tileMap" property at entity level
                tile_map_str = entity.get("tileMap", None)
                has_tile_map = tile_map_str is not None and str(tile_map_str).strip() != ""
                
                # Also check if any part has "tileMap" or "generate" in tileGrid
                needs_generation = False
                part_with_generate = None
                part_tile_map = None
                parts = entity.get("parts", [])
                
                if parts:
                    for part_idx, part in enumerate(parts):
                        # Check for tileMap in part
                        part_tile_map_str = part.get("tileMap", None)
                        if part_tile_map_str is not None and str(part_tile_map_str).strip() != "":
                            has_tile_map = True
                            tile_map_str = part_tile_map_str
                            part_with_generate = part_idx
                            break
                        
                        # Check for "generate" in tileGrid (legacy support)
                        tile_grid = part.get("tileGrid", [])
                        if not tile_grid:
                            continue
                            
                        for row in tile_grid:
                            if not isinstance(row, list):
                                continue
                            for tile_id in row:
                                # Check for "generate" (case-insensitive, handles string or exact match)
                                if tile_id and (tile_id == "generate" or (isinstance(tile_id, str) and tile_id.lower() == "generate")):
                                    needs_generation = True
                                    part_with_generate = part_idx
                                    break
                            if needs_generation:
                                break
                        if needs_generation:
                            break
                
                if has_tile_map or needs_generation:
                    entity_id = entity.get("id", f"entity_{idx}")
                    entity_name = entity.get("name", entity.get("id", "Unknown"))
                    reason = "tileMap" if has_tile_map else "generate in tileGrid"
                    print(f"   ✅ Found entity needing generation: {entity_name} (id: {entity_id}, type: {entity_type}) - {reason}")
                    entities_needing_gen.append({
                        "entity": entity,
                        "entity_index": idx,
                        "part_index": part_with_generate if (needs_generation or has_tile_map) else None,
                        "entity_type": entity_type,
                        "prefab_file": prefab_file,
                        "tile_map": tile_map_str if has_tile_map else None
                    })
        
        return entities_needing_gen
    
    
    def parse_tile_map(self, tile_map_str: str) -> List[int]:
        """Parse tileMap string like '2,3,1' into list of tile counts per row"""
        try:
            return [int(x.strip()) for x in str(tile_map_str).split(',') if x.strip()]
        except Exception as e:
            print(f"   ⚠️ Error parsing tileMap '{tile_map_str}': {e}")
            return [1]  # Default to single tile
    
    def update_prefab_with_tile_map(self, entity_info: Dict, tile_map_layout: List[List[str]], prefab_file: Path, tile_size: int = 16):
        """Update the prefab JSON file with tileMap-generated parts structure"""
        with open(prefab_file, 'r') as f:
            data = json.load(f)
        
        # Find the entity in the data structure
        entity_list_key = None
        entity_list = None
        
        # Handle all entity types
        if "animals" in data:
            entity_list_key = "animals"
            entity_list = data["animals"]
        elif "items" in data:
            entity_list_key = "items"
            entity_list = data["items"]
        elif "enemies" in data:
            entity_list_key = "enemies"
            entity_list = data["enemies"]
        elif "npcs" in data:
            entity_list_key = "npcs"
            entity_list = data["npcs"]
        elif "skills" in data:
            entity_list_key = "skills"
            entity_list = data["skills"]
        elif "chests" in data:
            entity_list_key = "chests"
            entity_list = data["chests"]
        elif "prefabs" in data:
            entity_list_key = "prefabs"
            entity_list = data["prefabs"]
        else:
            for key, value in data.items():
                if isinstance(value, list):
                    entity_list_key = key
                    entity_list = value
                    break
        
        if not entity_list or entity_info["entity_index"] >= len(entity_list):
            print(f"⚠️ Could not find entity at index {entity_info['entity_index']} in {prefab_file.name}")
            return False
        
        entity = entity_list[entity_info["entity_index"]]
        num_rows = len(tile_map_layout)
        
        # Try to get tileMap from original entity or part if not in entity_info
        original_tile_map = entity_info.get("tile_map", None)
        if not original_tile_map:
            # Check entity level
            original_tile_map = entity.get("tileMap", None)
            # Check part level (if part_index is specified)
            if not original_tile_map and entity_info.get("part_index") is not None:
                parts = entity.get("parts", [])
                part_idx = entity_info["part_index"]
                if part_idx < len(parts):
                    original_tile_map = parts[part_idx].get("tileMap", None)
        
        # Determine layer structure:
        # - 1-2 rows: single "low" layer
        # - 3+ rows: first 2 rows = "low", remaining = "high"
        if num_rows <= 2:
            # Single "low" layer
            low_rows = tile_map_layout
            high_rows = []
        else:
            # First 2 rows = "low", rest = "high"
            low_rows = tile_map_layout[:2]
            high_rows = tile_map_layout[2:]
        
        # Calculate zOffset based on tileMap structure
        # zOffset should increase with row index to ensure proper layering
        # Base zOffset for low layer (rows 0-1): 0
        # High layer zOffset: needs to be significantly higher to ensure proper rendering
        # Use a multiplier to ensure sufficient separation (at least 20, scales with rows)
        low_z_offset = 0
        high_z_offset = max(20, num_rows * 3)  # At least 20, scales with total rows (3x multiplier for safety)
        
        # Calculate sizes and offsets
        parts = []
        
        # Low layer
        if low_rows:
            max_cols = max(len(row) for row in low_rows) if low_rows else 0
            low_width = max_cols * tile_size
            low_height = len(low_rows) * tile_size
            
            low_part = {
                "layer": "low",
                "tileGrid": low_rows,
                "offset": {"x": 0, "y": 0},
                "size": {"width": low_width, "height": low_height},
                "zOffset": low_z_offset,
                "tileSize": tile_size
            }
            
            # Preserve tileMap property if it existed
            if original_tile_map:
                low_part["tileMap"] = original_tile_map
            
            parts.append(low_part)
        
        # High layer
        if high_rows:
            max_cols = max(len(row) for row in high_rows) if high_rows else 0
            high_width = max_cols * tile_size
            high_height = len(high_rows) * tile_size
            # Offset high layer to center it over low layer
            low_max_cols = max(len(row) for row in low_rows) if low_rows else 0
            offset_x = ((low_max_cols - max_cols) * tile_size) / 2 if low_max_cols > max_cols else 0
            # offset_y should position the high layer right at the top of the low layer
            # In SpriteKit with top-left anchor (0, 1), negative Y moves upward
            # We need to move up by the height of the low layer to position the high layer above it
            offset_y = -len(low_rows) * tile_size
            
            parts.append({
                "layer": "high",
                "tileGrid": high_rows,
                "offset": {"x": int(offset_x), "y": int(offset_y)},
                "size": {"width": high_width, "height": high_height},
                "zOffset": high_z_offset,  # Automatically calculated based on tileMap structure
                "tileSize": tile_size
            })
        
        # Update entity with new parts
        entity["parts"] = parts
        
        # Preserve tileMap property (keep it for reference/regeneration)
        # The tileMap property is useful for documentation and potential regeneration
        
        # Write back to file
        with open(prefab_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"   ✅ Updated {prefab_file.name} with {len(parts)} part(s) ({len(low_rows)} low rows, {len(high_rows)} high rows)")
        return True
    
    def update_prefab_with_tile_id(self, entity_info: Dict, tile_id: str, prefab_file: Path):
        """Update the prefab JSON file with the generated tile ID (legacy method for 'generate' in tileGrid)"""
        with open(prefab_file, 'r') as f:
            data = json.load(f)
        
        # Find the entity in the data structure
        entity_list_key = None
        entity_list = None
        
        # Handle all entity types
        if "animals" in data:
            entity_list_key = "animals"
            entity_list = data["animals"]
        elif "items" in data:
            entity_list_key = "items"
            entity_list = data["items"]
        elif "enemies" in data:
            entity_list_key = "enemies"
            entity_list = data["enemies"]
        elif "npcs" in data:
            entity_list_key = "npcs"
            entity_list = data["npcs"]
        elif "skills" in data:
            entity_list_key = "skills"
            entity_list = data["skills"]
        elif "chests" in data:
            entity_list_key = "chests"
            entity_list = data["chests"]
        elif "prefabs" in data:
            entity_list_key = "prefabs"
            entity_list = data["prefabs"]
        else:
            for key, value in data.items():
                if isinstance(value, list):
                    entity_list_key = key
                    entity_list = value
                    break
        
        if not entity_list or entity_info["entity_index"] >= len(entity_list):
            print(f"⚠️ Could not find entity at index {entity_info['entity_index']} in {prefab_file.name}")
            return False
        
        # Update the tileGrid
        entity = entity_list[entity_info["entity_index"]]
        parts = entity.get("parts", [])
        
        if entity_info["part_index"] is not None and entity_info["part_index"] < len(parts):
            part = parts[entity_info["part_index"]]
            tile_grid = part.get("tileGrid", [])
            
            # Replace "generate" with the actual tile ID
            for row_idx, row in enumerate(tile_grid):
                for col_idx, tile_id_val in enumerate(row):
                    if tile_id_val == "generate" or (isinstance(tile_id_val, str) and "generate" in tile_id_val.lower()):
                        tile_grid[row_idx][col_idx] = tile_id
        
            part["tileGrid"] = tile_grid
        
        # Also update the gid field if it exists and is empty/null
        if "gid" in entity and (not entity["gid"] or entity["gid"] == "generate"):
            entity["gid"] = tile_id
        
        # Write back to file
        with open(prefab_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"   ✅ Updated {prefab_file.name} with tile ID: {tile_id}")
        return True
    
    def extract_tile_ids(self, prefab_dir: Path) -> Dict[str, Dict]:
        """Extract all unique tile IDs from prefab files along with their metadata"""
        tile_map = {}
        
        # Find all JSON files in prefab directory
        json_files = list(prefab_dir.glob("*.json"))
        # Also check Maps subdirectory
        maps_dir = prefab_dir / "Maps"
        if maps_dir.exists():
            json_files.extend(maps_dir.glob("*.json"))
        
        for json_file in json_files:
            print(f"📄 Parsing {json_file.name}...")
            try:
                entities = self.parse_prefab_file(json_file)
                for entity in entities:
                    entity_id = entity.get("id", "")
                    entity_name = entity.get("name", "")
                    entity_desc = entity.get("description", "")
                    entity_type = entity.get("type", "unknown")
                    
                    # Extract tile IDs from parts
                    parts = entity.get("parts", [])
                    for part in parts:
                        tile_grid = part.get("tileGrid", [])
                        for row in tile_grid:
                            for tile_id in row:
                                if tile_id and tile_id != "generate" and "generate" not in str(tile_id).lower():
                                    # Store metadata for this tile ID
                                    if tile_id not in tile_map:
                                        tile_map[tile_id] = {
                                            "tile_id": tile_id,
                                            "name": entity_name,
                                            "description": entity_desc,
                                            "type": entity_type,
                                            "entity_id": entity_id,
                                            "source_file": json_file.name
                                        }
                                    else:
                                        # Prefer more descriptive information
                                        existing = tile_map[tile_id]
                                        if not existing["description"] and entity_desc:
                                            existing["description"] = entity_desc
                                        if not existing["name"] and entity_name:
                                            existing["name"] = entity_name
            except Exception as e:
                print(f"⚠️ Error parsing {json_file.name}: {e}")
                continue
        
        return tile_map
    
    def build_prompt_for_tile(self, tile_info: Dict) -> Tuple[str, str]:
        """Build prompt and negative prompt for generating a tile image"""
        name = tile_info.get("name", "")
        description = tile_info.get("description", "")
        entity_type = tile_info.get("type", "item")
        tile_id = tile_info.get("tile_id", "")
        tile_map = tile_info.get("tile_map", None)
        
        # Build base description using name and description from prefab
        if name and description:
            base_desc = f"{name}. {description}"
        elif name:
            base_desc = name
        elif description:
            base_desc = description
        else:
            base_desc = f"Game {entity_type}"
        
        # Add tileMap information to prompt if provided
        size_instruction = ""
        if tile_map:
            tile_map_counts = self.parse_tile_map(tile_map)
            num_rows = len(tile_map_counts)
            max_cols = max(tile_map_counts) if tile_map_counts else 1
            total_tiles = sum(tile_map_counts)
            width_px = max_cols * self.tile_size
            height_px = num_rows * self.tile_size
            
            # Describe the layout for the AI
            layout_desc = f"multi-tile sprite spanning {max_cols} tiles wide and {num_rows} tiles tall"
            if num_rows > 1:
                row_descs = []
                for i, count in enumerate(tile_map_counts, 1):
                    row_descs.append(f"row {i}: {count} tiles")
                layout_desc += f" ({', '.join(row_descs)})"
                # Important: specify left-aligned layout for consistent extraction
                layout_desc += ", all rows left-aligned (shorter rows have empty space on the right, not centered)"
            
            size_instruction = f"{layout_desc}, {width_px}x{height_px} pixel sprite, "
        else:
            size_instruction = f"single tile, {self.tile_size}x{self.tile_size} pixel sprite, "
        
        # Add style requirements similar to character generation
        # Use isometric/top-down perspective for game tiles
        style_instruction = f"Isometric top-down view game sprite, {size_instruction}game asset style matching existing tileset, clean edges, pixel art aesthetic, game-ready asset"
        
        prompt = f"{base_desc}. {style_instruction}. Centered in frame, full object visible."
        
        # Negative prompt to avoid unwanted features (similar to character generation)
        negative_prompt = (
            "multiple objects, cluttered, complex background, realistic photo, 3D render, "
            "blurry, low quality, text, watermark, signature, anime style, chibi style, "
            "super-deformed, hyper-realistic concept art, Pixar style, DreamWorks style, "
            "kid-like, childish, side view, front view, not isometric, not top-down"
        )
        
        return prompt, negative_prompt
    
    def _gcd(self, a: int, b: int) -> int:
        """Calculate greatest common divisor"""
        while b:
            a, b = b, a % b
        return a
    
    def generate_all_tiles(self, tile_map: Dict[str, Dict], output_dir: Path, limit: Optional[int] = None, interactive: bool = True) -> Dict[str, Path]:
        """Generate images for all tiles with interactive approval"""
        generated_images = {}
        tiles_to_generate = list(tile_map.items())
        
        if limit:
            tiles_to_generate = tiles_to_generate[:limit]
            print(f"\n🎨 Generating {limit} of {len(tile_map)} tile images (limited mode)...")
        else:
            print(f"\n🎨 Generating {len(tile_map)} tile images...")
        
        total = len(tiles_to_generate)
        
        for idx, (tile_id, tile_info) in enumerate(tiles_to_generate, 1):
            print(f"\n[{idx}/{total}] Generating tile: {tile_id} ({tile_info.get('name', 'Unknown')})")
            
            prompt, negative_prompt = self.build_prompt_for_tile(tile_info)
            print(f"   Prompt: {prompt[:100]}...")
            
            # Generate images until approved
            approved = False
            attempts = 0
            max_attempts = 10
            
            while not approved and attempts < max_attempts:
                attempts += 1
                if attempts > 1:
                    print(f"   🔄 Regenerating (attempt {attempts}/{max_attempts})...")
                
                # Generate image (generate at higher resolution, then resize)
                image = self.generate_image_text_to_image(
                    prompt=prompt,
                    negative_prompt=negative_prompt,
                    size=128  # Generate at 128x128, then resize to tile size
                )
                
                if not image:
                    print(f"   ❌ Failed to generate image for {tile_id}")
                    if attempts >= max_attempts:
                        print(f"   ⚠️ Skipping {tile_id} after {max_attempts} failed attempts")
                        break
                    continue
                
                # Resize to tile size
                if image.size != (self.tile_size, self.tile_size):
                    image = image.resize((self.tile_size, self.tile_size), Image.Resampling.LANCZOS)
                
                # Show for approval if interactive mode
                if interactive:
                    approved = self.show_image_for_approval(image, tile_id, tile_info)
                    if not approved:
                        if attempts >= max_attempts:
                            print(f"   ⚠️ Skipping {tile_id} after {max_attempts} rejections")
                            break
                        continue
                else:
                    # Non-interactive: auto-approve
                    approved = True
                
                # Remove background from approved image
                print("   🎨 Removing background...")
                image_no_bg = self.remove_background(image)
                
                if image_no_bg:
                    # Resize again after background removal (in case it changed)
                    if image_no_bg.size != (self.tile_size, self.tile_size):
                        image_no_bg = image_no_bg.resize((self.tile_size, self.tile_size), Image.Resampling.LANCZOS)
                    image = image_no_bg
                else:
                    print("   ⚠️ Background removal failed, using original image")
                
                # Save individual tile
                tile_filename = f"{tile_id.replace(':', '_').replace('/', '_')}.png"
                tile_path = output_dir / tile_filename
                image.save(tile_path)
                generated_images[tile_id] = tile_path
                print(f"   ✅ Approved and saved to {tile_filename}")
                break
            
            # Rate limiting - be nice to the API
            if idx < total:
                time.sleep(1)
        
        return generated_images
    
    def create_sprite_atlas(self, generated_images: Dict[str, Path], tile_map: Dict[str, Dict], output_path: Path):
        """Create a sprite atlas PNG from all generated images"""
        if not generated_images:
            print("❌ No images to create atlas from")
            return
        
        # Load existing metadata if it exists
        metadata_path = output_path.with_suffix('.json')
        if metadata_path.exists():
            with open(metadata_path, 'r') as f:
                atlas_metadata = json.load(f)
        else:
            atlas_metadata = {
                "tile_size": self.tile_size,
                "tiles": {}
            }
        
        # Load or create atlas
        if output_path.exists():
            print(f"📦 Loading existing atlas from {output_path}")
            atlas = Image.open(output_path)
            # Get current dimensions
            atlas_width, atlas_height = atlas.size
            # Calculate current grid size
            cols = atlas_width // self.tile_size
            rows = atlas_height // self.tile_size
            # Update metadata if not set
            if "atlas_width" not in atlas_metadata:
                atlas_metadata["atlas_width"] = atlas_width
                atlas_metadata["atlas_height"] = atlas_height
                atlas_metadata["cols"] = cols
                atlas_metadata["rows"] = rows
        else:
            # Calculate atlas dimensions (square grid)
            total_tiles = len(generated_images)
            cols = int(total_tiles ** 0.5) + (1 if (total_tiles ** 0.5) % 1 != 0 else 0)
            rows = (total_tiles + cols - 1) // cols  # Ceiling division
            
            atlas_width = cols * self.tile_size
            atlas_height = rows * self.tile_size
            
            print(f"\n📦 Creating sprite atlas: {cols}x{rows} grid ({atlas_width}x{atlas_height} pixels)")
            
            # Create new atlas image
            atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))
            
            # Update metadata
            atlas_metadata["atlas_width"] = atlas_width
            atlas_metadata["atlas_height"] = atlas_height
            atlas_metadata["cols"] = cols
            atlas_metadata["rows"] = rows
        
        # Find next available position in atlas
        existing_tile_ids = set(atlas_metadata.get("tiles", {}).keys())
        new_tiles = {tid: path for tid, path in generated_images.items() if tid not in existing_tile_ids}
        
        if not new_tiles:
            print("✅ All tiles already in atlas")
            return
        
        # Find first empty position
        x, y = 0, 0
        occupied = {(tile["col"], tile["row"]) for tile in atlas_metadata.get("tiles", {}).values()}
        
        for tile_id, tile_path in new_tiles.items():
            # Find next empty position
            while (x, y) in occupied:
                x += 1
                if x >= cols:
                    x = 0
                    y += 1
                    # Expand atlas if needed
                    if y >= rows:
                        # Need to expand atlas
                        new_rows = y + 1
                        new_height = new_rows * self.tile_size
                        new_atlas = Image.new('RGBA', (atlas_width, new_height), (0, 0, 0, 0))
                        new_atlas.paste(atlas, (0, 0))
                        atlas = new_atlas
                        rows = new_rows
                        atlas_height = new_height
                        atlas_metadata["rows"] = rows
                        atlas_metadata["atlas_height"] = atlas_height
            
            try:
                tile_image = Image.open(tile_path)
                # Ensure it's RGBA
                if tile_image.mode != 'RGBA':
                    tile_image = tile_image.convert('RGBA')
                
                atlas.paste(tile_image, (x * self.tile_size, y * self.tile_size), tile_image)
                
                # Store metadata
                atlas_metadata["tiles"][tile_id] = {
                    "x": x * self.tile_size,
                    "y": y * self.tile_size,
                    "width": self.tile_size,
                    "height": self.tile_size,
                    "col": x,
                    "row": y,
                    "name": tile_map.get(tile_id, {}).get("name", ""),
                    "description": tile_map.get(tile_id, {}).get("description", ""),
                    "type": tile_map.get(tile_id, {}).get("type", "")
                }
                
                occupied.add((x, y))
                
                # Move to next position
                x += 1
                if x >= cols:
                    x = 0
                    y += 1
            except Exception as e:
                print(f"⚠️ Error placing tile {tile_id} in atlas: {e}")
                continue
        
        # Update metadata with final dimensions
        atlas_metadata["atlas_width"] = atlas.width
        atlas_metadata["atlas_height"] = atlas.height
        atlas_metadata["cols"] = cols
        atlas_metadata["rows"] = rows
        
        # Save atlas
        atlas.save(output_path)
        print(f"✅ Sprite atlas saved to {output_path}")
        
        # Save metadata
        with open(metadata_path, 'w') as f:
            json.dump(atlas_metadata, f, indent=2)
        print(f"✅ Metadata saved to {metadata_path}")
    
    def generate_from_prefab_file(self, prefab_file: Path, atlas_png: Path, tile_id_prefix: str = "exterior"):
        """Generate tiles for entities with 'generate' in tileGrid and update the prefab file"""
        print(f"🚀 Starting generation from prefab file...")
        print(f"   Prefab file: {prefab_file}")
        print(f"   Atlas PNG: {atlas_png}")
        print(f"   Tile ID prefix: {tile_id_prefix}")
        
        if not prefab_file.exists():
            print(f"❌ Prefab file not found: {prefab_file}")
            return
        
        # Create atlas directory if it doesn't exist
        atlas_png.parent.mkdir(parents=True, exist_ok=True)
        
        if not atlas_png.exists():
            print(f"📦 Creating new atlas: {atlas_png}")
            # Create an empty atlas to start with
            initial_cols = 10
            initial_rows = 10
            initial_atlas = Image.new('RGBA', (initial_cols * self.tile_size, initial_rows * self.tile_size), (0, 0, 0, 0))
            initial_atlas.save(atlas_png)
            
            # Create initial metadata
            metadata_path = atlas_png.with_suffix('.json')
            initial_metadata = {
                "tile_size": self.tile_size,
                "atlas_width": initial_cols * self.tile_size,
                "atlas_height": initial_rows * self.tile_size,
                "cols": initial_cols,
                "rows": initial_rows,
                "tiles": {}
            }
            with open(metadata_path, 'w') as f:
                json.dump(initial_metadata, f, indent=2)
            print(f"✅ Created new atlas with {initial_cols}x{initial_rows} grid")
        else:
            # Load existing atlas info
            metadata_path = atlas_png.with_suffix('.json')
            if metadata_path.exists():
                with open(metadata_path, 'r') as f:
                    existing_metadata = json.load(f)
                existing_tile_count = len(existing_metadata.get("tiles", {}))
                print(f"📦 Found existing atlas: {atlas_png.name}")
                print(f"   📊 Contains {existing_tile_count} tiles")
            else:
                print(f"📦 Found existing atlas: {atlas_png.name} (no metadata, will create)")
        
        # Find entities needing generation
        print("\n📋 Scanning for entities with 'tileMap' or 'generate' in tileGrid...")
        entities_needing_gen = self.find_entities_needing_generation(prefab_file)
        
        if not entities_needing_gen:
            print("✅ No entities found with 'tileMap' property or 'generate' in tileGrid")
            return
        
        print(f"✅ Found {len(entities_needing_gen)} entities needing generation")
        
        # Check if dry run mode
        if hasattr(self, '_dry_run') and self._dry_run:
            print("\n📊 Entities to generate:")
            for entity_info in entities_needing_gen:
                entity = entity_info["entity"]
                print(f"   - {entity.get('name', entity.get('id', 'Unknown'))} ({entity_info['entity_type']})")
            print("\n🔍 Dry run complete - no images generated")
            return
        
        # Create tiles directory
        tiles_dir = atlas_png.parent / "tiles"
        tiles_dir.mkdir(parents=True, exist_ok=True)
        
        interactive = not getattr(self, '_no_interactive', False)
        generated_tiles = {}
        
        # Process each entity
        for idx, entity_info in enumerate(entities_needing_gen, 1):
            entity = entity_info["entity"]
            entity_name = entity.get("name", entity.get("id", "Unknown"))
            entity_desc = entity.get("description", "")
            entity_type = entity_info["entity_type"]
            
            print(f"\n[{idx}/{len(entities_needing_gen)}] Processing: {entity_name} ({entity_type})")
            
            # Check if using tileMap or legacy "generate"
            tile_map_str = entity_info.get("tile_map")
            if tile_map_str:
                # Parse tileMap (e.g., "2,3,1" -> [2, 3, 1])
                tile_map_counts = self.parse_tile_map(tile_map_str)
                num_rows = len(tile_map_counts)
                max_cols = max(tile_map_counts) if tile_map_counts else 1
                
                # Calculate image size based on tileMap
                image_width = max_cols * self.tile_size
                image_height = num_rows * self.tile_size
                
                print(f"   📐 TileMap: {tile_map_str} -> {num_rows} rows, max {max_cols} cols")
                print(f"   📏 Image size: {image_width}x{image_height} pixels")
            else:
                # Legacy: single tile
                tile_map_counts = [1]
                num_rows = 1
                max_cols = 1
                image_width = self.tile_size
                image_height = self.tile_size
            
            # Build prompt (tile_id will be set after adding to atlas)
            tile_info = {
                "name": entity_name,
                "description": entity_desc,
                "type": entity_type,
                "tile_map": tile_map_str if tile_map_str else None
            }
            prompt, negative_prompt = self.build_prompt_for_tile(tile_info)
            print(f"   Prompt: {prompt[:100]}...")
            
            # Generate images until approved
            approved = False
            attempts = 0
            max_attempts = 10
            
            while not approved and attempts < max_attempts:
                attempts += 1
                if attempts > 1:
                    print(f"   🔄 Regenerating (attempt {attempts}/{max_attempts})...")
                
                # Generate image at calculated size (generate larger for better quality)
                # For multi-tile images, generate at much higher resolution
                if tile_map_str:
                    # For multi-tile, scale up significantly based on tile count
                    total_tiles = sum(tile_map_counts)
                    # Scale factor: more tiles = larger generation size
                    # Base: 8x for small (2-4 tiles), 6x for medium (5-9 tiles), 4x for large (10+ tiles)
                    if total_tiles <= 4:
                        scale_factor = 8
                    elif total_tiles <= 9:
                        scale_factor = 6
                    else:
                        scale_factor = 4
                    
                    generate_width = image_width * scale_factor
                    generate_height = image_height * scale_factor
                    # Ensure minimum size for quality
                    generate_width = max(generate_width, 512)
                    generate_height = max(generate_height, 512)
                    # Round to nearest 16 for better processing
                    generate_width = ((generate_width + 8) // 16) * 16
                    generate_height = ((generate_height + 8) // 16) * 16
                else:
                    # Single tile: generate at 4x for quality
                    generate_width = image_width * 4
                    generate_height = image_height * 4
                    generate_width = max(generate_width, 256)
                    generate_height = max(generate_height, 256)
                
                print(f"   🎨 Generating image at {generate_width}x{generate_height} pixels (will resize to {image_width}x{image_height})")
                image = self.generate_image_text_to_image(
                    prompt=prompt,
                    negative_prompt=negative_prompt,
                    size=max(generate_width, generate_height),
                    width=generate_width,
                    height=generate_height
                )
                
                if not image:
                    print(f"   ❌ Failed to generate image")
                    if attempts >= max_attempts:
                        print(f"   ⚠️ Skipping after {max_attempts} failed attempts")
                        break
                    continue
                
                # Resize to calculated size
                if image.size != (image_width, image_height):
                    image = image.resize((image_width, image_height), Image.Resampling.LANCZOS)
                
                # Create temporary identifier for display (tile_id will be set after adding to atlas)
                temp_tile_id = f"{entity_name} (pending)"
                
                # Show for approval if interactive mode
                if interactive:
                    approved = self.show_image_for_approval(image, temp_tile_id, tile_info)
                    if not approved:
                        if attempts >= max_attempts:
                            print(f"   ⚠️ Skipping after {max_attempts} rejections")
                            break
                        continue
                else:
                    approved = True
                
                # Remove background from approved image
                print("   🎨 Removing background...")
                image_no_bg = self.remove_background(image)
                
                if image_no_bg:
                    if image_no_bg.size != (image_width, image_height):
                        image_no_bg = image_no_bg.resize((image_width, image_height), Image.Resampling.LANCZOS)
                    image = image_no_bg
                else:
                    print("   ⚠️ Background removal failed, using original image")
                
                if tile_map_str:
                    # Handle tileMap: split image into tiles and add to atlas
                    print(f"   ✂️  Splitting image into {num_rows} rows based on tileMap...")
                    tile_map_layout = []
                    frame_numbers = []
                    atlas_name = atlas_png.stem
                    
                    # Split image into tiles based on tileMap
                    current_frame = 1
                    print(f"   📐 Extracting tiles from image ({image_width}x{image_height})...")
                    for row_idx, tile_count in enumerate(tile_map_counts):
                        row_tiles = []
                        print(f"      Row {row_idx}: extracting {tile_count} tiles (from x=0 to x={tile_count * self.tile_size})")
                        for col_idx in range(tile_count):
                            # Extract tile from image
                            x = col_idx * self.tile_size
                            y = row_idx * self.tile_size
                            tile_image = image.crop((x, y, x + self.tile_size, y + self.tile_size))
                            
                            # Save temp tile
                            temp_tile_path = tiles_dir / f"tile_{idx}_r{row_idx}_c{col_idx}_temp.png"
                            tile_image.save(temp_tile_path)
                            
                            # Add to atlas
                            frame_number = self.add_tile_to_atlas(temp_tile_path, atlas_png, tile_info)
                            frame_numbers.append(frame_number)
                            tile_id = f"{atlas_name}-{frame_number}"
                            row_tiles.append(tile_id)
                            print(f"         Col {col_idx}: extracted from ({x},{y}) -> {tile_id} (frame {frame_number})")
                            
                            # Clean up temp file
                            try:
                                temp_tile_path.unlink()
                            except:
                                pass
                            
                            current_frame += 1
                        
                        tile_map_layout.append(row_tiles)
                        print(f"      Row {row_idx} complete: {row_tiles}")
                    
                    # Update prefab with tileMap structure
                    print(f"   📝 Updating prefab file with tileMap structure...")
                    print(f"   📋 Tile layout to write:")
                    for row_idx, row in enumerate(tile_map_layout):
                        print(f"      Row {row_idx}: {row}")
                    self.update_prefab_with_tile_map(entity_info, tile_map_layout, prefab_file, self.tile_size)
                    
                    print(f"   ✅ Complete! Generated {sum(tile_map_counts)} tiles across {num_rows} rows")
                else:
                    # Legacy: single tile
                    # Save individual tile (use a temp name, will be renamed after we get frame number)
                    tile_filename = f"tile_{idx}_temp.png"
                    tile_path = tiles_dir / tile_filename
                    image.save(tile_path)
                    
                    # Add to atlas and get the frame number
                    print(f"   📦 Adding to atlas...")
                    frame_number = self.add_tile_to_atlas(tile_path, atlas_png, tile_info)
                    
                    # Generate tile ID based on atlas name and frame number
                    atlas_name = atlas_png.stem  # filename without extension (e.g., "sprite_atlas")
                    tile_id = f"{atlas_name}-{frame_number}"
                    
                    # Rename tile file to match tile_id
                    final_tile_filename = f"{tile_id.replace(':', '_').replace('/', '_')}.png"
                    final_tile_path = tiles_dir / final_tile_filename
                    if tile_path != final_tile_path:
                        tile_path.rename(final_tile_path)
                    tile_path = final_tile_path
                    
                    # Update prefab file
                    print(f"   📝 Updating prefab file with tile ID: {tile_id}")
                    self.update_prefab_with_tile_id(entity_info, tile_id, prefab_file)
                    
                    # Clean up: delete the individual tile image (it's now in the atlas)
                    try:
                        if tile_path.exists():
                            tile_path.unlink()
                            print(f"   🗑️  Deleted individual tile file: {tile_path.name}")
                    except Exception as e:
                        print(f"   ⚠️  Could not delete tile file: {e}")
                    
                    generated_tiles[tile_id] = tile_path
                    print(f"   ✅ Complete! Tile ID: {tile_id}")
                
                # Clean up: delete the individual tile image (it's now in the atlas)
                try:
                    if tile_path.exists():
                        tile_path.unlink()
                        print(f"   🗑️  Deleted individual tile file: {tile_path.name}")
                except Exception as e:
                    print(f"   ⚠️  Could not delete tile file: {e}")
                
                break
            
            # Rate limiting
            if idx < len(entities_needing_gen):
                time.sleep(1)
        
        # Note: We keep the metadata JSON file - it's needed for incremental updates
        # The metadata tracks which tiles are already in the atlas to avoid duplicates
        
        print(f"\n✅ Generation complete!")
        print(f"   Generated {len(generated_tiles)} tiles")
        print(f"   Updated prefab file: {prefab_file}")
        print(f"   Updated atlas: {atlas_png}")
    
    def add_tile_to_atlas(self, tile_path: Path, atlas_png: Path, tile_info: Dict) -> int:
        """Add a single tile to the atlas and update metadata. Returns frame number (1-indexed)."""
        # Ensure atlas exists
        if not atlas_png.exists():
            # Create new atlas
            cols = 10  # Start with 10 columns
            rows = 10
            atlas_width = cols * self.tile_size
            atlas_height = rows * self.tile_size
            atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))
            atlas.save(atlas_png)
            
            # Create initial metadata
            metadata_path = atlas_png.with_suffix('.json')
            atlas_metadata = {
                "tile_size": self.tile_size,
                "atlas_width": atlas_width,
                "atlas_height": atlas_height,
                "cols": cols,
                "rows": rows,
                "tiles": {}
            }
            with open(metadata_path, 'w') as f:
                json.dump(atlas_metadata, f, indent=2)
        else:
            # Load existing atlas
            print(f"   📦 Loading existing atlas: {atlas_png.name}")
            atlas = Image.open(atlas_png)
            atlas_width, atlas_height = atlas.size
            cols = atlas_width // self.tile_size
            rows = atlas_height // self.tile_size
            print(f"   📐 Atlas size: {atlas_width}x{atlas_height} ({cols}x{rows} grid)")
            
            # Load metadata
            metadata_path = atlas_png.with_suffix('.json')
            if metadata_path.exists():
                with open(metadata_path, 'r') as f:
                    atlas_metadata = json.load(f)
                existing_tile_count = len(atlas_metadata.get("tiles", {}))
                print(f"   📊 Found {existing_tile_count} existing tiles in metadata")
            else:
                # Create metadata if missing (atlas exists but metadata doesn't)
                print(f"   ⚠️  Metadata not found, creating new metadata for existing atlas")
                atlas_metadata = {
                    "tile_size": self.tile_size,
                    "atlas_width": atlas_width,
                    "atlas_height": atlas_height,
                    "cols": cols,
                    "rows": rows,
                    "tiles": {}
                }
        
        # Find next empty position
        occupied = {(tile["col"], tile["row"]) for tile in atlas_metadata.get("tiles", {}).values()}
        x, y = 0, 0
        
        while (x, y) in occupied:
            x += 1
            if x >= cols:
                x = 0
                y += 1
                # Expand atlas if needed
                if y >= rows:
                    new_rows = y + 1
                    new_height = new_rows * self.tile_size
                    new_atlas = Image.new('RGBA', (atlas_width, new_height), (0, 0, 0, 0))
                    new_atlas.paste(atlas, (0, 0))
                    atlas = new_atlas
                    rows = new_rows
                    atlas_height = new_height
                    cols = atlas_width // self.tile_size  # Update cols in case it changed
        
        # Calculate frame number (1-indexed: row * cols + col + 1)
        frame_number = y * cols + x + 1
        
        # Add tile to atlas
        tile_image = Image.open(tile_path)
        if tile_image.mode != 'RGBA':
            tile_image = tile_image.convert('RGBA')
        
        atlas.paste(tile_image, (x * self.tile_size, y * self.tile_size), tile_image)
        
        # Update metadata
        if "tile_size" not in atlas_metadata:
            atlas_metadata["tile_size"] = self.tile_size
        atlas_metadata["atlas_width"] = atlas.width
        atlas_metadata["atlas_height"] = atlas.height
        atlas_metadata["cols"] = cols
        atlas_metadata["rows"] = rows
        
        if "tiles" not in atlas_metadata:
            atlas_metadata["tiles"] = {}
        
        # Store by frame number for metadata
        atlas_metadata["tiles"][str(frame_number)] = {
            "x": x * self.tile_size,
            "y": y * self.tile_size,
            "width": self.tile_size,
            "height": self.tile_size,
            "col": x,
            "row": y,
            "name": tile_info.get("name", ""),
            "description": tile_info.get("description", ""),
            "type": tile_info.get("type", "")
        }
        
        # Save atlas and metadata
        atlas.save(atlas_png)
        with open(metadata_path, 'w') as f:
            json.dump(atlas_metadata, f, indent=2)
        
        return frame_number
    
    def generate(self, prefab_dir: Path, output_dir: Path, atlas_name: str = "sprite_atlas.png"):
        """Main generation method"""
        print(f"🚀 Starting sprite atlas generation...")
        print(f"   Prefab directory: {prefab_dir}")
        print(f"   Output directory: {output_dir}")
        
        # Create output directory
        output_dir.mkdir(parents=True, exist_ok=True)
        tiles_dir = output_dir / "tiles"
        tiles_dir.mkdir(parents=True, exist_ok=True)
        
        # Extract tile IDs
        print("\n📋 Extracting tile IDs from prefab files...")
        tile_map = self.extract_tile_ids(prefab_dir)
        print(f"✅ Found {len(tile_map)} unique tile IDs")
        
        # Print tile summary
        print("\n📊 Tile Summary:")
        for tile_id, tile_info in sorted(tile_map.items()):
            print(f"   {tile_id}: {tile_info.get('name', 'Unknown')} ({tile_info.get('type', 'unknown')}) - {tile_info.get('source_file', 'unknown')}")
        
        # Check if dry run mode
        if hasattr(self, '_dry_run') and self._dry_run:
            print("\n🔍 Dry run complete - no images generated")
            return
        
        # Get limit and interactive mode if specified
        limit = getattr(self, '_limit', None)
        interactive = not getattr(self, '_no_interactive', False)
        
        # Generate all tile images
        generated_images = self.generate_all_tiles(tile_map, tiles_dir, limit=limit, interactive=interactive)
        
        if not generated_images:
            print("❌ No images were generated. Aborting atlas creation.")
            return
        
        # Create sprite atlas
        atlas_path = output_dir / atlas_name
        self.create_sprite_atlas(generated_images, tile_map, atlas_path)
        
        print(f"\n✅ Sprite atlas generation complete!")
        print(f"   Generated {len(generated_images)} tile images")
        print(f"   Atlas saved to: {atlas_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate sprite atlas from FableForge prefab JSON files using Replicate API"
    )
    parser.add_argument(
        "--prefab-dir",
        type=str,
        default="FableForge Shared/Prefabs",
        help="Path to prefab directory containing JSON files (default: FableForge Shared/Prefabs)"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="generated_assets",
        help="Output directory for generated atlas and tiles (default: generated_assets)"
    )
    parser.add_argument(
        "--atlas-name",
        type=str,
        default="sprite_atlas.png",
        help="Name of output atlas PNG file (default: sprite_atlas.png)"
    )
    parser.add_argument(
        "--tile-size",
        type=int,
        default=DEFAULT_TILE_SIZE,
        help=f"Tile size in pixels (default: {DEFAULT_TILE_SIZE})"
    )
    parser.add_argument(
        "--api-key",
        type=str,
        default=REPLICATE_API_KEY,
        help="Replicate API key (default: reads from REPLICATE_API_KEY environment variable)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse prefab files and show tile IDs without generating images"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Limit number of tiles to generate (useful for testing)"
    )
    parser.add_argument(
        "--no-interactive",
        action="store_true",
        help="Skip interactive approval (auto-approve all generated images)"
    )
    parser.add_argument(
        "--prefab-file",
        type=str,
        default=None,
        help="Specific prefab JSON file to process (e.g., items.json). Only processes entities with tileGrid containing 'generate'"
    )
    parser.add_argument(
        "--atlas-png",
        type=str,
        default=None,
        help="Specific PNG atlas file to add tiles to (required with --prefab-file)"
    )
    parser.add_argument(
        "--tile-id-prefix",
        type=str,
        default="exterior",
        help="Prefix for generated tile IDs (default: exterior)"
    )
    
    args = parser.parse_args()
    
    # Validate API key is provided
    if not args.api_key:
        print("❌ Error: Replicate API key is required")
        print("   Set it via environment variable: export REPLICATE_API_KEY='your_key_here'")
        print("   Or pass it via command line: --api-key 'your_key_here'")
        sys.exit(1)
    
    # Resolve paths relative to script directory
    script_dir = Path(__file__).parent.parent
    
    # Create generator
    generator = SpriteAtlasGenerator(api_key=args.api_key, tile_size=args.tile_size)
    generator._dry_run = args.dry_run
    generator._limit = args.limit
    generator._no_interactive = args.no_interactive
    
    # Check if using prefab file mode
    if args.prefab_file:
        if not args.atlas_png:
            print("❌ --atlas-png is required when using --prefab-file")
            sys.exit(1)
        
        prefab_file = Path(args.prefab_file)
        if not prefab_file.is_absolute():
            prefab_file = script_dir / prefab_file
        
        atlas_png = Path(args.atlas_png)
        if not atlas_png.is_absolute():
            atlas_png = script_dir / atlas_png
        
        generator.generate_from_prefab_file(prefab_file, atlas_png, args.tile_id_prefix)
    else:
        # Normal mode: process all prefabs
        prefab_dir = script_dir / args.prefab_dir
        output_dir = script_dir / args.output_dir
        
        if not prefab_dir.exists():
            print(f"❌ Prefab directory not found: {prefab_dir}")
            sys.exit(1)
        
        generator.generate(prefab_dir, output_dir, args.atlas_name)


if __name__ == "__main__":
    main()
