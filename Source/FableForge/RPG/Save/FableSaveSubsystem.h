#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableSaveSubsystem.generated.h"

class UFableCharacterSaveGame;
DECLARE_MULTICAST_DELEGATE_TwoParams(FFableActiveInventoryChangedSignature, const TArray<FString>&, const TArray<FString>&);

UCLASS()
class UFableSaveSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	static constexpr int32 SlotsPerCharacter = 5;
	static constexpr int32 EquipmentSlotsPerCharacter = 12;
	static constexpr int32 InventorySlotsPerCharacter = 40;

	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

	const TArray<FFableRaceDefinition>& GetRaces() const;
	const TArray<FFableCharacterProfile>& GetCharacters() const;

	bool LoadRacesFromJson(const FString& RelativePath = TEXT("Data/races.json"));

	bool HasAnyCharacters() const;
	bool HasAnySavedGames() const;
	bool CharacterHasAnySavedSlots(const FFableCharacterProfile& Profile) const;

	FGuid CreateCharacter(const FString& CharacterName, const FString& RaceId, EFableGender Gender);
	bool DeleteCharacter(const FGuid& CharacterId);

	bool SaveCharacterToSlot(const FGuid& CharacterId, int32 SlotIndex, const FString& MapName);
	UFableCharacterSaveGame* LoadCharacterFromSlot(const FGuid& CharacterId, int32 SlotIndex);

	bool TryGetCharacterProfile(const FGuid& CharacterId, FFableCharacterProfile& OutProfile) const;
	bool TryGetActiveCharacterProfile(FFableCharacterProfile& OutProfile) const;

	void GetSaveSlots(const FGuid& CharacterId, TArray<FFableSaveSlotMeta>& OutSlots) const;
	void SetCompanionsForCharacter(const FGuid& CharacterId, const TArray<FString>& CompanionNames);
	bool TryGetActiveInventory(TArray<FString>& OutInventorySlots, TArray<FString>& OutEquippedSlots) const;
	bool SetActiveInventory(const TArray<FString>& InInventorySlots, const TArray<FString>& InEquippedSlots);
	bool TryGetActiveLearnedSkills(TArray<FString>& OutLearnedSkills) const;
	bool TryGetActiveActionBars(TArray<FFableActionBarData>& OutActionBars) const;
	bool SetActiveActionBars(const TArray<FFableActionBarData>& InActionBars);

	FGuid GetActiveCharacterId() const;
	int32 GetActiveSlotIndex() const;
	const UFableCharacterSaveGame* GetLoadedGame() const;
	FFableActiveInventoryChangedSignature& OnActiveInventoryChanged();

private:
	bool LoadIndex();
	bool SaveIndex() const;

	int32 FindCharacterIndex(const FGuid& CharacterId) const;
	void EnsureCharacterSlots(FFableCharacterProfile& Profile) const;
	void EnsureInventoryData(FFableCharacterProfile& Profile) const;
	void EnsureActionBarsData(FFableCharacterProfile& Profile) const;
	FString MakeSlotName(const FGuid& CharacterId, int32 SlotIndex) const;
	FString MakeGuidToken(const FGuid& CharacterId) const;

private:
	UPROPERTY()
	TArray<FFableRaceDefinition> RaceDefinitions;

	UPROPERTY()
	TArray<FFableCharacterProfile> CharacterProfiles;

	UPROPERTY(Transient)
	TObjectPtr<UFableCharacterSaveGame> LoadedGame;

	FGuid ActiveCharacterId;
	int32 ActiveSlotIndex = INDEX_NONE;

	FFableActiveInventoryChangedSignature ActiveInventoryChanged;
};
