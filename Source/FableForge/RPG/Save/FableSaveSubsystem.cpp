#include "RPG/Save/FableSaveSubsystem.h"

#include "FableForge.h"
#include "Engine/DataTable.h"
#include "Kismet/GameplayStatics.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "RPG/Data/FableRaceDefinitionTableRow.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "RPG/Save/FableCharacterSaveGame.h"
#include "RPG/Save/FableProfileIndexSaveGame.h"
#include "RPG/UI/FableAppearancePresets.h"

namespace
{
	const FString ProfileIndexSlotName = TEXT("FableForge_ProfileIndex");
	constexpr int32 SaveUserIndex = 0;
	constexpr int32 MainActionBarColumns = 10;
	constexpr int32 MainActionBarCollapsedRows = 2;
	constexpr int32 MainActionBarExpandedRows = 4;
	const TCHAR* RacesDataTablePath = TEXT("/Game/Data/DT_Races.DT_Races");
	const TCHAR* SkillsDataTablePath = TEXT("/Game/Data/DT_Skills.DT_Skills");
	const TCHAR* BasicAttackSkillId = TEXT("basic_attack");
	const TCHAR* DefaultCosmicSkillId = TEXT("slow_time");

	bool IsCosmicSkillDefinition(const FString& SkillId)
	{
		FFableSkillDefinitionTableRow StarterDefinition;
		if (FableSkillCatalog::TryGetStarterSkillDefinition(SkillId, StarterDefinition))
			return StarterDefinition.Category == EFableSkillCategory::TimeManipulation;
		if (SkillId.Equals(DefaultCosmicSkillId, ESearchCase::IgnoreCase))
		{
			return true;
		}

		if (UDataTable* SkillTable = LoadObject<UDataTable>(nullptr, SkillsDataTablePath))
		{
			if (const FFableSkillDefinitionTableRow* Row = SkillTable->FindRow<FFableSkillDefinitionTableRow>(FName(*SkillId), TEXT("UFableSaveSubsystem::IsCosmicSkillDefinition")))
			{
				return Row->Category == EFableSkillCategory::TimeManipulation;
			}
		}

		FFableSkillDefinitionTableRow FallbackDefinition;
		return FableSkillCatalog::TryGetStarterSkillDefinition(SkillId, FallbackDefinition)
			&& FallbackDefinition.Category == EFableSkillCategory::TimeManipulation;
	}
}

void UFableSaveSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

	LoadRacesFromJson();
	LoadIndex();
}

void UFableSaveSubsystem::Deinitialize()
{
	LoadedGame = nullptr;
	Super::Deinitialize();
}

const TArray<FFableRaceDefinition>& UFableSaveSubsystem::GetRaces() const
{
	return RaceDefinitions;
}

const TArray<FFableCharacterProfile>& UFableSaveSubsystem::GetCharacters() const
{
	return CharacterProfiles;
}

bool UFableSaveSubsystem::LoadRacesFromJson(const FString& RelativePath)
{
	(void)RelativePath;
	RaceDefinitions.Reset();

	if (UDataTable* RacesTable = LoadObject<UDataTable>(nullptr, RacesDataTablePath))
	{
		static const FString ContextString(TEXT("UFableSaveSubsystem::LoadRacesFromJson"));
		TArray<FFableRaceDefinitionTableRow*> Rows;
		RacesTable->GetAllRows(ContextString, Rows);

		for (const FFableRaceDefinitionTableRow* Row : Rows)
		{
			if (Row == nullptr || Row->Id.IsEmpty())
			{
				continue;
			}

			FFableRaceDefinition RaceDefinition;
			RaceDefinition.Id = Row->Id;
			RaceDefinition.Name = Row->DisplayName;
			RaceDefinition.Description = Row->Description;
			RaceDefinition.Image = Row->Image;
			RaceDefinition.BaseHitPoints = Row->BaseHitPoints;
			RaceDefinition.BaseMana = Row->BaseMana;
			RaceDefinition.BaseEnergy = Row->BaseEnergy;
			RaceDefinition.BaseRage = Row->BaseRage;
			RaceDefinition.AbilityScoreBonuses.Strength = Row->Strength;
			RaceDefinition.AbilityScoreBonuses.Dexterity = Row->Dexterity;
			RaceDefinition.AbilityScoreBonuses.Constitution = Row->Constitution;
			RaceDefinition.AbilityScoreBonuses.Intelligence = Row->Intelligence;
			RaceDefinition.AbilityScoreBonuses.Wisdom = Row->Wisdom;
			RaceDefinition.AbilityScoreBonuses.Charisma = Row->Charisma;
			RaceDefinitions.Add(MoveTemp(RaceDefinition));
		}

		UE_LOG(LogFableForge, Log, TEXT("Loaded %d races from DataTable '%s'"), RaceDefinitions.Num(), RacesDataTablePath);
		return RaceDefinitions.Num() > 0;
	}
	UE_LOG(LogFableForge, Warning, TEXT("Race DataTable not found at '%s'."), RacesDataTablePath);
	return false;
}

bool UFableSaveSubsystem::HasAnyCharacters() const
{
	return CharacterProfiles.Num() > 0;
}

bool UFableSaveSubsystem::HasAnySavedGames() const
{
	for (const FFableCharacterProfile& Profile : CharacterProfiles)
	{
		if (CharacterHasAnySavedSlots(Profile))
		{
			return true;
		}
	}

	return false;
}

bool UFableSaveSubsystem::CharacterHasAnySavedSlots(const FFableCharacterProfile& Profile) const
{
	for (const FFableSaveSlotMeta& SlotMeta : Profile.SaveSlots)
	{
		if (SlotMeta.bHasSave)
		{
			return true;
		}
	}

	return false;
}

