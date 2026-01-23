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
        """Generate image using Replicate's Flux-2-pro text-to-image API"""
        version_hash = self.get_model_version(FLUX_2_PRO_MODEL)
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
        
        # Calculate resolution - must be one of the exact enum values: "match_input_image", "0.5 MP", "1 MP", "2 MP", "4 MP"
        # Choose based on total pixel count (megapixels)
        total_pixels = actual_width * actual_height
        total_megapixels = total_pixels / 1000000.0
        
        if total_megapixels >= 4.0:
            resolution = "4 MP"
        elif total_megapixels >= 2.0:
            resolution = "2 MP"
        elif total_megapixels >= 1.0:
            resolution = "1 MP"
        elif total_megapixels >= 0.5:
            resolution = "0.5 MP"
        else:
            # For very small images, use minimum
            resolution = "0.5 MP"
        
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
        
        # Note: Flux-2-pro model parameters need to be verified against the actual API schema.
        # Common parameters that may be supported:
        # "guidance_scale": 7.5,  # Higher = stronger prompt adherence (if supported)
        # "num_inference_steps": 50  # More steps = better detail (if supported)
        # Check https://replicate.com/black-forest-labs/flux-2-pro/api for actual supported parameters
        
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
        """Remove background from image using Replicate bria/remove-background model
        Bria RMBG 2.0 is better at preserving fine details like hair, especially light/white hair.
        It uses non-binary masks (256 levels of transparency) for smoother edge transitions."""
        # Convert image to bytes
        img_bytes = BytesIO()
        image.save(img_bytes, format='PNG')
        img_bytes.seek(0)
        image_data = img_bytes.getvalue()
        
        # Convert to base64
        base64_image = base64.b64encode(image_data).decode('utf-8')
        image_data_uri = f"data:image/png;base64,{base64_image}"
        
        # Get model version
        model_name = "bria/remove-background"
        version_hash = self.get_model_version(model_name)
        if not version_hash:
            print(f"❌ Failed to get version hash for {model_name}")
            return None
        
        url = f"{REPLICATE_BASE_URL}/predictions"
        headers = {
            "Authorization": f"Token {self.api_key}",
            "Content-Type": "application/json"
        }
        
        # Bria doesn't need alpha_matting parameters - it has its own internal algorithms
        input_params = {
            "image": image_data_uri
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
        elif "classes" in data:
            for class_entity in data["classes"]:
                entities.append({"type": "class", **class_entity})
        else:
            # Try to find any array at the top level
            for key, value in data.items():
                if isinstance(value, list):
                    for entity in value:
                        entities.append({"type": key.rstrip('s'), **entity})
        
        return entities
    
    def find_ground_tiles_needing_generation(self, map_file: Path, atlas_name: str) -> List[Dict]:
        """Find ground tiles in a map file that need generation (missing or placeholder IDs)"""
        ground_tiles_needing_gen = []
        
        with open(map_file, 'r') as f:
            data = json.load(f)
        
        # Check if this is a map file with worldConfig.terrain.groundTiles
        world_config = data.get("worldConfig", {})
        if not world_config:
            print(f"   ⚠️ No worldConfig found in {map_file.name}")
            return ground_tiles_needing_gen
        
        terrain = world_config.get("terrain", {})
        if not terrain:
            print(f"   ⚠️ No terrain found in worldConfig")
            return ground_tiles_needing_gen
        
        ground_tiles = terrain.get("groundTiles", {})
        if not ground_tiles:
            print(f"   ⚠️ No groundTiles found in terrain")
            return ground_tiles_needing_gen
        
        print(f"   🔍 Checking ground tiles in {map_file.name}...")
        
        # Check each ground tile type
        ground_types = ["water", "grass", "dirt", "stone"]
        for ground_type in ground_types:
            if ground_type not in ground_tiles:
                continue
            
            tile_ids = ground_tiles[ground_type]
            if not isinstance(tile_ids, list):
                continue
            
            for idx, tile_entry in enumerate(tile_ids):
                # Support both string tile IDs and object with tile_id and description
                # Format 1: "generate" or "grassland_atlas-1" (string)
                # Format 2: {"tile_id": "generate", "description": "dead dying grass"} (object)
                tile_id = None
                custom_description = None
                
                if isinstance(tile_entry, dict):
                    # Object format with tile_id and optional description
                    tile_id = tile_entry.get("tile_id") or tile_entry.get("tileId")
                    custom_description = tile_entry.get("description")
                elif isinstance(tile_entry, str):
                    # Simple string format
                    tile_id = tile_entry
                else:
                    # Handle None or other types
                    tile_id = tile_entry
                
                # Check if tile ID needs generation (empty, null, "generate", or ends with "-r")
                needs_gen = False
                replace_tile_id = None
                # Debug: print what we're checking
                print(f"      Checking {ground_type}[{idx}]: {repr(tile_id)} (type: {type(tile_id).__name__})" + (f", description: {custom_description}" if custom_description else ""))
                
                if not tile_id:
                    needs_gen = True
                    print(f"         -> Empty/null, needs generation")
                elif tile_id == "generate":
                    needs_gen = True
                    print(f"         -> Exact match 'generate', needs generation")
                elif isinstance(tile_id, str) and "generate" in tile_id.lower():
                    needs_gen = True
                    print(f"         -> Contains 'generate', needs generation")
                elif isinstance(tile_id, str) and tile_id.endswith("-r"):
                    # Check for replacement suffix "-r" (e.g., "grasslands-3-r")
                    needs_gen = True
                    replace_tile_id = tile_id[:-2]  # Remove "-r" suffix
                    print(f"         -> Ends with '-r', replacing tile {replace_tile_id}")
                elif isinstance(tile_id, str) and not tile_id.startswith(atlas_name + "-"):
                    # If it doesn't match the atlas name, we might want to regenerate it
                    # But we'll skip this for now - only generate if explicitly marked
                    print(f"         -> Doesn't match atlas name, skipping (only generate if marked 'generate')")
                
                if needs_gen:
                    print(f"   ✅ Found ground tile needing generation: {ground_type} (index {idx})" + (f" with description: {custom_description}" if custom_description else ""))
                    ground_tiles_needing_gen.append({
                        "ground_type": ground_type,
                        "tile_index": idx,
                        "map_file": map_file,
                        "current_tile_id": tile_id if tile_id else None,
                        "replace_tile_id": replace_tile_id,
                        "custom_description": custom_description  # Store custom description if provided
                    })
        
        # Check grass variants
        grass_variants = ground_tiles.get("grassVariants", {})
        if isinstance(grass_variants, dict):
            for variant_name, variant_tile_ids in grass_variants.items():
                if not isinstance(variant_tile_ids, list):
                    continue
                
                for idx, tile_entry in enumerate(variant_tile_ids):
                    # Support both string tile IDs and object with tile_id and description
                    # Format 1: "generate" or "grassland_atlas-1" (string)
                    # Format 2: {"tile_id": "generate", "description": "dead dying grass"} (object)
                    tile_id = None
                    custom_description = None
                    
                    if isinstance(tile_entry, dict):
                        # Object format with tile_id and optional description
                        tile_id = tile_entry.get("tile_id") or tile_entry.get("tileId")
                        custom_description = tile_entry.get("description")
                    elif isinstance(tile_entry, str):
                        # Simple string format
                        tile_id = tile_entry
                    else:
                        # Handle None or other types
                        tile_id = tile_entry
                    
                    needs_gen = False
                    replace_tile_id = None
                    if not tile_id or tile_id == "generate" or (isinstance(tile_id, str) and "generate" in tile_id.lower()):
                        needs_gen = True
                    elif isinstance(tile_id, str) and tile_id.endswith("-r"):
                        # Check for replacement suffix "-r"
                        needs_gen = True
                        replace_tile_id = tile_id[:-2]  # Remove "-r" suffix
                    
                    if needs_gen:
                        print(f"   ✅ Found grass variant needing generation: {variant_name} (index {idx})" + (f" with description: {custom_description}" if custom_description else ""))
                        ground_tiles_needing_gen.append({
                            "ground_type": "grass",
                            "ground_variant": variant_name,
                            "tile_index": idx,
                            "map_file": map_file,
                            "current_tile_id": tile_id if tile_id else None,
                            "replace_tile_id": replace_tile_id,
                            "custom_description": custom_description  # Store custom description if provided
                        })
        
        return ground_tiles_needing_gen
    
    def update_map_with_ground_tile(self, ground_tile_info: Dict, tile_id: str, map_file: Path, old_tile_id_with_suffix: str = None):
        """Update the map JSON file with the generated ground tile ID.
        If old_tile_id_with_suffix is provided (e.g., 'grasslands-3-r'), it will replace that tile ID instead of 'generate'."""
        with open(map_file, 'r') as f:
            data = json.load(f)
        
        world_config = data.get("worldConfig", {})
        terrain = world_config.get("terrain", {})
        ground_tiles = terrain.get("groundTiles", {})
        
        if not ground_tiles:
            print(f"⚠️ No groundTiles found in {map_file.name}")
            return False
        
        ground_type = ground_tile_info.get("ground_type")
        variant = ground_tile_info.get("ground_variant")
        tile_index = ground_tile_info.get("tile_index", 0)
        
        if variant:
            # Update grass variant
            grass_variants = ground_tiles.get("grassVariants", {})
            if variant in grass_variants and isinstance(grass_variants[variant], list):
                if tile_index < len(grass_variants[variant]):
                    # Get the current tile entry at this index (may be string or object)
                    old_entry = grass_variants[variant][tile_index]
                    # Extract tile_id from entry (handle both string and object formats)
                    old_tile_id = old_entry.get("tile_id") if isinstance(old_entry, dict) else old_entry
                    # Also check what we expected to replace from ground_tile_info
                    expected_tile_id = ground_tile_info.get("current_tile_id")
                    
                    # Verify we're replacing the correct entry:
                    # 1. If old_tile_id_with_suffix is provided, match it exactly
                    # 2. Otherwise, match if it's "generate" or matches what we expected
                    should_replace = False
                    if old_tile_id_with_suffix and old_tile_id == old_tile_id_with_suffix:
                        should_replace = True
                    elif not old_tile_id_with_suffix:
                        # Check if current entry is "generate" or matches what we expected
                        if old_tile_id == "generate" or (isinstance(old_tile_id, str) and "generate" in old_tile_id.lower()):
                            should_replace = True
                        elif expected_tile_id and old_tile_id == expected_tile_id:
                            # Also allow replacement if it matches what we expected when we found it
                            should_replace = True
                    
                    if should_replace:
                        # Preserve description if the original entry was an object with a description
                        old_entry = grass_variants[variant][tile_index]
                        custom_description = ground_tile_info.get("custom_description")
                        if isinstance(old_entry, dict) or custom_description:
                            # Preserve description from original entry or from ground_tile_info
                            preserved_description = custom_description or old_entry.get("description") if isinstance(old_entry, dict) else None
                            if preserved_description:
                                grass_variants[variant][tile_index] = {"tile_id": tile_id, "description": preserved_description}
                            else:
                                grass_variants[variant][tile_index] = tile_id
                        else:
                            grass_variants[variant][tile_index] = tile_id
                        if old_tile_id_with_suffix:
                            print(f"   ✅ Replaced {ground_type} variant '{variant}' tile at index {tile_index}: '{old_tile_id}' -> '{tile_id}'")
                        else:
                            print(f"   ✅ Updated {ground_type} variant '{variant}' tile at index {tile_index}: '{old_tile_id}' -> '{tile_id}'")
                    else:
                        print(f"   ⚠️ Skipped index {tile_index} - current value is '{old_tile_id}', expected 'generate' or '{expected_tile_id}'")
                        # Try to find the correct index with "generate"
                        found_index = None
                        for idx, val in enumerate(grass_variants[variant]):
                            # Handle both string and object formats
                            val_tile_id = val.get("tile_id") if isinstance(val, dict) else val
                            if val_tile_id == "generate" or (isinstance(val_tile_id, str) and "generate" in val_tile_id.lower()):
                                found_index = idx
                                break
                        if found_index is not None:
                            print(f"   🔍 Found 'generate' at index {found_index}, updating that instead")
                            # Preserve description if original entry was an object
                            old_entry = grass_variants[variant][found_index]
                            custom_description = ground_tile_info.get("custom_description")
                            if isinstance(old_entry, dict) or custom_description:
                                preserved_description = custom_description or old_entry.get("description") if isinstance(old_entry, dict) else None
                                if preserved_description:
                                    grass_variants[variant][found_index] = {"tile_id": tile_id, "description": preserved_description}
                                else:
                                    grass_variants[variant][found_index] = tile_id
                            else:
                                grass_variants[variant][found_index] = tile_id
                            print(f"   ✅ Updated {ground_type} variant '{variant}' tile at index {found_index}: 'generate' -> '{tile_id}'")
                        else:
                            print(f"   ❌ Could not find 'generate' entry in {ground_type} variant '{variant}' array")
                else:
                    # Extend list if needed
                    while len(grass_variants[variant]) <= tile_index:
                        grass_variants[variant].append(None)
                    # Preserve description if provided
                    custom_description = ground_tile_info.get("custom_description")
                    if custom_description:
                        grass_variants[variant][tile_index] = {"tile_id": tile_id, "description": custom_description}
                    else:
                        grass_variants[variant][tile_index] = tile_id
                    print(f"   ✅ Added {ground_type} variant '{variant}' tile at index {tile_index} with tile ID: {tile_id}")
        else:
            # Update regular ground tile
            if ground_type in ground_tiles and isinstance(ground_tiles[ground_type], list):
                if tile_index < len(ground_tiles[ground_type]):
                    # Get the current tile entry at this index (may be string or object)
                    old_entry = ground_tiles[ground_type][tile_index]
                    # Extract tile_id from entry (handle both string and object formats)
                    old_tile_id = old_entry.get("tile_id") if isinstance(old_entry, dict) else old_entry
                    # Also check what we expected to replace from ground_tile_info
                    expected_tile_id = ground_tile_info.get("current_tile_id")
                    
                    # Verify we're replacing the correct entry:
                    # 1. If old_tile_id_with_suffix is provided, match it exactly
                    # 2. Otherwise, match if it's "generate" or matches what we expected
                    should_replace = False
                    if old_tile_id_with_suffix and old_tile_id == old_tile_id_with_suffix:
                        should_replace = True
                    elif not old_tile_id_with_suffix:
                        # Check if current entry is "generate" or matches what we expected
                        if old_tile_id == "generate" or (isinstance(old_tile_id, str) and "generate" in old_tile_id.lower()):
                            should_replace = True
                        elif expected_tile_id and old_tile_id == expected_tile_id:
                            # Also allow replacement if it matches what we expected when we found it
                            should_replace = True
                    
                    if should_replace:
                        # Preserve description if the original entry was an object with a description
                        old_entry = ground_tiles[ground_type][tile_index]
                        custom_description = ground_tile_info.get("custom_description")
                        if isinstance(old_entry, dict) or custom_description:
                            # Preserve description from original entry or from ground_tile_info
                            preserved_description = custom_description or old_entry.get("description") if isinstance(old_entry, dict) else None
                            if preserved_description:
                                ground_tiles[ground_type][tile_index] = {"tile_id": tile_id, "description": preserved_description}
                            else:
                                ground_tiles[ground_type][tile_index] = tile_id
                        else:
                            ground_tiles[ground_type][tile_index] = tile_id
                        if old_tile_id_with_suffix:
                            print(f"   ✅ Replaced {ground_type} tile at index {tile_index}: '{old_tile_id}' -> '{tile_id}'")
                        else:
                            print(f"   ✅ Updated {ground_type} tile at index {tile_index}: '{old_tile_id}' -> '{tile_id}'")
                    else:
                        print(f"   ⚠️ Skipped index {tile_index} - current value is '{old_tile_id}', expected 'generate' or '{expected_tile_id}'")
                        # Try to find the correct index with "generate"
                        found_index = None
                        for idx, val in enumerate(ground_tiles[ground_type]):
                            # Handle both string and object formats
                            val_tile_id = val.get("tile_id") if isinstance(val, dict) else val
                            if val_tile_id == "generate" or (isinstance(val_tile_id, str) and "generate" in val_tile_id.lower()):
                                found_index = idx
                                break
                        if found_index is not None:
                            print(f"   🔍 Found 'generate' at index {found_index}, updating that instead")
                            # Preserve description if original entry was an object
                            old_entry = ground_tiles[ground_type][found_index]
                            custom_description = ground_tile_info.get("custom_description")
                            if isinstance(old_entry, dict) or custom_description:
                                preserved_description = custom_description or old_entry.get("description") if isinstance(old_entry, dict) else None
                                if preserved_description:
                                    ground_tiles[ground_type][found_index] = {"tile_id": tile_id, "description": preserved_description}
                                else:
                                    ground_tiles[ground_type][found_index] = tile_id
                            else:
                                ground_tiles[ground_type][found_index] = tile_id
                            print(f"   ✅ Updated {ground_type} tile at index {found_index}: 'generate' -> '{tile_id}'")
                        else:
                            print(f"   ❌ Could not find 'generate' entry in {ground_type} array")
                else:
                    # Extend list if needed
                    while len(ground_tiles[ground_type]) <= tile_index:
                        ground_tiles[ground_type].append(None)
                    # Preserve description if provided
                    custom_description = ground_tile_info.get("custom_description")
                    if custom_description:
                        ground_tiles[ground_type][tile_index] = {"tile_id": tile_id, "description": custom_description}
                    else:
                        ground_tiles[ground_type][tile_index] = tile_id
                    print(f"   ✅ Added {ground_type} tile at index {tile_index} with tile ID: {tile_id}")
        
        # Write back to file
        with open(map_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        return True
    
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
        if "classes" in data:
            entity_list.append((data["classes"], "class"))
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
                # Check if any part has "generate" in tileGrid
                # We ONLY generate if there's "generate" in the tileGrid, not just because tileMap exists
                needs_generation = False
                part_with_generate = None
                tile_map_str = None
                replace_tile_id = None
                parts = entity.get("parts", [])
                
                if parts:
                    for part_idx, part in enumerate(parts):
                        # Check for "generate" in tileGrid
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
                                    # Get tileMap from part or entity if available (for generation purposes)
                                    tile_map_str = part.get("tileMap", None) or entity.get("tileMap", None)
                                    break
                                # Check for replacement suffix "-r" (e.g., "grasslands-3-r")
                                elif isinstance(tile_id, str) and tile_id.endswith("-r"):
                                    needs_generation = True
                                    part_with_generate = part_idx
                                    # Extract original tile ID (remove "-r" suffix)
                                    replace_tile_id = tile_id[:-2]
                                    # Get tileMap from part or entity if available (for generation purposes)
                                    tile_map_str = part.get("tileMap", None) or entity.get("tileMap", None)
                                    break
                            if needs_generation:
                                break
                        if needs_generation:
                            break
                
                # Also check entity-level tileMap only if there are no parts or if parts need generation
                if not needs_generation and not parts:
                    # If no parts exist, check entity-level tileMap
                    entity_tile_map = entity.get("tileMap", None)
                    if entity_tile_map is not None and str(entity_tile_map).strip() != "":
                        # Only generate if there are no parts (entity is brand new)
                        needs_generation = True
                        tile_map_str = entity_tile_map
                
                if needs_generation:
                    entity_id = entity.get("id", f"entity_{idx}")
                    entity_name = entity.get("name", entity.get("id", "Unknown"))
                    if replace_tile_id:
                        reason = f"replacing tile {replace_tile_id} (tile ID ends with -r)" + (f" (tileMap: {tile_map_str})" if tile_map_str else "")
                    else:
                        reason = "generate in tileGrid" + (f" (tileMap: {tile_map_str})" if tile_map_str else "")
                    print(f"   ✅ Found entity needing generation: {entity_name} (id: {entity_id}, type: {entity_type}) - {reason}")
                    entities_needing_gen.append({
                        "entity": entity,
                        "entity_index": idx,
                        "part_index": part_with_generate,
                        "entity_type": entity_type,
                        "prefab_file": prefab_file,
                        "tile_map": tile_map_str,
                        "replace_tile_id": replace_tile_id
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
        elif "classes" in data:
            entity_list_key = "classes"
            entity_list = data["classes"]
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
        
        # Determine layer structure for trees:
        # - 1-2 rows: single "low" layer
        # - 3+ rows: LAST 2 rows = "low" (trunk at bottom), FIRST rows = "high" (canopy at top)
        # Note: For trees, the bottom rows (trunk) should be "low" and top rows (canopy) should be "high"
        if num_rows <= 2:
            # Single "low" layer
            low_rows = tile_map_layout
            high_rows = []
        else:
            # Last 2 rows = "low" (trunk), first rows = "high" (canopy)
            # This ensures trunk is in front of player (low layer) and canopy is behind (high layer)
            low_rows = tile_map_layout[-2:]  # Last 2 rows = trunk (bottom)
            high_rows = tile_map_layout[:-2]  # First rows = canopy (top)
        
        # Calculate zOffset based on tileMap structure
        # Since low layer (trunk, last rows) goes to entitiesAboveNode (in front of player)
        # and high layer (canopy, first rows) goes to entitiesBelowNode (behind player),
        # the low layer should have a higher zOffset to ensure proper layering within its container
        # Low layer (trunk): higher zOffset to be more in front
        # High layer (canopy): lower zOffset to be more behind
        low_z_offset = max(20, num_rows * 3)  # Higher zOffset for trunk (in front)
        high_z_offset = 0  # Lower zOffset for canopy (behind)
        
        # Calculate sizes and offsets
        parts = []
        
        # Low layer
        if low_rows:
            max_cols = max(len(row) for row in low_rows) if low_rows else 0
            low_width = max_cols * tile_size
            low_height = len(low_rows) * tile_size
            
            # Calculate offset_x to center low layer under high layer if low is narrower
            # If we have both high and low rows, center the narrower one
            if high_rows:
                high_max_cols = max(len(row) for row in high_rows) if high_rows else 0
                # Center low layer under high layer if low is narrower
                low_offset_x = ((high_max_cols - max_cols) * tile_size) / 2 if high_max_cols > max_cols else 0
            else:
                low_offset_x = 0
            
            low_part = {
                "layer": "low",
                "tileGrid": low_rows,
                "offset": {"x": int(low_offset_x), "y": 0},
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
            # offset_y should position the high layer above the low layer
            # Since high layer is the top rows (canopy) and low layer is the bottom rows (trunk),
            # the high layer needs to be positioned ABOVE the low layer
            # In SpriteKit with top-left anchor (0, 1), the position is the top-left corner
            # Low layer (trunk) is at offset (0, 0), meaning its top-left is at Y=0, extending down to Y=-low_height
            # High layer (canopy) should be positioned so its bottom aligns with the top of the low layer (Y=0)
            # High layer's top-left should be at Y=high_height so its bottom (top-left - height) is at Y=0
            # So offset_y should be positive: high_height
            offset_y = high_height
            
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
    
    def update_prefab_with_tile_id(self, entity_info: Dict, tile_id: str, prefab_file: Path, old_tile_id_with_suffix: str = None):
        """Update the prefab JSON file with the generated tile ID (legacy method for 'generate' in tileGrid).
        If old_tile_id_with_suffix is provided (e.g., 'grasslands-3-r'), it will replace that tile ID instead of 'generate'."""
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
        elif "classes" in data:
            entity_list_key = "classes"
            entity_list = data["classes"]
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
            
            # Replace "generate" or old tile ID with -r suffix with the actual tile ID
            for row_idx, row in enumerate(tile_grid):
                for col_idx, tile_id_val in enumerate(row):
                    if old_tile_id_with_suffix and tile_id_val == old_tile_id_with_suffix:
                        # Replace the tile ID that had -r suffix
                        tile_grid[row_idx][col_idx] = tile_id
                    elif not old_tile_id_with_suffix and (tile_id_val == "generate" or (isinstance(tile_id_val, str) and "generate" in tile_id_val.lower())):
                        # Replace "generate" with the actual tile ID
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
    
    def build_prompt_for_ground_tile(self, ground_type: str, variant: str = None, map_file: Path = None, custom_description: str = None) -> Tuple[str, str]:
        """Build prompt for generating a ground tile (grass, dirt, water, stone, or grass variants)
        If variant is provided, will reference the base tile to ensure color/style matching.
        If custom_description is provided, it will override the default description."""
        # Base descriptions for ground tile types
        # Emphasis on LARGE, VISIBLE textures that will remain clear when scaled down
        ground_descriptions = {
            "water": "clear shallow water, blue-green transparent water, large visible ripples and waves, prominent water surface patterns, coarse water texture with distinct wave patterns that remain visible at small scale",
            "grass": "lush green grass, meadow grass, large visible grass blades in irregular patches and tufts, prominent grass texture with distinct linear blade patterns arranged organically, coarse grass texture with irregular organic distribution that remains clear when scaled, avoid circular patterns or round shapes",
            "dirt": "brown dirt, soil, earth, large visible dirt particles and clumps, prominent ground texture with distinct soil patterns, coarse dirt texture with visible particles",
            "stone": "gray stone, rocky stone, large visible stone pieces and cracks, prominent stone texture with distinct rock patterns, coarse stone texture with visible rock details",
            "base": "lush green grass, meadow grass, large visible grass blades in irregular patches and tufts, prominent grass texture with distinct linear blade patterns arranged organically, coarse grass texture with irregular organic distribution that remains clear when scaled, avoid circular patterns or round shapes",
            "edgeN": "grass edge at north (top edge), grass transitioning to dirt/stone at top edge, smooth transition line at top",
            "edgeS": "grass edge at south (bottom edge), grass transitioning to dirt/stone at bottom edge, smooth transition line at bottom",
            "edgeE": "grass edge at east (right edge), grass transitioning to dirt/stone at right edge, smooth transition line at right",
            "edgeW": "grass edge at west (left edge), grass transitioning to dirt/stone at left edge, smooth transition line at left",
            "cornerNE": "grass outer corner northeast (top-right corner), grass fills the top-right L-shaped area (top edge and right edge), dirt/stone fills the opposite bottom-left corner area",
            "cornerNW": "grass outer corner northwest (top-left corner), grass fills the top-left L-shaped area (top edge and left edge), dirt/stone fills the opposite bottom-right corner area",
            "cornerSE": "grass outer corner southeast (bottom-right corner), grass fills the bottom-right L-shaped area (bottom edge and right edge), dirt/stone fills the opposite top-left corner area",
            "cornerSW": "grass outer corner southwest (bottom-left corner), grass fills the bottom-left L-shaped area (bottom edge and left edge), dirt/stone fills the opposite top-right corner area",
            "innerCornerNE": "grass inner corner northeast (concave corner), grass fills the inner concave corner area (bottom-left area), dirt/stone fills the L-shaped area along top and right edges meeting at the top-right corner",
            "innerCornerNW": "grass inner corner northwest (concave corner), grass fills the inner concave corner area (bottom-right area), dirt/stone fills the L-shaped area along top and left edges meeting at the top-left corner",
            "innerCornerSE": "grass inner corner southeast (concave corner), grass fills the inner concave corner area (top-left area), dirt/stone fills the L-shaped area along bottom and right edges meeting at the bottom-right corner",
            "innerCornerSW": "grass inner corner southwest (concave corner), grass fills the inner concave corner area (top-right area), dirt/stone fills the L-shaped area along bottom and left edges meeting at the bottom-left corner",
            "transitionN": "grass transition north, grass smoothly blending and transitioning to different terrain (dirt/stone) at top edge",
            "transitionS": "grass transition south, grass smoothly blending and transitioning to different terrain (dirt/stone) at bottom edge",
            "transitionE": "grass transition east, grass smoothly blending and transitioning to different terrain (dirt/stone) at right edge",
            "transitionW": "grass transition west, grass smoothly blending and transitioning to different terrain (dirt/stone) at left edge",
            "transitionNE": "grass transition northeast, grass smoothly blending diagonally to different terrain (dirt/stone) at top-right diagonal edge",
            "transitionNW": "grass transition northwest, grass smoothly blending diagonally to different terrain (dirt/stone) at top-left diagonal edge",
            "transitionSE": "grass transition southeast, grass smoothly blending diagonally to different terrain (dirt/stone) at bottom-right diagonal edge",
            "transitionSW": "grass transition southwest, grass smoothly blending diagonally to different terrain (dirt/stone) at bottom-left diagonal edge"
        }
        
        # Determine the description based on type and variant
        # If custom_description is provided, use it as-is (texture emphasis will be added separately)
        if custom_description:
            # Use custom description directly - don't add default texture keywords here
            # The texture_emphasis section will handle scaling requirements generically
            base_desc = custom_description
            tile_type_name = f"{ground_type} {variant}" if variant else ground_type
            print(f"   📝 Using custom description: {custom_description}")
        elif variant and variant in ground_descriptions:
            base_desc = ground_descriptions[variant]
            tile_type_name = f"{ground_type} {variant}" if ground_type != "grass" else variant
        elif ground_type in ground_descriptions:
            base_desc = ground_descriptions[ground_type]
            tile_type_name = ground_type
        else:
            base_desc = f"{ground_type} ground tile, large visible texture details, prominent texture patterns, coarse texture with distinct features"
            tile_type_name = ground_type
        
        size_instruction = f"single tile, {self.tile_size}x{self.tile_size} pixel sprite, "
        
        # Add style requirements for ground tiles
        # CRITICAL: Emphasize LARGE, PROMINENT textures that will remain visible when scaled
        # Fine textures become blurry, so we need coarse, prominent textures
        # If custom_description is provided, use generic texture emphasis (no grass-specific details)
        # Otherwise, include ground-type-specific texture guidance
        if custom_description:
            # Generic texture emphasis when custom description is provided
            texture_emphasis = (
                f"CRITICAL TEXTURE SCALE: This tile will be displayed at small sizes, so the texture MUST have LARGE, "
                f"PROMINENT, VISIBLE texture details. Use COARSE texture patterns with DISTINCT features that remain "
                f"clear when the tile is scaled down. Avoid fine, delicate, or subtle textures - use BOLD, STRIKING "
                f"texture patterns with STRONG visual elements. The texture should be OBVIOUS and EASILY VISIBLE, "
                f"not subtle or barely noticeable. The texture pattern should dominate the tile visually. "
                f"CRITICAL: For grass textures, the grass must be evenly distributed across the entire tile surface - "
                f"NO clumps, NO clusters, NO concentrated patches, NO grouped formations. The grass should be uniformly "
                f"spread with consistent density throughout the entire tile area. Avoid any circular, round, or clustered patterns. "
            )
        else:
            # Ground-type-specific texture emphasis for default descriptions
            texture_emphasis = (
                f"CRITICAL TEXTURE SCALE: This tile will be displayed at small sizes, so the texture MUST have LARGE, "
                f"PROMINENT, VISIBLE texture details. Use COARSE texture patterns with DISTINCT features that remain "
                f"clear when the tile is scaled down. Avoid fine, delicate, or subtle textures - use BOLD, STRIKING "
                f"texture patterns with STRONG visual elements. The texture should be OBVIOUS and EASILY VISIBLE, "
                f"not subtle or barely noticeable. Think large-scale texture features: large ripples, large irregular grass patches, "
                f"large dirt particles, large stone pieces. The texture pattern should dominate the tile visually. "
                f"For grass: use irregular, organic patterns with linear grass blades - avoid circular shapes, round patterns, or geometric clumps. "
            )
        
        style_instruction = (
            f"Isometric top-down view game sprite, {size_instruction}game asset style matching existing ground tileset, "
            f"seamless tileable texture with LARGE PROMINENT TEXTURE DETAILS, clean edges, pixel art aesthetic, "
            f"game-ready terrain asset with COARSE VISIBLE TEXTURE that scales well"
        )
        
        # For variants (not base), add reference to base tile to ensure color/style matching
        base_tile_reference = ""
        if variant and variant != "base" and map_file and map_file.exists():
            try:
                with open(map_file, 'r') as f:
                    data = json.load(f)
                world_config = data.get("worldConfig", {})
                terrain = world_config.get("terrain", {})
                ground_tiles = terrain.get("groundTiles", {})
                
                # Try to find base tile - check grassVariants.base first, then grass array
                base_tile_id = None
                if ground_type == "grass" and ground_tiles.get("grassVariants"):
                    grass_variants = ground_tiles.get("grassVariants", {})
                    base_array = grass_variants.get("base", [])
                    if base_array and isinstance(base_array, list) and len(base_array) > 0:
                        # Get first non-"generate" base tile if available
                        for tile_id in base_array:
                            if tile_id and tile_id != "generate" and isinstance(tile_id, str):
                                base_tile_id = tile_id
                                break
                
                # Fall back to flat grass array if no base in variants
                if not base_tile_id and ground_type == "grass":
                    grass_array = ground_tiles.get("grass", [])
                    if grass_array and isinstance(grass_array, list) and len(grass_array) > 0:
                        for tile_id in grass_array:
                            if tile_id and tile_id != "generate" and isinstance(tile_id, str):
                                base_tile_id = tile_id
                                break
                
                if base_tile_id:
                    # Extract just the tile type from the ID (e.g., "grassland_atlas-2" -> "base grass tile")
                    base_tile_reference = (
                        f"CRITICAL COLOR/STYLE MATCHING: This is a VARIANT tile ({variant}) that must match "
                        f"the exact same colors, texture style, grass color, and overall appearance as the base {ground_type} tile. "
                        f"Use the same shade of green (or appropriate color for {ground_type}), same texture density, same lighting, "
                        f"and same visual style as the base tile. The only difference should be the edge/corner/transition pattern - "
                        f"the base ground texture and colors must be IDENTICAL to the base tile. "
                        f"This variant tile will be placed next to base tiles, so it MUST match seamlessly in color and texture. "
                    )
                    print(f"   🎨 Adding base tile reference for color/style matching (base tile: {base_tile_id})")
            except Exception as e:
                print(f"   ⚠️ Could not load base tile reference: {e}")
        
        # Add variant-specific orientation instructions
        variant_instructions = ""
        if variant:
            if variant.startswith("edge"):
                direction = variant[-1]  # N, S, E, or W
                direction_map = {"N": "top", "S": "bottom", "E": "right", "W": "left"}
                edge_dir = direction_map.get(direction, "edge")
                variant_instructions = (
                    f"CRITICAL ORIENTATION: This is an edge tile. The {edge_dir} edge should show a clear transition "
                    f"to a different terrain type (dirt, stone, or water). The other three edges ({', '.join([v for k, v in direction_map.items() if k != direction])}) "
                    f"must match seamlessly with base grass tiles. The {edge_dir} edge is the transition edge, other edges are seamless. "
                )
            elif variant.startswith("corner"):
                direction = variant[-2:]  # NE, NW, SE, or SW
                # For corner variants, the corner name indicates where the DIFFERENT terrain (dirt/stone) appears
                # The current tile is grass, and the corner shows where grass transitions to dirt/stone
                corner_map = {
                    "NE": {
                        "dirt_corner": "top-right corner (NE)",
                        "dirt_edges": "top edge and right edge",
                        "grass_corner": "bottom-left corner (SW)",
                        "grass_edges": "bottom edge and left edge",
                        "opposite_edges": "bottom and left"
                    },
                    "NW": {
                        "dirt_corner": "top-left corner (NW)",
                        "dirt_edges": "top edge and left edge",
                        "grass_corner": "bottom-right corner (SE)",
                        "grass_edges": "bottom edge and right edge",
                        "opposite_edges": "bottom and right"
                    },
                    "SE": {
                        "dirt_corner": "bottom-right corner (SE)",
                        "dirt_edges": "bottom edge and right edge",
                        "grass_corner": "top-left corner (NW)",
                        "grass_edges": "top edge and left edge",
                        "opposite_edges": "top and left"
                    },
                    "SW": {
                        "dirt_corner": "bottom-left corner (SW)",
                        "dirt_edges": "bottom edge and left edge",
                        "grass_corner": "top-right corner (NE)",
                        "grass_edges": "top edge and right edge",
                        "opposite_edges": "top and right"
                    }
                }
                corner_info = corner_map.get(direction, {
                    "dirt_corner": "corner",
                    "dirt_edges": "edges",
                    "grass_corner": "opposite corner",
                    "grass_edges": "opposite edges",
                    "opposite_edges": "opposite edges"
                })
                variant_instructions = (
                    f"CRITICAL ORIENTATION: This is a {variant} tile (corner {direction}). "
                    f"The tile represents a grass tile where the {corner_info['dirt_corner']} is exposed to different terrain (dirt/stone). "
                    f"CRITICAL: Dirt/stone MUST fill the {corner_info['dirt_corner']} - this is the exposed corner where grass transitions to dirt/stone. "
                    f"CRITICAL: Grass MUST fill the {corner_info['grass_corner']} and extend along the {corner_info['grass_edges']} - this is where grass continues. "
                    f"The dirt/stone fills the {corner_info['dirt_corner']} and extends along the {corner_info['dirt_edges']} forming an L-shape. "
                    f"The grass fills the {corner_info['grass_corner']} and extends along the {corner_info['grass_edges']} forming the opposite L-shape. "
                    f"The transition between grass and dirt/stone should be a clean, sharp diagonal line from the {corner_info['dirt_corner']} to the center. "
                    f"The {corner_info['opposite_edges']} edges (where grass extends) must match seamlessly with base grass tiles when tiled. "
                    f"CRITICAL: The {corner_info['dirt_corner']} MUST be dirt/stone, NOT grass. "
                    f"CRITICAL: The {corner_info['grass_corner']} MUST be grass, NOT dirt/stone. "
                    f"Both areas should fill completely with no gaps or borders. "
                )
            elif variant.startswith("innerCorner"):
                direction = variant[-2:]  # NE, NW, SE, or SW
                corner_map = {
                    "NE": ("top-right", "top and right", "bottom-left", "bottom and left"),
                    "NW": ("top-left", "top and left", "bottom-right", "bottom and right"),
                    "SE": ("bottom-right", "bottom and right", "top-left", "top and left"),
                    "SW": ("bottom-left", "bottom and left", "top-right", "top and right")
                }
                dirt_corner, dirt_edges, grass_area, opposite_edges = corner_map.get(direction, ("corner", "edges", "inner area", "opposite edges"))
                variant_instructions = (
                    f"CRITICAL ORIENTATION: This is an inner (concave) corner tile. "
                    f"Grass fills the inner concave {grass_area} area (the area away from the {dirt_corner} corner). "
                    f"Dirt/stone fills the L-shaped area along the {dirt_edges} edges, meeting at the {dirt_corner} corner. "
                    f"The transition between grass and dirt/stone should be a clean, sharp line forming the concave corner. "
                    f"The {opposite_edges} edges (where grass extends) must match seamlessly with base grass tiles when tiled. "
                    f"CRITICAL: The grass area must fill the inner corner completely with no gaps, borders, or white/blank areas. "
                    f"CRITICAL: The dirt/stone L-shape must extend fully to the {dirt_edges} edges with no gaps, borders, or white/blank areas. "
                    f"CRITICAL: ALL FOUR CORNERS of the tile must be completely filled - the top-left corner, top-right corner, bottom-left corner, and bottom-right corner. "
                    f"NO white corners, NO blank corners, NO unfilled corners, NO empty corners - every single corner pixel must be filled with either grass or dirt/stone texture. "
                    f"The {dirt_corner} corner must be completely filled with dirt/stone texture extending all the way to the corner pixel. "
                    f"The opposite corner (where grass meets the edge) must be completely filled with grass texture extending all the way to the corner pixel. "
                    f"The other two corners must also be completely filled - one with grass and one with dirt/stone, depending on the layout. "
                    f"EVERY PIXEL in ALL FOUR CORNERS must be filled with ground texture - no exceptions, no white space, no blank areas. "
                )
            elif variant.startswith("transition"):
                direction = variant[-2:] if len(variant) > 10 else variant[-1]  # NE/NW/SE/SW or N/S/E/W
                direction_map = {"N": "top", "S": "bottom", "E": "right", "W": "left",
                               "NE": "top-right diagonal", "NW": "top-left diagonal", 
                               "SE": "bottom-right diagonal", "SW": "bottom-left diagonal"}
                trans_dir = direction_map.get(direction, "edge")
                variant_instructions = (
                    f"CRITICAL ORIENTATION: This is a transition tile. The {trans_dir} edge/diagonal should show "
                    f"a smooth blend and transition from grass to different terrain (dirt/stone). "
                    f"Other edges must match seamlessly with base grass tiles. "
                    f"The transition should be gradual and natural-looking, not a sharp line. "
                )
        
        # Strong, explicit prompt with repetition for emphasis
        # Add extra emphasis for base tiles (most critical for seamless tiling)
        base_tile_emphasis = ""
        if not variant or variant == "base":
            base_tile_emphasis = (
                f"CRITICAL FOR BASE TILE: This is a BASE ground tile that will be repeated thousands of times to fill the entire map. "
                f"It is ABSOLUTELY CRITICAL that the entire image area is completely filled from edge to edge. "
                f"EVERY SINGLE PIXEL must be part of the ground texture - no transparent areas, no empty corners, no unfilled edges. "
                f"The entire {self.tile_size}x{self.tile_size} pixel area MUST be completely filled with ground texture. "
                f"NO exceptions - the entire frame from top-left corner to bottom-right corner must be solid ground texture. "
            )
        
        # Add explicit anti-clump instruction for grass tiles (even with custom descriptions)
        anti_clump_instruction = ""
        if ground_type == "grass" or (variant and "grass" in str(variant).lower()):
            anti_clump_instruction = (
                f"CRITICAL GRASS DISTRIBUTION: The grass must be evenly and uniformly distributed across the ENTIRE tile surface. "
                f"NO clumps, NO clusters, NO grouped patches, NO concentrated areas, NO circular formations. "
                f"The grass should have consistent, even density throughout - think of a well-maintained lawn, not wild patches. "
                f"Every area of the tile should have similar grass coverage - avoid any areas that look more dense or sparse than others. "
            )
        
        prompt = (
            f"{base_desc}. {style_instruction}. "
            f"{texture_emphasis}"
            f"{anti_clump_instruction}"
            f"{base_tile_reference}"
            f"{variant_instructions}"
            f"{base_tile_emphasis}"
            f"Single ground tile only, one tile only, no objects, no creatures. "
            f"CRITICAL: Tile must completely fill the entire frame from edge to edge. "
            f"No empty space, no gaps, no padding, no margin, no border. "
            f"Tile extends to all four edges - top edge, bottom edge, left edge, right edge. "
            f"EVERY PIXEL MUST BE FILLED: The entire {self.tile_size}x{self.tile_size} pixel image area must be completely filled with ground texture. "
            f"No transparent pixels, no empty areas, no unfilled corners, no blank spaces - the entire image from corner to corner must be solid ground texture. "
            f"SEAMLESS TILEABLE FROM ALL SIDES: Tile must seamlessly connect on ALL four sides when tiled repeatedly. "
            f"Top edge must match bottom edge perfectly when tiled vertically. "
            f"Left edge must match right edge perfectly when tiled horizontally. "
            f"When multiple tiles are placed together, they should form one continuous seamless surface with no visible seams. "
            f"CRITICAL TILING: The pattern should repeat seamlessly in all directions. "
            f"Top border of tile should seamlessly connect with bottom border of tile above it. "
            f"Bottom border of tile should seamlessly connect with top border of tile below it. "
            f"Left border of tile should seamlessly connect with right border of tile to its left. "
            f"Right border of tile should seamlessly connect with left border of tile to its right. "
            f"SOLID SEAMLESS IMAGE: No visible grid lines, no tile boundaries, no dividing lines, "
            f"no segmentation marks, no grid overlay, no tile markers, no checkerboard pattern. "
            f"NO base. NO ground patch. NO pedestal. NO square base. "
            f"CRITICAL EDGE REQUIREMENTS: Ground texture must extend all the way to the very edge of the image on ALL four sides. "
            f"NO borders of ANY kind - NO black borders, NO dark borders, NO light borders, NO colored borders, NO frame, NO outline, NO rim, NO margin, NO padding. "
            f"NO edge darkening - edges must have the SAME brightness, color, and texture as the center of the tile. "
            f"NO edge shadows, NO edge gradients, NO edge fading, NO edge dimming, NO edge darkening effects. "
            f"The edges must look IDENTICAL to the center - same color, same brightness, same texture density. "
            f"The ground texture must touch and fill every single edge pixel - top edge, bottom edge, left edge, right edge. "
            f"ALL four edges must be filled with ground texture with NO visual difference from the center. "
            f"The ground texture must extend pixel-perfect to the absolute edge with NO border effects. "
            f"EDGE-TO-EDGE GROUND: The ground texture pattern must continue uninterrupted right up to and including every border pixel. "
            f"No borders visible anywhere - not at edges, not at corners, not in the middle. "
            f"No darkening visible anywhere - edges must be as bright and vibrant as the center. "
            f"Pure ground texture filling the entire frame with uniform appearance from edge to edge. "
        )
        
        # Negative prompt to avoid unwanted features - emphasize NO black borders/edges and NO fine textures
        negative_prompt = (
            "multiple objects, two objects, three objects, many objects, several objects, "
            "duplicate objects, repeated objects, creatures, animals, characters, people, "
            "cluttered, complex background, detailed background, textured background, "
            "colored background, gradient background, white background, transparent background, "
            "realistic photo, 3D render, blurry, low quality, text, watermark, signature, "
            "anime style, chibi style, super-deformed, hyper-realistic concept art, "
            "Pixar style, DreamWorks style, kid-like, childish, "
            "side view, front view, not isometric, not top-down, "
            "grid lines, tile boundaries, dividing lines, segmentation marks, grid overlay, "
            "tile markers, checkerboard pattern, tile grid, visible grid, grid pattern, "
            "(base at bottom:3.0), (ground patch:3.0), (pedestal:3.0), (square base:3.0), "
            "empty space around edges, gaps, padding, margin, border, "
            "(black border:5.0), (black edges:5.0), (black frame:5.0), (black outline:5.0), (black rim:5.0), (black margin:5.0), "
            "(black border around edges:5.0), (black frame around image:5.0), (black outline border:5.0), "
            "black background, black corners, black edges, black borders, black frame, black outline, "
            "any black visible at edges, any black at corners, any black anywhere in the image, "
            "borders, border effects, edge borders, frame borders, outline borders, rim borders, "
            "edge darkening, edge shadows, edge gradients, edge fading, edge dimming, edge darkening effects, "
            "darkened edges, shadowed edges, gradient edges, faded edges, dimmed edges, "
            "edge contrast, edge brightness difference, edge color difference, edge variation, "
            "darker edges, lighter edges, edge effects, border effects, frame effects, "
            "any visual difference at edges, any brightness difference at edges, any color difference at edges, "
            "fine texture, subtle texture, delicate texture, small texture details, tiny patterns, "
            "microscopic details, fine grain, small-scale texture, barely visible texture, "
            "smooth texture, flat texture, uniform texture, textureless, no visible texture, "
            "circular patterns, round shapes, circular clumps, circular patches, circular textures, "
            "geometric circles, round objects, circular arrangements, circular formations, "
            "orb shapes, sphere patterns, ring patterns, circular rings, circular designs, "
            "clumps, clusters, grouped patches, concentrated patches, clustered grass, "
            "grass clumps, grass clusters, grouped formations, uneven distribution, "
            "patchy grass, clumped grass, clustered patterns, grouped patterns"
        )
        
        return prompt, negative_prompt
    
    def build_prompt_for_tile(self, tile_info: Dict) -> Tuple[str, str]:
        """Build prompt and negative prompt for generating a tile image"""
        name = tile_info.get("name", "")
        description = tile_info.get("description", "")
        entity_type = tile_info.get("type", "item")
        tile_id = tile_info.get("tile_id", "")
        tile_map = tile_info.get("tile_map", None)
        ground_type = tile_info.get("ground_type", None)  # For ground tiles
        ground_variant = tile_info.get("ground_variant", None)  # For grass variants
        
        # If this is a ground tile, use the ground tile prompt builder
        if ground_type:
            # Get map_file and custom_description from tile_info if available
            map_file = tile_info.get("map_file", None)
            custom_description = tile_info.get("custom_description", None)
            return self.build_prompt_for_ground_tile(ground_type, ground_variant, map_file=map_file, custom_description=custom_description)
        
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
            
            # Describe the size/dimensions for the AI - AVOID mentioning "tiles" or "grid" in visual description
            # CRITICAL: This is ONLY for size reference - the image should be ONE SOLID CONTINUOUS OBJECT
            # Do NOT visualize tiles, grid, rows, or any segmentation - just generate a single seamless image
            # Use visual descriptions like "width" and "height" instead of "tiles"
            if num_rows > 1:
                # Describe shape without mentioning tiles
                if max_cols > num_rows:
                    shape_desc = f"wide horizontal sprite" if max_cols > num_rows * 2 else f"rectangular sprite"
                elif num_rows > max_cols:
                    shape_desc = f"tall vertical sprite" if num_rows > max_cols * 2 else f"rectangular sprite"
                else:
                    shape_desc = f"square sprite"
                
                # Describe the object shape (wider at top, narrower at bottom, etc.) without mentioning tiles
                layout_desc = f"{shape_desc}, {width_px} pixels wide and {height_px} pixels tall"
            else:
                layout_desc = f"{width_px}x{height_px} pixel sprite"
            
            # Add CRITICAL note about seamless image
            layout_desc += ". CRITICAL: Generate as ONE SOLID CONTINUOUS OBJECT - no grid lines, no divisions, no segmentation, no visible boundaries, no checkerboard, no tile marks, completely seamless image"
            
            size_instruction = f"{layout_desc}, EXACTLY {width_px}x{height_px} pixels (width {width_px} pixels, height {height_px} pixels), CRITICAL: entire image must fill full {height_px} pixel height from top to bottom with seamless continuous object, no cropping, no missing bottom content, "
        else:
            size_instruction = f"single tile, {self.tile_size}x{self.tile_size} pixel sprite, "
        
        # Add style requirements similar to character generation
        # Use isometric/top-down perspective for game tiles
        style_instruction = f"Isometric top-down view game sprite, {size_instruction}game asset style matching existing tileset, clean edges, pixel art aesthetic, game-ready asset"
        
        # Strong, explicit prompt with repetition for emphasis
        # Note: Prompt weighting syntax like (keyword:weight) may or may not be supported by Flux-2-pro
        # Using explicit repetition instead for guaranteed effect
        prompt = (
            f"{base_desc}. {style_instruction}. "
            f"Single object only, one object only, no other objects. "
            f"CRITICAL: Object must completely fill the entire frame from edge to edge. "
            f"No empty space, no gaps, no padding, no margin, no border. "
            f"Object extends to all four edges - top edge, bottom edge, left edge, right edge. "
            f"Full object visible from top to bottom edge, nothing cut off at bottom, "
            f"complete from top row to bottom row. "
            f"SOLID SEAMLESS IMAGE: No visible grid lines, no tile boundaries, no dividing lines, "
            f"no segmentation marks, no grid overlay, no tile markers, no checkerboard pattern. "
            f"Generate as ONE continuous solid object - the image will be split into tiles later during processing. "
            f"NO base. NO ground patch. NO pedestal. NO square base. "
            f"NO green base. NO brown base. NO grass base. NO dirt base. NO stone base. "
            f"NO base at bottom. NO ground tile at bottom. NO base element. "
            f"Object extends directly to bottom edge without any base element or ground tile. "
            f"Black background, solid black background only, no other background elements."
        )
        
        # Negative prompt to avoid unwanted features - use weighting for emphasis
        # Repeat key unwanted terms to increase their weight
        negative_prompt = (
            "multiple objects, two objects, three objects, many objects, several objects, "
            "duplicate objects, repeated objects, cluttered, complex background, "
            "detailed background, textured background, colored background, gradient background, "
            "white background, transparent background, realistic photo, 3D render, blurry, "
            "low quality, text, watermark, signature, anime style, chibi style, super-deformed, "
            "hyper-realistic concept art, Pixar style, DreamWorks style, kid-like, childish, "
            "side view, front view, not isometric, not top-down, "
            "grid lines, tile boundaries, dividing lines, segmentation marks, grid overlay, "
            "tile markers, checkerboard pattern, tile grid, visible grid, grid pattern, "
            "grid structure, grid layout, grid segmentation, tile divisions, tile borders, "
            "(base at bottom:3.0), (ground patch:3.0), (pedestal:3.0), (square base:3.0), "
            "(green base:3.0), (brown base:3.0), (ground tile:3.0), (base element:3.0), "
            "(grass base:3.0), (dirt base:3.0), (stone base:3.0), "
            "empty space around edges, gaps, padding, margin, border, "
            "(unwanted base at bottom:4.0), (unwanted ground element:4.0)"
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
        
        # Ask user if they want to replace or append to existing atlas
        replace_atlas = False
        if atlas_png.exists():
            interactive = not getattr(self, '_no_interactive', False)
            if interactive:
                print(f"\n📦 Found existing atlas: {atlas_png.name}")
                response = input("   Replace existing atlas (r) or append to it (a)? [a]: ").strip().lower()
                if response == 'r' or response == 'replace':
                    replace_atlas = True
                    print(f"   ✅ Will replace existing atlas")
                else:
                    print(f"   ✅ Will append to existing atlas")
            else:
                # In non-interactive mode, default to append
                replace_atlas = False
                print(f"\n📦 Found existing atlas: {atlas_png.name} (non-interactive mode: will append)")
            
            if replace_atlas:
                # Delete existing atlas and metadata
                atlas_png.unlink()
                metadata_path = atlas_png.with_suffix('.json')
                if metadata_path.exists():
                    metadata_path.unlink()
                print(f"   🗑️  Deleted existing atlas and metadata")
        
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
        
        # Get atlas name for tile ID generation
        # Normalize to use underscores instead of hyphens to avoid parsing issues
        # ChunkSystem splits on first "-" to get atlas name and frame number
        # So atlas name should not contain hyphens (use underscores instead)
        atlas_name = atlas_png.stem.replace("-", "_")  # e.g., "grassland-atlas" -> "grassland_atlas"
        
        # Find entities needing generation
        print("\n📋 Scanning for entities with 'tileMap' or 'generate' in tileGrid...")
        entities_needing_gen = self.find_entities_needing_generation(prefab_file)
        
        # Also check for ground tiles if this is a map file
        ground_tiles_needing_gen = self.find_ground_tiles_needing_generation(prefab_file, atlas_name)
        
        if not entities_needing_gen and not ground_tiles_needing_gen:
            print("✅ No entities or ground tiles found with 'generate' in tileGrid or groundTiles")
            return
        
        if entities_needing_gen:
            print(f"✅ Found {len(entities_needing_gen)} entities needing generation")
        if ground_tiles_needing_gen:
            print(f"✅ Found {len(ground_tiles_needing_gen)} ground tiles needing generation")
        
        # Check if dry run mode
        if hasattr(self, '_dry_run') and self._dry_run:
            print("\n📊 Entities to generate:")
            for entity_info in entities_needing_gen:
                entity = entity_info["entity"]
                print(f"   - {entity.get('name', entity.get('id', 'Unknown'))} ({entity_info['entity_type']})")
            if ground_tiles_needing_gen:
                print("\n📊 Ground tiles to generate:")
                for ground_info in ground_tiles_needing_gen:
                    variant = ground_info.get("ground_variant")
                    if variant:
                        print(f"   - {ground_info['ground_type']} ({variant})")
                    else:
                        print(f"   - {ground_info['ground_type']}")
            print("\n🔍 Dry run complete - no images generated")
            return
        
        # Create tiles directory
        tiles_dir = atlas_png.parent / "tiles"
        tiles_dir.mkdir(parents=True, exist_ok=True)
        
        interactive = not getattr(self, '_no_interactive', False)
        generated_tiles = {}
        
        # Process ground tiles FIRST (before entities) - they're simpler and may be referenced by entities
        if ground_tiles_needing_gen:
            print(f"\n{'='*60}")
            print(f"🎨 Processing {len(ground_tiles_needing_gen)} ground tiles...")
            print(f"{'='*60}")
            
            interactive = not getattr(self, '_no_interactive', False)
            atlas_name = atlas_png.stem.replace("-", "_")  # Normalize to underscores
            
            for idx, ground_info in enumerate(ground_tiles_needing_gen, 1):
                ground_type = ground_info["ground_type"]
                variant = ground_info.get("ground_variant")
                replace_tile_id = ground_info.get("replace_tile_id")
                display_name = f"{ground_type} ({variant})" if variant else ground_type
                
                print(f"\n[{idx}/{len(ground_tiles_needing_gen)}] Processing ground tile: {display_name}")
                
                if replace_tile_id:
                    print(f"   🔄 REPLACEMENT MODE: Will replace existing tile {replace_tile_id}")
                
                # Build prompt for ground tile (include map_file for base tile reference and custom_description if provided)
                tile_info = {
                    "ground_type": ground_type,
                    "ground_variant": variant,
                    "type": "ground_tile",
                    "map_file": prefab_file,  # Pass map file for base tile lookup
                    "custom_description": ground_info.get("custom_description")  # Pass custom description if provided
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
                    
                    # Generate single tile for ground at 32x32 pixels
                    # Ground tiles are repeated many times and don't need high resolution
                    # 32x32 is sufficient for seamless tiling and keeps file sizes small
                    generate_size = 32
                    print(f"   🎨 Generating ground tile at {generate_size}x{generate_size} pixels...")
                    image = self.generate_image_text_to_image(
                        prompt=prompt,
                        negative_prompt=negative_prompt,
                        size=generate_size,
                        width=generate_size,
                        height=generate_size
                    )
                    
                    if not image:
                        print(f"   ❌ Failed to generate image")
                        if attempts >= max_attempts:
                            print(f"   ⚠️ Skipping after {max_attempts} failed attempts")
                            break
                        continue
                    
                    # Resize to match requested size if needed
                    actual_width, actual_height = image.size
                    if actual_width != generate_size or actual_height != generate_size:
                        print(f"   ⚠️ Generated size {actual_width}x{actual_height} differs from requested {generate_size}x{generate_size}")
                        # Resize to match requested size
                        image = image.resize((generate_size, generate_size), Image.Resampling.LANCZOS)
                    
                    # Show for approval if interactive mode
                    if interactive:
                        approved = self.show_image_for_approval(image, display_name, tile_info)
                        if not approved:
                            if attempts >= max_attempts:
                                print(f"   ⚠️ Skipping after {max_attempts} rejections")
                                break
                            continue
                    else:
                        approved = True
                    
                    # Ground tiles should NOT have their backgrounds removed - they need to tile seamlessly
                    # Only remove background for entity tiles (trees, items, etc.)
                    # Keep ground tiles as-is (no background removal needed for seamless tiling)
                    print(f"   ✅ Keeping ground tile at {generate_size}x{generate_size} without background removal (ground tiles need seamless tiling)")
                    
                    # Save temp tile and add to atlas
                    temp_tile_path = tiles_dir / f"ground_{ground_type}_{variant if variant else 'base'}_temp.png"
                    image.save(temp_tile_path)
                    
                    # Add to atlas or replace existing tile
                    if replace_tile_id:
                        # Replace existing tile
                        print(f"   🔄 Replacing tile in atlas...")
                        success = self.replace_tile_in_atlas(replace_tile_id, temp_tile_path, atlas_png, tile_info)
                        if not success:
                            # If replacement failed (tile doesn't exist), add it as a new tile instead
                            print(f"   ⚠️  Tile {replace_tile_id} not found in atlas, adding as new tile instead...")
                            print(f"   📦 Adding to atlas...")
                            frame_number = self.add_tile_to_atlas(temp_tile_path, atlas_png, tile_info)
                            tile_id = f"{atlas_name}-{frame_number}"
                            print(f"   ✅ Added tile as {tile_id} (original ID {replace_tile_id} didn't exist)")
                        else:
                            tile_id = replace_tile_id  # Use the original tile ID
                    else:
                        # Add new tile
                        print(f"   📦 Adding to atlas...")
                        frame_number = self.add_tile_to_atlas(temp_tile_path, atlas_png, tile_info)
                        tile_id = f"{atlas_name}-{frame_number}"
                    
                    # Update map file with tile ID (replace -r suffix with actual tile ID)
                    if replace_tile_id:
                        print(f"   📝 Updating map file: replacing '{replace_tile_id}-r' with '{tile_id}'")
                        self.update_map_with_ground_tile(ground_info, tile_id, prefab_file, old_tile_id_with_suffix=f"{replace_tile_id}-r")
                    else:
                        print(f"   📝 Updating map file with tile ID: {tile_id}")
                        self.update_map_with_ground_tile(ground_info, tile_id, prefab_file)
                    
                    # Clean up temp file
                    try:
                        temp_tile_path.unlink()
                    except:
                        pass
                    
                    generated_tiles[tile_id] = temp_tile_path
                    print(f"   ✅ Complete! Ground tile ID: {tile_id}")
                    break
                
                # Rate limiting
                if idx < len(ground_tiles_needing_gen):
                    time.sleep(1)
        
        # Process each entity
        for idx, entity_info in enumerate(entities_needing_gen, 1):
            entity = entity_info["entity"]
            entity_name = entity.get("name", entity.get("id", "Unknown"))
            entity_desc = entity.get("description", "")
            entity_type = entity_info["entity_type"]
            replace_tile_id = entity_info.get("replace_tile_id")
            
            print(f"\n[{idx}/{len(entities_needing_gen)}] Processing: {entity_name} ({entity_type})")
            
            if replace_tile_id:
                print(f"   🔄 REPLACEMENT MODE: Will replace existing tile {replace_tile_id}")
            
            # Check if entity already has tiles assigned to this atlas (skip if replacing a specific tile)
            existing_tile_ids = []
            if not replace_tile_id:
                existing_tile_ids = self.extract_existing_tile_ids_from_entity(entity, atlas_name)
            
            should_skip = False
            if existing_tile_ids:
                print(f"   🔍 Found {len(existing_tile_ids)} existing tile(s) for this entity: {existing_tile_ids}")
                if interactive:
                    # Ask user if they want to replace or keep existing
                    while True:
                        response = input(f"   Replace existing tiles? (y/n/yes/no): ").strip().lower()
                        if response in ['y', 'yes']:
                            # Remove old tiles from atlas
                            print(f"   🗑️  Removing old tiles from atlas...")
                            self.remove_tiles_from_atlas(existing_tile_ids, atlas_png)
                            break
                        elif response in ['n', 'no']:
                            print(f"   ⏭️  Keeping existing tiles, skipping generation for this entity")
                            should_skip = True
                            break
                        else:
                            print("   Please enter 'y'/'yes' to replace or 'n'/'no' to skip")
                else:
                    # Non-interactive: automatically remove old tiles
                    print(f"   🗑️  Automatically removing old tiles from atlas (non-interactive mode)...")
                    self.remove_tiles_from_atlas(existing_tile_ids, atlas_png)
            
            # Skip this entity if user chose to keep existing tiles
            if should_skip:
                continue
            
            # Check if using tileMap or legacy "generate"
            tile_map_str = entity_info.get("tile_map")
            
            # Get the correct tile size from the part if available (entities may use different sizes than ground tiles)
            entity_tile_size = self.tile_size  # Default to global tile_size
            entity = entity_info.get("entity", {})
            part_index = entity_info.get("part_index")
            if part_index is not None:
                parts = entity.get("parts", [])
                if part_index < len(parts):
                    part = parts[part_index]
                    part_tile_size = part.get("tileSize", 0)
                    if part_tile_size > 0:
                        entity_tile_size = int(part_tile_size)
                        print(f"   📏 Using part tileSize: {entity_tile_size}px (part index {part_index})")
                    else:
                        print(f"   📏 Part has no tileSize, using global: {entity_tile_size}px")
                else:
                    print(f"   ⚠️ Part index {part_index} out of range (entity has {len(parts)} parts), using global tileSize: {entity_tile_size}px")
            else:
                # Try to get tileSize from first part if available
                parts = entity.get("parts", [])
                if parts:
                    first_part_tile_size = parts[0].get("tileSize", 0)
                    if first_part_tile_size > 0:
                        entity_tile_size = int(first_part_tile_size)
                        print(f"   📏 Using first part tileSize: {entity_tile_size}px")
            
            if tile_map_str:
                # Parse tileMap (e.g., "2,3,1" -> [2, 3, 1])
                tile_map_counts = self.parse_tile_map(tile_map_str)
                num_rows = len(tile_map_counts)
                max_cols = max(tile_map_counts) if tile_map_counts else 1
                
                # Calculate image size based on tileMap using entity's tile size
                image_width = max_cols * entity_tile_size
                image_height = num_rows * entity_tile_size
                
                print(f"   📐 TileMap: {tile_map_str} -> {num_rows} rows, max {max_cols} cols")
                print(f"   📏 Image size: {image_width}x{image_height} pixels (tile size: {entity_tile_size}px)")
            else:
                # Legacy: single tile
                tile_map_counts = [1]
                num_rows = 1
                max_cols = 1
                image_width = entity_tile_size
                image_height = entity_tile_size
            
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
                    # Single tile: generate at high resolution (1024x1024) for quality
                    # SpriteKit will scale these down when displaying, preserving quality
                    generate_width = 1024
                    generate_height = 1024
                
                print(f"   🎨 Generating image at {generate_width}x{generate_height} pixels (high resolution - will be kept at this size)")
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
                
                # Verify and resize to calculated size
                # First, check if generated image matches expected dimensions (within tolerance)
                generated_width, generated_height = image.size
                expected_width = generate_width
                expected_height = generate_height
                
                # Warn if dimensions are significantly off
                width_diff = abs(generated_width - expected_width) / expected_width if expected_width > 0 else 0
                height_diff = abs(generated_height - expected_height) / expected_height if expected_height > 0 else 0
                
                if width_diff > 0.05 or height_diff > 0.05:
                    print(f"   ⚠️ Generated image size {generated_width}x{generated_height} differs from expected {expected_width}x{expected_height}")
                    print(f"      Width diff: {width_diff*100:.1f}%, Height diff: {height_diff*100:.1f}%")
                
                # CRITICAL: Check if generated image is missing bottom content
                # If height is significantly less than expected, reject and regenerate
                if generated_height < expected_height * 0.9:
                    print(f"   ❌ REJECTING: Generated image height ({generated_height}) is too short - missing bottom content!")
                    print(f"      Expected: {expected_height}, Got: {generated_height} (missing {expected_height - generated_height} pixels at bottom)")
                    if attempts < max_attempts:
                        print(f"      Regenerating to ensure full height...")
                        continue  # Skip to next attempt
                    else:
                        print(f"      Max attempts reached - proceeding with partial image (will stretch)")
                
                # Keep at high resolution - don't resize down
                # SpriteKit will handle scaling when displaying, preserving quality
                actual_width, actual_height = image.size
                if actual_width != generate_width or actual_height != generate_height:
                    print(f"   ⚠️ Generated size {actual_width}x{actual_height} differs from requested {generate_width}x{generate_height}")
                    # Resize to match requested size if needed
                    if actual_width != generate_width or actual_height != generate_height:
                        image = image.resize((generate_width, generate_height), Image.Resampling.LANCZOS)
                else:
                    print(f"   ✅ Generated at high resolution: {generate_width}x{generate_height}")
                
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
                # IMPORTANT: Add padding before background removal to prevent cropping
                # Background removal might auto-crop, so we pad to ensure full content is preserved
                print(f"   📏 Image before background removal: {image.size[0]}x{image.size[1]} (target: {image_width}x{image_height})")
                
                padding = max(10, self.tile_size // 4)  # Add padding (at least 10px or 1/4 tile size)
                padded_width = image_width + (padding * 2)
                padded_height = image_height + (padding * 2)
                
                # Create padded image with black background
                padded_image = Image.new('RGBA', (padded_width, padded_height), (0, 0, 0, 255))
                # Paste original image centered in padded image
                paste_x = (padded_width - actual_width) // 2
                paste_y = (padded_height - actual_height) // 2
                print(f"   📦 Adding padding: {padding}px on all sides, pasting original at ({paste_x}, {paste_y})")
                padded_image.paste(image, (paste_x, paste_y))
                
                print(f"   🎨 Removing background from padded image ({padded_width}x{padded_height})...")
                image_no_bg = self.remove_background(padded_image)
                
                if image_no_bg:
                    # Check if background removal changed the size
                    bg_removed_width, bg_removed_height = image_no_bg.size
                    if bg_removed_width != padded_width or bg_removed_height != padded_height:
                        print(f"   ⚠️ Background removal changed size from {padded_width}x{padded_height} to {bg_removed_width}x{bg_removed_height}")
                        # If background removal cropped the image (made it smaller),
                        # resize it back to padded size first to restore full dimensions
                        # This preserves what content remains, even if slightly stretched
                        if bg_removed_width < padded_width or bg_removed_height < padded_height:
                            print(f"   ⚠️ Background removal cropped content, resizing back to padded size...")
                            image_no_bg = image_no_bg.resize((padded_width, padded_height), Image.Resampling.LANCZOS)
                    
                    print(f"   📏 Image after background removal: {bg_removed_width}x{bg_removed_height} (expected padded: {padded_width}x{padded_height})")
                    
                    # Crop back to original high-res size (removing padding from all sides)
                    # The padding ensures that even if background removal cropped some edges,
                    # our content should still be in the padded region
                    crop_box = (padding, padding, padding + actual_width, padding + actual_height)
                    print(f"   ✂️  Cropping to remove padding: crop_box=({crop_box[0]}, {crop_box[1]}, {crop_box[2]}, {crop_box[3]})")
                    
                    # Verify crop box is within image bounds
                    if crop_box[2] > bg_removed_width or crop_box[3] > bg_removed_height:
                        print(f"   ⚠️ WARNING: Crop box extends beyond image bounds!")
                        print(f"      Crop box: ({crop_box[0]}, {crop_box[1]}, {crop_box[2]}, {crop_box[3]})")
                        print(f"      Image size: {bg_removed_width}x{bg_removed_height}")
                        # Adjust crop box to fit within image
                        crop_box = (
                            crop_box[0],
                            crop_box[1],
                            min(crop_box[2], bg_removed_width),
                            min(crop_box[3], bg_removed_height)
                        )
                        print(f"      Adjusted crop box: ({crop_box[0]}, {crop_box[1]}, {crop_box[2]}, {crop_box[3]})")
                    
                    image_no_bg = image_no_bg.crop(crop_box)
                    final_width, final_height = image_no_bg.size
                    print(f"   📏 Image after cropping: {final_width}x{final_height} (target: {actual_width}x{actual_height})")
                    
                    # Keep at high resolution - don't resize down
                    # SpriteKit will handle scaling when displaying
                    final_width, final_height = image_no_bg.size
                    if final_width != actual_width or final_height != actual_height:
                        print(f"   📏 Resizing to match original high-res size: {actual_width}x{actual_height}")
                        image_no_bg = image_no_bg.resize((actual_width, actual_height), Image.Resampling.LANCZOS)
                    else:
                        print(f"   ✅ Image kept at high resolution: {actual_width}x{actual_height}")
                    
                    image = image_no_bg
                else:
                    print("   ⚠️ Background removal failed, using original image")
                
                if tile_map_str:
                    # Handle tileMap: split image into tiles and add to atlas
                    # CRITICAL: Verify image dimensions match expected before extraction
                    actual_width, actual_height = image.size
                    if actual_width != image_width or actual_height != image_height:
                        print(f"   ⚠️ WARNING: Image size mismatch before extraction!")
                        print(f"      Expected: {image_width}x{image_height}")
                        print(f"      Actual: {actual_width}x{actual_height}")
                        if actual_width < image_width or actual_height < image_height:
                            print(f"      ❌ Image is smaller than expected - tiles may be missing!")
                    
                    print(f"   ✂️  Splitting image into {num_rows} rows based on tileMap...")
                    tile_map_layout = []
                    frame_numbers = []
                    atlas_name = atlas_png.stem.replace("-", "_")  # Normalize to underscores
                    
                    # Determine layer structure to calculate per-layer center offsets
                    # All rows in the same layer should use the SAME center offset (based on widest row in that layer)
                    num_rows = len(tile_map_counts)
                    if num_rows <= 2:
                        # Single low layer: all rows use the same offset
                        low_row_indices = list(range(num_rows))
                        high_row_indices = []
                    else:
                        # Last 2 rows = low layer, first rows = high layer
                        low_row_indices = list(range(num_rows - 2, num_rows))  # Last 2 rows
                        high_row_indices = list(range(num_rows - 2))  # First rows
                    
                    # Calculate max width per layer (use entity_tile_size for extraction, not self.tile_size)
                    low_layer_max_width = max([tile_map_counts[i] * entity_tile_size for i in low_row_indices]) if low_row_indices else 0
                    high_layer_max_width = max([tile_map_counts[i] * entity_tile_size for i in high_row_indices]) if high_row_indices else 0
                    
                    # Calculate center offsets per layer
                    low_layer_center_offset = (actual_width - low_layer_max_width) / 2 if actual_width > low_layer_max_width and low_layer_max_width > 0 else 0
                    high_layer_center_offset = (actual_width - high_layer_max_width) / 2 if actual_width > high_layer_max_width and high_layer_max_width > 0 else 0
                    
                    print(f"   📐 Layer offsets: high={high_layer_center_offset:.0f}px (max {high_layer_max_width}px), low={low_layer_center_offset:.0f}px (max {low_layer_max_width}px)")
                    
                    # Split image into tiles based on tileMap (use entity_tile_size for extraction)
                    current_frame = 1
                    print(f"   📐 Extracting tiles from image ({actual_width}x{actual_height}) (expected {image_width}x{image_height}) using tile size {entity_tile_size}px...")
                    for row_idx, tile_count in enumerate(tile_map_counts):
                        row_tiles = []
                        y = row_idx * entity_tile_size
                        
                        # Use the appropriate center offset for this row's layer
                        if row_idx in low_row_indices:
                            center_offset_x = low_layer_center_offset
                        elif row_idx in high_row_indices:
                            center_offset_x = high_layer_center_offset
                        else:
                            # Fallback: center this specific row
                            row_width = tile_count * entity_tile_size
                            center_offset_x = (actual_width - row_width) / 2 if actual_width > row_width else 0
                        
                        row_width = tile_count * entity_tile_size
                        start_x = center_offset_x
                        end_x = center_offset_x + row_width
                        layer_name = "low" if row_idx in low_row_indices else "high"
                        print(f"      Row {row_idx} ({layer_name}): extracting {tile_count} tiles (centered from x={start_x:.0f} to x={end_x:.0f}, y={y} to y={y + entity_tile_size})")
                        
                        # Verify row is within image bounds
                        if y + entity_tile_size > actual_height:
                            print(f"         ⚠️ WARNING: Row {row_idx} extends beyond image height! (y={y}, tile_size={entity_tile_size}, image_height={actual_height})")
                        
                        for col_idx in range(tile_count):
                            # Extract tile from image (centered if row is narrower than image)
                            x = center_offset_x + (col_idx * entity_tile_size)
                            
                            # Verify tile is within image bounds
                            if x + entity_tile_size > actual_width:
                                print(f"         ⚠️ WARNING: Tile at col {col_idx} extends beyond image width! (x={x}, tile_size={entity_tile_size}, image_width={actual_width})")
                            
                            # Ensure crop coordinates are within image bounds
                            crop_left = max(0, x)
                            crop_top = max(0, y)
                            crop_right = min(actual_width, x + entity_tile_size)
                            crop_bottom = min(actual_height, y + entity_tile_size)
                            
                            # Validate crop box before extracting
                            if crop_right <= crop_left or crop_bottom <= crop_top:
                                print(f"         ❌ ERROR: Invalid crop box for tile ({col_idx},{row_idx}): ({crop_left},{crop_top},{crop_right},{crop_bottom})")
                                # Create empty tile instead of skipping
                                tile_image = Image.new('RGBA', (entity_tile_size, entity_tile_size), (0, 0, 0, 0))
                                print(f"         ⚠️ Created empty tile as placeholder")
                            else:
                                tile_image = image.crop((crop_left, crop_top, crop_right, crop_bottom))
                            
                            # If crop resulted in smaller tile, pad or resize to entity_tile_size
                            if tile_image.size[0] != entity_tile_size or tile_image.size[1] != entity_tile_size:
                                print(f"         ⚠️ WARNING: Extracted tile size {tile_image.size} != expected {entity_tile_size}x{entity_tile_size}")
                                # Always resize to expected size (even if empty, to maintain grid structure)
                                if tile_image.size[0] > 0 and tile_image.size[1] > 0:
                                    tile_image = tile_image.resize((entity_tile_size, entity_tile_size), Image.Resampling.LANCZOS)
                                else:
                                    # Create empty tile instead of skipping - we need to maintain the tileGrid structure
                                    tile_image = Image.new('RGBA', (entity_tile_size, entity_tile_size), (0, 0, 0, 0))
                                    print(f"         ⚠️ Tile was empty, created transparent placeholder to maintain grid")
                            
                            # Save temp tile
                            temp_tile_path = tiles_dir / f"tile_{idx}_r{row_idx}_c{col_idx}_temp.png"
                            tile_image.save(temp_tile_path)
                            
                            # Add to atlas
                            frame_number = self.add_tile_to_atlas(temp_tile_path, atlas_png, tile_info)
                            frame_numbers.append(frame_number)
                            tile_id = f"{atlas_name}-{frame_number}"
                            row_tiles.append(tile_id)
                            
                            # Check if tile has content (not fully transparent)
                            has_content = False
                            if tile_image.mode == 'RGBA':
                                # Check if any pixel is not fully transparent
                                alpha_channel = tile_image.split()[3]
                                has_content = any(alpha_channel.getdata())
                            else:
                                has_content = True
                            
                            content_status = "✅" if has_content else "⚠️ (transparent/empty)"
                            print(f"         Col {col_idx}: extracted from ({x:.0f},{y:.0f}) to ({crop_right:.0f},{crop_bottom:.0f}) -> {tile_id} (frame {frame_number}) {content_status}")
                            
                            # Clean up temp file
                            try:
                                temp_tile_path.unlink()
                            except:
                                pass
                            
                            current_frame += 1
                        
                        # Validate row has expected number of tiles
                        expected_tile_count = tile_count
                        actual_tile_count = len(row_tiles)
                        if actual_tile_count != expected_tile_count:
                            print(f"      ⚠️ WARNING: Row {row_idx} has {actual_tile_count} tiles but expected {expected_tile_count}!")
                            print(f"         This will cause a mismatch in the tileGrid structure!")
                        
                        tile_map_layout.append(row_tiles)
                        print(f"      Row {row_idx} complete: {row_tiles} ({actual_tile_count}/{expected_tile_count} tiles)")
                    
                    # Validate tile_map_layout matches tileMap structure
                    print(f"   📝 Updating prefab file with tileMap structure...")
                    print(f"   📋 Tile layout to write:")
                    for row_idx, row in enumerate(tile_map_layout):
                        expected_count = tile_map_counts[row_idx] if row_idx < len(tile_map_counts) else 0
                        actual_count = len(row)
                        status = "✅" if actual_count == expected_count else "❌"
                        print(f"      Row {row_idx}: {row} {status} ({actual_count}/{expected_count} tiles)")
                    
                    # Verify tile_map_layout structure matches tileMap
                    if len(tile_map_layout) != len(tile_map_counts):
                        print(f"   ❌ ERROR: tile_map_layout has {len(tile_map_layout)} rows but tileMap has {len(tile_map_counts)} rows!")
                    else:
                        for row_idx in range(len(tile_map_layout)):
                            expected = tile_map_counts[row_idx]
                            actual = len(tile_map_layout[row_idx])
                            if actual != expected:
                                print(f"   ❌ ERROR: Row {row_idx} has {actual} tiles but tileMap expects {expected}!")
                    
                    self.update_prefab_with_tile_map(entity_info, tile_map_layout, prefab_file, entity_tile_size)
                    
                    print(f"   ✅ Complete! Generated {sum(tile_map_counts)} tiles across {num_rows} rows")
                else:
                    # Legacy: single tile
                    # Save individual tile (use a temp name, will be renamed after we get frame number)
                    tile_filename = f"tile_{idx}_temp.png"
                    tile_path = tiles_dir / tile_filename
                    image.save(tile_path)
                    
                    # Add to atlas or replace existing tile
                    atlas_name = atlas_png.stem.replace("-", "_")  # Normalize to underscores (filename without extension)
                    
                    if replace_tile_id:
                        # Replace existing tile
                        print(f"   🔄 Replacing tile in atlas...")
                        success = self.replace_tile_in_atlas(replace_tile_id, tile_path, atlas_png, tile_info)
                        if not success:
                            print(f"   ❌ Failed to replace tile {replace_tile_id}")
                            continue
                        tile_id = replace_tile_id  # Use the original tile ID
                    else:
                        # Add new tile
                        print(f"   📦 Adding to atlas...")
                        frame_number = self.add_tile_to_atlas(tile_path, atlas_png, tile_info)
                        tile_id = f"{atlas_name}-{frame_number}"
                        
                        # Rename tile file to match tile_id
                        final_tile_filename = f"{tile_id.replace(':', '_').replace('/', '_')}.png"
                        final_tile_path = tiles_dir / final_tile_filename
                        if tile_path != final_tile_path:
                            tile_path.rename(final_tile_path)
                        tile_path = final_tile_path
                    
                    # Update prefab file (replace -r suffix with actual tile ID)
                    if replace_tile_id:
                        # When replacing, update the tile ID that had -r suffix to the original ID
                        print(f"   📝 Updating prefab file: replacing '{replace_tile_id}-r' with '{tile_id}'")
                        self.update_prefab_with_tile_id(entity_info, tile_id, prefab_file, old_tile_id_with_suffix=f"{replace_tile_id}-r")
                    else:
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
        print(f"   Updated prefab/map file: {prefab_file}")
        print(f"   Updated atlas: {atlas_png}")
    
    def extract_existing_tile_ids_from_entity(self, entity: Dict, atlas_name: str) -> List[str]:
        """Extract all existing tile IDs from an entity's parts that reference the given atlas"""
        existing_tile_ids = []
        
        # Check if entity has parts
        parts = entity.get("parts", [])
        for part in parts:
            tile_grid = part.get("tileGrid", [])
            for row in tile_grid:
                if not isinstance(row, list):
                    continue
                for tile_id in row:
                    if tile_id and isinstance(tile_id, str) and tile_id.startswith(atlas_name + "-"):
                        # Extract frame number from tile ID (e.g., "atlas-123" -> "123")
                        existing_tile_ids.append(tile_id)
        
        # Also check gid field if it exists
        if "gid" in entity and entity["gid"] and isinstance(entity["gid"], str):
            if entity["gid"].startswith(atlas_name + "-"):
                existing_tile_ids.append(entity["gid"])
        
        return existing_tile_ids
    
    def replace_tile_in_atlas(self, tile_id: str, tile_path: Path, atlas_png: Path, tile_info: Dict) -> bool:
        """Replace an existing tile in the atlas by its tile ID. Returns True if successful."""
        if not atlas_png.exists():
            print(f"   ⚠️  Atlas not found, cannot replace tile")
            return False
        
        metadata_path = atlas_png.with_suffix('.json')
        if not metadata_path.exists():
            print(f"   ⚠️  Metadata not found, cannot replace tile")
            return False
        
        # Load atlas and metadata
        try:
            atlas = Image.open(atlas_png)
            atlas = atlas.convert('RGBA')
            atlas = atlas.copy()  # Make a mutable copy
            
            with open(metadata_path, 'r') as f:
                atlas_metadata = json.load(f)
        except Exception as e:
            print(f"   ❌ Error loading atlas/metadata: {e}")
            return False
        
        # Load the new tile image
        tile_image = Image.open(tile_path)
        tile_width, tile_height = tile_image.size
        if tile_image.mode != 'RGBA':
            tile_image = tile_image.convert('RGBA')
        
        # Extract frame number from tile ID (e.g., "grasslands-3" -> 3)
        frame_number = None
        if "-" in tile_id:
            parts = tile_id.split("-")
            if len(parts) >= 2:
                try:
                    frame_number = int(parts[-1])
                except ValueError:
                    print(f"   ❌ Could not extract frame number from tile ID: {tile_id}")
                    return False
        
        if not frame_number:
            print(f"   ❌ Could not find frame number in tile ID: {tile_id}")
            return False
        
        # Find tile in metadata
        frame_key = str(frame_number)
        tiles_dict = atlas_metadata.get("tiles", {})
        
        if frame_key not in tiles_dict:
            # Tile not found - provide helpful debug info
            print(f"   ⚠️  Tile {tile_id} (frame {frame_number}) not found in atlas metadata")
            
            # List available frames in metadata for debugging
            available_frames = sorted([int(k) for k in tiles_dict.keys() if k.isdigit()])
            if available_frames:
                print(f"   📊 Available frames in metadata: {available_frames[:10]}{'...' if len(available_frames) > 10 else ''}")
                print(f"   💡 Tip: The tile might not exist yet. You may need to generate it first, or check if the tile ID is correct.")
            else:
                print(f"   📊 No tiles found in metadata - atlas might be empty")
            
            # If this is a replacement and the tile doesn't exist, we should add it instead
            print(f"   💡 If this is a new tile, it will be added to the atlas instead of replaced.")
            print(f"   ⚠️  Cannot replace tile that doesn't exist. Skipping replacement.")
            return False
        
        tile_info_meta = atlas_metadata["tiles"][frame_key]
        
        # Get position from metadata
        stored_tile_size = atlas_metadata.get("tile_size", self.tile_size)
        x = tile_info_meta.get("x", 0)
        y = tile_info_meta.get("y", 0)
        col = tile_info_meta.get("col", x // stored_tile_size)
        row = tile_info_meta.get("row", y // stored_tile_size)
        
        # Resize tile to match stored tile size if needed
        if tile_width != stored_tile_size or tile_height != stored_tile_size:
            print(f"   📏 Resizing tile from {tile_width}x{tile_height} to {stored_tile_size}x{stored_tile_size}")
            tile_image = tile_image.resize((stored_tile_size, stored_tile_size), Image.Resampling.LANCZOS)
        
        # Replace the tile at the existing position
        print(f"   🔄 Replacing tile {tile_id} at position ({col}, {row}) = pixel ({x}, {y})")
        atlas.paste(tile_image, (x, y), tile_image)
        
        # Update metadata with new tile info (keep position but update other fields)
        atlas_metadata["tiles"][frame_key].update({
            "name": tile_info.get("name", tile_info_meta.get("name", "")),
            "description": tile_info.get("description", tile_info_meta.get("description", "")),
            "type": tile_info.get("type", tile_info_meta.get("type", ""))
        })
        
        # Save updated atlas and metadata
        try:
            atlas.save(atlas_png)
            with open(metadata_path, 'w') as f:
                json.dump(atlas_metadata, f, indent=2)
            
            print(f"   ✅ Replaced tile {tile_id} in atlas")
            return True
        except Exception as e:
            print(f"   ❌ Error saving atlas after replacement: {e}")
            return False
    
    def remove_tiles_from_atlas(self, tile_ids: List[str], atlas_png: Path) -> bool:
        """Remove tiles from atlas by filling their positions with transparent pixels"""
        if not tile_ids:
            return True
        
        if not atlas_png.exists():
            print(f"   ⚠️  Atlas not found, cannot remove tiles")
            return False
        
        metadata_path = atlas_png.with_suffix('.json')
        if not metadata_path.exists():
            print(f"   ⚠️  Metadata not found, cannot remove tiles")
            return False
        
        # Load atlas and metadata
        try:
            atlas = Image.open(atlas_png)
            atlas = atlas.convert('RGBA')  # Ensure RGBA mode
            
            with open(metadata_path, 'r') as f:
                atlas_metadata = json.load(f)
        except Exception as e:
            print(f"   ❌ Error loading atlas/metadata: {e}")
            return False
        
        # Get tile size from metadata
        tile_size = atlas_metadata.get("tile_size", self.tile_size)
        
        removed_count = 0
        for tile_id in tile_ids:
            # Find tile in metadata
            # Tiles can be stored by frame number or by tile_id
            tile_info = None
            frame_number = None
            
            # Try to find by tile_id
            for frame_key, tile_data in atlas_metadata.get("tiles", {}).items():
                # Check if this tile matches our tile_id
                # Frame numbers are stored as strings in metadata
                if isinstance(tile_data, dict):
                    # If tile_id format is "atlas-name", extract frame number
                    if "-" in tile_id:
                        parts = tile_id.split("-")
                        if len(parts) >= 2:
                            try:
                                potential_frame = int(parts[-1])
                                if str(potential_frame) == frame_key:
                                    tile_info = tile_data
                                    frame_number = potential_frame
                                    break
                            except ValueError:
                                pass
            
            # If not found by tile_id, try parsing frame number directly
            if not tile_info and "-" in tile_id:
                parts = tile_id.split("-")
                if len(parts) >= 2:
                    try:
                        frame_number = int(parts[-1])
                        frame_key = str(frame_number)
                        if frame_key in atlas_metadata.get("tiles", {}):
                            tile_info = atlas_metadata["tiles"][frame_key]
                    except ValueError:
                        pass
            
            if tile_info:
                # Get position from metadata
                x = tile_info.get("x", 0)
                y = tile_info.get("y", 0)
                col = tile_info.get("col", x // tile_size)
                row = tile_info.get("row", y // tile_size)
                
                # Create transparent tile
                transparent_tile = Image.new('RGBA', (tile_size, tile_size), (0, 0, 0, 0))
                
                # Paste transparent tile over old tile
                atlas.paste(transparent_tile, (x, y), transparent_tile)
                
                # Remove from metadata
                if frame_key in atlas_metadata.get("tiles", {}):
                    del atlas_metadata["tiles"][frame_key]
                
                removed_count += 1
                print(f"   🗑️  Removed tile {tile_id} from atlas (frame {frame_number}, position {col},{row})")
            else:
                print(f"   ⚠️  Tile {tile_id} not found in atlas metadata (may have been already removed)")
        
        # Save updated atlas and metadata
        try:
            atlas.save(atlas_png)
            with open(metadata_path, 'w') as f:
                json.dump(atlas_metadata, f, indent=2)
            
            if removed_count > 0:
                print(f"   ✅ Removed {removed_count} tile(s) from atlas")
            return True
        except Exception as e:
            print(f"   ❌ Error saving atlas after removal: {e}")
            return False
    
    def add_tile_to_atlas(self, tile_path: Path, atlas_png: Path, tile_info: Dict) -> int:
        """Add a single tile to the atlas and update metadata. Returns frame number (1-indexed)."""
        # Load the tile image first to get its actual size
        tile_image = Image.open(tile_path)
        tile_width, tile_height = tile_image.size
        
        # Use the actual tile size from the image (may be high-res like 707x707 or 1024x1024)
        # If tile is larger than default tile_size, use its size; otherwise use tile_size
        actual_tile_size = max(tile_width, tile_height, self.tile_size)
        
        # Ensure atlas exists
        if not atlas_png.exists():
            # Create new atlas using actual tile size
            cols = 10  # Start with 10 columns
            rows = 10
            atlas_width = cols * actual_tile_size
            atlas_height = rows * actual_tile_size
            atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))
            atlas.save(atlas_png)
            
            # Create initial metadata
            metadata_path = atlas_png.with_suffix('.json')
            atlas_metadata = {
                "tile_size": actual_tile_size,  # Use actual tile size (high-res)
                "atlas_width": atlas_width,
                "atlas_height": atlas_height,
                "cols": cols,
                "rows": rows,
                "tiles": {}
            }
            with open(metadata_path, 'w') as f:
                json.dump(atlas_metadata, f, indent=2)
        else:
            # Load existing atlas - IMPORTANT: Make a copy and convert to RGBA to preserve transparency
            print(f"   📦 Loading existing atlas: {atlas_png.name}")
            atlas = Image.open(atlas_png)
            # Ensure atlas is in RGBA mode to preserve transparency
            if atlas.mode != 'RGBA':
                print(f"   🔄 Converting atlas from {atlas.mode} to RGBA mode")
                atlas = atlas.convert('RGBA')
            # Make a copy of the atlas to ensure we preserve all existing pixels
            # This prevents any issues with PIL's lazy loading when the file is modified
            atlas = atlas.copy()
            atlas_width, atlas_height = atlas.size
            print(f"   📐 Loaded existing atlas: {atlas_width}x{atlas_height} pixels")
            print(f"   ✅ Preserving existing atlas image (all {atlas_width}x{atlas_height} pixels will be kept)")
            
            # Load metadata to get actual tile size
            metadata_path = atlas_png.with_suffix('.json')
            if metadata_path.exists():
                with open(metadata_path, 'r') as f:
                    atlas_metadata = json.load(f)
                # Use tile size from metadata - this is critical for grid positioning
                stored_tile_size = atlas_metadata.get("tile_size")
                if stored_tile_size:
                    actual_tile_size = stored_tile_size
                    print(f"   📏 Using stored tile size from metadata: {actual_tile_size}x{actual_tile_size}")
                else:
                    # Fall back to calculated size if not in metadata
                    actual_tile_size = max(tile_width, tile_height, self.tile_size)
                    print(f"   ⚠️  No tile_size in metadata, using calculated: {actual_tile_size}x{actual_tile_size}")
                
                existing_tile_count = len(atlas_metadata.get("tiles", {}))
                print(f"   📊 Found {existing_tile_count} existing tiles in metadata")
            else:
                # Create metadata if missing (atlas exists but metadata doesn't)
                # CRITICAL: Infer tile size from atlas dimensions, not from the new tile
                # Try common tile sizes: 16, 32, 64, 128, 256, etc.
                # Find the largest tile size that divides evenly into both width and height
                print(f"   ⚠️  Metadata not found, inferring tile size from atlas dimensions...")
                
                # Try to find a common divisor that makes sense
                # Check if atlas dimensions suggest a specific tile size
                inferred_tile_size = None
                common_tile_sizes = [16, 32, 64, 128, 256, 512, 707, 1024]
                
                # Try to find a tile size that divides evenly into atlas dimensions
                for candidate_size in common_tile_sizes:
                    if atlas_width % candidate_size == 0 and atlas_height % candidate_size == 0:
                        cols = atlas_width // candidate_size
                        rows = atlas_height // candidate_size
                        # Only accept if it gives us a reasonable grid (at least 1x1, reasonable upper bound)
                        if cols > 0 and rows > 0 and cols <= 1000 and rows <= 1000:
                            inferred_tile_size = candidate_size
                            print(f"   ✅ Inferred tile size from atlas dimensions: {candidate_size}x{candidate_size} (atlas {atlas_width}x{atlas_height} = {cols}x{rows} grid)")
                            break
                
                # If we couldn't infer from atlas, try to use the new tile size
                if inferred_tile_size is None:
                    # If the new tile is larger than the atlas, the atlas might need to be resized
                    if tile_width > atlas_width or tile_height > atlas_height:
                        print(f"   ⚠️  New tile ({tile_width}x{tile_height}) is larger than atlas ({atlas_width}x{atlas_height})")
                        print(f"      Will resize atlas to accommodate new tile size")
                        # Use the new tile size and expand the atlas
                        actual_tile_size = max(tile_width, tile_height, self.tile_size)
                        # Create a minimal grid that can fit at least one tile
                        cols = 10
                        rows = 10
                    else:
                        # Use default tile size and infer grid from atlas
                        actual_tile_size = self.tile_size  # Use default (16)
                        cols = atlas_width // actual_tile_size if actual_tile_size > 0 else 10
                        rows = atlas_height // actual_tile_size if actual_tile_size > 0 else 10
                        inferred_tile_size = actual_tile_size
                else:
                    actual_tile_size = inferred_tile_size
                    cols = atlas_width // actual_tile_size
                    rows = atlas_height // actual_tile_size
                
                # Ensure cols and rows are never zero
                if cols == 0:
                    cols = 1
                if rows == 0:
                    rows = 1
                
                atlas_metadata = {
                    "tile_size": actual_tile_size,
                    "atlas_width": atlas_width,
                    "atlas_height": atlas_height,
                    "cols": cols,
                    "rows": rows,
                    "tiles": {}
                }
                print(f"   ⚠️  Created metadata: tile size {actual_tile_size}x{actual_tile_size}, grid: {cols}x{rows}")
            
            cols = atlas_width // actual_tile_size if actual_tile_size > 0 else 1
            rows = atlas_height // actual_tile_size if actual_tile_size > 0 else 1
            
            # Ensure cols and rows are never zero (safety check)
            if cols == 0:
                cols = 1
            if rows == 0:
                rows = 1
            
            print(f"   📐 Atlas grid: {cols}x{rows} (tile size: {actual_tile_size}x{actual_tile_size})")
        
        # Find next empty position based on metadata
        occupied = {(tile["col"], tile["row"]) for tile in atlas_metadata.get("tiles", {}).values()}
        
        # Find the highest frame number to determine where to start
        max_frame = 0
        if atlas_metadata.get("tiles", {}):
            for frame_key in atlas_metadata["tiles"].keys():
                try:
                    frame_num = int(frame_key)
                    if frame_num > max_frame:
                        max_frame = frame_num
                except ValueError:
                    pass
        
        if max_frame > 0 and cols > 0:
            # Calculate position from highest frame number
            # Frame number is 1-indexed: frame = row * cols + col + 1
            # So: frame - 1 = row * cols + col
            # row = (frame - 1) // cols, col = (frame - 1) % cols
            start_frame = max_frame + 1
            start_row = (start_frame - 1) // cols if cols > 0 else 0
            start_col = (start_frame - 1) % cols if cols > 0 else 0
            print(f"   📊 Found {len(occupied)} occupied positions in metadata")
            print(f"   📊 Highest frame number: {max_frame}, starting new tiles from frame {start_frame} (position {start_col},{start_row})")
            x, y = start_col, start_row
        elif occupied:
            print(f"   📊 Found {len(occupied)} occupied positions in metadata: {sorted(occupied)}")
            # Start from (0,0) and find first empty
            x, y = 0, 0
        else:
            print(f"   📊 No occupied positions in metadata - will start from (0, 0)")
            # If we have an existing atlas but no metadata, we need to be careful
            # Check if the atlas appears to have existing content at (0,0)
            if atlas_png.exists():
                try:
                    sample_pixel = atlas.getpixel((0, 0))
                    if len(sample_pixel) >= 4 and sample_pixel[3] > 0:
                        # Has content at (0,0) - metadata might be missing
                        print(f"   ⚠️  WARNING: Atlas has content at (0,0) but no metadata!")
                        print(f"      This might cause tiles to overwrite existing content.")
                        print(f"      Consider providing metadata or regenerating the atlas.")
                except:
                    pass
        x, y = 0, 0
        
        # Find next empty position (in case the calculated position is occupied)
        while (x, y) in occupied:
            x += 1
            if x >= cols:
                x = 0
                y += 1
                # Expand atlas if needed
                if y >= rows:
                    new_rows = y + 1
                    new_height = new_rows * actual_tile_size
                    print(f"   📏 Expanding atlas height from {atlas_height} to {new_height} pixels")
                    new_atlas = Image.new('RGBA', (atlas_width, new_height), (0, 0, 0, 0))
                    new_atlas.paste(atlas, (0, 0))
                    atlas = new_atlas
                    rows = new_rows
                    atlas_height = new_height
                    cols = atlas_width // actual_tile_size  # Update cols in case it changed
        
        # Calculate frame number (1-indexed: row * cols + col + 1)
        frame_number = y * cols + x + 1
        
        # Ensure tile is the correct size for the atlas grid
        # Use the stored tile_size from metadata for consistency (all tiles in atlas should be same size)
        stored_tile_size = atlas_metadata.get("tile_size", actual_tile_size)
        
        # If new tile is larger than atlas tile size, we need to expand the atlas
        # This happens when transitioning from low-res (16x16) to high-res (707x707) tiles
        if tile_width > stored_tile_size or tile_height > stored_tile_size:
            print(f"   ⚠️  New tile ({tile_width}x{tile_height}) is larger than atlas tile size ({stored_tile_size}x{stored_tile_size})")
            print(f"      Expanding atlas and updating tile size to accommodate high-resolution tiles")
            
            # Update atlas metadata to use the new (larger) tile size
            new_tile_size = max(tile_width, tile_height)
            atlas_metadata["tile_size"] = new_tile_size
            stored_tile_size = new_tile_size
            
            # Recalculate grid based on new tile size
            # Need to expand atlas to fit at least the new tile
            new_cols = max(cols, (atlas_width + new_tile_size - 1) // new_tile_size)  # Round up
            new_rows = max(rows, (atlas_height + new_tile_size - 1) // new_tile_size)  # Round up
            # Expand to at least fit existing tiles + some buffer
            new_cols = max(new_cols, 10)
            new_rows = max(new_rows, 10)
            
            # Calculate new atlas dimensions
            new_atlas_width = new_cols * new_tile_size
            new_atlas_height = new_rows * new_tile_size
            
            # Expand the atlas image if needed
            if new_atlas_width > atlas_width or new_atlas_height > atlas_height:
                print(f"      Expanding atlas from {atlas_width}x{atlas_height} to {new_atlas_width}x{new_atlas_height}")
                new_atlas = Image.new('RGBA', (new_atlas_width, new_atlas_height), (0, 0, 0, 0))
                new_atlas.paste(atlas, (0, 0))
                atlas = new_atlas
                atlas_width = new_atlas_width
                atlas_height = new_atlas_height
            
            # Update grid dimensions
            cols = new_cols
            rows = new_rows
            atlas_metadata["atlas_width"] = atlas_width
            atlas_metadata["atlas_height"] = atlas_height
            atlas_metadata["cols"] = cols
            atlas_metadata["rows"] = rows
            
            print(f"      Updated atlas: {atlas_width}x{atlas_height}, grid: {cols}x{rows}, tile size: {stored_tile_size}x{stored_tile_size}")
        elif tile_width != stored_tile_size or tile_height != stored_tile_size:
            # If new tile is smaller, resize it to match atlas tile size
            print(f"   📏 Resizing tile from {tile_width}x{tile_height} to {stored_tile_size}x{stored_tile_size} for atlas")
            tile_image = tile_image.resize((stored_tile_size, stored_tile_size), Image.Resampling.LANCZOS)
        
        if tile_image.mode != 'RGBA':
            tile_image = tile_image.convert('RGBA')
        
        # Paste tile at calculated position (use stored_tile_size for grid position)
        paste_x = x * stored_tile_size
        paste_y = y * stored_tile_size
        print(f"   📍 Placing tile at position ({x}, {y}) in grid = pixel ({paste_x}, {paste_y})")
        
        # Verify we're not overwriting existing content (check if position is transparent or empty)
        # This is a safety check - the occupied check should have prevented this
        if paste_x + stored_tile_size <= atlas.width and paste_y + stored_tile_size <= atlas.height:
            # Check a sample of pixels at this position to see if they're already filled
            # Only check corners to avoid false positives from edge blending
            check_points = [
                (paste_x, paste_y),  # Top-left
                (paste_x + stored_tile_size - 1, paste_y),  # Top-right
                (paste_x, paste_y + stored_tile_size - 1),  # Bottom-left
                (paste_x + stored_tile_size - 1, paste_y + stored_tile_size - 1)  # Bottom-right
            ]
            has_content = False
            for px, py in check_points:
                if 0 <= px < atlas.width and 0 <= py < atlas.height:
                    pixel = atlas.getpixel((px, py))
                    # Check if pixel has non-transparent content (alpha > 0 and not black)
                    if len(pixel) >= 4 and pixel[3] > 0:  # Has alpha channel and is visible
                        # Check if it's not just black (R, G, or B > 10)
                        if pixel[0] > 10 or pixel[1] > 10 or pixel[2] > 10:
                            has_content = True
                            break
            
            if has_content:
                print(f"   ⚠️  WARNING: Position ({paste_x}, {paste_y}) appears to have existing content!")
                print(f"      This might overwrite an existing tile. Continuing anyway...")
        
        # Paste the new tile (this will overwrite any existing content at this position)
        atlas.paste(tile_image, (paste_x, paste_y), tile_image)
        
        # Update metadata
        if "tile_size" not in atlas_metadata:
            atlas_metadata["tile_size"] = actual_tile_size
        else:
            # Ensure metadata tile_size matches actual (in case atlas has mixed sizes, use largest)
            atlas_metadata["tile_size"] = max(atlas_metadata.get("tile_size", self.tile_size), actual_tile_size)
        
        atlas_metadata["atlas_width"] = atlas.width
        atlas_metadata["atlas_height"] = atlas.height
        atlas_metadata["cols"] = cols
        atlas_metadata["rows"] = rows
        
        if "tiles" not in atlas_metadata:
            atlas_metadata["tiles"] = {}
        
        # Store by frame number for metadata (use actual_tile_size from metadata for consistency)
        stored_tile_size = atlas_metadata["tile_size"]
        atlas_metadata["tiles"][str(frame_number)] = {
            "x": x * stored_tile_size,
            "y": y * stored_tile_size,
            "width": stored_tile_size,
            "height": stored_tile_size,
            "col": x,
            "row": y,
            "name": tile_info.get("name", ""),
            "description": tile_info.get("description", ""),
            "type": tile_info.get("type", "")
        }
        
        # Save atlas and metadata
        # Verify atlas dimensions before saving
        final_atlas_width, final_atlas_height = atlas.size
        print(f"   💾 Saving atlas: {final_atlas_width}x{final_atlas_height} pixels (grid: {cols}x{rows}, tile size: {stored_tile_size})")
        print(f"   ✅ Preserving all {final_atlas_width}x{final_atlas_height} pixels including existing tiles")
        
        atlas.save(atlas_png)
        print(f"   💾 Saved atlas to {atlas_png.name}")
        
        with open(metadata_path, 'w') as f:
            json.dump(atlas_metadata, f, indent=2)
        print(f"   💾 Saved metadata with {len(atlas_metadata.get('tiles', {}))} tile(s)")
        
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
