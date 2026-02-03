// Export each layer to PNG. Edit BASE_PARTS_PATH once below, then run: File → Scripts → Browse → this file.
// Layer names = filenames (e.g. "eyes_round_01" → Eyes/eyes_round_01.png). No dialog each time.

#target photoshop

// ========== EDIT THIS ONCE ==========
// Full path to your Parts folder (no trailing slash). Mac: "/Users/you/Projects/Unity/FableForge/Assets/Characters/Parts"
var BASE_PARTS_PATH = "/Users/scottlandes/Projects/Unity/FableForge/Assets/Characters/Parts";
// ====================================

function getSubfolder(layerName) {
  var lower = layerName.toLowerCase();
  if (lower.indexOf("eyes") === 0) return "Eyes";
  if (lower.indexOf("eyebrows") === 0) return "Eyebrows";
  if (lower.indexOf("mouth") === 0) return "Mouth";
  if (lower.indexOf("nose") === 0) return "Nose";
  if (lower.indexOf("body") === 0) return "Body/Human";
  if (lower.indexOf("top") === 0) return "Top";
  if (lower.indexOf("bottom") === 0) return "Bottom";
  if (lower.indexOf("hair_front") === 0) return "HairFront";
  if (lower.indexOf("hair_back") === 0) return "HairBack";
  if (lower.indexOf("hair_side") === 0) return "HairSide";
  return "Eyes";
}

function sanitizeFileName(name) {
  var s = name.replace(/[^a-zA-Z0-9_\-\.]/g, "_");
  if (s.toLowerCase().indexOf(".png") === s.length - 4) s = s.substring(0, s.length - 4);
  if (s.toLowerCase().indexOf(".jpg") === s.length - 4) s = s.substring(0, s.length - 4);
  return s;
}

function collectLayers(layerSet, list) {
  for (var i = 0; i < layerSet.layers.length; i++) {
    var layer = layerSet.layers[i];
    if (layer.typename === "LayerSet") {
      collectLayers(layer, list);
    } else if (layer.typename === "ArtLayer") {
      list.push(layer);
    }
  }
  return list;
}

function saveVisibility(layerSet, map) {
  for (var i = 0; i < layerSet.layers.length; i++) {
    var l = layerSet.layers[i];
    map[l.id] = l.visible;
    if (l.typename === "LayerSet") saveVisibility(l, map);
  }
}

function restoreVisibility(layerSet, map) {
  for (var i = 0; i < layerSet.layers.length; i++) {
    var l = layerSet.layers[i];
    if (map[l.id] !== undefined) l.visible = map[l.id];
    if (l.typename === "LayerSet") restoreVisibility(l, map);
  }
}

function setLayerAndParentsVisible(layer, on) {
  layer.visible = on;
  if (layer.parent && layer.parent.typename === "LayerSet") setLayerAndParentsVisible(layer.parent, on);
}

function hideAllThenShowOne(layerSet, showOnly) {
  for (var i = 0; i < layerSet.layers.length; i++) {
    var l = layerSet.layers[i];
    if (l === showOnly) {
      setLayerAndParentsVisible(l, true);
    } else {
      l.visible = false;
      if (l.typename === "LayerSet") hideAllThenShowOne(l, showOnly);
    }
  }
}

function main() {
  var doc = app.activeDocument;
  if (!doc) {
    alert("No document active.");
    return;
  }

  var layers = [];
  for (var i = 0; i < doc.layers.length; i++) {
    var layer = doc.layers[i];
    if (layer.typename === "LayerSet") collectLayers(layer, layers);
    else if (layer.typename === "ArtLayer") layers.push(layer);
  }

  if (layers.length === 0) {
    alert("No layers to export.");
    return;
  }

  var origVis = {};
  saveVisibility(doc, origVis);

  var exportOpts = new ExportOptionsSaveForWeb();
  exportOpts.format = SaveDocumentType.PNG;
  exportOpts.PNG8 = false;
  exportOpts.transparency = true;
  exportOpts.interlaced = false;

  var count = 0;
  for (var i = 0; i < layers.length; i++) {
    var layer = layers[i];
    var name = layer.name || ("layer_" + i);
    var fileName = sanitizeFileName(name) + ".png";
    var subfolder = getSubfolder(name);
    var folder = new File(BASE_PARTS_PATH + "/" + subfolder);
    if (!folder.exists) folder.create();

    var outFile = new File(folder.fsName + "/" + fileName);
    if (outFile.exists) outFile.remove();

    hideAllThenShowOne(doc, layer);
    try {
      doc.exportDocument(outFile, ExportType.SAVEFORWEB, exportOpts);
      count++;
    } catch (e) {}
  }

  restoreVisibility(doc, origVis);
  alert("Exported " + count + " layer(s) to:\n" + BASE_PARTS_PATH);
}

main();