FGuid UFableSaveSubsystem::CreateCharacter(const FString& CharacterName, const FString& RaceId, EFableGender Gender, const TMap<FName, float>& BodyMorphs, float HeightScale, FLinearColor SkinColor, FLinearColor HairColor, FLinearColor EyeColor, const FString& HairStyle, const FString& BeardStyle)
{
	FFableCharacterProfile Profile;
	Profile.CharacterId = FGuid::NewGuid();
	Profile.CharacterName = CharacterName.TrimStartAndEnd();
	if (Profile.CharacterName.IsEmpty())
	{
		Profile.CharacterName = TEXT("Adventurer");
	}

	Profile.RaceId = RaceId.TrimStartAndEnd();
	if (Profile.RaceId.IsEmpty())
	{
		Profile.RaceId = TEXT("human");
	}
	Profile.Gender = Gender;
	Profile.BodyMorphs = BodyMorphs;
	Profile.HeightScale = HeightScale;
	Profile.SkinColor = SkinColor;
	Profile.HairColor = HairColor;
	Profile.EyeColor = EyeColor;
	Profile.HairStyle = HairStyle;
	Profile.BeardStyle = BeardStyle;
	FableAppearance::SanitizeAppearance(Profile);

	EnsureCharacterSlots(Profile);
	EnsureInventoryData(Profile);
	if (Profile.InventorySlots.Num() >= 3)
	{
		Profile.InventorySlots[0] = TEXT("iron_sword");
		Profile.InventorySlots[1] = TEXT("peasant_chest");
		Profile.InventorySlots[2] = TEXT("health_potion");
		Profile.InventoryQuantities[0] = 1;
		Profile.InventoryQuantities[1] = 1;
		Profile.InventoryQuantities[2] = 1;
	}
	Profile.LearnedSkills = { TEXT("basic_attack"), TEXT("heal_wave") };
	EnsureStarterSkills(Profile);
	EnsureActionBarsData(Profile);

	CharacterProfiles.Add(MoveTemp(Profile));
	ActiveCharacterId = CharacterProfiles.Last().CharacterId;
	ActiveSlotIndex = INDEX_NONE;
	SaveIndex();

	return ActiveCharacterId;
}

