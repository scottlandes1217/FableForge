#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/MorphTarget.h"
#include "Materials/Material.h"
#include "Materials/MaterialInterface.h"
#include "Kismet/GameplayStatics.h"
#include "RPG/Save/FableCharacterSaveGame.h"
#include "RPG/UI/FableAppearancePresets.h"
#include "RPG/UI/FableAppearanceAssets.h"
#include <limits>

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFableAppearanceAssetsTest,
 "FableForge.Character.AppearanceAssetCompatibility",
 EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FFableAppearanceAssetsTest::RunTest(const FString& Parameters)
{
 USkeletalMesh* Body = LoadObject<USkeletalMesh>(nullptr, TEXT("/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2.basecharacter_v2"));
 USkeletalMesh* Tunic = LoadObject<USkeletalMesh>(nullptr, TEXT("/Game/Items/Armor/FittedTunic/peasant_tunic_v2.peasant_tunic_v2"));
 if (!TestNotNull(TEXT("Authored body exists"), Body) || !TestNotNull(TEXT("Fitted tunic exists"), Tunic)) { return false; }
 TestNotNull(TEXT("Body has an animation skeleton"), Body->GetSkeleton());
 TestTrue(TEXT("Tunic uses the body animation skeleton"), Body->GetSkeleton() == Tunic->GetSkeleton());
 USkeletalMesh* Female=LoadObject<USkeletalMesh>(nullptr,TEXT("/Game/Characters/PlayableCharacter/Meshes/femalecharacter_v2.femalecharacter_v2"));
 USkeletalMesh* FemaleTunic=LoadObject<USkeletalMesh>(nullptr,TEXT("/Game/Items/Armor/FittedTunic/female_tunic_v2.female_tunic_v2"));
 if (!TestNotNull(TEXT("Authored female exists"),Female) || !TestNotNull(TEXT("Authored female tunic exists"),FemaleTunic)) return false;
 TestTrue(TEXT("Female shares the animation skeleton"),Female->GetSkeleton()==Body->GetSkeleton());
 TestTrue(TEXT("Female tunic shares the animation skeleton"),FemaleTunic->GetSkeleton()==Body->GetSkeleton());
 TestTrue(TEXT("Authored female has distinct geometry bounds"),!Female->GetBounds().BoxExtent.Equals(Body->GetBounds().BoxExtent,.1f));
 TestEqual(TEXT("Female preserves the full bone hierarchy"),Female->GetRefSkeleton().GetNum(),Body->GetRefSkeleton().GetNum());
 for (int32 Bone=0;Bone<Body->GetRefSkeleton().GetNum() && Bone<Female->GetRefSkeleton().GetNum();++Bone)
 {
  TestEqual(TEXT("Shared bone names"),Female->GetRefSkeleton().GetBoneName(Bone),Body->GetRefSkeleton().GetBoneName(Bone));
  TestTrue(TEXT("Shared reference transforms"),Female->GetRefSkeleton().GetRefBonePose()[Bone].Equals(Body->GetRefSkeleton().GetRefBonePose()[Bone],.01f));
 }
 for (USkeletalMesh* Mesh : {Body,Female})
 {
  const FName Tints[]={TEXT("HairTint"),TEXT("EyeTint"),TEXT("SkinTint")};
  for (int32 Slot=0;Slot<3;++Slot)
  {
   UMaterialInterface* Material=Mesh->GetMaterials().IsValidIndex(Slot) ? Mesh->GetMaterials()[Slot].MaterialInterface : nullptr;
   if (!TestNotNull(TEXT("Body material slot is assigned"),Material)) continue;
   FLinearColor Value;
   TestTrue(TEXT("Body material exposes its appearance tint"),Material->GetVectorParameterValue(FMaterialParameterInfo(Tints[Slot]),Value));
   TestTrue(TEXT("Body material supports morph rendering"),Material->GetMaterial()->GetUsageByFlag(MATUSAGE_MorphTargets));
  }
 }
 for (const TCHAR* Name : {TEXT("BodyBuild"),TEXT("ShoulderWidth"),TEXT("WaistWidth"),TEXT("HipWidth"),TEXT("JawWidth"),TEXT("CheekWidth"),TEXT("NoseWidth"),TEXT("EarLength"),TEXT("FemaleBody"),TEXT("BodyFat"),TEXT("Muscle"),TEXT("Bust"),TEXT("TorsoLength"),TEXT("ChinHeight"),TEXT("ChinDepth"),TEXT("JawDepth"),TEXT("CheekFullness"),TEXT("NoseLength"),TEXT("NoseHeight"),TEXT("EyeSize"),TEXT("EyeSpacing"),TEXT("BrowHeight"),TEXT("MouthWidth"),TEXT("LipFullness"),TEXT("EarPoint"),TEXT("HeadSize")})
 {
  if (FName(Name)!=TEXT("FemaleBody"))
  {
   UMorphTarget* FemaleMorph=Female->FindMorphTarget(FName(Name));
   if (TestNotNull(FString::Printf(TEXT("Female exposes %s"),Name),FemaleMorph)) TestTrue(TEXT("Female morph has deformation data"),FemaleMorph->HasDataForLOD(0));
  }
  UMorphTarget* Morph = Body->FindMorphTarget(FName(Name));
  if (TestNotNull(FString::Printf(TEXT("Body exposes %s"), Name), Morph))
  {
   TestTrue(FString::Printf(TEXT("Body %s contains deformation vertices"), Name), Morph->HasDataForLOD(0));
  }
 }
 // Hair and beards must enlarge around the head pivot, rather than the mesh origin.
 for(USkeletalMesh* Mesh:{Body,Female})
 {
  const FTransform ReferenceHead=FableAppearanceAssets::HeadRelativeTransform(Mesh).Inverse();
  const FTransform Enlarged=FableAppearanceAssets::HeadRelativeTransform(Mesh,1.f)*ReferenceHead;
  TestTrue(TEXT("Head attachment keeps its pivot"),Enlarged.TransformPosition(FVector(0,0,154)).Equals(FVector(0,0,154),.01f));
  TestTrue(TEXT("Head attachment follows enlarged scalp"),Enlarged.TransformPosition(FVector(10,0,174)).Equals(FVector(13,0,180),.01f));
 }
 for (const TCHAR* Name : {TEXT("BodyBuild"), TEXT("ShoulderWidth"), TEXT("WaistWidth"), TEXT("HipWidth")})
 {
  UMorphTarget* Morph = Tunic->FindMorphTarget(FName(Name));
  if (TestNotNull(FString::Printf(TEXT("Tunic follows %s"), Name), Morph))
  {
   TestTrue(FString::Printf(TEXT("Tunic %s contains deformation vertices"), Name), Morph->HasDataForLOD(0));
  }
 }
 return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFableAppearanceSaveTest,
 "FableForge.Character.AppearanceSaveRoundTrip",
 EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FFableAppearanceSaveTest::RunTest(const FString& Parameters)
{
 UFableCharacterSaveGame* Original = NewObject<UFableCharacterSaveGame>();
 Original->CharacterName = TEXT("Appearance Test");
 Original->HeightScale = 1.08f;
 Original->Gender=EFableGender::Female;
 Original->SkinColor=FLinearColor(1.4f,.72f,.54f,1.f);
 Original->HairColor=FLinearColor(.12f,.32f,.55f,1.f);
 Original->EyeColor=FLinearColor(.3f,.7f,.2f,1.f);
 Original->HairStyle=TEXT("buns");
 Original->BeardStyle=TEXT("beard");
 Original->BodyMorphs.Add(TEXT("BodyBuild"), -0.35f);
 Original->BodyMorphs.Add(TEXT("HeadSize"), .25f);
 Original->BodyMorphs.Add(TEXT("ShoulderWidth"), 0.60f);
 Original->BodyMorphs.Add(TEXT("EarLength"), 0.80f);
 TArray<uint8> Bytes;
 if (!TestTrue(TEXT("Appearance serializes using the real save-game format"), UGameplayStatics::SaveGameToMemory(Original, Bytes))) { return false; }
 UFableCharacterSaveGame* Restored = Cast<UFableCharacterSaveGame>(UGameplayStatics::LoadGameFromMemory(Bytes));
 if (!TestNotNull(TEXT("Appearance save can be restored"), Restored)) { return false; }
 TestEqual(TEXT("Gender survives save/load"),Restored->Gender,Original->Gender);
 TestTrue(TEXT("Light skin tint survives save/load"),Restored->SkinColor.Equals(Original->SkinColor));
 TestTrue(TEXT("Hair color survives save/load"),Restored->HairColor.Equals(Original->HairColor));
 TestTrue(TEXT("Eye color survives save/load"),Restored->EyeColor.Equals(Original->EyeColor));
 TestEqual(TEXT("Hair style survives save/load"),Restored->HairStyle,Original->HairStyle);
 TestEqual(TEXT("Beard style survives save/load"),Restored->BeardStyle,Original->BeardStyle);
 TestEqual(TEXT("Height survives save/load"), Restored->HeightScale, Original->HeightScale);
 TestEqual(TEXT("All selected morphs survive save/load"), Restored->BodyMorphs.Num(), Original->BodyMorphs.Num());
 for (const TPair<FName, float>& Morph : Original->BodyMorphs)
 {
  const float* Weight = Restored->BodyMorphs.Find(Morph.Key);
  if (TestNotNull(FString::Printf(TEXT("Saved morph %s exists"), *Morph.Key.ToString()), Weight))
  {
   TestEqual(FString::Printf(TEXT("Saved weight for %s"), *Morph.Key.ToString()), *Weight, Morph.Value);
  }
 }
 return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFableRaceAppearancePolicyTest,
 "FableForge.Character.RaceAppearancePolicy",
 EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FFableRaceAppearancePolicyTest::RunTest(const FString& Parameters)
{
 const float Invalid=std::numeric_limits<float>::quiet_NaN();
 for (const FString Race : {TEXT("human"),TEXT("elf"),TEXT("dwarf"),TEXT("halfling"),TEXT("orc"),TEXT("tiefling")})
 for (EFableGender Gender : {EFableGender::Male,EFableGender::Female})
 {
  FFableCharacterProfile Profile;
  Profile.RaceId=Race; Profile.Gender=Gender; Profile.HeightScale=Invalid;
  Profile.SkinColor=FableAppearance::DefaultSkinColor(Race);
  FableAppearance::SanitizeAppearance(Profile);
  const auto HeightRange=FableAppearance::Range(TEXT("Height"),Race,Gender);
  TestEqual(TEXT("Invalid height recovers the racial default"),Profile.HeightScale,HeightRange.Default);
  for (const auto& Control : FableAppearance::Controls())
  {
   const auto Range=FableAppearance::Range(Control.Name,Race,Gender);
   TestTrue(TEXT("Every race/gender default is within its allowed range"),Range.Min<=Range.Default && Range.Default<=Range.Max);
   if (Control.Name==TEXT("Height")) continue;
   const float* Value=Profile.BodyMorphs.Find(Control.Name);
   if (TestNotNull(TEXT("Missing appearance values receive defaults"),Value))
    TestEqual(TEXT("Missing morph uses the racial default"),*Value,Range.Default);
  }
  for (float Outside : {-100.f,100.f,Invalid})
  {
   for (const auto& Control : FableAppearance::Controls())
    if (Control.Name!=TEXT("Height")) Profile.BodyMorphs.Add(Control.Name,Outside);
   Profile.HeightScale=Outside;
   Profile.BodyMorphs.Add(TEXT("NotAnAuthoredMorph"),Outside);
   FableAppearance::SanitizeAppearance(Profile);
   TestFalse(TEXT("Unknown morphs cannot enter saved appearance"),Profile.BodyMorphs.Contains(TEXT("NotAnAuthoredMorph")));
   TestTrue(TEXT("Height remains finite and race bounded"),FMath::IsFinite(Profile.HeightScale) && Profile.HeightScale>=HeightRange.Min && Profile.HeightScale<=HeightRange.Max);
   for (const auto& Control : FableAppearance::Controls())
   {
    if (Control.Name==TEXT("Height")) continue;
    const auto Range=FableAppearance::Range(Control.Name,Race,Gender);
    const float Value=Profile.BodyMorphs.FindRef(Control.Name);
    TestTrue(TEXT("Out of range and invalid morphs are safely bounded"),FMath::IsFinite(Value) && Value>=Range.Min && Value<=Range.Max);
   }
  }
 }
 FFableCharacterProfile Orc;
 Orc.RaceId=TEXT(" ORC "); Orc.SkinColor=FLinearColor(1.f,0.f,1.f,1.f);
 FableAppearance::SanitizeAppearance(Orc);
 TestEqual(TEXT("Race IDs are canonicalized"),Orc.RaceId,FString(TEXT("orc")));
 TestFalse(TEXT("Orcs reject arbitrary magenta skin"),Orc.SkinColor.Equals(FLinearColor(1.f,0.f,1.f,1.f)));
 TestTrue(TEXT("Orc skin is one of the allowed racial tones"),FableAppearance::SkinPalette(TEXT("orc")).ContainsByPredicate([&Orc](const FableAppearance::FSkinTone& Tone){return Tone.Color.Equals(Orc.SkinColor);}));
 for (const auto& Tone : FableAppearance::SkinPalette(TEXT("orc")))
  TestTrue(TEXT("Configured orc tones stay green, olive or neutral"),Tone.Color.G>=Tone.Color.R && Tone.Color.G>=Tone.Color.B);
 const FFableCharacterProfile Stable=Orc;
 FableAppearance::SanitizeAppearance(Orc);
 TestTrue(TEXT("Repeated validation preserves an accepted skin tone"),Orc.SkinColor.Equals(Stable.SkinColor));
 TestEqual(TEXT("Repeated validation preserves accepted height"),Orc.HeightScale,Stable.HeightScale);
 UFableCharacterSaveGame* Save=NewObject<UFableCharacterSaveGame>();
 Save->RaceId=Orc.RaceId;Save->SkinColor=Orc.SkinColor;Save->BodyMorphs=Orc.BodyMorphs;Save->HeightScale=Orc.HeightScale;
 TArray<uint8> Bytes;
 if (!TestTrue(TEXT("Validated race appearance serializes"),UGameplayStatics::SaveGameToMemory(Save,Bytes))) return false;
 UFableCharacterSaveGame* Restored=Cast<UFableCharacterSaveGame>(UGameplayStatics::LoadGameFromMemory(Bytes));
 if (!TestNotNull(TEXT("Validated race appearance restores"),Restored)) return false;
 TestEqual(TEXT("Race survives round trip"),Restored->RaceId,Orc.RaceId);
 TestTrue(TEXT("Restricted orc palette selection survives round trip"),Restored->SkinColor.Equals(Orc.SkinColor));
 TestEqual(TEXT("Racial height survives round trip"),Restored->HeightScale,Orc.HeightScale);
 for (const auto& Morph : Orc.BodyMorphs) TestEqual(TEXT("Racial morph survives round trip"),Restored->BodyMorphs.FindRef(Morph.Key),Morph.Value);
 FFableCharacterProfile Unknown;Unknown.RaceId=TEXT("invalid-race");
 Unknown.Gender=static_cast<EFableGender>(255);Unknown.SkinColor=FLinearColor(Invalid,100.f,-100.f,Invalid);
 FableAppearance::SanitizeAppearance(Unknown);
 TestEqual(TEXT("Unknown races safely fall back to human"),Unknown.RaceId,FString(TEXT("human")));
 TestEqual(TEXT("Invalid gender recovers safely"),Unknown.Gender,EFableGender::Male);
 TestTrue(TEXT("Invalid skin color becomes a legal finite palette tone"),FableAppearance::SkinPalette(TEXT("human")).ContainsByPredicate([&Unknown](const FableAppearance::FSkinTone& Tone){return Tone.Color.Equals(Unknown.SkinColor);}));
 return true;
}
#endif
