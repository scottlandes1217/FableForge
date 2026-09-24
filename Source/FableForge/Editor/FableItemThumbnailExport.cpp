#if WITH_EDITOR
#include "HAL/IConsoleManager.h"
#include "HAL/FileManager.h"
#include "Engine/DataTable.h"
#include "Engine/StaticMesh.h"
#include "Engine/SkeletalMesh.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "ObjectTools.h"
#include "Misc/ObjectThumbnail.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "ImageUtils.h"
#include "AssetCompilingManager.h"
#include "RenderingThread.h"

// Opt-in editor command. Never changes the item table or source meshes.
static FAutoConsoleCommand FableExportItemIcons(
 TEXT("FableForge.ExportItemIcons"),
 TEXT("Render actual item table meshes to Content/Slate/ItemIcons, with a coverage report."),
 FConsoleCommandDelegate::CreateLambda([]()
 {
  const FString Folder = FPaths::ProjectContentDir() / TEXT("Slate/ItemIcons");
  IFileManager::Get().MakeDirectory(*Folder, true);
  FString Report = TEXT("Item\tStatus\tSource mesh\n");
  TArray<FFableItemDefinitionTableRow*> Rows;
  for (const TCHAR* Path : {TEXT("/Game/Data/DT_Items.DT_Items"), TEXT("/Game/Data/DT_Weapons.DT_Weapons"), TEXT("/Game/Data/DT_Armor.DT_Armor")})
  {
   if (UDataTable* Table = LoadObject<UDataTable>(nullptr, Path))
   {
    TArray<FFableItemDefinitionTableRow*> TableRows;
    Table->GetAllRows(TEXT("Item icon export"), TableRows);
    Rows.Append(TableRows);
   }
  }
  for (const FFableItemDefinitionTableRow* Row : Rows)
  {
   UObject* Mesh = Row->WorldSkeletalMesh.LoadSynchronous();
   if (!Mesh) { Mesh = Row->WorldStaticMesh.LoadSynchronous(); }
   const FString Source = Mesh ? Mesh->GetPathName() : TEXT("none");
   // Primitive stand-ins are not representations of the actual item.
   if (!Mesh || Source.StartsWith(TEXT("/Engine/BasicShapes/")))
   {
    Report += Row->ItemId + TEXT("\tfallback: no item model\t") + Source + TEXT("\n");
    continue;
   }
   FAssetCompilingManager::Get().FinishAllCompilation();
   FObjectThumbnail Thumbnail;
  ThumbnailTools::RenderThumbnail(Mesh, 112, 112,
    ThumbnailTools::EThumbnailTextureFlushMode::AlwaysFlush, nullptr, &Thumbnail);
   // The first draw creates the preview scene and can enqueue material shaders.
   // Wait after that warm-up, then capture the completed material resources.
   FAssetCompilingManager::Get().FinishAllCompilation();
   FlushRenderingCommands();
   ThumbnailTools::RenderThumbnail(Mesh, 112, 112,
    ThumbnailTools::EThumbnailTextureFlushMode::AlwaysFlush, nullptr, &Thumbnail);
   const TArray<uint8>& Bytes = Thumbnail.GetUncompressedImageData();
   const int32 Width = Thumbnail.GetImageWidth(), Height = Thumbnail.GetImageHeight();
   if (Width <= 0 || Height <= 0 || Width > 112 || Height > 112 || Bytes.Num() < Width * Height * 4)
   {
    Report += Row->ItemId + TEXT("\tfailed rendering\t") + Source + TEXT("\n");
    continue;
   }
   TArray<FColor> Pixels;
   Pixels.Init(FColor::Transparent, 128 * 128);
   const FColor* Input = reinterpret_cast<const FColor*>(Bytes.GetData());
   for (int32 Y=0; Y<Height; ++Y) for (int32 X=0; X<Width; ++X)
   {
    FColor C = Input[Y*Width+X]; C.A=255;
    Pixels[(Y+(128-Height)/2)*128+X+(128-Width)/2] = C;
   }
   TArray64<uint8> PNG;
   FImageUtils::PNGCompressImageArray(128, 128, Pixels, PNG);
   const bool Saved = FFileHelper::SaveArrayToFile(PNG, *(Folder / (Row->ItemId.ToLower()+TEXT(".png"))));
   Report += Row->ItemId + (Saved ? TEXT("\trendered\t") : TEXT("\tfailed saving\t")) + Source + TEXT("\n");
  }
  FFileHelper::SaveStringToFile(Report, *(FPaths::ProjectSavedDir()/TEXT("ItemIconCoverage.tsv")));
  UE_LOG(LogTemp, Display, TEXT("FABLE_ITEM_ICONS_COMPLETE\n%s"), *Report);
 }));
#endif