bool UFableSaveSubsystem::DeleteCharacter(const FGuid& CharacterId)
{
	const int32 CharacterIndex = FindCharacterIndex(CharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	for (int32 SlotIndex = 0; SlotIndex < SlotsPerCharacter; ++SlotIndex)
	{
		const FString SlotName = MakeSlotName(CharacterId, SlotIndex);
		if (UGameplayStatics::DoesSaveGameExist(SlotName, SaveUserIndex))
		{
			UGameplayStatics::DeleteGameInSlot(SlotName, SaveUserIndex);
		}
	}

	CharacterProfiles.RemoveAt(CharacterIndex);
	if (ActiveCharacterId == CharacterId)
	{
		ActiveCharacterId.Invalidate();
		ActiveSlotIndex = INDEX_NONE;
		LoadedGame = nullptr;
	}

	return SaveIndex();
}

bool UFableSaveSubsystem::SaveCharacterToSlot(const FGuid& CharacterId, int32 SlotIndex, const FString& MapName)
{
	if (SlotIndex < 0 || SlotIndex >= SlotsPerCharacter)
	{
		return false;
	}

	const int32 CharacterIndex = FindCharacterIndex(CharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	EnsureCharacterSlots(Profile);
	EnsureInventoryData(Profile);
	EnsureActionBarsData(Profile);

	UFableCharacterSaveGame* SaveGame = Cast<UFableCharacterSaveGame>(UGameplayStatics::CreateSaveGameObject(UFableCharacterSaveGame::StaticClass()));
	if (SaveGame == nullptr)
	{
		return false;
	}

	SaveGame->CharacterId = CharacterId;
	SaveGame->CharacterName = Profile.CharacterName;
	SaveGame->RaceId = Profile.RaceId;
	SaveGame->Gender = Profile.Gender;
	SaveGame->BodyMorphs = Profile.BodyMorphs;
	SaveGame->HeightScale = Profile.HeightScale;
	SaveGame->SkinColor = Profile.SkinColor;
	SaveGame->HairColor = Profile.HairColor;
	SaveGame->EyeColor = Profile.EyeColor;
	SaveGame->HairStyle = Profile.HairStyle;
	SaveGame->BeardStyle = Profile.BeardStyle;
	SaveGame->SlotIndex = SlotIndex;
	SaveGame->SavedAtUtc = FDateTime::UtcNow().ToIso8601();
	SaveGame->MapName = MapName;
	SaveGame->CompanionNames = Profile.CompanionNames;
	SaveGame->HealthPercent = Profile.HealthPercent;
	SaveGame->ManaPercent = Profile.ManaPercent;
	SaveGame->ExperiencePercent = Profile.ExperiencePercent;
	SaveGame->EquippedItems = Profile.EquippedItems;
	SaveGame->InventoryItems = Profile.InventorySlots;
	SaveGame->InventoryQuantities = Profile.InventoryQuantities;
	SaveGame->LearnedSkills = Profile.LearnedSkills;
	SaveGame->EquippedCosmicSkillId = CharacterId == ActiveCharacterId
		? GetActiveCosmicSkillId()
		: DefaultCosmicSkillId;
	SaveGame->ActionBars = Profile.ActionBars;
	SaveGame->QuickWheelPages = Profile.QuickWheelPages;

	const FString SlotName = MakeSlotName(CharacterId, SlotIndex);
	if (!UGameplayStatics::SaveGameToSlot(SaveGame, SlotName, SaveUserIndex))
	{
		UE_LOG(LogFableForge, Warning, TEXT("Failed to save character '%s' to slot %d"), *Profile.CharacterName, SlotIndex);
		return false;
	}

	FFableSaveSlotMeta& SlotMeta = Profile.SaveSlots[SlotIndex];
	SlotMeta.SlotIndex = SlotIndex;
	SlotMeta.bHasSave = true;
	SlotMeta.LastPlayedUtc = SaveGame->SavedAtUtc;
	SlotMeta.LastMapName = MapName;

	LoadedGame = SaveGame;
	ActiveCharacterId = CharacterId;
	ActiveSlotIndex = SlotIndex;
	SaveIndex();

	return true;
}

UFableCharacterSaveGame* UFableSaveSubsystem::LoadCharacterFromSlot(const FGuid& CharacterId, int32 SlotIndex)
{
	if (SlotIndex < 0 || SlotIndex >= SlotsPerCharacter)
	{
		return nullptr;
	}

	const int32 CharacterIndex = FindCharacterIndex(CharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return nullptr;
	}

	const FString SlotName = MakeSlotName(CharacterId, SlotIndex);
	if (!UGameplayStatics::DoesSaveGameExist(SlotName, SaveUserIndex))
	{
		return nullptr;
	}

	UFableCharacterSaveGame* SaveGame = Cast<UFableCharacterSaveGame>(UGameplayStatics::LoadGameFromSlot(SlotName, SaveUserIndex));
	if (SaveGame == nullptr)
	{
		return nullptr;
	}

	FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	EnsureCharacterSlots(Profile);
	Profile.CharacterName = SaveGame->CharacterName;
	Profile.RaceId = SaveGame->RaceId;
	Profile.Gender = SaveGame->Gender;
	Profile.BodyMorphs = SaveGame->BodyMorphs;
	Profile.HeightScale = SaveGame->HeightScale;
	Profile.SkinColor = SaveGame->SkinColor;
	Profile.HairColor = SaveGame->HairColor;
	Profile.EyeColor = SaveGame->EyeColor;
	Profile.HairStyle = SaveGame->HairStyle;
	Profile.BeardStyle = SaveGame->BeardStyle;
	Profile.CompanionNames = SaveGame->CompanionNames;
	Profile.HealthPercent = SaveGame->HealthPercent;
	Profile.ManaPercent = SaveGame->ManaPercent;
	Profile.ExperiencePercent = SaveGame->ExperiencePercent;
	Profile.EquippedItems = SaveGame->EquippedItems;
	Profile.InventorySlots = SaveGame->InventoryItems;
	Profile.InventoryQuantities = SaveGame->InventoryQuantities;
	Profile.LearnedSkills = SaveGame->LearnedSkills;
	Profile.ActionBars = SaveGame->ActionBars;
	Profile.QuickWheelPages = SaveGame->QuickWheelPages;
	EnsureInventoryData(Profile);
	EnsureActionBarsData(Profile);

	FFableSaveSlotMeta& SlotMeta = Profile.SaveSlots[SlotIndex];
	SlotMeta.SlotIndex = SlotIndex;
	SlotMeta.bHasSave = true;
	SlotMeta.LastPlayedUtc = SaveGame->SavedAtUtc;
	SlotMeta.LastMapName = SaveGame->MapName;

	LoadedGame = SaveGame;
	ActiveCharacterId = CharacterId;
	ActiveSlotIndex = SlotIndex;
	SaveIndex();

	return SaveGame;
}

bool UFableSaveSubsystem::TryGetCharacterProfile(const FGuid& CharacterId, FFableCharacterProfile& OutProfile) const
{
	const int32 CharacterIndex = FindCharacterIndex(CharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	OutProfile = CharacterProfiles[CharacterIndex];
	return true;
}

bool UFableSaveSubsystem::TryGetActiveCharacterProfile(FFableCharacterProfile& OutProfile) const
{
	if (!ActiveCharacterId.IsValid())
	{
		return false;
	}

	return TryGetCharacterProfile(ActiveCharacterId, OutProfile);
}

void UFableSaveSubsystem::GetSaveSlots(const FGuid& CharacterId, TArray<FFableSaveSlotMeta>& OutSlots) const
{
	OutSlots.Reset();
	const int32 CharacterIndex = FindCharacterIndex(CharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return;
	}

	OutSlots = CharacterProfiles[CharacterIndex].SaveSlots;
}

void UFableSaveSubsystem::SetCompanionsForCharacter(const FGuid& CharacterId, const TArray<FString>& CompanionNames)
{
	const int32 CharacterIndex = FindCharacterIndex(CharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return;
	}

	CharacterProfiles[CharacterIndex].CompanionNames = CompanionNames;
	SaveIndex();
}

bool UFableSaveSubsystem::TryGetActiveInventory(TArray<FString>& OutInventorySlots, TArray<FString>& OutEquippedSlots) const
{
	OutInventorySlots.Reset();
	OutEquippedSlots.Reset();

	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	OutInventorySlots = CharacterProfiles[CharacterIndex].InventorySlots;
	OutEquippedSlots = CharacterProfiles[CharacterIndex].EquippedItems;
	return true;
}

bool UFableSaveSubsystem::TryGetActiveInventoryQuantities(TArray<int32>& OutInventoryQuantities) const
{
	OutInventoryQuantities.Reset();
	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	OutInventoryQuantities = CharacterProfiles[CharacterIndex].InventoryQuantities;
	return true;
}

bool UFableSaveSubsystem::SetActiveInventory(const TArray<FString>& InInventorySlots, const TArray<FString>& InEquippedSlots)
{
	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	const FFableCharacterProfile& ExistingProfile = CharacterProfiles[CharacterIndex];
	TArray<int32> PreservedQuantities;
	PreservedQuantities.SetNum(InInventorySlots.Num());
	for (int32 Index = 0; Index < InInventorySlots.Num(); ++Index)
	{
		if (ExistingProfile.InventorySlots.IsValidIndex(Index)
			&& ExistingProfile.InventorySlots[Index].Equals(InInventorySlots[Index], ESearchCase::CaseSensitive)
			&& !InInventorySlots[Index].IsEmpty()
			&& ExistingProfile.InventoryQuantities.IsValidIndex(Index))
		{
			PreservedQuantities[Index] = ExistingProfile.InventoryQuantities[Index];
		}
		else if (!InInventorySlots[Index].IsEmpty())
		{
			PreservedQuantities[Index] = 1;
		}
	}
	return SetActiveInventory(InInventorySlots, InEquippedSlots, PreservedQuantities);
}

bool UFableSaveSubsystem::SetActiveInventory(const TArray<FString>& InInventorySlots, const TArray<FString>& InEquippedSlots, const TArray<int32>& InInventoryQuantities)
{
	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	// Loot actors consume their items only after this succeeds. Keep failed saves
	// from granting an item in memory while leaving the same loot in the world.
	FFableCharacterProfile PreviousProfile = Profile;
	Profile.InventorySlots = InInventorySlots;
	Profile.InventoryQuantities = InInventoryQuantities;
	Profile.EquippedItems = InEquippedSlots;
	EnsureInventoryData(Profile);
	if (!SaveIndex())
	{
		Profile = MoveTemp(PreviousProfile);
		return false;
	}
	ActiveInventoryChanged.Broadcast(Profile.InventorySlots, Profile.EquippedItems);
	return true;
}

bool UFableSaveSubsystem::IsItemStackable(const FString& ItemId) const
{
	if (ItemId.IsEmpty())
	{
		return false;
	}

	if (UDataTable* ItemTable = LoadObject<UDataTable>(nullptr, TEXT("/Game/Data/DT_Items.DT_Items")))
	{
		static const FString ContextString(TEXT("UFableSaveSubsystem::IsItemStackable"));
		if (const FFableItemDefinitionTableRow* Row = ItemTable->FindRow<FFableItemDefinitionTableRow>(FName(*ItemId), ContextString, false))
		{
			return Row->bStackable;
		}
		TArray<FFableItemDefinitionTableRow*> Rows;
		ItemTable->GetAllRows(ContextString, Rows);
		for (const FFableItemDefinitionTableRow* Row : Rows)
		{
			if (Row != nullptr && Row->ItemId.Equals(ItemId, ESearchCase::IgnoreCase))
			{
				return Row->bStackable;
			}
		}
	}

	// Keep authored consumable/material behavior when the cooked table is unavailable.
	static const TSet<FString> FallbackStackableItems = {
		TEXT("health_potion"), TEXT("mana_potion"), TEXT("wood"), TEXT("stone"),
		TEXT("iron_ore"), TEXT("meat"), TEXT("honey"), TEXT("berries")
	};
	return FallbackStackableItems.Contains(ItemId.ToLower());
}

int32 UFableSaveSubsystem::AddActiveInventoryItem(const FString& ItemId, int32 Quantity)
{
	if (ItemId.IsEmpty() || Quantity <= 0)
	{
		return 0;
	}

	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return 0;
	}

	FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	const FFableCharacterProfile PreviousProfile = Profile;
	EnsureInventoryData(Profile);
	int32 Remaining = Quantity;
	const bool bStackable = IsItemStackable(ItemId);

	if (bStackable)
	{
		for (int32 Index = 0; Index < Profile.InventorySlots.Num() && Remaining > 0; ++Index)
		{
			if (!Profile.InventorySlots[Index].Equals(ItemId, ESearchCase::IgnoreCase))
			{
				continue;
			}
			const int32 ExistingQuantity = FMath::Max(0, Profile.InventoryQuantities[Index]);
			const int32 Addable = MAX_int32 - ExistingQuantity;
			const int32 AcceptedHere = FMath::Min(Remaining, FMath::Max(0, Addable));
			Profile.InventoryQuantities[Index] = ExistingQuantity + AcceptedHere;
			Remaining -= AcceptedHere;
		}
	}

	for (int32 Index = 0; Index < Profile.InventorySlots.Num() && Remaining > 0; ++Index)
	{
		if (!Profile.InventorySlots[Index].IsEmpty())
		{
			continue;
		}
		Profile.InventorySlots[Index] = ItemId;
		const int32 AcceptedHere = bStackable ? FMath::Min(Remaining, MAX_int32) : 1;
		Profile.InventoryQuantities[Index] = AcceptedHere;
		Remaining -= AcceptedHere;
	}

	const int32 Accepted = Quantity - Remaining;
	if (Accepted <= 0 || !SaveIndex())
	{
		Profile = PreviousProfile;
		return 0;
	}

	ActiveInventoryChanged.Broadcast(Profile.InventorySlots, Profile.EquippedItems);
	return Accepted;
}

bool UFableSaveSubsystem::ConsumeActiveInventoryItem(int32 InventorySlot)
{
	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	EnsureInventoryData(Profile);
	if (!Profile.InventorySlots.IsValidIndex(InventorySlot))
	{
		UE_LOG(LogFableForge, Warning, TEXT("Consumable rejected: invalid inventory slot %d"), InventorySlot);
		return false;
	}

	const FString ItemId = Profile.InventorySlots[InventorySlot];
	if (ItemId.IsEmpty() || Profile.InventoryQuantities[InventorySlot] <= 0)
	{
		return false;
	}
	float HealthDelta = 0.0f;
	float ManaDelta = 0.0f;
	if (ItemId.Equals(TEXT("health_potion"), ESearchCase::IgnoreCase))
	{
		HealthDelta = 0.25f;
	}
	else if (ItemId.Equals(TEXT("mana_potion"), ESearchCase::IgnoreCase))
	{
		ManaDelta = 0.25f;
	}
	else if (ItemId.Equals(TEXT("meat"), ESearchCase::IgnoreCase)
		|| ItemId.Equals(TEXT("honey"), ESearchCase::IgnoreCase)
		|| ItemId.Equals(TEXT("berries"), ESearchCase::IgnoreCase))
	{
		HealthDelta = 0.10f;
	}
	else
	{
		UE_LOG(LogFableForge, Display, TEXT("Consumable rejected: unsupported item '%s'"), *ItemId);
		return false;
	}

	if (HealthDelta > 0.0f && Profile.HealthPercent >= 1.0f - KINDA_SMALL_NUMBER)
	{
		UE_LOG(LogFableForge, Display, TEXT("Consumable rejected: health already full item='%s'"), *ItemId);
		return false;
	}
	if (ManaDelta > 0.0f)
	{
		const FFableRaceDefinition* Race = nullptr;
		for (const FFableRaceDefinition& Candidate : RaceDefinitions)
		{
			if (Candidate.Id.Equals(Profile.RaceId, ESearchCase::IgnoreCase))
			{
				Race = &Candidate;
				break;
			}
		}
		if (Race == nullptr || Race->BaseMana <= 0)
		{
			UE_LOG(LogFableForge, Display, TEXT("Consumable rejected: mana unavailable item='%s' race='%s'"), *ItemId, *Profile.RaceId);
			return false;
		}
		if (Profile.ManaPercent >= 1.0f - KINDA_SMALL_NUMBER)
		{
			UE_LOG(LogFableForge, Display, TEXT("Consumable rejected: mana already full item='%s'"), *ItemId);
			return false;
		}
	}

	const FFableCharacterProfile PreviousProfile = Profile;
	Profile.HealthPercent = FMath::Clamp(Profile.HealthPercent + HealthDelta, 0.0f, 1.0f);
	Profile.ManaPercent = FMath::Clamp(Profile.ManaPercent + ManaDelta, 0.0f, 1.0f);
	--Profile.InventoryQuantities[InventorySlot];
	if (Profile.InventoryQuantities[InventorySlot] <= 0)
	{
		Profile.InventoryQuantities[InventorySlot] = 0;
		Profile.InventorySlots[InventorySlot].Reset();
	}
	if (!SaveIndex())
	{
		Profile = PreviousProfile;
		UE_LOG(LogFableForge, Warning, TEXT("Consumable rejected: profile save failed item='%s' slot=%d"), *ItemId, InventorySlot);
		return false;
	}

	ActiveInventoryChanged.Broadcast(Profile.InventorySlots, Profile.EquippedItems);
	UE_LOG(LogFableForge, Display, TEXT("Consumable consumed item='%s' slot=%d health=%.2f mana=%.2f"),
		*ItemId, InventorySlot, Profile.HealthPercent, Profile.ManaPercent);
	return true;
}

bool UFableSaveSubsystem::RestoreActiveHealth(float HealthFraction)
{
	if (!FMath::IsFinite(HealthFraction) || HealthFraction <= 0.0f)
	{
		UE_LOG(LogFableForge, Display, TEXT("Health restore rejected: invalid fraction %.3f"), HealthFraction);
		return false;
	}

	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	EnsureInventoryData(Profile);
	if (Profile.HealthPercent >= 1.0f - KINDA_SMALL_NUMBER)
	{
		UE_LOG(LogFableForge, Display, TEXT("Health restore rejected: health already full"));
		return false;
	}

	const FFableCharacterProfile PreviousProfile = Profile;
	Profile.HealthPercent = FMath::Clamp(Profile.HealthPercent + FMath::Clamp(HealthFraction, 0.0f, 1.0f), 0.0f, 1.0f);
	if (!SaveIndex())
	{
		Profile = PreviousProfile;
		UE_LOG(LogFableForge, Warning, TEXT("Health restore rejected: profile save failed fraction=%.3f"), HealthFraction);
		return false;
	}

	ActiveInventoryChanged.Broadcast(Profile.InventorySlots, Profile.EquippedItems);
	UE_LOG(LogFableForge, Display, TEXT("Health restored fraction=%.3f health=%.2f"), HealthFraction, Profile.HealthPercent);
	return true;
}

bool UFableSaveSubsystem::TryGetActiveLearnedSkills(TArray<FString>& OutLearnedSkills) const
{
	OutLearnedSkills.Reset();

	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	OutLearnedSkills = CharacterProfiles[CharacterIndex].LearnedSkills;
	return true;
}

FString UFableSaveSubsystem::GetActiveCosmicSkillId() const
{
	if (LoadedGame == nullptr)
	{
		return DefaultCosmicSkillId;
	}

	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return DefaultCosmicSkillId;
	}

	const FString EquippedSkillId = LoadedGame->EquippedCosmicSkillId.TrimStartAndEnd();
	if (EquippedSkillId.Equals(DefaultCosmicSkillId, ESearchCase::IgnoreCase))
	{
		return DefaultCosmicSkillId;
	}

	const FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	if (IsCosmicSkillDefinition(EquippedSkillId)
		&& Profile.LearnedSkills.ContainsByPredicate([&EquippedSkillId](const FString& LearnedSkillId)
		{
			return LearnedSkillId.Equals(EquippedSkillId, ESearchCase::IgnoreCase);
		}))
	{
		return EquippedSkillId;
	}

	return DefaultCosmicSkillId;
}

bool UFableSaveSubsystem::SetActiveCosmicSkillId(const FString& SkillId)
{
	if (LoadedGame == nullptr || ActiveSlotIndex < 0 || ActiveSlotIndex >= SlotsPerCharacter)
	{
		return false;
	}

	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	const FString RequestedSkillId = SkillId.TrimStartAndEnd();
	const bool bIsBuiltInDefault = RequestedSkillId.Equals(DefaultCosmicSkillId, ESearchCase::IgnoreCase);
	const FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	const bool bIsLearnedCosmic = IsCosmicSkillDefinition(RequestedSkillId)
		&& Profile.LearnedSkills.ContainsByPredicate([&RequestedSkillId](const FString& LearnedSkillId)
		{
			return LearnedSkillId.Equals(RequestedSkillId, ESearchCase::IgnoreCase);
		});
	if (!bIsBuiltInDefault && !bIsLearnedCosmic)
	{
		return false;
	}

	const FString PreviousSkillId = LoadedGame->EquippedCosmicSkillId;
	LoadedGame->EquippedCosmicSkillId = bIsBuiltInDefault ? DefaultCosmicSkillId : RequestedSkillId;
	const FString SlotName = MakeSlotName(ActiveCharacterId, ActiveSlotIndex);
	if (!UGameplayStatics::SaveGameToSlot(LoadedGame, SlotName, SaveUserIndex))
	{
		LoadedGame->EquippedCosmicSkillId = PreviousSkillId;
		return false;
	}

	return true;
}

bool UFableSaveSubsystem::TryGetActiveActionBars(TArray<FFableActionBarData>& OutActionBars) const
{
	OutActionBars.Reset();

	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	OutActionBars = CharacterProfiles[CharacterIndex].ActionBars;
	return true;
}

bool UFableSaveSubsystem::SetActiveActionBars(const TArray<FFableActionBarData>& InActionBars)
{
	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE)
	{
		return false;
	}

	FFableCharacterProfile& Profile = CharacterProfiles[CharacterIndex];
	Profile.ActionBars = InActionBars;
	EnsureActionBarsData(Profile);
	return SaveIndex();
}

