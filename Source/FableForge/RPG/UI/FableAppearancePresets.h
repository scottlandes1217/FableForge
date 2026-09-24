#pragma once
#include "CoreMinimal.h"
#include "RPG/Data/FableForgeRPGTypes.h"

namespace FableAppearance
{
struct FControl { FName Name; const TCHAR* Label; int32 Category; };
inline const TArray<FControl>& Controls()
{
 static const TArray<FControl> Items = {
  {TEXT("Height"),TEXT("Height"),0},
  {TEXT("BodyBuild"),TEXT("Frame"),0},{TEXT("BodyFat"),TEXT("Body fat"),0},
  {TEXT("Muscle"),TEXT("Muscle"),0},{TEXT("Bust"),TEXT("Chest volume"),0},
  {TEXT("ShoulderWidth"),TEXT("Shoulders"),0},{TEXT("WaistWidth"),TEXT("Waist"),0},
  {TEXT("HipWidth"),TEXT("Hips"),0},{TEXT("TorsoLength"),TEXT("Torso"),0},
  {TEXT("HeadSize"),TEXT("Head size"),1},{TEXT("JawWidth"),TEXT("Jaw width"),1},{TEXT("JawDepth"),TEXT("Jaw depth"),1},
  {TEXT("ChinHeight"),TEXT("Chin height"),1},{TEXT("ChinDepth"),TEXT("Chin depth"),1},
  {TEXT("CheekWidth"),TEXT("Cheekbones"),1},{TEXT("CheekFullness"),TEXT("Cheek fullness"),1},
  {TEXT("EyeSize"),TEXT("Eye size"),2},{TEXT("EyeSpacing"),TEXT("Eye spacing"),2},
  {TEXT("BrowHeight"),TEXT("Brow height"),2},
  {TEXT("NoseWidth"),TEXT("Nose width"),3},{TEXT("NoseLength"),TEXT("Nose length"),3},
  {TEXT("NoseHeight"),TEXT("Nose height"),3},
  {TEXT("MouthWidth"),TEXT("Mouth width"),4},{TEXT("LipFullness"),TEXT("Lip fullness"),4},
  {TEXT("EarLength"),TEXT("Ear length"),5},{TEXT("EarPoint"),TEXT("Ear shape"),5}
 };
 return Items;
}
// All values are authored against the shared skeletal mesh morph contract.
struct FRange { float Min=-1.f; float Max=1.f; float Default=0.f; };
struct FSkinTone { FName Id; const TCHAR* Label; FLinearColor Color; };

inline FString NormalizeRace(const FString& Race)
{
 const FString Id=Race.TrimStartAndEnd().ToLower();
 return Id==TEXT("elf") || Id==TEXT("dwarf") || Id==TEXT("halfling") || Id==TEXT("orc") || Id==TEXT("tiefling") ? Id : TEXT("human");
}
inline const TCHAR* RaceDisplayName(const FString& Race)
{
 const FString Id=NormalizeRace(Race);
 if(Id==TEXT("elf")) return TEXT("Elf");
 if(Id==TEXT("dwarf")) return TEXT("Dwarf");
 if(Id==TEXT("halfling")) return TEXT("Halfling");
 if(Id==TEXT("orc")) return TEXT("Orc");
 if(Id==TEXT("tiefling")) return TEXT("Tiefling");
 return TEXT("Human");
}
inline const TCHAR* RaceDescription(const FString& Race)
{
 const FString Id=NormalizeRace(Race);
 if(Id==TEXT("elf")) return TEXT("Tall and slender, with long pointed ears.");
 if(Id==TEXT("dwarf")) return TEXT("Short and broad, with a sturdy build.");
 if(Id==TEXT("halfling")) return TEXT("Small, with a soft build and rounded features.");
 if(Id==TEXT("orc")) return TEXT("Large and muscular, with a broad jaw, pointed ears, and green or gray skin.");
 if(Id==TEXT("tiefling")) return TEXT("Pointed ears and red, purple, or ashen skin.");
 return TEXT("Balanced proportions and a broad range of natural skin tones.");
}
inline const TArray<FSkinTone>& SkinPalette(const FString& Race)
{
 // Colors multiply the authored albedo; they are linear material parameters.
 static const TArray<FSkinTone> Natural={
  {TEXT("natural"),TEXT("Natural"),FLinearColor(1.f,1.f,1.f,1.f)},
  {TEXT("warm"),TEXT("Warm"),FLinearColor(.94f,.78f,.63f,1.f)},
  {TEXT("tan"),TEXT("Tan"),FLinearColor(.76f,.56f,.39f,1.f)},
  {TEXT("brown"),TEXT("Brown"),FLinearColor(.53f,.34f,.22f,1.f)},
  {TEXT("deep"),TEXT("Deep"),FLinearColor(.30f,.18f,.12f,1.f)},
  {TEXT("cool"),TEXT("Cool"),FLinearColor(.83f,.85f,.89f,1.f)}
 };
 static const TArray<FSkinTone> Elven={
  {TEXT("ivory"),TEXT("Ivory"),FLinearColor(.94f,.96f,1.f,1.f)},
  {TEXT("golden"),TEXT("Golden"),FLinearColor(.91f,.78f,.53f,1.f)},
  {TEXT("copper"),TEXT("Copper"),FLinearColor(.66f,.42f,.28f,1.f)},
  {TEXT("umber"),TEXT("Umber"),FLinearColor(.38f,.25f,.20f,1.f)},
  {TEXT("moon"),TEXT("Moon"),FLinearColor(.66f,.72f,.86f,1.f)},
  {TEXT("dusk"),TEXT("Dusk"),FLinearColor(.40f,.37f,.54f,1.f)}
 };
 static const TArray<FSkinTone> Orcish={
  {TEXT("moss"),TEXT("Moss"),FLinearColor(.38f,.72f,.24f,1.f)},
  {TEXT("olive"),TEXT("Olive"),FLinearColor(.46f,.58f,.20f,1.f)},
  {TEXT("forest"),TEXT("Forest"),FLinearColor(.22f,.48f,.20f,1.f)},
  {TEXT("sage"),TEXT("Sage"),FLinearColor(.52f,.72f,.45f,1.f)},
  {TEXT("slate"),TEXT("Slate"),FLinearColor(.46f,.58f,.56f,1.f)},
  {TEXT("ash"),TEXT("Ash"),FLinearColor(.62f,.66f,.58f,1.f)}
 };
 static const TArray<FSkinTone> Infernal={
  {TEXT("crimson"),TEXT("Crimson"),FLinearColor(.72f,.20f,.18f,1.f)},
  {TEXT("ember"),TEXT("Ember"),FLinearColor(.84f,.32f,.20f,1.f)},
  {TEXT("violet"),TEXT("Violet"),FLinearColor(.52f,.28f,.70f,1.f)},
  {TEXT("plum"),TEXT("Plum"),FLinearColor(.38f,.18f,.48f,1.f)},
  {TEXT("ash"),TEXT("Ash"),FLinearColor(.65f,.65f,.72f,1.f)},
  {TEXT("charcoal"),TEXT("Charcoal"),FLinearColor(.24f,.25f,.32f,1.f)}
 };
 const FString Id=NormalizeRace(Race);
 if(Id==TEXT("orc")) return Orcish;
 if(Id==TEXT("tiefling")) return Infernal;
 if(Id==TEXT("elf")) return Elven;
 return Natural;
}
inline FLinearColor DefaultSkinColor(const FString& Race) { return SkinPalette(Race)[0].Color; }
inline FLinearColor NormalizeSkinColor(const FLinearColor& Color,const FString& Race)
{
 if(!FMath::IsFinite(Color.R) || !FMath::IsFinite(Color.G) || !FMath::IsFinite(Color.B)) return DefaultSkinColor(Race);
 const TArray<FSkinTone>& Palette=SkinPalette(Race);
 int32 Best=0; double Distance=TNumericLimits<double>::Max();
 for(int32 Index=0;Index<Palette.Num();++Index)
 {
  const FLinearColor& Candidate=Palette[Index].Color;
  const double R=static_cast<double>(Color.R)-Candidate.R;
  const double G=static_cast<double>(Color.G)-Candidate.G;
  const double B=static_cast<double>(Color.B)-Candidate.B;
  const double D=R*R+G*G+B*B;
  if(D<Distance) { Distance=D; Best=Index; }
 }
 return Palette[Best].Color;
}
inline FRange Range(FName Name,const FString& Race,EFableGender Gender)
{
 const FString Id=NormalizeRace(Race);
 const bool Female=Gender==EFableGender::Female;
 if(Name==TEXT("FemaleBody")) return Female ? FRange{1.f,1.f,1.f} : FRange{0.f,0.f,0.f};
 if(Name==TEXT("Height"))
 {
  if(Id==TEXT("elf")) return {1.04f,1.20f,Female?1.10f:1.14f};
  if(Id==TEXT("dwarf")) return {.70f,.85f,Female?.75f:.79f};
  if(Id==TEXT("halfling")) return {.82f,.94f,Female?.85f:.88f};
  if(Id==TEXT("orc")) return {1.08f,1.20f,Female?1.12f:1.17f};
  if(Id==TEXT("tiefling")) return {.96f,1.16f,Female?1.02f:1.07f};
  return {.88f,1.12f,Female?.98f:1.02f};
 }
 if(Name==TEXT("HeadSize")) return Id==TEXT("dwarf") ? FRange{.40f,1.f,.67f} : FRange{0.f,.35f,0.f};
 FRange R=Id==TEXT("human") ? FRange{-1.f,1.f,0.f} : FRange{-.85f,.85f,0.f};
 if(Name==TEXT("BodyFat")) R={0.f,1.f,.10f};
 else if(Name==TEXT("Muscle")) R={0.f,1.f,.10f};
 else if(Name==TEXT("Bust")) R={0.f,1.f,0.f};
 else if(Name==TEXT("EarLength")) R={-.35f,.35f,0.f};
 else if(Name==TEXT("EarPoint")) R={-.30f,.15f,-.10f};
 if(Id==TEXT("orc"))
 {
  if(Name==TEXT("BodyBuild")) return {.20f,.70f,.42f};
  if(Name==TEXT("Muscle")) return {.60f,1.f,.85f};
  if(Name==TEXT("BodyFat")) return {0.f,.50f,.08f};
  if(Name==TEXT("ShoulderWidth")) return {.30f,.80f,.50f};
  if(Name==TEXT("WaistWidth")) return {-.10f,.45f,.05f};
  if(Name==TEXT("HipWidth")) return {0.f,.50f,.20f};
  if(Name==TEXT("TorsoLength")) return {-.10f,.50f,.05f};
  if(Name==TEXT("JawWidth")) return {.35f,.95f,.70f};
  if(Name==TEXT("JawDepth")) return {.20f,.85f,.50f};
  if(Name==TEXT("ChinDepth")) return {.05f,.70f,.35f};
  if(Name==TEXT("NoseWidth")) return {.15f,.80f,.45f};
  if(Name==TEXT("EarLength")) return {.30f,.85f,.55f};
  if(Name==TEXT("EarPoint")) return {.55f,1.f,.85f};
 }
 else if(Id==TEXT("elf"))
 {
  if(Name==TEXT("BodyBuild")) return {-.75f,-.10f,-.40f};
  if(Name==TEXT("BodyFat")) return {0.f,.40f,.03f};
  if(Name==TEXT("Muscle")) return {0.f,.65f,.15f};
  if(Name==TEXT("ShoulderWidth")) return {-.55f,.05f,-.25f};
  if(Name==TEXT("WaistWidth")) return {-.50f,.10f,-.25f};
  if(Name==TEXT("HipWidth")) return {-.25f,.35f,0.f};
  if(Name==TEXT("TorsoLength")) return {.05f,.60f,.25f};
  if(Name==TEXT("JawWidth")) return {-.65f,.10f,-.30f};
  if(Name==TEXT("CheekWidth")) return {-.10f,.65f,.25f};
  if(Name==TEXT("CheekFullness")) return {-.50f,.25f,-.20f};
  if(Name==TEXT("EarLength")) return {.60f,1.f,.90f};
  if(Name==TEXT("EarPoint")) return {.70f,1.f,.95f};
 }
 else if(Id==TEXT("dwarf"))
 {
  if(Name==TEXT("BodyBuild")) return {.25f,.85f,.55f};
  if(Name==TEXT("ShoulderWidth")) return {.25f,.85f,.55f};
  if(Name==TEXT("WaistWidth")) return {.10f,.65f,.30f};
  if(Name==TEXT("HipWidth")) return {.10f,.55f,.25f};
  if(Name==TEXT("BodyFat")) return {.10f,.75f,.25f};
  if(Name==TEXT("Muscle")) return {.25f,.90f,.55f};
  if(Name==TEXT("TorsoLength")) return {-.65f,-.10f,-.35f};
  if(Name==TEXT("JawWidth")) return {.15f,.80f,.40f};
  if(Name==TEXT("ChinDepth")) return {.10f,.65f,.30f};
 }
 else if(Id==TEXT("halfling"))
 {
  if(Name==TEXT("BodyBuild")) return {-.35f,.30f,-.05f};
  if(Name==TEXT("BodyFat")) return {.18f,.80f,.35f};
  if(Name==TEXT("Muscle")) return {0.f,.45f,.08f};
  if(Name==TEXT("ShoulderWidth")) return {-.35f,.30f,-.10f};
  if(Name==TEXT("TorsoLength")) return {-.60f,.10f,-.25f};
  if(Name==TEXT("CheekFullness")) return {.15f,.75f,.45f};
  if(Name==TEXT("JawWidth")) return {-.25f,.35f,0.f};
  if(Name==TEXT("EyeSize")) return {0.f,.60f,.20f};
  if(Name==TEXT("EarLength")) return {-.10f,.45f,.15f};
  if(Name==TEXT("EarPoint")) return {0.f,.45f,.20f};
 }
 else if(Id==TEXT("tiefling"))
 {
  if(Name==TEXT("BodyBuild")) return {-.45f,.55f,-.10f};
  if(Name==TEXT("ShoulderWidth")) return {-.35f,.60f,.05f};
  if(Name==TEXT("JawWidth")) return {-.45f,.45f,-.10f};
  if(Name==TEXT("ChinDepth")) return {-.15f,.65f,.20f};
  if(Name==TEXT("CheekWidth")) return {-.15f,.65f,.20f};
  if(Name==TEXT("EarLength")) return {.30f,.90f,.60f};
  if(Name==TEXT("EarPoint")) return {.65f,1.f,.90f};
 }
 return R;
}
inline float ClampValue(float Value,const FRange& Bounds)
{
 return FMath::IsFinite(Value) ? FMath::Clamp(Value,Bounds.Min,Bounds.Max) : Bounds.Default;
}
inline FLinearColor NormalizeTint(const FLinearColor& Color)
{
 const auto Channel=[](float Value) { return FMath::IsFinite(Value) ? FMath::Clamp(Value,0.f,1.f) : 1.f; };
 return FLinearColor(Channel(Color.R),Channel(Color.G),Channel(Color.B),1.f);
}
inline void SanitizeAppearance(FFableCharacterProfile& Profile)
{
 Profile.RaceId=NormalizeRace(Profile.RaceId);
 if(Profile.Gender!=EFableGender::Male && Profile.Gender!=EFableGender::Female) Profile.Gender=EFableGender::Male;
 Profile.HeightScale=ClampValue(Profile.HeightScale,Range(TEXT("Height"),Profile.RaceId,Profile.Gender));
 TMap<FName,float> Clean;
 for(const FControl& Control:Controls())
 {
  if(Control.Name==TEXT("Height")) continue;
  const FRange Bounds=Range(Control.Name,Profile.RaceId,Profile.Gender);
  const float* Value=Profile.BodyMorphs.Find(Control.Name);
  Clean.Add(Control.Name,Value ? ClampValue(*Value,Bounds) : Bounds.Default);
 }
 Clean.Add(TEXT("FemaleBody"),Range(TEXT("FemaleBody"),Profile.RaceId,Profile.Gender).Default);
 Profile.BodyMorphs=MoveTemp(Clean);
 Profile.SkinColor=NormalizeSkinColor(Profile.SkinColor,Profile.RaceId);
 Profile.HairColor=NormalizeTint(Profile.HairColor);
 Profile.EyeColor=NormalizeTint(Profile.EyeColor);
}
}
