#!/bin/zsh
# Requires a built FableForgeEditor target and a rendering-capable editor (no -nullrhi).
set -eu
project_dir="${0:A:h:h:h}"
editor_bin="/Users/Shared/Epic Games/UE_5.7/Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor"
"$editor_bin" "$project_dir/FableForge.uproject" /Engine/Maps/Entry \
  -unattended -nosplash -nosound -windowed -ResX=256 -ResY=256 \
  -UserDir=/tmp/FableForgeItemIconExport \
  '-ExecCmds=FableForge.ExportItemIcons,QUIT_EDITOR' \
  "-abslog=$project_dir/Saved/ItemIconExport.log"
cp /tmp/FableForgeItemIconExport/Saved/ItemIconCoverage.tsv "$project_dir/Saved/ItemIconCoverage.tsv"