bool UFableSaveSubsystem::TryGetActiveQuickWheelPages(TArray<FFableQuickWheelPageData>& OutPages) const
{
	OutPages.Reset();
	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE) return false;
	OutPages = CharacterProfiles[CharacterIndex].QuickWheelPages;
	return true;
}

bool UFableSaveSubsystem::SetActiveQuickWheelPages(const TArray<FFableQuickWheelPageData>& InPages)
{
	const int32 CharacterIndex = FindCharacterIndex(ActiveCharacterId);
	if (CharacterIndex == INDEX_NONE) return false;
	CharacterProfiles[CharacterIndex].QuickWheelPages = InPages;
	return SaveIndex();
}

FGuid UFableSaveSubsystem::GetActiveCharacterId() const
{
	return ActiveCharacterId;
}

int32 UFableSaveSubsystem::GetActiveSlotIndex() const
{
	return ActiveSlotIndex;
}

const UFableCharacterSaveGame* UFableSaveSubsystem::GetLoadedGame() const
{
	return LoadedGame;
}

FFableActiveInventoryChangedSignature& UFableSaveSubsystem::OnActiveInventoryChanged()
{
	return ActiveInventoryChanged;
}

bool UFableSaveSubsystem::LoadIndex()
{
	CharacterProfiles.Reset();
	ActiveCharacterId.Invalidate();
	ActiveSlotIndex = INDEX_NONE;

	if (!UGameplayStatics::DoesSaveGameExist(ProfileIndexSlotName, SaveUserIndex))
	{
		return true;
	}

	UFableProfileIndexSaveGame* LoadedIndex = Cast<UFableProfileIndexSaveGame>(UGameplayStatics::LoadGameFromSlot(ProfileIndexSlotName, SaveUserIndex));
	if (LoadedIndex == nullptr)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Profile index exists but failed to load."));
		return false;
	}

	CharacterProfiles = LoadedIndex->Characters;
	ActiveCharacterId = LoadedIndex->ActiveCharacterId;
	ActiveSlotIndex = LoadedIndex->ActiveSlotIndex;

	for (FFableCharacterProfile& Profile : CharacterProfiles)
	{
		EnsureCharacterSlots(Profile);
		EnsureInventoryData(Profile);
		EnsureActionBarsData(Profile);
		for (int32 SlotIndex = 0; SlotIndex < Profile.SaveSlots.Num(); ++SlotIndex)
		{
			FFableSaveSlotMeta& SlotMeta = Profile.SaveSlots[SlotIndex];
			SlotMeta.SlotIndex = SlotIndex;
			SlotMeta.bHasSave = UGameplayStatics::DoesSaveGameExist(MakeSlotName(Profile.CharacterId, SlotIndex), SaveUserIndex);
		}
	}

	return true;
}

