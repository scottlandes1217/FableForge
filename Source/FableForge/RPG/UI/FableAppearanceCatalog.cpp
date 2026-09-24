#include "RPG/UI/FableAppearanceCatalog.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/PackageName.h"

namespace FableAppearanceAssets
{
namespace
{
struct FCatalog
{
 TArray<FStyle> Hair,Beards,HairMale,HairFemale,BeardsMale,BeardsFemale;
 TArray<FColorPreset> HairColors,EyeColors;
};
FStyle BuiltinStyle(const TCHAR* Id,const TCHAR* Label,const TCHAR* Mesh)
{
 FStyle S{Id,Label,FString(),FString()};
 if(*Mesh)
 {
  S.MaleMeshPath=FString::Printf(TEXT("/Game/Characters/PlayableCharacter/Hair/SM_Hair_%s.SM_Hair_%s"),Mesh,Mesh);
  S.FemaleMeshPath=FString::Printf(TEXT("/Game/Characters/PlayableCharacter/Hair/SM_Female_Hair_%s.SM_Female_Hair_%s"),Mesh,Mesh);
 }
 return S;
}
FCatalog Builtins()
{
 FCatalog C;
 C.Hair={BuiltinStyle(TEXT("none"),TEXT("Bald"),TEXT("")),BuiltinStyle(TEXT("buzzed"),TEXT("Short"),TEXT("Buzzed")),BuiltinStyle(TEXT("buzzed_female"),TEXT("Cropped"),TEXT("BuzzedFemale")),BuiltinStyle(TEXT("parted"),TEXT("Parted"),TEXT("SimpleParted")),BuiltinStyle(TEXT("long"),TEXT("Long"),TEXT("Long")),BuiltinStyle(TEXT("buns"),TEXT("Buns"),TEXT("Buns"))};
 C.Beards={BuiltinStyle(TEXT("none"),TEXT("None"),TEXT("")),BuiltinStyle(TEXT("beard"),TEXT("Full beard"),TEXT("Beard"))};
 C.HairColors={{TEXT("black"),TEXT("Black"),FLinearColor(.025f,.02f,.018f)}, {TEXT("brown"),TEXT("Brown"),FLinearColor(.18f,.10f,.055f)}, {TEXT("chestnut"),TEXT("Chestnut"),FLinearColor(.30f,.13f,.06f)}, {TEXT("blond"),TEXT("Blond"),FLinearColor(.55f,.32f,.12f)}, {TEXT("auburn"),TEXT("Auburn"),FLinearColor(.45f,.11f,.045f)}, {TEXT("silver"),TEXT("Silver"),FLinearColor(.65f,.65f,.65f)}};
 C.EyeColors={{TEXT("brown"),TEXT("Brown"),FLinearColor(.28f,.16f,.07f)}, {TEXT("hazel"),TEXT("Hazel"),FLinearColor(.30f,.25f,.10f)}, {TEXT("blue"),TEXT("Blue"),FLinearColor(.10f,.28f,.40f)}, {TEXT("green"),TEXT("Green"),FLinearColor(.18f,.34f,.15f)}, {TEXT("gray"),TEXT("Gray"),FLinearColor(.36f,.40f,.43f)}, {TEXT("amber"),TEXT("Amber"),FLinearColor(.55f,.32f,.12f)}};
 return C;
}
bool ValidId(const FString& Id)
{
 if(Id.IsEmpty()) return false;
 for(TCHAR Ch:Id) if(!((Ch>='a' && Ch<='z') || (Ch>='0' && Ch<='9') || Ch=='_')) return false;
 return true;
}
bool ValidMeshPath(const FString& Path)
{
 return Path.IsEmpty() || (Path.StartsWith(TEXT("/Game/")) && FPackageName::IsValidObjectPath(Path));
}
bool ReadStyles(const TSharedPtr<FJsonObject>& Root,const TCHAR* Key,TArray<FStyle>& Out)
{
 const TArray<TSharedPtr<FJsonValue>>* Values=nullptr;
 if(!Root->TryGetArrayField(Key,Values) || !Values || Values->IsEmpty()) return false;
 TSet<FString> Ids;bool HasNone=false;
 for(const auto& Value:*Values)
 {
  const TSharedPtr<FJsonObject>* Obj=nullptr;
  if(!Value.IsValid() || !Value->TryGetObject(Obj) || !Obj || !Obj->IsValid()) return false;
  FStyle S;
  if(!(*Obj)->TryGetStringField(TEXT("id"),S.Id) || !ValidId(S.Id) || Ids.Contains(S.Id) || !(*Obj)->TryGetStringField(TEXT("name"),S.DisplayName) || S.DisplayName.TrimStartAndEnd().IsEmpty()) return false;
  if(!(*Obj)->TryGetStringField(TEXT("maleMesh"),S.MaleMeshPath) || !(*Obj)->TryGetStringField(TEXT("femaleMesh"),S.FemaleMeshPath) || !ValidMeshPath(S.MaleMeshPath) || !ValidMeshPath(S.FemaleMeshPath)) return false;
  if(S.Id==TEXT("none")) {if(!S.MaleMeshPath.IsEmpty() || !S.FemaleMeshPath.IsEmpty()) return false;HasNone=true;}
  else if(S.MaleMeshPath.IsEmpty() && S.FemaleMeshPath.IsEmpty()) return false;
  Ids.Add(S.Id);Out.Add(MoveTemp(S));
 }
 return HasNone;
}
bool ReadColors(const TSharedPtr<FJsonObject>& Root,const TCHAR* Key,TArray<FColorPreset>& Out)
{
 const TArray<TSharedPtr<FJsonValue>>* Values=nullptr;
 if(!Root->TryGetArrayField(Key,Values) || !Values || Values->IsEmpty()) return false;
 TSet<FString> Ids;
 for(const auto& Value:*Values)
 {
  const TSharedPtr<FJsonObject>* Obj=nullptr;
  if(!Value.IsValid() || !Value->TryGetObject(Obj) || !Obj || !Obj->IsValid()) return false;
  FColorPreset P;const TArray<TSharedPtr<FJsonValue>>* RGB=nullptr;
  if(!(*Obj)->TryGetStringField(TEXT("id"),P.Id) || !ValidId(P.Id) || Ids.Contains(P.Id) || !(*Obj)->TryGetStringField(TEXT("name"),P.DisplayName) || P.DisplayName.TrimStartAndEnd().IsEmpty() || !(*Obj)->TryGetArrayField(TEXT("rgb"),RGB) || !RGB || RGB->Num()!=3) return false;
  float Channels[3];
  for(int32 I=0;I<3;++I)
  {
   double N=0;if(!(*RGB)[I].IsValid() || !(*RGB)[I]->TryGetNumber(N) || !FMath::IsFinite(N) || N<0 || N>1) return false;
   Channels[I]=static_cast<float>(N);
  }
  P.Color=FLinearColor(Channels[0],Channels[1],Channels[2],1);Ids.Add(P.Id);Out.Add(MoveTemp(P));
 }
 return true;
}
void FilterStyles(const TArray<FStyle>& Source,bool Female,TArray<FStyle>& Out)
{
 for(const FStyle& S:Source)
 {
  const FString& Path=Female?S.FemaleMeshPath:S.MaleMeshPath;
  if(S.Id==TEXT("none") || (!Path.IsEmpty() && FPackageName::DoesPackageExist(FPackageName::ObjectPathToPackageName(Path)))) Out.Add(S);
  else UE_LOG(LogTemp,Warning,TEXT("Appearance catalog: unavailable %s style %s (%s)"),Female?TEXT("female"):TEXT("male"),*S.Id,*Path);
 }
}
const FCatalog& Catalog()
{
 static const FCatalog Instance=[]()
 {
  FCatalog C=Builtins();FString Json;
  const FString Path=FPaths::ProjectContentDir()/TEXT("Data/AppearanceStyles.json");
  if(FFileHelper::LoadFileToString(Json,*Path))
  {
   TSharedPtr<FJsonObject> Root;FCatalog Parsed;double Version=0;
   const bool Valid=FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Root) && Root.IsValid() && Root->TryGetNumberField(TEXT("version"),Version) && Version==1 && ReadStyles(Root,TEXT("hairStyles"),Parsed.Hair) && ReadStyles(Root,TEXT("beardStyles"),Parsed.Beards) && ReadColors(Root,TEXT("hairColors"),Parsed.HairColors) && ReadColors(Root,TEXT("eyeColors"),Parsed.EyeColors);
   if(Valid) C=MoveTemp(Parsed);
   else UE_LOG(LogTemp,Warning,TEXT("Appearance catalog invalid; using built-in styles and colors: %s"),*Path);
  }
  FilterStyles(C.Hair,false,C.HairMale);FilterStyles(C.Hair,true,C.HairFemale);
  FilterStyles(C.Beards,false,C.BeardsMale);FilterStyles(C.Beards,true,C.BeardsFemale);
  return C;
 }();
 return Instance;
}
}
const TArray<FStyle>& ListHairStyles(bool Female) {return Female?Catalog().HairFemale:Catalog().HairMale;}
const TArray<FStyle>& ListBeardStyles(bool Female) {return Female?Catalog().BeardsFemale:Catalog().BeardsMale;}
const TArray<FColorPreset>& ListHairColors() {return Catalog().HairColors;}
const TArray<FColorPreset>& ListEyeColors() {return Catalog().EyeColors;}
}
