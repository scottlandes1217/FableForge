#include "RPG/Save/FableSaveSubsystem.h"

#include "FableForge.h"
#include "Engine/DataTable.h"
#include "Kismet/GameplayStatics.h"
#include "RPG/Data/FableRaceDefinitionTableRow.h"
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
	}
	Profile.LearnedSkills = { TEXT("basic_attack"), TEXT("heal_wave") };
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
	SaveGame->LearnedSkills = Profile.LearnedSkills;
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

bool UFableSaveSubsystem::SetActiveInventory(const TArray<FString>& InInventorySlots, const TArray<FString>& InEquippedSlots)
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

	Profile.HealthPercent = FMath::Clamp(Profile.HealthPercent, 0.0f, 1.0f);
	Profile.ManaPercent = FMath::Clamp(Profile.ManaPercent, 0.0f, 1.0f);
	Profile.ExperiencePercent = FMath::Clamp(Profile.ExperiencePercent, 0.0f, 1.0f);

	if (Profile.LearnedSkills.Num() == 0)
	{
		Profile.LearnedSkills = { TEXT("basic_attack"), TEXT("heal_wave") };
	}
}

void UFableSaveSubsystem::EnsureActionBarsData(FFableCharacterProfile& Profile) const
{
	if (Profile.QuickWheelPages.Num() == 0)
	{
		FFableQuickWheelPageData CombatPage;
		CombatPage.PageName = TEXT("Combat");
		CombatPage.Slots.SetNum(8);
		if (Profile.LearnedSkills.Num() > 0) CombatPage.Slots[0] = { TEXT("skill:") + Profile.LearnedSkills[0], Profile.LearnedSkills[0] };
		if (Profile.LearnedSkills.Num() > 1) CombatPage.Slots[1] = { TEXT("skill:") + Profile.LearnedSkills[1], Profile.LearnedSkills[1] };
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
			for (int32 Index = 0; Index < FMath::Min(2, Profile.LearnedSkills.Num()); ++Index)
			{
				Profile.QuickWheelPages[0].Slots[Index] = {
					TEXT("skill:") + Profile.LearnedSkills[Index], Profile.LearnedSkills[Index] };
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