bool UFableSaveSubsystem::SaveIndex() const
{
	UFableProfileIndexSaveGame* SaveGame = Cast<UFableProfileIndexSaveGame>(UGameplayStatics::CreateSaveGameObject(UFableProfileIndexSaveGame::StaticClass()));
	if (SaveGame == nullptr)
	{
		return false;
	}

	SaveGame->Characters = CharacterProfiles;
	SaveGame->ActiveCharacterId = ActiveCharacterId;
	SaveGame->ActiveSlotIndex = ActiveSlotIndex;

	return UGameplayStatics::SaveGameToSlot(SaveGame, ProfileIndexSlotName, SaveUserIndex);
}

int32 UFableSaveSubsystem::FindCharacterIndex(const FGuid& CharacterId) const
{
	return CharacterProfiles.IndexOfByPredicate([&CharacterId](const FFableCharacterProfile& Profile)
	{
		return Profile.CharacterId == CharacterId;
	});
}

void UFableSaveSubsystem::EnsureCharacterSlots(FFableCharacterProfile& Profile) const
{
	if (Profile.SaveSlots.Num() == SlotsPerCharacter)
	{
		return;
	}

	Profile.SaveSlots.SetNum(SlotsPerCharacter);
	for (int32 SlotIndex = 0; SlotIndex < SlotsPerCharacter; ++SlotIndex)
	{
		Profile.SaveSlots[SlotIndex].SlotIndex = SlotIndex;
	}
}

