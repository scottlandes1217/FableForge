Export layers to character part PNGs (no dialogs)
================================================

1. Edit the script once
   Open: Assets/Editor/Photoshop_ExportLayersToParts.jsx
   Change BASE_PARTS_PATH to your full path to Assets/Characters/Parts (line 8).
   Save.

2. Name your layers like the target filenames
   e.g. eyes_round_01, eyes_side_round_01, mouth_neutral_01, body_human_male_front_01
   The script uses the layer name as the PNG filename and picks the subfolder from it.

3. Run the script from Photoshop
   File → Scripts → Browse…
   Navigate to your project’s Assets/Editor folder and select:
   Photoshop_ExportLayersToParts.jsx
   Click Open. It exports every (art) layer to the right Parts subfolder and shows a done message.

4. Next time
   Just run File → Scripts → Browse → same file again (or add it to Photoshop’s Presets/Scripts so it appears under File → Scripts). You never pick the folder again.

If you don’t see “Export Layers to Files” in the menu
   Adobe’s built-in script is at:
   Mac: /Applications/Adobe Photoshop [Year]/Presets/Scripts/Export Layers To Files.jsx
   Run it via File → Scripts → Browse and open that file. It asks for a folder each time. This custom script avoids that by using the path you set once in the file.