void UFableSaveSubsystem::EnsureInventoryData(FFableCharacterProfile& Profile) const
{
	// Existing human saves keep their authored colors and proportions within the
	// previous safety bounds. New characters pass the strict policy at creation.
	Profile.RaceId = FableAppearance::NormalizeRace(Profile.RaceId);
	if (Profile.RaceId != TEXT("human"))
	{
		FableAppearance::SanitizeAppearance(Profile);
	}
	if (!Profile.BodyMorphs.Contains(TEXT("FemaleBody")))
	{
		Profile.BodyMorphs.Add(TEXT("FemaleBody"), Profile.Gender == EFableGender::Female ? 1.0f : 0.0f);
	}
	auto SanitizeColor = [](FLinearColor& Color, float Maximum)
	{
		Color = FLinearColor(
			FMath::IsFinite(Color.R) ? FMath::Clamp(Color.R,0.f,Maximum) : 1.f,
			FMath::IsFinite(Color.G) ? FMath::Clamp(Color.G,0.f,Maximum) : 1.f,
			FMath::IsFinite(Color.B) ? FMath::Clamp(Color.B,0.f,Maximum) : 1.f,1.f);
	};
	SanitizeColor(Profile.SkinColor,1.5f);
	SanitizeColor(Profile.HairColor,1.f);
	SanitizeColor(Profile.EyeColor,1.f);
	Profile.HeightScale = FMath::IsFinite(Profile.HeightScale) ? FMath::Clamp(Profile.HeightScale, 0.7f, 1.2f) : 1.0f;
	for (TPair<FName, float>& Morph : Profile.BodyMorphs)
	{
		const bool PositiveOnly = Morph.Key == TEXT("FemaleBody") || Morph.Key == TEXT("BodyFat") || Morph.Key == TEXT("Muscle") || Morph.Key == TEXT("Bust");
		Morph.Value = FMath::IsFinite(Morph.Value) ? FMath::Clamp(Morph.Value, PositiveOnly ? 0.f : -1.f, 1.f) : 0.f;
	}
	// Migrate legacy 6-slot equipment layout:
	// [Weapon, Head, Chest, Hands, Legs, Feet]
	// to new equipment layout:
	// [Main Hand, Off Hand, Head, Chest, Hands, Legs, Feet, Back, Neck, Ring 1, Ring 2, Bow]
	if (Profile.EquippedItems.Num() == 6 && EquipmentSlotsPerCharacter >= 11)
	{
		TArray<FString> MigratedEquipment;
		MigratedEquipment.SetNum(EquipmentSlotsPerCharacter);
		MigratedEquipment[0] = Profile.EquippedItems[0];
		MigratedEquipment[2] = Profile.EquippedItems[1];
		MigratedEquipment[3] = Profile.EquippedItems[2];
		MigratedEquipment[4] = Profile.EquippedItems[3];
		MigratedEquipment[5] = Profile.EquippedItems[4];
		MigratedEquipment[6] = Profile.EquippedItems[5];
		Profile.EquippedItems = MoveTemp(MigratedEquipment);
	}

	if (Profile.EquippedItems.Num() != EquipmentSlotsPerCharacter)
	{
		Profile.EquippedItems.SetNum(EquipmentSlotsPerCharacter);
	}

	if (Profile.InventorySlots.Num() != InventorySlotsPerCharacter)
	{
		Profile.InventorySlots.SetNum(InventorySlotsPerCharacter);
	}

	const bool bLegacyQuantitiesMissing = Profile.InventoryQuantities.Num() == 0;
	if (Profile.InventoryQuantities.Num() != InventorySlotsPerCharacter)
	{
		Profile.InventoryQuantities.SetNum(InventorySlotsPerCharacter);
	}
	for (int32 Index = 0; Index < Profile.InventorySlots.Num(); ++Index)
	{
		if (Profile.InventorySlots[Index].IsEmpty())
		{
			Profile.InventoryQuantities[Index] = 0;
		}
		else if (Profile.InventoryQuantities[Index] <= 0)
		{
			Profile.InventoryQuantities[Index] = 1;
		}
	}

	if (bLegacyQuantitiesMissing)
	{
		// Legacy saves represented one item per slot. Merge duplicate stackables only
		// during this migration; explicit modern slot moves remain untouched.
		for (int32 SourceIndex = 0; SourceIndex < Profile.InventorySlots.Num(); ++SourceIndex)
		{
			if (Profile.InventorySlots[SourceIndex].IsEmpty() || !IsItemStackable(Profile.InventorySlots[SourceIndex]))
			{
				continue;
			}
			for (int32 TargetIndex = 0; TargetIndex < SourceIndex; ++TargetIndex)
			{
				if (!Profile.InventorySlots[TargetIndex].Equals(Profile.InventorySlots[SourceIndex], ESearchCase::IgnoreCase))
				{
					continue;
				}
				const int32 Addable = MAX_int32 - Profile.InventoryQuantities[TargetIndex];
				const int32 Moved = FMath::Min(Profile.InventoryQuantities[SourceIndex], FMath::Max(0, Addable));
				Profile.InventoryQuantities[TargetIndex] += Moved;
				Profile.InventoryQuantities[SourceIndex] -= Moved;
				if (Profile.InventoryQuantities[SourceIndex] == 0)
				{
					Profile.InventorySlots[SourceIndex].Reset();
					break;
				}
			}
		}
	}

	Profile.HealthPercent = FMath::Clamp(Profile.HealthPercent, 0.0f, 1.0f);
	Profile.ManaPercent = FMath::Clamp(Profile.ManaPercent, 0.0f, 1.0f);
	Profile.ExperiencePercent = FMath::Clamp(Profile.ExperiencePercent, 0.0f, 1.0f);

	if (Profile.LearnedSkills.Num() == 0)
	{
		Profile.LearnedSkills.Add(BasicAttackSkillId);
	}
	EnsureStarterSkills(Profile);
}

void UFableSaveSubsystem::EnsureStarterSkills(FFableCharacterProfile& Profile) const
{
	// Add missing starter spells to legacy profiles without replacing learned or
	// discovered skills. Basic Attack remains learned for the melee path but is
	// intentionally not an assignable starter skill.
	Profile.LearnedSkills.AddUnique(BasicAttackSkillId);
	for (const FFableStarterSkillDefinition& Starter : FableSkillCatalog::GetStarterSkills())
	{
		Profile.LearnedSkills.AddUnique(Starter.SkillId);
	}
}

void UFableSaveSubsystem::EnsureActionBarsData(FFableCharacterProfile& Profile) const
{
	if (Profile.QuickWheelPages.Num() == 0)
	{
		FFableQuickWheelPageData CombatPage;
		CombatPage.PageName = TEXT("Combat");
		CombatPage.Slots.SetNum(8);
		int32 AssignedSkills = 0;
		for (const FString& SkillId : Profile.LearnedSkills)
		{
			if (!FableSkillCatalog::IsAssignableSkillId(SkillId) || AssignedSkills >= 2) continue;
			CombatPage.Slots[AssignedSkills++] = { TEXT("skill:") + SkillId, SkillId };
		}
		Profile.QuickWheelPages.Add(MoveTemp(CombatPage));
	}
	else if (Profile.LearnedSkills.Num() > 0)
	{
		bool bHasAssignedWheelEntry = false;
		for (const FFableQuickWheelPageData& Page : Profile.QuickWheelPages)
		{
			for (const FFableActionSlotData& Slot : Page.Slots)
			{
				if (!Slot.EntryId.IsEmpty())
				{
					bHasAssignedWheelEntry = true;
					break;
				}
			}
			if (bHasAssignedWheelEntry) break;
		}
		if (!bHasAssignedWheelEntry)
		{
			Profile.QuickWheelPages[0].PageName = Profile.QuickWheelPages[0].PageName.IsEmpty()
				? TEXT("Combat") : Profile.QuickWheelPages[0].PageName;
			Profile.QuickWheelPages[0].Slots.SetNum(8);
			int32 AssignedSkills = 0;
			for (const FString& SkillId : Profile.LearnedSkills)
			{
				if (!FableSkillCatalog::IsAssignableSkillId(SkillId) || AssignedSkills >= 2) continue;
				Profile.QuickWheelPages[0].Slots[AssignedSkills++] = {
					TEXT("skill:") + SkillId, SkillId };
			}
		}
	}
	for (FFableQuickWheelPageData& Page : Profile.QuickWheelPages)
	{
		Page.Slots.SetNum(8);
	}

	auto EnsureSlotCount = [](FFableActionBarData& Bar)
	{
		Bar.Columns = FMath::Max(1, Bar.Columns);
		Bar.Rows = FMath::Max(1, Bar.Rows);
		Bar.ExpandedRows = FMath::Max(Bar.Rows, Bar.ExpandedRows);
		const int32 RequiredSlots = Bar.Columns * Bar.ExpandedRows;
		if (Bar.Slots.Num() != RequiredSlots)
		{
			Bar.Slots.SetNum(RequiredSlots);
		}
	};

	bool bHasMainBar = false;
	for (FFableActionBarData& ExistingBar : Profile.ActionBars)
	{
		if (!ExistingBar.BarId.IsValid())
		{
			ExistingBar.BarId = FGuid::NewGuid();
		}

		EnsureSlotCount(ExistingBar);
		if (ExistingBar.bIsMainBar)
		{
			bHasMainBar = true;
			ExistingBar.Orientation = EFableActionBarOrientation::Horizontal;
			ExistingBar.Columns = MainActionBarColumns;
			ExistingBar.Rows = MainActionBarCollapsedRows;
			ExistingBar.ExpandedRows = MainActionBarExpandedRows;
			EnsureSlotCount(ExistingBar);
		}
	}

	if (!bHasMainBar)
	{
		FFableActionBarData MainBar;
		MainBar.BarId = FGuid::NewGuid();
		MainBar.bIsMainBar = true;
		MainBar.Orientation = EFableActionBarOrientation::Horizontal;
		MainBar.Columns = MainActionBarColumns;
		MainBar.Rows = MainActionBarCollapsedRows;
		MainBar.ExpandedRows = MainActionBarExpandedRows;
		MainBar.bExpanded = false;
		MainBar.ScreenPosition = FVector2D(420.0f, 640.0f);
		MainBar.Slots.SetNum(MainBar.Columns * MainBar.ExpandedRows);
		Profile.ActionBars.Insert(MainBar, 0);
	}
}

FString UFableSaveSubsystem::MakeSlotName(const FGuid& CharacterId, int32 SlotIndex) const
{
	return FString::Printf(TEXT("FableForge_Character_%s_Slot_%d"), *MakeGuidToken(CharacterId), SlotIndex);
}

FString UFableSaveSubsystem::MakeGuidToken(const FGuid& CharacterId) const
{
	FString GuidToken = CharacterId.ToString(EGuidFormats::DigitsWithHyphensLower);
	GuidToken.ReplaceInline(TEXT("-"), TEXT(""));
	return GuidToken;
}
