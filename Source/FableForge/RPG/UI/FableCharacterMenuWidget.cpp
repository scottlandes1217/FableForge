#include "RPG/UI/FableCharacterMenuWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Image.h"
#include "Components/ScrollBox.h"
#include "Components/ScrollBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/ScaleBox.h"
#include "Components/SlateWrapperTypes.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/UniformGridPanel.h"
#include "Components/UniformGridSlot.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Engine/DataTable.h"
#include "Engine/Texture2D.h"
#include "ImageUtils.h"
#include "ImageCore.h"
#include "TextureResource.h"
#include "Misc/Paths.h"
#include "FableForgePlayerController.h"
#include "FableForge.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableActionButton.h"
#include "RPG/UI/FableBookStyle.h"
#include "RPG/UI/FableBookSurface.h"
#include "RPG/UI/FableInventorySlotWidget.h"
#include "RPG/UI/FableWheelAssignmentWidget.h"
#include "RPG/UI/FableItemInspectWidget.h"
#include "RPG/UI/FableItemIconLibrary.h"
#include "Interaction/FFItemInteractable.h"
#include "GameFramework/Pawn.h"
#include "TimerManager.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "UObject/StrongObjectPtr.h"

namespace
{
	void AddJournalHint(UWidgetTree* Tree, UHorizontalBox* Row, const TCHAR* Label)
	{
		UTextBlock* Hint = Tree->ConstructWidget<UTextBlock>();
		Hint->SetText(FText::FromString(Label));
		Hint->SetFont(FableBookStyle::Font(14, true));
		Hint->SetColorAndOpacity(FLinearColor(.08f, .04f, .014f));
		if (UHorizontalBoxSlot* Slot = Row->AddChildToHorizontalBox(Hint))
		{
			Slot->SetVerticalAlignment(VAlign_Center);
			Slot->SetPadding(FMargin(6.f, 0.f));
		}
	}
	// Runtime PNG imports have only one mip. Build alpha-aware, linear-light
	// reductions so fine engraving remains stable when drawn at small UI sizes.
	UTexture2D* LoadEquipmentIcon(const FString& Filename)
	{
		FImage Source;
		if (!FImageUtils::LoadImage(*Filename, Source)) return nullptr;
		Source.ChangeFormat(ERawImageFormat::RGBA32F, EGammaSpace::Linear);
		int32 Width = Source.SizeX, Height = Source.SizeY;
		UTexture2D* Texture = UTexture2D::CreateTransient(Width, Height, PF_B8G8R8A8);
		if (!Texture) return nullptr;
		Texture->SRGB = true;
		Texture->NeverStream = true;
		Texture->LODGroup = TEXTUREGROUP_UI;
		Texture->Filter = TF_Trilinear;
		Texture->AddressX = TA_Clamp;
		Texture->AddressY = TA_Clamp;
		TArray<FLinearColor> Pixels;
		Pixels.Append(reinterpret_cast<const FLinearColor*>(Source.RawData.GetData()), Width * Height);
		FTexturePlatformData* Platform = Texture->GetPlatformData();
		int32 Level = 0;
		for (;;)
		{
			if (Level > 0) Platform->Mips.Add(new FTexture2DMipMap());
			FTexture2DMipMap& Mip = Platform->Mips[Level++];
			Mip.SizeX = Width; Mip.SizeY = Height; Mip.SizeZ = 1;
			Mip.BulkData.Lock(LOCK_READ_WRITE);
			FColor* Output = reinterpret_cast<FColor*>(Mip.BulkData.Realloc(int64(Width) * Height * sizeof(FColor)));
			for (int32 I = 0; I < Pixels.Num(); ++I) Output[I] = Pixels[I].ToFColorSRGB();
			Mip.BulkData.Unlock();
			if (Width == 1 && Height == 1) break;
			const int32 NextWidth = FMath::Max(1, Width / 2), NextHeight = FMath::Max(1, Height / 2);
			TArray<FLinearColor> Next;
			Next.SetNumUninitialized(NextWidth * NextHeight);
			for (int32 Y = 0; Y < NextHeight; ++Y)
			for (int32 X = 0; X < NextWidth; ++X)
			{
				FLinearColor Sum(0, 0, 0, 0);
				int32 Samples = 0;
				for (int32 SY = Y * Height / NextHeight; SY < (Y + 1) * Height / NextHeight; ++SY)
				for (int32 SX = X * Width / NextWidth; SX < (X + 1) * Width / NextWidth; ++SX)
				{
					const FLinearColor& P = Pixels[SY * Width + SX];
					Sum.R += P.R * P.A; Sum.G += P.G * P.A; Sum.B += P.B * P.A;
					Sum.A += P.A; ++Samples;
				}
				Next[Y * NextWidth + X] = Sum.A > SMALL_NUMBER
					? FLinearColor(Sum.R / Sum.A, Sum.G / Sum.A, Sum.B / Sum.A, Sum.A / Samples)
					: FLinearColor::Transparent;
			}
			Pixels = MoveTemp(Next); Width = NextWidth; Height = NextHeight;
		}
		Texture->UpdateResource();
		UE_LOG(LogFableForge, Display, TEXT("Equipment icon filtered: %s (%d mips)"), *Filename, Level);
		return Texture;
	}

	UTexture2D* JournalArt(const FString& Name)
	{
		static TMap<FString, TStrongObjectPtr<UTexture2D>> Cache;
		if (const auto* Found = Cache.Find(Name)) return Found->Get();
		UTexture2D* Texture = LoadEquipmentIcon(FPaths::ProjectContentDir() / TEXT("Slate/Textures/Journal") / (Name + TEXT(".png")));
		if (Texture) Cache.Add(Name, TStrongObjectPtr<UTexture2D>(Texture));
		return Texture;
	}

	void StyleJournalTab(UButton* Button, bool bSelected, bool bPrimary)
	{
		FSlateBrush Brush;
		if (bPrimary && JournalArt(TEXT("TabPaper")))
		{
			Brush.SetResourceObject(JournalArt(TEXT("TabPaper")));
			Brush.ImageSize = FVector2D(180.f, 60.f);
			Brush.TintColor = bSelected ? FLinearColor(.92f, .68f, .35f) : FLinearColor::White;
		}
		else Brush = FSlateRoundedBoxBrush(bSelected ? FLinearColor(.44f, .25f, .08f, .16f) : FLinearColor::Transparent, 2.f,
			bSelected ? FLinearColor(.30f, .15f, .04f, .6f) : FLinearColor::Transparent, 1.f);
		FButtonStyle Style;
		Style.SetNormal(Brush);
		Brush.TintColor = FLinearColor(1.1f, 1.04f, .92f); Style.SetHovered(Brush);
		Brush.TintColor = FLinearColor(.82f, .73f, .58f); Style.SetPressed(Brush);
		Style.SetNormalPadding(FMargin(0.f)); Style.SetPressedPadding(FMargin(0.f));
		Button->SetStyle(Style); Button->SetBackgroundColor(FLinearColor::White);
	}

	FSlateFontInfo JournalBookmarkFont(int32 Size)
	{
		// The packaged game owns this copy; the root integration task supplies it
		// under Content/Slate/Fonts rather than reaching into Editor content.
		const FString FontPath = FPaths::ProjectContentDir() / TEXT("Slate/Fonts/FontAwesome.ttf");
		return FPaths::FileExists(FontPath)
			? FSlateFontInfo(FontPath, Size)
			: FSlateFontInfo();
	}

	void StyleJournalBookmark(UButton* Button, bool bSelected, const FLinearColor& LeatherColor)
	{
		const FLinearColor BorderColor = bSelected ? FLinearColor(.83f, .61f, .25f, 1.f) : FLinearColor(.30f, .19f, .08f, .85f);
		const FLinearColor FillColor = bSelected
			? FLinearColor(FMath::Min(LeatherColor.R * 1.18f, 1.f), FMath::Min(LeatherColor.G * 1.18f, 1.f), FMath::Min(LeatherColor.B * 1.18f, 1.f), 1.f)
			: LeatherColor;
		FButtonStyle Style;
		Style.SetNormal(FSlateRoundedBoxBrush(FillColor, 9.f, BorderColor, bSelected ? 2.f : 1.f));
		Style.SetHovered(FSlateRoundedBoxBrush(FLinearColor(FillColor.R * 1.12f, FillColor.G * 1.12f, FillColor.B * 1.12f, 1.f), 9.f, FLinearColor(.92f, .73f, .38f, 1.f), 2.f));
		Style.SetPressed(FSlateRoundedBoxBrush(FLinearColor(FillColor.R * .88f, FillColor.G * .88f, FillColor.B * .88f, 1.f), 9.f, BorderColor, 2.f));
		Style.SetNormalPadding(FMargin(0.f));
		Style.SetPressedPadding(FMargin(0.f));
		Button->SetStyle(Style);
		Button->SetBackgroundColor(FLinearColor::White);
	}

	void AddBookmarkHint(UWidgetTree* Tree, UVerticalBox* Stack, const TCHAR* Label)
	{
		UTextBlock* Hint = Tree->ConstructWidget<UTextBlock>();
		Hint->SetText(FText::FromString(Label));
		Hint->SetFont(FableBookStyle::Font(11, true));
		Hint->SetColorAndOpacity(FLinearColor(.88f, .76f, .51f, 1.f));
		Hint->SetJustification(ETextJustify::Center);
		if (UVerticalBoxSlot* Slot = Stack->AddChildToVerticalBox(Hint))
		{
			Slot->SetHorizontalAlignment(HAlign_Center);
			Slot->SetPadding(FMargin(0.f, 3.f));
		}
	}

	FLinearColor JournalBookmarkLeather(FName ActionId)
	{
		if (ActionId == TEXT("tab_inventory")) return FLinearColor(.57f, .36f, .12f, 1.f);
		if (ActionId == TEXT("tab_skills")) return FLinearColor(.10f, .40f, .39f, 1.f);
		if (ActionId == TEXT("tab_companions")) return FLinearColor(.42f, .12f, .16f, 1.f);
		if (ActionId == TEXT("tab_build")) return FLinearColor(.17f, .28f, .49f, 1.f);
		return FLinearColor(.31f, .19f, .43f, 1.f);
	}

	const FName InventoryAction = TEXT("tab_inventory");
	const FName SkillsAction = TEXT("tab_skills");
	const FName CompanionsAction = TEXT("tab_companions");
	const FName BuildAction = TEXT("tab_build");
	const FName SettingsAction = TEXT("tab_settings");
	const FName CloseMenuAction = TEXT("close_menu");
	const FName CancelSkillContextAction = TEXT("cancel_skill_context");

	const FName CategoryWeaponsAction = TEXT("cat_weapons");
	const FName CategoryArmorAction = TEXT("cat_armor");
	const FName CategoryConsumablesAction = TEXT("cat_consumables");
	const FName CategoryMiscAction = TEXT("cat_misc");
	const FName CategoryKeyItemsAction = TEXT("cat_key_items");
	const FName CategoryAllAction = TEXT("cat_all");
	const FName SkillCategoryAllAction = TEXT("skillcat_all");
	static const TCHAR* SkillSelectActionPrefix = TEXT("skillselect_");
	static const TCHAR* SkillCategoryActionPrefix = TEXT("skillcat_");
	static const TCHAR* AssignSkillActionPrefix = TEXT("assign_skill_");

	const FLinearColor CharacterMenuUiPanelColor = FLinearColor::Transparent;
	const FLinearColor UiSectionColor(0.50f, 0.33f, 0.13f, 0.065f);
	const FLinearColor CharacterMenuUiButtonColor(0.93f, 0.82f, 0.62f, 1.0f);
	const FLinearColor CharacterMenuUiButtonSelectedColor(0.73f, 0.49f, 0.25f, 1.0f);
	const FLinearColor CharacterMenuUiTextColor(0.12f, 0.060f, 0.027f, 1.0f);
	const FLinearColor CharacterMenuUiMutedTextColor(0.29f, 0.17f, 0.085f, 1.0f);
	const TArray<FString> EquipmentSlotNames = {
		TEXT("Main Hand"),
		TEXT("Off Hand"),
		TEXT("Head"),
		TEXT("Chest"),
		TEXT("Hands"),
		TEXT("Legs"),
		TEXT("Feet"),
		TEXT("Back"),
		TEXT("Neck"),
		TEXT("Ring 1"),
		TEXT("Ring 2"),
		TEXT("Bow")
	};

	struct FEquipmentLayoutCell
	{
		int32 LogicalIndex;
		const TCHAR* IconName;
		float SlotX, SlotY, SlotSize;
	};

	const TArray<FEquipmentLayoutCell> EquipmentLayout = {
		// Each slot owns an independent illustration; rings share their icon only.
		{2, TEXT("Head"), 136, 0, 68},
		{7, TEXT("Back"), 40, 80, 68},
		{8, TEXT("Neck"), 136, 80, 68},
		{11, TEXT("Bow"), 232, 80, 68},
		{1, TEXT("OffHand"), 40, 160, 68},
		{3, TEXT("Chest"), 136, 160, 68},
		{0, TEXT("MainHand"), 232, 160, 68},
		{4, TEXT("Hands"), 40, 240, 68},
		{9, TEXT("Ring"), 222, 254, 40},
		{10, TEXT("Ring"), 270, 254, 40},
		{5, TEXT("Legs"), 136, 240, 68},
		{6, TEXT("Feet"), 136, 320, 68}
	};

	static const TCHAR* ItemsDataTablePath = TEXT("/Game/Data/DT_Items.DT_Items");
	static const TCHAR* WeaponsDataTablePath = TEXT("/Game/Data/DT_Weapons.DT_Weapons");
	static const TCHAR* ArmorDataTablePath = TEXT("/Game/Data/DT_Armor.DT_Armor");
	static const TCHAR* CharacterMenuSkillsDataTablePath = TEXT("/Game/Data/DT_Skills.DT_Skills");

	FName CategoryFromType(const FString& InType)
	{
		const FString Type = InType.ToLower();
		if (Type == TEXT("weapon"))
		{
			return CategoryWeaponsAction;
		}

		if (Type == TEXT("armor"))
		{
			return CategoryArmorAction;
		}

		if (Type == TEXT("consumable") || Type == TEXT("befriending"))
		{
			return CategoryConsumablesAction;
		}

		if (Type == TEXT("key") || Type == TEXT("keyitem") || Type == TEXT("key_item") || Type == TEXT("quest"))
		{
			return CategoryKeyItemsAction;
		}

		return CategoryMiscAction;
	}

	FString BuildIconToken(const FString& InName)
	{
		FString Compact = InName;
		Compact.ReplaceInline(TEXT("_"), TEXT(" "));
		TArray<FString> Words;
		Compact.ParseIntoArray(Words, TEXT(" "), true);

		FString Token;
		for (const FString& Word : Words)
		{
			if (Word.IsEmpty())
			{
				continue;
			}

			Token += Word.Left(1).ToUpper();
			if (Token.Len() >= 2)
			{
				return Token.Left(2);
			}
		}

		if (Token.Len() == 1)
		{
			return Token + TEXT("?");
		}

		return TEXT("??");
	}

	int32 ArmorSlotIndexFromString(const FString& InSlotName)
	{
		const FString Slot = InSlotName.ToLower();
		if (Slot == TEXT("offhand") || Slot == TEXT("off_hand") || Slot == TEXT("shield"))
		{
			return 1;
		}

		if (Slot == TEXT("head"))
		{
			return 2;
		}

		if (Slot == TEXT("chest"))
		{
			return 3;
		}

		if (Slot == TEXT("hands") || Slot == TEXT("arms"))
		{
			return 4;
		}

		if (Slot == TEXT("legs"))
		{
			return 5;
		}

		if (Slot == TEXT("feet"))
		{
			return 6;
		}

		if (Slot == TEXT("back"))
		{
			return 7;
		}

		if (Slot == TEXT("neck") || Slot == TEXT("amulet"))
		{
			return 8;
		}

		if (Slot == TEXT("ring"))
		{
			return 9;
		}

		if (Slot == TEXT("bow"))
		{
			return 11;
		}

		return INDEX_NONE;
	}

	FString CategoryDisplayName(FName Category)
	{
		if (Category == CategoryAllAction)
		{
			return TEXT("All");
		}

		if (Category == CategoryWeaponsAction)
		{
			return TEXT("Weapons");
		}

		if (Category == CategoryArmorAction)
		{
			return TEXT("Armor");
		}

		if (Category == CategoryConsumablesAction)
		{
			return TEXT("Consumables");
		}

		if (Category == CategoryKeyItemsAction)
		{
			return TEXT("Key Items");
		}

		return TEXT("Misc");
	}

	bool IsRingEquipmentSlotIndex(const int32 SlotIndex)
	{
		return SlotIndex == 9 || SlotIndex == 10;
	}

	TArray<FString> ParseDelimitedList(const FString& Source)
	{
		TArray<FString> Result;
		if (Source.IsEmpty())
		{
			return Result;
		}

		FString Normalized = Source;
		Normalized.ReplaceInline(TEXT(";"), TEXT("|"));
		if (!Normalized.Contains(TEXT("|")) && Normalized.Contains(TEXT(",")))
		{
			Normalized.ParseIntoArray(Result, TEXT(","), true);
		}
		else
		{
			Normalized.ParseIntoArray(Result, TEXT("|"), true);
		}

		for (FString& Entry : Result)
		{
			Entry = Entry.TrimStartAndEnd();
		}
		Result.RemoveAll([](const FString& Value) { return Value.IsEmpty(); });
		return Result;
	}

	FString HumanizeToken(const FString& Source)
	{
		if (Source.IsEmpty())
		{
			return FString();
		}

		FString Out = Source;
		Out.ReplaceInline(TEXT("_"), TEXT(" "));
		Out.ReplaceInline(TEXT("."), TEXT(" "));
		Out.ReplaceInline(TEXT(":"), TEXT(" "));
		if (!Out.IsEmpty())
		{
			Out[0] = FChar::ToUpper(Out[0]);
		}
		return Out;
	}

	FString JoinHumanizedList(const FString& Source)
	{
		const TArray<FString> Parts = ParseDelimitedList(Source);
		TArray<FString> Humanized;
		Humanized.Reserve(Parts.Num());
		for (const FString& Part : Parts)
		{
			Humanized.Add(HumanizeToken(Part));
		}
		return FString::Join(Humanized, TEXT(", "));
	}

	FString EnumToString(EFableSkillType Value)
	{
		switch (Value)
		{
		case EFableSkillType::Active: return TEXT("Active");
		case EFableSkillType::Passive: return TEXT("Passive");
		case EFableSkillType::Triggered: return TEXT("Triggered");
		default: return TEXT("Unknown");
		}
	}

	FString EnumToString(EFableSkillResourceType Value)
	{
		switch (Value)
		{
		case EFableSkillResourceType::Mana: return TEXT("Mana");
		case EFableSkillResourceType::Stamina: return TEXT("Stamina");
		case EFableSkillResourceType::Energy: return TEXT("Energy");
		case EFableSkillResourceType::Rage: return TEXT("Rage");
		case EFableSkillResourceType::None:
		default:
			return TEXT("None");
		}
	}

	FString EnumToString(EFableSkillTargetingMode Value)
	{
		switch (Value)
		{
		case EFableSkillTargetingMode::Self: return TEXT("Self");
		case EFableSkillTargetingMode::TargetUnit: return TEXT("Target Unit");
		case EFableSkillTargetingMode::Ground: return TEXT("Ground");
		case EFableSkillTargetingMode::Object: return TEXT("Object");
		case EFableSkillTargetingMode::Weapon: return TEXT("Weapon");
		case EFableSkillTargetingMode::Equipment: return TEXT("Equipment");
		case EFableSkillTargetingMode::Area: return TEXT("Area");
		default: return TEXT("Unknown");
		}
	}

	FString EnumToString(EFableSkillCategory Value)
	{
		switch (Value)
		{
		case EFableSkillCategory::Basic: return TEXT("Basic");
		case EFableSkillCategory::Light: return TEXT("Light");
		case EFableSkillCategory::Elemental: return TEXT("Elemental");
		case EFableSkillCategory::Arcane: return TEXT("Arcane");
		case EFableSkillCategory::Sword: return TEXT("Sword");
		case EFableSkillCategory::Shield: return TEXT("Shield");
		case EFableSkillCategory::Support: return TEXT("Support");
		case EFableSkillCategory::Movement: return TEXT("Movement");
		case EFableSkillCategory::Utility: return TEXT("Utility");
		case EFableSkillCategory::Fire: return TEXT("Fire");
		case EFableSkillCategory::Water: return TEXT("Water");
		case EFableSkillCategory::Earth: return TEXT("Earth");
		case EFableSkillCategory::Air: return TEXT("Air");
		case EFableSkillCategory::TimeManipulation: return TEXT("Cosmic");
		default: return TEXT("Unknown");
		}
	}

	FName SkillCategoryActionFromEnum(EFableSkillCategory Category)
	{
		return *FString::Printf(TEXT("%s%s"), SkillCategoryActionPrefix, *EnumToString(Category).ToLower().Replace(TEXT(" "), TEXT("_")));
	}

	UTexture2D* SkillSchoolArt(EFableSkillCategory Category)
	{
		return JournalArt(Category == EFableSkillCategory::TimeManipulation ? TEXT("Time") : EnumToString(Category));
	}

	struct FSkillGestureHint
	{
		FString DPadInstruction;
		FString Instruction;
		bool bCircular = false;
	};

	bool TryGetSkillGestureHint(const FString& SkillId, FSkillGestureHint& OutHint)
	{
		if (SkillId.Equals(TEXT("fire_tornado"), ESearchCase::IgnoreCase))
		{
			OutHint.DPadInstruction = TEXT("Hold D-pad Right (Fire)");
			OutHint.Instruction = TEXT("Rotate the Right Stick in a full circle while held out; release is not needed.");
			OutHint.bCircular = true;
			return true;
		}

		if (SkillId.Equals(TEXT("fireball"), ESearchCase::IgnoreCase))
		{
			OutHint.DPadInstruction = TEXT("Hold D-pad Right (Fire)");
			OutHint.Instruction = TEXT("Flick the Right Stick outward, then return it to center; release is not needed.");
			return true;
		}

		if (SkillId.Equals(TEXT("heal_wave"), ESearchCase::IgnoreCase))
		{
			OutHint.DPadInstruction = TEXT("Hold D-pad Left (Water)");
			OutHint.Instruction = TEXT("Flick the Right Stick outward, then return it to center; release is not needed.");
			return true;
		}

		if (SkillId.Equals(TEXT("stone_spike"), ESearchCase::IgnoreCase))
		{
			OutHint.DPadInstruction = TEXT("Hold D-pad Down (Earth)");
			OutHint.Instruction = TEXT("Flick the Right Stick outward, then return it to center; release is not needed.");
			return true;
		}

		if (SkillId.Equals(TEXT("gust"), ESearchCase::IgnoreCase))
		{
			OutHint.DPadInstruction = TEXT("Hold D-pad Up (Air)");
			OutHint.Instruction = TEXT("Flick the Right Stick outward, then return it to center; release is not needed.");
			return true;
		}

		return false;
	}

	bool TryParseSkillCategoryAction(FName ActionId, FName& OutCategoryAction)
	{
		const FString ActionString = ActionId.ToString();
		if (!ActionString.StartsWith(SkillCategoryActionPrefix))
		{
			return false;
		}

		OutCategoryAction = ActionId;
		return true;
	}
}

TSharedRef<SWidget> UFableCharacterMenuWidget::RebuildWidget()
{
	Rebuild();
	return Super::RebuildWidget();
}

void UFableCharacterMenuWidget::NativeConstruct()
{
	Super::NativeConstruct();
	SetIsFocusable(true);
	Close();
}

void UFableCharacterMenuWidget::Open()
{
	SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	bInventoryLoaded = false;

	if (WidgetTree == nullptr || WidgetTree->RootWidget == nullptr || ContentRoot == nullptr)
	{
		Rebuild();
		return;
	}

	LoadInventoryFromSave();
	LoadItemDefinitionsFromUnityJson();
	if (ActiveTab == TEXT("inventory") && InventoryCells.Num()>0) RefreshInventoryPresentation();
	else RebuildTabContent();
}

void UFableCharacterMenuWidget::Close()
{
	CloseItemActions();
	if (ItemInspect) ItemInspect->Close();
	bSkillContextVisible = false;
	ContextSkillId.Reset();
	ControllerPickedSlot = NAME_None;
	bControllerSelectionVisible = false;
	SetVisibility(ESlateVisibility::Collapsed);
}

FReply UFableCharacterMenuWidget::NativeOnPreviewKeyDown(const FGeometry& Geometry, const FKeyEvent& Event)
{
	if (!IsOpen() || EmbeddedQuickWheel) return Super::NativeOnPreviewKeyDown(Geometry, Event);
	const FKey Key = Event.GetKey();
	if (ItemInspect && ItemInspect->IsOpen()) return Super::NativeOnPreviewKeyDown(Geometry, Event);
	if (ItemActionsLayer)
	{
		if (Key == EKeys::Gamepad_DPad_Up || Key == EKeys::Up) { ItemActionSelection = FMath::Max(0, ItemActionSelection-1); RefreshItemActionSelection(); }
		else if (Key == EKeys::Gamepad_DPad_Down || Key == EKeys::Down) { ItemActionSelection = FMath::Min(ItemActionIds.Num()-1, ItemActionSelection+1); RefreshItemActionSelection(); }
		else if ((Key == EKeys::Gamepad_FaceButton_Bottom || Key == EKeys::Enter) && !Event.IsRepeat()) { if (ItemActionIds.IsValidIndex(ItemActionSelection)) HandleActionClicked(ItemActionIds[ItemActionSelection]); }
		else if (Key == EKeys::Gamepad_FaceButton_Right || Key == EKeys::Escape) CloseItemActions();
		return FReply::Handled();
	}
	if (Key == EKeys::Gamepad_FaceButton_Left) { if (!Event.IsRepeat()) InspectSelectedItem(); return FReply::Handled(); }
	if (Key == EKeys::Gamepad_DPad_Left) MoveControllerSelection(-1, 0);
	else if (Key == EKeys::Gamepad_DPad_Right) MoveControllerSelection(1, 0);
	else if (Key == EKeys::Gamepad_DPad_Up) MoveControllerSelection(0, -1);
	else if (Key == EKeys::Gamepad_DPad_Down) MoveControllerSelection(0, 1);
	else if (Key == EKeys::Gamepad_LeftShoulder) { if (!Event.IsRepeat()) CycleCategoryTab(-1); }
	else if (Key == EKeys::Gamepad_RightShoulder) { if (!Event.IsRepeat()) CycleCategoryTab(1); }
	else if (Key == EKeys::Gamepad_FaceButton_Bottom) { if (!Event.IsRepeat()) ActivateControllerSelection(); }
	else if (Key == EKeys::Gamepad_FaceButton_Right || Key == EKeys::Escape) { if (!Event.IsRepeat()) HandleControllerCancel(); }
	else return Super::NativeOnPreviewKeyDown(Geometry, Event);
	return FReply::Handled();
}

void UFableCharacterMenuWidget::CycleMainTab(int32 Direction)
{
	if (!IsOpen() || EmbeddedQuickWheel || HasItemModal()) return;
	const TArray<FName> Tabs = {InventoryAction, SkillsAction, CompanionsAction, BuildAction, SettingsAction};
	const FName Current(*FString::Printf(TEXT("tab_%s"), *ActiveTab.ToString()));
	const int32 Index = FMath::Max(0, Tabs.IndexOfByKey(Current));
	ControllerPickedSlot = NAME_None;
	bControllerSelectionVisible = true;
	HandleActionClicked(Tabs[(Index + Direction + Tabs.Num()) % Tabs.Num()]);
	UE_LOG(LogFableForge, Display, TEXT("JOURNAL main_tab=%s"), *ActiveTab.ToString());
}

void UFableCharacterMenuWidget::CycleCategoryTab(int32 Direction)
{
	if (!IsOpen() || EmbeddedQuickWheel || HasItemModal()) return;
	if (bSkillContextVisible) HandleActionClicked(CancelSkillContextAction);
	const TArray<FName> Categories = ActiveTab == TEXT("inventory")
		? TArray<FName>{CategoryAllAction, CategoryArmorAction, CategoryWeaponsAction, CategoryConsumablesAction, CategoryMiscAction, CategoryKeyItemsAction}
		: (ActiveTab == TEXT("skills") ? OrderedSkillCategories : TArray<FName>());
	if (Categories.IsEmpty()) return;
	const int32 Index = FMath::Max(0, Categories.IndexOfByKey(ActiveTab == TEXT("inventory") ? ActiveInventoryCategory : ActiveSkillCategory));
	ControllerPickedSlot = NAME_None;
	ControllerSlotId = NAME_None;
	bControllerSelectionVisible = true;
	HandleActionClicked(Categories[(Index + Direction + Categories.Num()) % Categories.Num()]);
	RefreshControllerSelection();
	UE_LOG(LogFableForge, Display, TEXT("JOURNAL category=%s"), *(ActiveTab == TEXT("inventory") ? ActiveInventoryCategory : ActiveSkillCategory).ToString());
}

void UFableCharacterMenuWidget::HandleControllerCancel()
{
	if (!IsOpen() || EmbeddedQuickWheel) return;
	if (ItemInspect && ItemInspect->IsOpen()) { ItemInspect->Close(); return; }
	if (ItemActionsLayer) { CloseItemActions(); return; }
	if (ActiveTab == TEXT("settings") && !SettingsPage.IsNone())
	{
		SettingsPage = NAME_None; SettingsSelection = 0; SettingsStatus.Reset();
		QueueTabContentRebuild(); return;
	}
	if (!ControllerPickedSlot.IsNone())
	{
		ControllerPickedSlot = NAME_None;
		RefreshControllerSelection();
		return;
	}
	if (bSkillContextVisible)
	{
		HandleActionClicked(CancelSkillContextAction);
		return;
	}
	HandleActionClicked(CloseMenuAction);
}

void UFableCharacterMenuWidget::RefreshControllerSelection()
{
	if (ActiveTab != TEXT("inventory")) return;
	bool bEquip = false; int32 Index = INDEX_NONE;
	if (!ResolveSlotAddress(ControllerSlotId, bEquip, Index) || (!bEquip && !ControllerVisibleInventory.Contains(Index)))
		ControllerSlotId = ControllerVisibleInventory.IsEmpty() ? FName(TEXT("equip_2"))
			: FName(*FString::Printf(TEXT("inv_%d"), ControllerVisibleInventory[0]));
	for (const auto& Entry : SlotWidgets)
		if (Entry.Value) Entry.Value->SetControllerSelection(bControllerSelectionVisible && Entry.Key == ControllerSlotId, Entry.Key == ControllerPickedSlot);
}

void UFableCharacterMenuWidget::MoveControllerSelection(int32 X, int32 Y)
{
	if (!IsOpen() || EmbeddedQuickWheel || HasItemModal()) return;
	if (bSkillContextVisible) HandleActionClicked(CancelSkillContextAction);
	bControllerSelectionVisible = true;
	if (ActiveTab == TEXT("settings"))
	{
		SettingsSelection = FMath::Clamp(SettingsSelection + (Y != 0 ? Y : X), 0, FMath::Max(0, SettingsActions.Num()-1));
		RefreshSettingsSelection(); return;
	}
	if (ActiveTab == TEXT("skills"))
	{
		TArray<FString> Visible;
		for (const FString& Id : DisplayedSkillOrder)
			if (SkillRows.FindRef(Id) && SkillRows[Id]->GetVisibility() != ESlateVisibility::Collapsed) Visible.Add(Id);
		if (Visible.IsEmpty()) return;
		const int32 Current = FMath::Max(0, Visible.IndexOfByKey(ActiveSkillDetailsId));
		ActiveSkillDetailsId = Visible[FMath::Clamp(Current + (Y != 0 ? Y : X), 0, Visible.Num() - 1)];
		UE_LOG(LogFableForge, Display, TEXT("SKILL_NAV selected=%s visible=%d details=%s"), *ActiveSkillDetailsId, Visible.Num(), *GetNameSafe(SkillDetailsContent));
		RefreshSkillsPresentation();
		if (SkillsScroll) SkillsScroll->ScrollWidgetIntoView(SkillRows.FindRef(ActiveSkillDetailsId), false);
		return;
	}
	if (ActiveTab != TEXT("inventory")) return;
	RefreshControllerSelection();
	TMap<FName, FVector2D> Positions;
	for (int32 I = 0; I < ControllerVisibleInventory.Num(); ++I)
		Positions.Add(FName(*FString::Printf(TEXT("inv_%d"), ControllerVisibleInventory[I])), FVector2D((I % 5) * 88 + 44, (I / 5) * 88 + 44));
	for (const auto& Cell : EquipmentLayout)
		Positions.Add(FName(*FString::Printf(TEXT("equip_%d"), Cell.LogicalIndex)), FVector2D(718 + Cell.SlotX + Cell.SlotSize / 2, Cell.SlotY + Cell.SlotSize / 2));
	const FVector2D Origin = Positions.FindRef(ControllerSlotId);
	float Best = TNumericLimits<float>::Max();
	FName Next = ControllerSlotId;
	for (const auto& Entry : Positions)
	{
		const FVector2D Delta = Entry.Value - Origin;
		const float Along = X != 0 ? Delta.X * X : Delta.Y * Y;
		const float Across = FMath::Abs(X != 0 ? Delta.Y : Delta.X);
		if (Along <= 1.f) continue;
		const float Score = Along + Across * 5.f;
		if (Score < Best) { Best = Score; Next = Entry.Key; }
	}
	ControllerSlotId = Next;
	RefreshControllerSelection();
	if (InventoryScroll && ControllerSlotId.ToString().StartsWith(TEXT("inv_")))
		InventoryScroll->ScrollWidgetIntoView(SlotWidgets.FindRef(ControllerSlotId), false);
	UE_LOG(LogFableForge, Display, TEXT("JOURNAL selected=%s"), *ControllerSlotId.ToString());
}

void UFableCharacterMenuWidget::ActivateControllerSelection()
{
	if (!IsOpen() || EmbeddedQuickWheel || HasItemModal()) return;
	if (ActiveTab == TEXT("settings"))
	{
		if (SettingsActions.IsValidIndex(SettingsSelection)) HandleActionClicked(SettingsActions[SettingsSelection]);
		return;
	}
	bControllerSelectionVisible = true;
	if (ActiveTab == TEXT("skills"))
	{
		if (!ActiveSkillDetailsId.IsEmpty())
			HandleActionClicked(FName(*FString::Printf(TEXT("%s%s"), AssignSkillActionPrefix, *ActiveSkillDetailsId)));
		return;
	}
	if (ActiveTab != TEXT("inventory")) return;
	RefreshControllerSelection();
	if (ControllerPickedSlot.IsNone())
	{
		OpenItemActions();
	}
	else
	{
		bool bFromEquip, bToEquip; int32 From, To;
		if (ResolveSlotAddress(ControllerPickedSlot, bFromEquip, From) && ResolveSlotAddress(ControllerSlotId, bToEquip, To))
		{
			if (!(bFromEquip ? EquippedSlots : InventorySlots).IsValidIndex(From)
				|| !(bToEquip ? EquippedSlots : InventorySlots).IsValidIndex(To)) return;
			const FString Source = (bFromEquip ? EquippedSlots : InventorySlots)[From];
			const FString Target = (bToEquip ? EquippedSlots : InventorySlots)[To];
			const bool bAllowed = (!bToEquip || IsItemAllowedInEquipmentSlot(Source, To))
				&& (!bFromEquip || Target.IsEmpty() || IsItemAllowedInEquipmentSlot(Target, From));
			HandleInventorySlotDropped(ControllerPickedSlot, ControllerSlotId, Source, FString());
			if (bAllowed) ControllerPickedSlot = NAME_None;
			else if (InventoryStatus)
			{
				InventoryStatus->SetText(FText::FromString(TEXT("That item cannot be equipped in this slot.")));
				InventoryStatus->SetVisibility(ESlateVisibility::HitTestInvisible);
			}
		}
	}
	RefreshControllerSelection();
}

bool UFableCharacterMenuWidget::HasItemModal() const
{
	return ItemActionsLayer || (ItemInspect && ItemInspect->IsOpen());
}

FString UFableCharacterMenuWidget::SelectedInventoryItem(bool& bEquipment, int32& Index) const
{
	if (!ResolveSlotAddress(ControllerSlotId, bEquipment, Index)) return FString();
	const auto& Slots = bEquipment ? EquippedSlots : InventorySlots;
	return Slots.IsValidIndex(Index) ? Slots[Index] : FString();
}

void UFableCharacterMenuWidget::RestoreJournalFocus()
{
	if (IsOpen() && GetOwningPlayer()) SetUserFocus(GetOwningPlayer());
}

void UFableCharacterMenuWidget::HandleInventorySlotHovered(FName SlotId, const FString& PayloadId)
{
	if (!HasItemModal() && ControllerPickedSlot.IsNone()) ControllerSlotId = SlotId;
}

void UFableCharacterMenuWidget::HandleInventorySlotContext(FName SlotId, const FString& PayloadId)
{
	if (HasItemModal() || !ControllerPickedSlot.IsNone()) return;
	ControllerSlotId = SlotId; bControllerSelectionVisible = true; OpenItemActions();
}

void UFableCharacterMenuWidget::InspectSelectedItem()
{
	if (ActiveTab != TEXT("inventory") || HasItemModal()) return;
	RefreshControllerSelection();
	bool bEquipment = false; int32 Index = INDEX_NONE;
	const FString ItemId = SelectedInventoryItem(bEquipment, Index);
	if (ItemId.IsEmpty()) return;
	const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId);
	TArray<TPair<FString, FString>> Details;
	FString Type = ResolveItemCategory(ItemId).ToString(); Type.RemoveFromStart(TEXT("cat_"));
	Details.Emplace(TEXT("Type"), HumanizeToken(Type));
	Details.Emplace(TEXT("Location"), bEquipment && EquipmentSlotNames.IsValidIndex(Index) ? EquipmentSlotNames[Index] : TEXT("Backpack"));
	Details.Emplace(TEXT("Quantity"), FString::FromInt(!bEquipment && InventoryQuantities.IsValidIndex(Index) ? InventoryQuantities[Index] : 1));
	if (Definition)
	{
		Details.Emplace(TEXT("Stackable"), Definition->bStackable ? TEXT("Yes") : TEXT("No"));
		Details.Emplace(TEXT("Equipable"), Definition->bEquipable ? TEXT("Yes") : TEXT("No"));
		if (EquipmentSlotNames.IsValidIndex(Definition->EquipmentSlot)) Details.Emplace(TEXT("Equipment slot"), EquipmentSlotNames[Definition->EquipmentSlot]);
	}
	if (ItemId == TEXT("health_potion")) Details.Emplace(TEXT("Use"), TEXT("Drink to restore 25% of maximum health."));
	else if (ItemId == TEXT("mana_potion")) Details.Emplace(TEXT("Use"), TEXT("Drink to restore 25% of maximum mana."));
	else if (ItemId == TEXT("meat") || ItemId == TEXT("honey") || ItemId == TEXT("berries")) Details.Emplace(TEXT("Use"), TEXT("Eat to restore 10% of maximum health."));
	if (!ItemInspect)
	{
		ItemInspect = CreateWidget<UFableItemInspectWidget>(GetOwningPlayer());
		ItemInspect->OnClosed.AddDynamic(this, &UFableCharacterMenuWidget::RestoreJournalFocus);
		UCanvasPanel* Root = Cast<UCanvasPanel>(WidgetTree->RootWidget);
		if (UCanvasPanelSlot* Slot = Root->AddChildToCanvas(ItemInspect))
		{
			Slot->SetAnchors(FAnchors(0.f,0.f,1.f,1.f)); Slot->SetOffsets(FMargin(0.f)); Slot->SetZOrder(30);
		}
	}
	UTexture2D* Icon = GetItemIconForSlot(ItemId);
	ItemInspect->Open(GetItemLabelForSlot(ItemId, bEquipment), Details, Icon ? Icon : FableItemIcons::Get(ItemId));
	ItemInspect->SetUserFocus(GetOwningPlayer());
	UE_LOG(LogFableForge, Display, TEXT("JOURNAL inspect=%s"), *ItemId);
}

void UFableCharacterMenuWidget::OpenItemActions()
{
	bool bEquipment = false; int32 Index = INDEX_NONE;
	ItemActionIdentity = SelectedInventoryItem(bEquipment, Index);
	if (ItemActionIdentity.IsEmpty()) return;
	ItemActionSource = ControllerSlotId; ItemActionSelection = 0; bConfirmItemDrop = false; ItemActionStatus.Reset();
	RebuildItemActions();
}

void UFableCharacterMenuWidget::CloseItemActions()
{
	if (ItemActionsLayer) ItemActionsLayer->RemoveFromParent();
	ItemActionsLayer = nullptr; ItemActionButtons.Reset(); ItemActionIds.Reset(); bConfirmItemDrop = false;
	RestoreJournalFocus();
}

void UFableCharacterMenuWidget::RefreshItemActionSelection()
{
	for (int32 I = 0; I < ItemActionButtons.Num(); ++I) StyleJournalTab(ItemActionButtons[I], I == ItemActionSelection, false);
	UE_LOG(LogFableForge, Display, TEXT("JOURNAL item_action=%s"), ItemActionIds.IsValidIndex(ItemActionSelection) ? *ItemActionIds[ItemActionSelection].ToString() : TEXT("none"));
}

void UFableCharacterMenuWidget::RebuildItemActions()
{
	if (ItemActionsLayer) ItemActionsLayer->RemoveFromParent();
	ItemActionButtons.Reset(); ItemActionIds.Reset();
	ItemActionsLayer = WidgetTree->ConstructWidget<UBorder>();
	ItemActionsLayer->SetBrushColor(FLinearColor(.02f,.01f,.005f,.76f)); ItemActionsLayer->SetPadding(FMargin(0.f));
	ItemActionsLayer->SetHorizontalAlignment(HAlign_Center); ItemActionsLayer->SetVerticalAlignment(VAlign_Center);
	UCanvasPanel* Root = Cast<UCanvasPanel>(WidgetTree->RootWidget);
	UCanvasPanelSlot* ModalSlot = Root->AddChildToCanvas(ItemActionsLayer);
	ModalSlot->SetAnchors(FAnchors(0.f,0.f,1.f,1.f)); ModalSlot->SetOffsets(FMargin(0.f)); ModalSlot->SetZOrder(20);
	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>(); Size->SetWidthOverride(500.f); ItemActionsLayer->SetContent(Size);
	UBorder* Paper = WidgetTree->ConstructWidget<UBorder>();
	Paper->SetBrush(FSlateRoundedBoxBrush(FLinearColor(.86f,.75f,.55f), 8.f, FLinearColor(.32f,.17f,.055f), 2.f));
	Paper->SetPadding(FMargin(30.f,24.f)); Size->SetContent(Paper);
	UVerticalBox* List = WidgetTree->ConstructWidget<UVerticalBox>(); Paper->SetContent(List);
	auto AddText = [&](const FString& Value, int32 FontSize)
	{
		UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(); Label->SetText(FText::FromString(Value));
		Label->SetFont(FableBookStyle::Font(FontSize, FontSize>18)); Label->SetColorAndOpacity(CharacterMenuUiTextColor); Label->SetAutoWrapText(true);
		List->AddChildToVerticalBox(Label)->SetPadding(FMargin(4.f,0.f,4.f,14.f));
	};
	auto AddAction = [&](const FString& Label, FName Id)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(); Button->InitializeAction(Id);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(); Text->SetText(FText::FromString(Label));
		Text->SetFont(FableBookStyle::Font(20)); Text->SetColorAndOpacity(CharacterMenuUiTextColor); Button->AddChild(Text);
		Cast<UButtonSlot>(Text->Slot)->SetPadding(FMargin(16.f,10.f));
		List->AddChildToVerticalBox(Button)->SetPadding(FMargin(0.f,2.f)); ItemActionButtons.Add(Button); ItemActionIds.Add(Id);
	};
	AddText(GetItemLabelForSlot(ItemActionIdentity, false), 26);
	if (!ItemActionStatus.IsEmpty()) AddText(ItemActionStatus, 16);
	if (bConfirmItemDrop)
	{
		AddText(TEXT("Drop this item or entire stack nearby? You can pick it up again before leaving this game session. Ground drops are not saved."),16);
		AddAction(TEXT("Drop Item / Stack"), TEXT("item_drop_confirm")); AddAction(TEXT("Cancel"), TEXT("item_cancel"));
	}
	else
	{
		AddAction(TEXT("Move"), TEXT("item_move"));
		const bool bFood = ItemActionIdentity == TEXT("meat") || ItemActionIdentity == TEXT("honey") || ItemActionIdentity == TEXT("berries");
		if (ResolveItemCategory(ItemActionIdentity) == CategoryConsumablesAction || bFood)
		{
			AddAction(bFood ? TEXT("Eat") : TEXT("Drink"), TEXT("item_consume"));
			AddAction(TEXT("Assign to Slot"), TEXT("item_assign"));
		}
		else if (const auto* Definition = ItemDefinitions.Find(ItemActionIdentity); Definition && Definition->bEquipable)
			AddAction(ItemActionSource.ToString().StartsWith(TEXT("equip_")) ? TEXT("Unequip") : TEXT("Equip"), TEXT("item_equip"));
		AddAction(TEXT("Drop"), TEXT("item_drop"));
	}
	AddText(TEXT("Circle  ·  Close"), 14);
	ItemActionSelection = FMath::Clamp(ItemActionSelection, 0, ItemActionIds.Num()-1); RefreshItemActionSelection(); RestoreJournalFocus();
}

void UFableCharacterMenuWidget::Toggle()
{
	if (IsOpen())
	{
		Close();
	}
	else
	{
		Open();
	}
}

void UFableCharacterMenuWidget::OpenSkillsForQa()
{
	ActiveTab = TEXT("skills");
	Open();
}

bool UFableCharacterMenuWidget::IsOpen() const
{
	const ESlateVisibility CurrentVisibility = GetVisibility();
	return CurrentVisibility != ESlateVisibility::Collapsed && CurrentVisibility != ESlateVisibility::Hidden;
}

bool UFableCharacterMenuWidget::ShowEmbeddedQuickWheel(UFableWheelAssignmentWidget* AssignmentWidget, const TArray<FFableQuickWheelPageData>& Pages, const TArray<FString>& Payloads, const TArray<FString>& Labels)
{
	if (!IsOpen() || ContentRoot == nullptr || AssignmentWidget == nullptr)
	{
		return false;
	}

	EmbeddedQuickWheel = AssignmentWidget;
	EmbeddedQuickWheel->RemoveFromParent();
	EmbeddedQuickWheel->SetEmbedded(true);
	ContentRoot->ClearChildren();
	ContentRoot->AddChild(EmbeddedQuickWheel);
	EmbeddedQuickWheel->Open(Pages, Payloads, Labels);
	return true;
}

void UFableCharacterMenuWidget::HideEmbeddedQuickWheel()
{
	if (EmbeddedQuickWheel == nullptr)
	{
		return;
	}

	EmbeddedQuickWheel->Close();
	EmbeddedQuickWheel->RemoveFromParent();
	EmbeddedQuickWheel = nullptr;
	RebuildTabContent();
}

void UFableCharacterMenuWidget::Rebuild()
{
	if (WidgetTree == nullptr)
	{
		return;
	}

	SlotWidgets.Reset();
	MainTabButtons.Reset();
	SkillRowActions.Reset();

	UCanvasPanel* Root = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("CharacterMenuRoot"));
	Root->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	WidgetTree->RootWidget = Root;

	UBorder* Scrim = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
	Scrim->SetBrushColor(FLinearColor(0.019f, 0.012f, 0.009f, 0.86f));
	if (UCanvasPanelSlot* ScrimSlot = Root->AddChildToCanvas(Scrim))
	{
		ScrimSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		ScrimSlot->SetOffsets(FMargin(0.0f));
	}
	UScaleBox* Scale = WidgetTree->ConstructWidget<UScaleBox>(UScaleBox::StaticClass());
	Scale->SetStretch(EStretch::ScaleToFit);
	Scale->SetStretchDirection(EStretchDirection::Both);
	if (UCanvasPanelSlot* ScaleSlot = Root->AddChildToCanvas(Scale))
	{
		ScaleSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		// Let the open-book art bleed slightly past the viewport edges so the
		// journal reads as the dominant surface instead of a small centered panel.
		ScaleSlot->SetOffsets(FMargin(12.0f));
	}
	USizeBox* DesignSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
	DesignSize->SetWidthOverride(1400.0f);
	DesignSize->SetHeightOverride(780.0f);
	Scale->SetContent(DesignSize);
	UOverlay* BookLayers = WidgetTree->ConstructWidget<UOverlay>(UOverlay::StaticClass());
	DesignSize->SetContent(BookLayers);
	// Bookmarks are behind the cover, with only their icon ends protruding.
	UVerticalBox* BookmarkStack = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("JournalBookmarkStack"));
	BookmarkStack->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	if (UOverlaySlot* BookmarkSlot = BookLayers->AddChildToOverlay(BookmarkStack))
	{
		BookmarkSlot->SetHorizontalAlignment(HAlign_Left);
		BookmarkSlot->SetVerticalAlignment(VAlign_Top);
		BookmarkSlot->SetPadding(FMargin(8.f, 146.f, 0.f, 0.f));
	}
	UFableBookSurface* Book = WidgetTree->ConstructWidget<UFableBookSurface>(UFableBookSurface::StaticClass());
	Book->SetOpenBook(true);
	Book->SetVisibility(ESlateVisibility::HitTestInvisible);
	if (UOverlaySlot* BookSlot = BookLayers->AddChildToOverlay(Book))
	{
		BookSlot->SetHorizontalAlignment(HAlign_Fill);
		BookSlot->SetVerticalAlignment(VAlign_Fill);
		BookSlot->SetPadding(FMargin(64.f, 0.f, 0.f, 0.f));
	}
	UBorder* Frame = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("Frame"));
	Frame->SetBrushColor(CharacterMenuUiPanelColor);
	// The bookmark stack projects from the left page edge, so reserve a little
	// more inner width for the actual page content without shrinking the book.
	Frame->SetPadding(FMargin(168.0f, 72.0f, 104.0f, 86.0f));
	if (UOverlaySlot* FrameSlot = BookLayers->AddChildToOverlay(Frame))
	{
		FrameSlot->SetHorizontalAlignment(HAlign_Fill);
		FrameSlot->SetVerticalAlignment(VAlign_Fill);
	}

	AddBookmarkHint(WidgetTree, BookmarkStack, TEXT("L2"));
	auto AddBookmarkButton = [&](const TCHAR* Label, uint32 Glyph, FName ActionId, const FLinearColor& LeatherColor)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(ActionId);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		Button->SetToolTipText(FText::FromString(Label));
		Button->AccessibleBehavior = ESlateAccessibleBehavior::Custom;
		Button->AccessibleText = FText::FromString(Label);
		StyleJournalBookmark(Button, ActiveTab == FName(*ActionId.ToString().RightChop(4)), LeatherColor);

		UTextBlock* Icon = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Icon->SetFont(JournalBookmarkFont(27));
		Icon->SetText(FText::FromString(FString::Chr(Glyph)));
		Icon->SetColorAndOpacity(FLinearColor(.97f, .88f, .68f, 1.f));
		Icon->SetJustification(ETextJustify::Center);
		Button->AddChild(Icon);
		if (UButtonSlot* IconSlot = Cast<UButtonSlot>(Icon->Slot))
		{
			IconSlot->SetHorizontalAlignment(HAlign_Left);
			IconSlot->SetVerticalAlignment(VAlign_Center);
			IconSlot->SetPadding(FMargin(17.f, 0.f, 0.f, 0.f));
		}

		USizeBox* TabSize = WidgetTree->ConstructWidget<USizeBox>();
		TabSize->SetWidthOverride(96.f);
		TabSize->SetHeightOverride(58.f);
		TabSize->SetContent(Button);
		if (UVerticalBoxSlot* VerticalSlot = BookmarkStack->AddChildToVerticalBox(TabSize))
		{
			VerticalSlot->SetHorizontalAlignment(HAlign_Left);
			VerticalSlot->SetPadding(FMargin(0.f, 2.f));
		}
		MainTabButtons.Add(ActionId, Button);
	};

	AddBookmarkButton(TEXT("Inventory"), 0xf290, InventoryAction, JournalBookmarkLeather(InventoryAction));
	AddBookmarkButton(TEXT("Skills"), 0xf0d0, SkillsAction, JournalBookmarkLeather(SkillsAction));
	AddBookmarkButton(TEXT("Companions"), 0xf0c0, CompanionsAction, JournalBookmarkLeather(CompanionsAction));
	AddBookmarkButton(TEXT("Build"), 0xf0e3, BuildAction, JournalBookmarkLeather(BuildAction));
	AddBookmarkButton(TEXT("Settings"), 0xf013, SettingsAction, JournalBookmarkLeather(SettingsAction));
	AddBookmarkHint(WidgetTree, BookmarkStack, TEXT("R2"));

	UVerticalBox* VBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("FrameVBox"));
	VBox->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	Frame->SetContent(VBox);


	ContentRoot = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("TabContent"));
	ContentRoot->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	if (UVerticalBoxSlot* ContentSlot = VBox->AddChildToVerticalBox(ContentRoot))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		ContentSlot->SetSize(FillSize);
		ContentSlot->SetPadding(FMargin(20.0f, 0.0f, 20.0f, 14.0f));
	}
	RebuildTabContent();
}

void UFableCharacterMenuWidget::RefreshMainTabButtonStyles()
{
	auto UpdateButton = [&](FName ActionId, bool bSelected)
	{
		if (TObjectPtr<UFableActionButton>* ButtonPtr = MainTabButtons.Find(ActionId))
		{
			if (UFableActionButton* Button = ButtonPtr->Get())
			{
				StyleJournalBookmark(Button, bSelected, JournalBookmarkLeather(ActionId));
			}
		}
	};

	UpdateButton(InventoryAction, ActiveTab == TEXT("inventory"));
	UpdateButton(SkillsAction, ActiveTab == TEXT("skills"));
	UpdateButton(CompanionsAction, ActiveTab == TEXT("companions"));
	UpdateButton(BuildAction, ActiveTab == TEXT("build"));
	UpdateButton(SettingsAction, ActiveTab == TEXT("settings"));
}

void UFableCharacterMenuWidget::QueueTabContentRebuild()
{
	if (bTabContentRebuildQueued)
	{
		return;
	}

	bTabContentRebuildQueued = true;
	if (UWorld* World = GetWorld())
	{
		World->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateUObject(this, &UFableCharacterMenuWidget::PerformQueuedTabContentRebuild));
	}
	else
	{
		PerformQueuedTabContentRebuild();
	}
}

void UFableCharacterMenuWidget::PerformQueuedTabContentRebuild()
{
	bTabContentRebuildQueued = false;
	RefreshMainTabButtonStyles();
	RebuildTabContent();
}

void UFableCharacterMenuWidget::RebuildTabContent()
{
	if (ContentRoot == nullptr)
	{
		return;
	}

	ContentRoot->ClearChildren();
	SlotWidgets.Reset();
	InventoryCells.Reset(); InventoryCategoryButtons.Reset(); SkillCategoryButtons.Reset(); SkillRows.Reset();
	DisplayedSkillOrder.Reset(); SkillRowActions.Reset();
	InventoryHeading=nullptr; InventoryStatus=nullptr; SkillDetailsContent=nullptr;

	if (ActiveTab == TEXT("inventory"))
	{
		BuildInventoryTab();
		return;
	}

	if (ActiveTab == TEXT("skills"))
	{
		BuildSkillsTab();
		return;
	}

	if (ActiveTab == TEXT("companions"))
	{
		BuildSimpleInfoTab(TEXT("Companions"), TEXT("No companions recruited yet."));
		return;
	}
	if (ActiveTab == TEXT("settings")) { BuildSettingsTab(); return; }

	BuildSimpleInfoTab(TEXT("Build"), TEXT("No structures queued."));
}

void UFableCharacterMenuWidget::RefreshSettingsSelection()
{
	for (int32 I = 0; I < SettingsButtons.Num(); ++I)
		if (SettingsButtons[I]) SettingsButtons[I]->SetBackgroundColor(I == SettingsSelection ? CharacterMenuUiButtonSelectedColor : CharacterMenuUiButtonColor);
	if (SettingsScroll && SettingsButtons.IsValidIndex(SettingsSelection)) SettingsScroll->ScrollWidgetIntoView(SettingsButtons[SettingsSelection], false);
}

void UFableCharacterMenuWidget::BuildSettingsTab()
{
	SettingsActions.Reset(); SettingsButtons.Reset(); SettingsSlots.Reset();
	UScrollBox* Scroll = WidgetTree->ConstructWidget<UScrollBox>();
	SettingsScroll = Scroll;
	Scroll->SetClipping(EWidgetClipping::ClipToBoundsAlways);
	UVerticalBoxSlot* ScrollSlot = ContentRoot->AddChildToVerticalBox(Scroll);
	FSlateChildSize Fill; Fill.SizeRule = ESlateSizeRule::Fill; ScrollSlot->SetSize(Fill);
	USizeBox* Width = WidgetTree->ConstructWidget<USizeBox>(); Width->SetWidthOverride(490.f);
	Cast<UScrollBoxSlot>(Scroll->AddChild(Width))->SetHorizontalAlignment(HAlign_Left);
	UVerticalBox* List = WidgetTree->ConstructWidget<UVerticalBox>(); Width->SetContent(List);
	auto Text = [&](const FString& Value, int32 Size)
	{
		UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(); Label->SetText(FText::FromString(Value));
		Label->SetFont(FableBookStyle::Font(Size, Size >= 18)); Label->SetColorAndOpacity(CharacterMenuUiTextColor);
		Label->SetAutoWrapText(true); List->AddChildToVerticalBox(Label)->SetPadding(FMargin(8.f, 8.f, 8.f, 12.f));
	};
	auto Button = [&](const FString& Label, FName Action)
	{
		UFableActionButton* Item = WidgetTree->ConstructWidget<UFableActionButton>();
		Item->InitializeAction(Action); Item->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		FableBookStyle::ApplyButton(Item);
		UTextBlock* Title = WidgetTree->ConstructWidget<UTextBlock>(); Title->SetText(FText::FromString(Label));
		Title->SetFont(FableBookStyle::Font(16, true)); Title->SetColorAndOpacity(CharacterMenuUiTextColor);
		Item->AddChild(Title); Cast<UButtonSlot>(Title->Slot)->SetPadding(FMargin(14.f, 10.f));
		List->AddChildToVerticalBox(Item)->SetPadding(FMargin(8.f, 0.f, 8.f, 10.f));
		SettingsActions.Add(Action); SettingsButtons.Add(Item);
	};
	Text(SettingsPage == TEXT("save") ? TEXT("Save Game") : SettingsPage == TEXT("load") ? TEXT("Load Game") : TEXT("Settings"), 22);
	if (!SettingsStatus.IsEmpty()) Text(SettingsStatus, 14);
	UFableSaveSubsystem* Saves = GetGameInstance()->GetSubsystem<UFableSaveSubsystem>();
	if (!Saves) { Text(TEXT("Save system unavailable."), 14); return; }
	if (SettingsPage.IsNone())
	{
		Button(TEXT("Save Game"), TEXT("settings_save"));
		Button(TEXT("Load Game"), TEXT("settings_load"));
		Button(TEXT("Quit to Main Menu"), TEXT("settings_quit"));
	}
	else if (SettingsPage == TEXT("save") || SettingsPage == TEXT("load"))
	{
		TArray<FFableSaveSlotMeta> Slots;
		Saves->GetSaveSlots(SettingsPage == TEXT("save") ? Saves->GetActiveCharacterId() : SettingsLoadCharacter, Slots);
		for (const auto& Slot : Slots)
		{
			const FName Action(*FString::Printf(TEXT("settings_slot_%d"), Slot.SlotIndex));
			SettingsSlots.Add(Action, Slot.SlotIndex);
			Button(FString::Printf(TEXT("Slot %d  —  %s"), Slot.SlotIndex + 1, Slot.bHasSave ? TEXT("Saved game") : TEXT("Empty")), Action);
		}
		if (SettingsActions.IsEmpty()) Text(TEXT("No saved slots."), 14);
	}
	else if (SettingsPage == TEXT("quit"))
	{
		Text(TEXT("Return to the main menu? Save your game first if you want to keep your current progress."), 16);
		Button(TEXT("Return to Main Menu"), TEXT("settings_quit_confirm"));
	}
	if (!SettingsPage.IsNone()) Button(TEXT("Back"), TEXT("settings_back"));
	SettingsSelection = FMath::Clamp(SettingsSelection, 0, FMath::Max(0, SettingsActions.Num()-1));
	RefreshSettingsSelection();
}

void UFableCharacterMenuWidget::BuildInventoryTab()
{
	LoadInventoryFromSave();
	LoadItemDefinitionsFromUnityJson();

	UHorizontalBox* CategoryRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("InventoryCategoryRow"));
	if (UVerticalBoxSlot* CategoryRowSlot = ContentRoot->AddChildToVerticalBox(CategoryRow))
	{
		CategoryRowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 12.0f));
	}

auto AddCategoryButton = [&](const FString& Label, FName CategoryAction)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(CategoryAction);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		StyleJournalTab(Button, ActiveInventoryCategory == CategoryAction, true);
		InventoryCategoryButtons.Add(CategoryAction,Button);

		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		FSlateFontInfo TextBaseFont = FableBookStyle::Font(14, true);
		TextBaseFont.Size = 14;
		Text->SetFont(TextBaseFont);
		Text->SetText(FText::FromString(Label));
		Text->SetColorAndOpacity(FSlateColor(FLinearColor(.035f, .014f, .004f, 1.f)));
		Text->SetJustification(ETextJustify::Center);
		FSlateFontInfo FontInfo = FableBookStyle::Font(14, true);
		FontInfo.Size = 13;
		Text->SetFont(FontInfo);
		Button->AddChild(Text);
		if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
		{
			TextSlot->SetHorizontalAlignment(HAlign_Center);
			TextSlot->SetVerticalAlignment(VAlign_Center);
			TextSlot->SetPadding(FMargin(8.0f, 6.0f));
		}

		if (UHorizontalBoxSlot* HorizontalSlot = CategoryRow->AddChildToHorizontalBox(Button))
		{
			FSlateChildSize FillSize;
			FillSize.SizeRule = ESlateSizeRule::Fill;
			FillSize.Value = 1.0f;
			HorizontalSlot->SetSize(FillSize);
			HorizontalSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
		}
	};

	AddJournalHint(WidgetTree, CategoryRow, TEXT("L1"));
	AddCategoryButton(TEXT("All"), CategoryAllAction);
	AddCategoryButton(TEXT("Armor"), CategoryArmorAction);
	AddCategoryButton(TEXT("Weapons"), CategoryWeaponsAction);
	AddCategoryButton(TEXT("Consumables"), CategoryConsumablesAction);
	AddCategoryButton(TEXT("Misc"), CategoryMiscAction);
	AddCategoryButton(TEXT("Key Items"), CategoryKeyItemsAction);
	AddJournalHint(WidgetTree, CategoryRow, TEXT("R1"));

	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("InventoryMainRow"));
	if (UVerticalBoxSlot* MainRowSlot = ContentRoot->AddChildToVerticalBox(MainRow))
	{
		MainRowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 0.0f));
		// Reserve the full section height before laying out the footer. A Fill
		// slot can shrink below its fixed-height children and overlap the hint.
		FSlateChildSize AutoSize;
		AutoSize.SizeRule = ESlateSizeRule::Automatic;
		MainRowSlot->SetSize(AutoSize);
		MainRowSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UVerticalBox* LeftColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventoryLeftColumn"));
	if (UHorizontalBoxSlot* LeftSlot = MainRow->AddChildToHorizontalBox(LeftColumn))
	{
		LeftSlot->SetHorizontalAlignment(HAlign_Left);
		LeftSlot->SetPadding(FMargin(0.0f, 0.0f, 108.0f, 0.0f));
	}

	USizeBox* InventorySectionSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("InventorySectionSize"));
	InventorySectionSize->SetWidthOverride(520.0f);
	InventorySectionSize->SetHeightOverride(460.0f);
	if (UVerticalBoxSlot* InventorySectionSizeSlot = LeftColumn->AddChildToVerticalBox(InventorySectionSize))
	{
		InventorySectionSizeSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UBorder* InventorySection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("InventorySection"));
	InventorySection->SetBrushColor(UiSectionColor);
	InventorySection->SetPadding(FMargin(12.0f));
	InventorySectionSize->SetContent(InventorySection);

	UVerticalBox* LeftSectionBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventorySectionVBox"));
	InventorySection->SetContent(LeftSectionBox);


	USizeBox* InventoryGridScrollSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("InventoryGridScrollSize"));
	if (UVerticalBoxSlot* InventoryGridSlot = LeftSectionBox->AddChildToVerticalBox(InventoryGridScrollSize))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		InventoryGridSlot->SetSize(FillSize);
	}

	UScrollBox* InventoryGridScroll = WidgetTree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("InventoryGridScroll"));
	InventoryScroll = InventoryGridScroll;
	InventoryGridScroll->SetClipping(EWidgetClipping::ClipToBoundsAlways);
	InventoryGridScrollSize->SetContent(InventoryGridScroll);

	UUniformGridPanel* InventoryGrid = WidgetTree->ConstructWidget<UUniformGridPanel>(UUniformGridPanel::StaticClass(), TEXT("InventoryGrid"));
	// Keep the bag cells compact and square so the frame remains visible while
	// leaving enough room for the actual icon artwork.
	InventoryGrid->SetMinDesiredSlotWidth(80.0f);
	InventoryGrid->SetMinDesiredSlotHeight(80.0f);
	InventoryGrid->SetSlotPadding(FMargin(0.0f));
	USizeBox* GridWidth = WidgetTree->ConstructWidget<USizeBox>();
	GridWidth->SetWidthOverride(440.f);
	GridWidth->SetContent(InventoryGrid);
	if (UScrollBoxSlot* GridSlot = Cast<UScrollBoxSlot>(InventoryGridScroll->AddChild(GridWidth)))
	{
		GridSlot->SetHorizontalAlignment(HAlign_Left);
		GridSlot->SetPadding(FMargin(0.f));
	}

	for (int32 DisplayIndex = 0; DisplayIndex < UFableSaveSubsystem::InventorySlotsPerCharacter; ++DisplayIndex)
	{
		const int32 SlotIndex = DisplayIndex;
		const FName SlotId(*FString::Printf(TEXT("inv_%d"), SlotIndex));
		const FString ItemId = InventorySlots.IsValidIndex(SlotIndex) ? InventorySlots[SlotIndex] : TEXT("");

		UFableInventorySlotWidget* SlotWidget = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SlotWidget->InitializeSlot(SlotId, TEXT(""), false);
		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, false), GetItemIconForSlot(ItemId));
		SlotWidget->SetItemQuantity(InventoryQuantities.IsValidIndex(SlotIndex) ? InventoryQuantities[SlotIndex] : 1);
		SlotWidget->OnItemDrop.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotDropped);
		SlotWidget->OnSlotClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotContext);
		SlotWidget->OnSlotHovered.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotHovered);
		SlotWidget->OnSlotRightClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotContext);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(88.0f);
		SlotSizeBox->SetHeightOverride(88.0f);
		SlotSizeBox->SetContent(SlotWidget);

		if (UUniformGridSlot* GridSlot = InventoryGrid->AddChildToUniformGrid(SlotSizeBox, DisplayIndex / 5, DisplayIndex % 5))
		{
			GridSlot->SetHorizontalAlignment(HAlign_Left);
			GridSlot->SetVerticalAlignment(VAlign_Top);
		}

		SlotWidgets.Add(SlotId, SlotWidget);
		InventoryCells.Add(SlotIndex,SlotSizeBox);
	}

	UVerticalBox* RightColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventoryRightColumn"));
	if (UHorizontalBoxSlot* RightSlot = MainRow->AddChildToHorizontalBox(RightColumn))
	{
		RightSlot->SetHorizontalAlignment(HAlign_Left);
	}

	USizeBox* EquipmentSectionSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("EquipmentSectionSize"));
	EquipmentSectionSize->SetWidthOverride(520.0f);
	EquipmentSectionSize->SetHeightOverride(460.0f);
	if (UVerticalBoxSlot* EquipmentSectionSizeSlot = RightColumn->AddChildToVerticalBox(EquipmentSectionSize))
	{
		EquipmentSectionSizeSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UBorder* EquipmentSection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("EquipmentSection"));
	EquipmentSection->SetBrushColor(UiSectionColor);
	EquipmentSection->SetPadding(FMargin(12.0f));
	EquipmentSectionSize->SetContent(EquipmentSection);

	UOverlay* EquipmentOverlay = WidgetTree->ConstructWidget<UOverlay>(UOverlay::StaticClass(), TEXT("EquipmentOverlay"));
	EquipmentSection->SetContent(EquipmentOverlay);
	UCanvasPanel* EquipmentCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("EquipmentCanvas"));
	UVerticalBox* RightSectionBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("EquipmentSectionVBox"));
	if (UOverlaySlot* ContentSlot = EquipmentOverlay->AddChildToOverlay(RightSectionBox))
	{
		ContentSlot->SetHorizontalAlignment(HAlign_Fill);
		ContentSlot->SetVerticalAlignment(VAlign_Fill);
	}


	USizeBox* EquipmentGridSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("EquipmentGridSize"));
	EquipmentGridSize->SetWidthOverride(340.0f);
	EquipmentGridSize->SetHeightOverride(400.0f);
	if (UVerticalBoxSlot* EquipmentGridSizeSlot = RightSectionBox->AddChildToVerticalBox(EquipmentGridSize))
	{
		EquipmentGridSizeSlot->SetHorizontalAlignment(HAlign_Center);
	}

	EquipmentGridSize->SetContent(EquipmentCanvas);
	for (const FEquipmentLayoutCell& LayoutCell : EquipmentLayout)
	{
		const int32 SlotIndex = LayoutCell.LogicalIndex;
		const FName SlotId(*FString::Printf(TEXT("equip_%d"), SlotIndex));
		const FString ItemId = EquippedSlots.IsValidIndex(SlotIndex) ? EquippedSlots[SlotIndex] : TEXT("");

		UFableInventorySlotWidget* SlotWidget = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SlotWidget->InitializeSlot(SlotId, EquipmentSlotNames.IsValidIndex(SlotIndex) ? EquipmentSlotNames[SlotIndex] : TEXT("Equip"), true);
		TObjectPtr<UTexture2D>& EmptyTexture = EquipmentSlotTextures.FindOrAdd(LayoutCell.IconName);
		if (!EmptyTexture)
		{
			EmptyTexture = LoadEquipmentIcon(FPaths::ProjectContentDir()
				/ TEXT("Slate/Textures/EquipmentSlots") / (FString(LayoutCell.IconName) + TEXT(".png")));
		}
		if (EmptyTexture)
		{
			FSlateBrush EmptyBrush;
			EmptyBrush.SetResourceObject(EmptyTexture);
			EmptyBrush.ImageSize = FVector2D(EmptyTexture->GetSizeX(), EmptyTexture->GetSizeY());
			SlotWidget->SetEmptyEquipmentBrush(EmptyBrush);
		}
		else
		{
			UE_LOG(LogFableForge, Warning, TEXT("Missing equipment slot icon: %s"), LayoutCell.IconName);
		}
		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, true), GetItemIconForSlot(ItemId));
		SlotWidget->OnItemDrop.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotDropped);
		SlotWidget->OnSlotClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotContext);
		SlotWidget->OnSlotHovered.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotHovered);
		SlotWidget->OnSlotRightClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotContext);

		if (UCanvasPanelSlot* GridSlot = EquipmentCanvas->AddChildToCanvas(SlotWidget))
		{
			GridSlot->SetPosition(FVector2D(LayoutCell.SlotX, LayoutCell.SlotY));
			GridSlot->SetSize(FVector2D(LayoutCell.SlotSize, LayoutCell.SlotSize));
			GridSlot->SetZOrder(1);
		}

		SlotWidgets.Add(SlotId, SlotWidget);
	}

	UTextBlock* InventoryHint = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	InventoryStatus=InventoryHint;
	InventoryHint->SetVisibility(ESlateVisibility::Collapsed);
	FSlateFontInfo InventoryHintBaseFont = FableBookStyle::Font(14, false);
	InventoryHintBaseFont.Size = 14;
	InventoryHint->SetFont(InventoryHintBaseFont);
	InventoryHint->SetText(FText::FromString(InventorySaveWarning.IsEmpty()
		? TEXT("Drag items to move or equip them. Hover for details.")
		: InventorySaveWarning));
	InventoryHint->SetColorAndOpacity(FSlateColor(InventorySaveWarning.IsEmpty()
		? CharacterMenuUiMutedTextColor : FLinearColor(0.48f, 0.065f, 0.025f, 1.0f)));
	InventoryHint->SetAutoWrapText(true);
	FSlateFontInfo HintFont = FableBookStyle::Font(14, false);
	HintFont.Size = 12;
	InventoryHint->SetFont(HintFont);
	if (UVerticalBoxSlot* HintSlot = LeftSectionBox->AddChildToVerticalBox(InventoryHint))
	{
		HintSlot->SetPadding(FMargin(0.0f, 10.0f, 0.0f, 0.0f));
	}

	RefreshInventoryPresentation();

}

void UFableCharacterMenuWidget::BuildSimpleInfoTab(const FString& Header, const FString& Body)
{
	auto AddLine = [&](const FString& Text, bool bMuted = false)
	{
		UTextBlock* Line = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		FSlateFontInfo LineBaseFont = FableBookStyle::Font(bMuted ? 18 : 28, !bMuted);
		LineBaseFont.Size = bMuted ? 18 : 28;
		Line->SetFont(LineBaseFont);
		Line->SetText(FText::FromString(Text));
		Line->SetAutoWrapText(true);
		Line->SetColorAndOpacity(FSlateColor(bMuted ? CharacterMenuUiMutedTextColor : CharacterMenuUiTextColor));
		if (UVerticalBoxSlot* LineSlot = ContentRoot->AddChildToVerticalBox(Line))
		{
			LineSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 10.0f));
		}
	};

	AddLine(Header, false);
	AddLine(Body, true);
}

void UFableCharacterMenuWidget::BuildSkillsTab()
{
	LoadSkillDefinitionsFromDataTable();

	TArray<FString> LearnedSkills;
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		SaveSubsystem->TryGetActiveLearnedSkills(LearnedSkills);
	}

	LearnedSkills.RemoveAll([](const FString& Id) { return !FableSkillCatalog::IsAssignableSkillId(Id); });
	if (LearnedSkills.Num() == 0)
	{
		BuildSimpleInfoTab(TEXT("Skills"), TEXT("No learned skills yet."));
		return;
	}

	if (ActiveSkillDetailsId.IsEmpty() || !LearnedSkills.Contains(ActiveSkillDetailsId))
	{
		ActiveSkillDetailsId = LearnedSkills[0];
	}

	const TArray<EFableSkillCategory> AvailableCategories = { EFableSkillCategory::Fire, EFableSkillCategory::Water,
		EFableSkillCategory::Earth, EFableSkillCategory::Air, EFableSkillCategory::TimeManipulation };

	// Rebuilt tabs need fresh UObjects as well as fresh Slate children. Reusing
	// explicit names can reconstruct a widget whose old Slate tree is still alive.
	UHorizontalBox* SkillCategoryRow = WidgetTree->ConstructWidget<UHorizontalBox>();

	auto AddSkillCategoryButton = [&](EFableSkillCategory Category)
	{
		const FName CategoryAction = SkillCategoryActionFromEnum(Category);
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(CategoryAction);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		StyleJournalTab(Button, ActiveSkillCategory == CategoryAction, true);
		SkillCategoryButtons.Add(CategoryAction,Button);
		Button->SetToolTipText(FText::FromString(EnumToString(Category)));
		UVerticalBox* Content = WidgetTree->ConstructWidget<UVerticalBox>();
		Content->SetVisibility(ESlateVisibility::HitTestInvisible);
		Button->AddChild(Content); Cast<UButtonSlot>(Content->Slot)->SetPadding(FMargin(6.f, 16.f, 6.f, 14.f));
		USizeBox* IconSize = WidgetTree->ConstructWidget<USizeBox>();
		IconSize->SetWidthOverride(38.f); IconSize->SetHeightOverride(38.f);
		UImage* Icon = WidgetTree->ConstructWidget<UImage>();
		Icon->SetBrushFromTexture(SkillSchoolArt(Category));
		UScaleBox* IconScale = WidgetTree->ConstructWidget<UScaleBox>();
		IconScale->SetStretch(EStretch::ScaleToFit);
		IconScale->SetStretchDirection(EStretchDirection::Both);
		IconScale->SetContent(Icon);
		IconSize->SetContent(IconScale);
		Content->AddChildToVerticalBox(IconSize)->SetHorizontalAlignment(HAlign_Center);
		UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>();
		Label->SetText(FText::FromString(EnumToString(Category)));
		Label->SetFont(FableBookStyle::Font(12, true)); Label->SetColorAndOpacity(CharacterMenuUiTextColor);
		Label->SetJustification(ETextJustify::Center);
		Content->AddChildToVerticalBox(Label);
		USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>(); Size->SetWidthOverride(88.f); Size->SetContent(Button);
		if (UHorizontalBoxSlot* CategorySlot = SkillCategoryRow->AddChildToHorizontalBox(Size))
		{
			CategorySlot->SetPadding(FMargin(0.f, 0.f, 4.f, 0.f));
		}
	};

	OrderedSkillCategories.Reset();
	AddJournalHint(WidgetTree, SkillCategoryRow, TEXT("L1"));
	for (EFableSkillCategory Category : AvailableCategories)
	{
		AddSkillCategoryButton(Category);
		OrderedSkillCategories.Add(SkillCategoryActionFromEnum(Category));
	}
	AddJournalHint(WidgetTree, SkillCategoryRow, TEXT("R1"));


	const TArray<FString>& VisibleSkills=LearnedSkills;
	DisplayedSkillOrder=LearnedSkills;

	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* MainRowSlot = ContentRoot->AddChildToVerticalBox(MainRow))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		MainRowSlot->SetSize(FillSize);
	}

	UBorder* SkillListSection = WidgetTree->ConstructWidget<UBorder>();
	SkillListSection->SetBrushColor(FLinearColor::Transparent);
	SkillListSection->SetPadding(FMargin(8.0f));
	if (UHorizontalBoxSlot* ListSlot = MainRow->AddChildToHorizontalBox(SkillListSection))
	{
		FSlateChildSize ListSize;
		ListSize.SizeRule = ESlateSizeRule::Fill;
		ListSize.Value = 0.5f;
		ListSlot->SetSize(ListSize);
		ListSlot->SetPadding(FMargin(0.0f, 0.0f, 32.0f, 0.0f));
	}

	UScrollBox* SkillsListScroll = WidgetTree->ConstructWidget<UScrollBox>();
	SkillsScroll = SkillsListScroll;
	UVerticalBox* SkillsLeftColumn = WidgetTree->ConstructWidget<UVerticalBox>();
	SkillListSection->SetContent(SkillsLeftColumn);
	SkillsLeftColumn->AddChildToVerticalBox(SkillCategoryRow)->SetPadding(FMargin(0.f, 0.f, 0.f, 10.f));
	if (UVerticalBoxSlot* ScrollSlot = SkillsLeftColumn->AddChildToVerticalBox(SkillsListScroll))
	{
		FSlateChildSize FillSize; FillSize.SizeRule = ESlateSizeRule::Fill;
		ScrollSlot->SetSize(FillSize);
	}

	UVerticalBox* SkillsListVBox = WidgetTree->ConstructWidget<UVerticalBox>();
	SkillsListScroll->AddChild(SkillsListVBox);

	for (int32 SkillIndex = 0; SkillIndex < VisibleSkills.Num(); ++SkillIndex)
	{
		const FString& SkillId = VisibleSkills[SkillIndex];
		const FFableSkillDefinitionTableRow* SkillRow = FindSkillDefinition(SkillId);
		const bool bSelected = SkillId == ActiveSkillDetailsId;
		const FString Token = (SkillRow != nullptr && !SkillRow->IconToken.IsEmpty())
			? SkillRow->IconToken
			: BuildIconToken(SkillRow != nullptr && !SkillRow->DisplayName.IsEmpty() ? SkillRow->DisplayName : SkillId);

		UBorder* RowBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		RowBorder->SetBrush(FSlateRoundedBoxBrush(bSelected ? FLinearColor(.45f, .27f, .1f, .12f) : FLinearColor::Transparent, 3.f));
		SkillRows.Add(SkillId,RowBorder);
		RowBorder->SetPadding(FMargin(8.0f, 14.f));
		if (UVerticalBoxSlot* RowSlot = SkillsListVBox->AddChildToVerticalBox(RowBorder))
		{
			RowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 6.0f));
		}

		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass());
		RowBorder->SetContent(Row);

		const FName SlotId(*FString::Printf(TEXT("skill_%d"), SkillIndex));
		UFableInventorySlotWidget* SkillSlot = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SkillSlot->InitializeSlot(SlotId, TEXT(""), false);
		UTexture2D* SkillIcon = SkillRow ? SkillSchoolArt(SkillRow->Category) : nullptr;
		if (!SkillIcon && SkillRow && !SkillRow->SkillIconTexture.IsNull()) SkillIcon = SkillRow->SkillIconTexture.LoadSynchronous();
		SkillSlot->SetItemData(FString::Printf(TEXT("skill:%s"), *SkillId), Token, SkillIcon);
		SkillSlot->OnSlotHovered.AddDynamic(this, &UFableCharacterMenuWidget::HandleSkillSlotHovered);
		SkillSlot->OnSlotClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleSkillSlotClicked);
		SkillSlot->OnSlotRightClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleSkillSlotRightClicked);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(76.0f);
		SlotSizeBox->SetHeightOverride(76.0f);
		SlotSizeBox->SetContent(SkillSlot);
		if (UHorizontalBoxSlot* SlotHBox = Row->AddChildToHorizontalBox(SlotSizeBox))
		{
			SlotHBox->SetPadding(FMargin(0.0f, 0.0f, 16.0f, 0.0f));
		}

		const FName SkillSelectAction(*FString::Printf(TEXT("%s%d"), SkillSelectActionPrefix, SkillIndex));
		SkillRowActions.Add(SkillSelectAction, SkillId);
		UFableActionButton* RowTextButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		RowTextButton->InitializeAction(SkillSelectAction);
		RowTextButton->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		FableBookStyle::ApplyButton(RowTextButton);
		RowTextButton->SetBackgroundColor(FLinearColor::Transparent);
		if (UHorizontalBoxSlot* TextButtonSlot = Row->AddChildToHorizontalBox(RowTextButton))
		{
			FSlateChildSize FillSize;
			FillSize.SizeRule = ESlateSizeRule::Fill;
			FillSize.Value = 1.0f;
			TextButtonSlot->SetSize(FillSize);
			TextButtonSlot->SetVerticalAlignment(VAlign_Fill);
		}

		UVerticalBox* RowText = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass());
		RowText->SetVisibility(ESlateVisibility::HitTestInvisible);
		RowTextButton->AddChild(RowText);
		if (UButtonSlot* LabelSlot = Cast<UButtonSlot>(RowText->Slot))
		{
			LabelSlot->SetHorizontalAlignment(HAlign_Fill); LabelSlot->SetVerticalAlignment(VAlign_Center);
			LabelSlot->SetPadding(FMargin(0.f));
		}

		UTextBlock* NameText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		FSlateFontInfo NameTextBaseFont = FableBookStyle::Font(14, false);
		NameTextBaseFont.Size = 20;
		NameText->SetFont(NameTextBaseFont);
		NameText->SetText(FText::FromString(SkillRow != nullptr && !SkillRow->DisplayName.IsEmpty() ? SkillRow->DisplayName : HumanizeToken(SkillId)));
		NameText->SetColorAndOpacity(FSlateColor(CharacterMenuUiTextColor));
		NameText->SetAutoWrapText(true);
		RowText->AddChildToVerticalBox(NameText);

		UTextBlock* Subtitle = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		FSlateFontInfo SubtitleBaseFont = FableBookStyle::Font(14, false);
		SubtitleBaseFont.Size = 14;
		Subtitle->SetFont(SubtitleBaseFont);
		Subtitle->SetText(FText::FromString(SkillRow != nullptr ? SkillRow->Summary : TEXT("An undiscovered technique")));
		Subtitle->SetColorAndOpacity(FSlateColor(CharacterMenuUiMutedTextColor));
		Subtitle->SetAutoWrapText(true);
		FSlateFontInfo SubtitleFont = FableBookStyle::Font(14, false);
		SubtitleFont.Size = 14;
		Subtitle->SetFont(SubtitleFont);
		RowText->AddChildToVerticalBox(Subtitle);
	}

	UBorder* DetailsSection = WidgetTree->ConstructWidget<UBorder>();
	DetailsSection->SetBrushColor(FLinearColor::Transparent);
	DetailsSection->SetPadding(FMargin(12.0f, 6.0f, 12.0f, 12.0f));
	if (UHorizontalBoxSlot* DetailsSlot = MainRow->AddChildToHorizontalBox(DetailsSection))
	{
		FSlateChildSize DetailsSize;
		DetailsSize.SizeRule = ESlateSizeRule::Fill;
		DetailsSize.Value = 0.5f;
		DetailsSlot->SetSize(DetailsSize);
		DetailsSlot->SetPadding(FMargin(32.0f, 0.0f, 0.0f, 0.0f));
	}

	UScrollBox* DetailsScroll = WidgetTree->ConstructWidget<UScrollBox>();
	DetailsScroll->SetClipping(EWidgetClipping::ClipToBoundsAlways);
	DetailsSection->SetContent(DetailsScroll);

	UVerticalBox* DetailsVBox = WidgetTree->ConstructWidget<UVerticalBox>();
	DetailsScroll->AddChild(DetailsVBox);
	SkillDetailsContent=DetailsVBox;
	RefreshSkillsPresentation();
}

void UFableCharacterMenuWidget::RefreshSkillDetails()
{
	if (!SkillDetailsContent) return;
	if (UScrollBox* DetailsScroll = Cast<UScrollBox>(SkillDetailsContent->GetParent()))
		DetailsScroll->ScrollToStart();
	// Only the passive details text changes; hovered/clicked rows and both
	// scroll containers retain their Slate instances and focus.
	SkillDetailsContent->ClearChildren();
	UE_LOG(LogFableForge, Display, TEXT("SKILL_DETAILS refresh=%s"), *ActiveSkillDetailsId);
	UVerticalBox* DetailsVBox=SkillDetailsContent;


	const FFableSkillDefinitionTableRow* SelectedSkill = FindSkillDefinition(ActiveSkillDetailsId);
	const FString SelectedSkillName = SelectedSkill != nullptr && !SelectedSkill->DisplayName.IsEmpty()
		? SelectedSkill->DisplayName
		: HumanizeToken(ActiveSkillDetailsId);

	auto AddDetailLine = [&](const FString& Label, const FString& Value, bool bMuted = false, int32 FontSize = 13)
	{
		if (Value.IsEmpty())
		{
			return;
		}

		UTextBlock* Line = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		FSlateFontInfo LineBaseFont = FableBookStyle::Font(14, false);
		LineBaseFont.Size = 14;
		Line->SetFont(LineBaseFont);
		Line->SetText(FText::FromString(Label.IsEmpty() ? Value : FString::Printf(TEXT("%s: %s"), *Label, *Value)));
		Line->SetAutoWrapText(true);
		Line->SetColorAndOpacity(FSlateColor(bMuted ? CharacterMenuUiMutedTextColor : CharacterMenuUiTextColor));
		FSlateFontInfo Font = FableBookStyle::Font(14, false);
		Font.Size = FontSize;
		Line->SetFont(Font);
		if (UVerticalBoxSlot* LineSlot = DetailsVBox->AddChildToVerticalBox(Line))
		{
			LineSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 6.0f));
		}
	};

	if (SelectedSkill)
	{
		USizeBox* IllustrationSize = WidgetTree->ConstructWidget<USizeBox>();
		IllustrationSize->SetWidthOverride(104.f); IllustrationSize->SetHeightOverride(104.f);
		UImage* Illustration = WidgetTree->ConstructWidget<UImage>();
		Illustration->SetBrushFromTexture(SkillSchoolArt(SelectedSkill->Category));
		UScaleBox* IllustrationScale = WidgetTree->ConstructWidget<UScaleBox>();
		IllustrationScale->SetStretch(EStretch::ScaleToFit);
		IllustrationScale->SetStretchDirection(EStretchDirection::Both);
		IllustrationScale->SetContent(Illustration);
		IllustrationSize->SetContent(IllustrationScale);
		UVerticalBoxSlot* ArtSlot = DetailsVBox->AddChildToVerticalBox(IllustrationSize);
		ArtSlot->SetHorizontalAlignment(HAlign_Left); ArtSlot->SetPadding(FMargin(0.f, 4.f, 0.f, 16.f));
	}
	AddDetailLine(TEXT(""), SelectedSkillName, false, 26);

	if (SelectedSkill == nullptr)
	{
		AddDetailLine(TEXT("Status"), TEXT("Details for this technique are not yet available."), true);
		return;
	}

	AddDetailLine(TEXT(""), EnumToString(SelectedSkill->Category), true, 15);
	AddDetailLine(TEXT(""), SelectedSkill->Description, false, 16);

	FSkillGestureHint GestureHint;
	if (TryGetSkillGestureHint(SelectedSkill->SkillId, GestureHint))
	{
		UBorder* GesturePanel = WidgetTree->ConstructWidget<UBorder>();
		GesturePanel->SetBrush(FSlateRoundedBoxBrush(FLinearColor(.20f, .12f, .045f, .10f), 5.f, FLinearColor(.44f, .28f, .10f, .34f), 1.f));
		GesturePanel->SetPadding(FMargin(12.f, 10.f));
		UVerticalBox* GestureContent = WidgetTree->ConstructWidget<UVerticalBox>();
		GesturePanel->SetContent(GestureContent);

		UTextBlock* GestureHeading = WidgetTree->ConstructWidget<UTextBlock>();
		GestureHeading->SetText(FText::FromString(TEXT("RIGHT-STICK SPELL GESTURE")));
		FSlateFontInfo GestureHeadingFont = FableBookStyle::Font(13, true);
		GestureHeadingFont.Size = 13;
		GestureHeading->SetFont(GestureHeadingFont);
		GestureHeading->SetColorAndOpacity(FSlateColor(CharacterMenuUiTextColor));
		GestureContent->AddChildToVerticalBox(GestureHeading)->SetPadding(FMargin(0.f, 0.f, 0.f, 4.f));

		UTextBlock* DPadInstruction = WidgetTree->ConstructWidget<UTextBlock>();
		DPadInstruction->SetText(FText::FromString(GestureHint.DPadInstruction));
		FSlateFontInfo DPadFont = FableBookStyle::Font(14, true);
		DPadFont.Size = 14;
		DPadInstruction->SetFont(DPadFont);
		DPadInstruction->SetColorAndOpacity(FSlateColor(CharacterMenuUiTextColor));
		GestureContent->AddChildToVerticalBox(DPadInstruction)->SetPadding(FMargin(0.f, 0.f, 0.f, 8.f));

		const bool bFontAwesomeAvailable = FPaths::FileExists(FPaths::ProjectContentDir() / TEXT("Slate/Fonts/FontAwesome.ttf"));
		const FSlateFontInfo GestureArrowFont = bFontAwesomeAvailable
			? JournalBookmarkFont(25)
			: FableBookStyle::Font(25, true);
		auto MakeGestureGlyph = [&](uint32 FontAwesomeCodepoint, const TCHAR* SafeGlyph) -> UTextBlock*
		{
			UTextBlock* Glyph = WidgetTree->ConstructWidget<UTextBlock>();
			Glyph->SetFont(GestureArrowFont);
			Glyph->SetText(FText::FromString(bFontAwesomeAvailable ? FString::Chr(FontAwesomeCodepoint) : FString(SafeGlyph)));
			Glyph->SetColorAndOpacity(FSlateColor(CharacterMenuUiMutedTextColor));
			Glyph->SetJustification(ETextJustify::Center);
			return Glyph;
		};
		auto AddGestureNode = [&](UHorizontalBox* Row, const TCHAR* Label, bool bStickNode, bool bWide)
		{
			USizeBox* NodeSize = WidgetTree->ConstructWidget<USizeBox>();
			NodeSize->SetWidthOverride(bWide ? 110.f : 52.f);
			NodeSize->SetHeightOverride(44.f);
			UBorder* Node = WidgetTree->ConstructWidget<UBorder>();
			Node->SetBrush(FSlateRoundedBoxBrush(bStickNode ? FLinearColor(.13f, .32f, .31f, .30f) : FLinearColor(.40f, .25f, .09f, .16f), 18.f,
				bStickNode ? FLinearColor(.16f, .55f, .52f, .80f) : FLinearColor(.54f, .35f, .13f, .65f), 1.f));
			Node->SetHorizontalAlignment(HAlign_Center);
			Node->SetVerticalAlignment(VAlign_Center);
			UTextBlock* LabelText = WidgetTree->ConstructWidget<UTextBlock>();
			LabelText->SetText(FText::FromString(Label));
			FSlateFontInfo LabelFont = FableBookStyle::Font(12, true);
			LabelFont.Size = 12;
			LabelText->SetFont(LabelFont);
			LabelText->SetColorAndOpacity(FSlateColor(CharacterMenuUiTextColor));
			LabelText->SetJustification(ETextJustify::Center);
			Node->SetContent(LabelText);
			NodeSize->SetContent(Node);
			if (UHorizontalBoxSlot* NodeSlot = Row->AddChildToHorizontalBox(NodeSize))
			{
				NodeSlot->SetVerticalAlignment(VAlign_Center);
				NodeSlot->SetPadding(FMargin(2.f, 0.f));
			}
		};
		auto AddGestureArrow = [&](UHorizontalBox* Row, uint32 FontAwesomeCodepoint, const TCHAR* SafeGlyph)
		{
			USizeBox* ArrowSize = WidgetTree->ConstructWidget<USizeBox>();
			ArrowSize->SetWidthOverride(42.f);
			ArrowSize->SetHeightOverride(44.f);
			ArrowSize->SetContent(MakeGestureGlyph(FontAwesomeCodepoint, SafeGlyph));
			if (UHorizontalBoxSlot* ArrowSlot = Row->AddChildToHorizontalBox(ArrowSize))
			{
				ArrowSlot->SetVerticalAlignment(VAlign_Center);
			}
		};

		UHorizontalBox* GestureDiagram = WidgetTree->ConstructWidget<UHorizontalBox>();
		if (GestureHint.bCircular)
		{
			AddGestureNode(GestureDiagram, TEXT("RS"), true, false);
			AddGestureArrow(GestureDiagram, 0xF01E, TEXT("O"));
			AddGestureNode(GestureDiagram, TEXT("FULL CIRCLE"), false, true);
		}
		else
		{
			AddGestureNode(GestureDiagram, TEXT("RS"), true, false);
			AddGestureArrow(GestureDiagram, 0xF061, TEXT(">"));
			AddGestureNode(GestureDiagram, TEXT("OUT"), false, false);
			AddGestureArrow(GestureDiagram, 0xF060, TEXT("<"));
			AddGestureNode(GestureDiagram, TEXT("CENTER"), false, true);
		}
		UVerticalBoxSlot* DiagramSlot = GestureContent->AddChildToVerticalBox(GestureDiagram);
		DiagramSlot->SetHorizontalAlignment(HAlign_Center);
		DiagramSlot->SetPadding(FMargin(0.f, 0.f, 0.f, 8.f));

		UTextBlock* GestureInstruction = WidgetTree->ConstructWidget<UTextBlock>();
		GestureInstruction->SetText(FText::FromString(GestureHint.Instruction));
		FSlateFontInfo GestureInstructionFont = FableBookStyle::Font(14, false);
		GestureInstructionFont.Size = 14;
		GestureInstruction->SetFont(GestureInstructionFont);
		GestureInstruction->SetColorAndOpacity(FSlateColor(CharacterMenuUiTextColor));
		GestureInstruction->SetAutoWrapText(true);
		GestureContent->AddChildToVerticalBox(GestureInstruction);

		DetailsVBox->AddChildToVerticalBox(GesturePanel)->SetPadding(FMargin(0.f, 2.f, 0.f, 10.f));
	}

	AddDetailLine(TEXT("Target"), EnumToString(SelectedSkill->TargetingMode));

	FString CostText = SelectedSkill->ResourceType == EFableSkillResourceType::None
		? TEXT("No resource cost")
		: FString::Printf(TEXT("%.0f %s"), SelectedSkill->ResourceCost, *EnumToString(SelectedSkill->ResourceType));
	if (SelectedSkill->SkillId == TEXT("slow_time")) CostText = TEXT("Drains Cosmic while active");
	AddDetailLine(TEXT("Cost"), CostText);
	if (SelectedSkill->CooldownSeconds > 0.f) AddDetailLine(TEXT("Cooldown"), FString::Printf(TEXT("%.1f s"), SelectedSkill->CooldownSeconds));
	AddDetailLine(TEXT("Range"), FString::Printf(TEXT("%.1f m"), SelectedSkill->RangeUnits / 100.f));
	if (SelectedSkill->RadiusUnits > 0.0f)
	{
		AddDetailLine(TEXT("Radius"), FString::Printf(TEXT("%.1f m"), SelectedSkill->RadiusUnits / 100.f));
	}

	FString ScalingText = SelectedSkill->ScalingPrimaryStat.IsEmpty()
		? TEXT("None")
		: FString::Printf(TEXT("%s x%.2f"), *HumanizeToken(SelectedSkill->ScalingPrimaryStat), SelectedSkill->ScalingPrimaryCoefficient);
	if (!SelectedSkill->ScalingSecondaryStat.IsEmpty())
	{
		ScalingText += FString::Printf(TEXT(", %s x%.2f"), *HumanizeToken(SelectedSkill->ScalingSecondaryStat), SelectedSkill->ScalingSecondaryCoefficient);
	}
	if (!SelectedSkill->ScalingPrimaryStat.IsEmpty()) AddDetailLine(TEXT("Scaling"), ScalingText);
}

void UFableCharacterMenuWidget::LoadSkillDefinitionsFromDataTable()
{
	if (bSkillDefinitionsLoaded)
	{
		return;
	}

	SkillDefinitions.Reset();

	if (UDataTable* SkillsTable = LoadObject<UDataTable>(nullptr, CharacterMenuSkillsDataTablePath))
	{
		static const FString ContextString(TEXT("UFableCharacterMenuWidget::LoadSkillDefinitionsFromDataTable"));
		TArray<FFableSkillDefinitionTableRow*> Rows;
		SkillsTable->GetAllRows(ContextString, Rows);

		for (const FFableSkillDefinitionTableRow* Row : Rows)
		{
			if (Row == nullptr || Row->SkillId.IsEmpty())
			{
				continue;
			}

			SkillDefinitions.Add(Row->SkillId, *Row);
		}
	}
	else
	{
		UE_LOG(LogFableForge, Warning, TEXT("Skills DataTable not found at '%s'."), CharacterMenuSkillsDataTablePath);
	}

	// Starter schools are available without requiring an editor CSV reimport.
	for (const auto& Starter : FableSkillCatalog::GetStarterSkills())
	{
		FFableSkillDefinitionTableRow Definition;
		if (FableSkillCatalog::TryGetStarterSkillDefinition(Starter.SkillId, Definition)) SkillDefinitions.Add(Starter.SkillId, Definition);
	}
	bSkillDefinitionsLoaded = true;
}

const FFableSkillDefinitionTableRow* UFableCharacterMenuWidget::FindSkillDefinition(const FString& SkillId) const
{
	return SkillDefinitions.Find(SkillId);
}

void UFableCharacterMenuWidget::LoadInventoryFromSave()
{
	if (bInventoryLoaded)
	{
		return;
	}

	InventorySlots.Reset();
	InventoryQuantities.Reset();
	EquippedSlots.Reset();
	InventorySlots.SetNum(UFableSaveSubsystem::InventorySlotsPerCharacter);
	EquippedSlots.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);

	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		TArray<FString> SavedInventory;
		TArray<FString> SavedEquipment;
		if (SaveSubsystem->TryGetActiveInventory(SavedInventory, SavedEquipment))
		{
			InventorySlots = SavedInventory;
			SaveSubsystem->TryGetActiveInventoryQuantities(InventoryQuantities);
			EquippedSlots = SavedEquipment;
		}
	}

	if (InventorySlots.Num() != UFableSaveSubsystem::InventorySlotsPerCharacter)
	{
		InventorySlots.SetNum(UFableSaveSubsystem::InventorySlotsPerCharacter);
	}
	if (EquippedSlots.Num() != UFableSaveSubsystem::EquipmentSlotsPerCharacter)
	{
		EquippedSlots.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);
	}
	InventoryQuantities.SetNum(InventorySlots.Num());
	for (int32 Index = 0; Index < InventorySlots.Num(); ++Index)
		InventoryQuantities[Index] = InventorySlots[Index].IsEmpty() ? 0 : FMath::Max(1, InventoryQuantities[Index]);

	bInventoryLoaded = true;
}

void UFableCharacterMenuWidget::SaveInventoryToSaveSubsystem()
{
	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem != nullptr && SaveSubsystem->SetActiveInventory(InventorySlots, EquippedSlots, InventoryQuantities))
	{
		SaveSubsystem->TryGetActiveInventory(InventorySlots, EquippedSlots);
		SaveSubsystem->TryGetActiveInventoryQuantities(InventoryQuantities);
		InventorySaveWarning.Reset();
		return;
	}

	// The subsystem rolls back failed writes. Discard the optimistic UI swap too,
	// before rebuilding widgets, so subsequent drags cannot save a failed move.
	bInventoryLoaded = false;
	LoadInventoryFromSave();
	InventorySaveWarning = TEXT("Item move could not be saved. Check available disk space and save-folder permissions, then try again.");
	UE_LOG(LogFableForge, Warning, TEXT("%s Inventory reloaded from the active character."), *InventorySaveWarning);
}

void UFableCharacterMenuWidget::LoadItemDefinitionsFromUnityJson()
{
	if (bItemDefinitionsLoaded)
	{
		return;
	}

	ItemDefinitions.Reset();
	IconTextureCache.Reset();

	auto AddDefinition = [&](const FFableUiItemDefinition& Definition)
	{
		if (Definition.Id.IsEmpty())
		{
			return;
		}

		ItemDefinitions.Add(Definition.Id, Definition);
	};

	auto LoadDefinitionsFromTable = [&](const TCHAR* TablePath, const TCHAR* TableLabel) -> bool
	{
		UDataTable* ItemDefinitionsTable = LoadObject<UDataTable>(nullptr, TablePath);
		if (ItemDefinitionsTable == nullptr)
		{
			UE_LOG(LogFableForge, Warning, TEXT("%s DataTable not found at '%s'."), TableLabel, TablePath);
			return false;
		}

		const FString ContextString = FString::Printf(TEXT("UFableCharacterMenuWidget::LoadItemDefinitionsFromUnityJson(%s)"), TableLabel);
		TArray<FFableItemDefinitionTableRow*> Rows;
		ItemDefinitionsTable->GetAllRows(ContextString, Rows);

		const FString Label = TableLabel;
		const bool bIsWeaponsTable = Label.Equals(TEXT("Weapons"));
		const bool bIsArmorTable = Label.Equals(TEXT("Armor"));

		for (const FFableItemDefinitionTableRow* Row : Rows)
		{
			if (Row == nullptr)
			{
				continue;
			}

			FFableUiItemDefinition Definition;
			Definition.Id = Row->ItemId;
			if (Definition.Id.IsEmpty())
			{
				continue;
			}

			Definition.Name = !Row->DisplayName.IsEmpty() ? Row->DisplayName : Definition.Id;
			Definition.Category = CategoryFromType(Row->Type);
			Definition.bStackable = Row->bStackable;
			Definition.bEquipable = Row->bEquipable;
			if (bIsWeaponsTable)
			{
				const FString LowerId = Definition.Id.ToLower();
				Definition.EquipmentSlot = (LowerId.Contains(TEXT("bow")) || LowerId.Contains(TEXT("crossbow"))) ? 11 : 0;
			}
			else if (bIsArmorTable)
			{
				const FString LowerId = Definition.Id.ToLower();
				if (LowerId.EndsWith(TEXT("_offhand")) || LowerId.EndsWith(TEXT("_off_hand")) || LowerId.Contains(TEXT("shield")))
				{
					Definition.EquipmentSlot = 1;
				}
				else if (LowerId.EndsWith(TEXT("_back")))
				{
					Definition.EquipmentSlot = 7;
				}
				else if (LowerId.EndsWith(TEXT("_neck")) || LowerId.Contains(TEXT("amulet")) || LowerId.Contains(TEXT("necklace")))
				{
					Definition.EquipmentSlot = 8;
				}
				else if (LowerId.Contains(TEXT("ring")))
				{
					Definition.EquipmentSlot = 9;
				}
				else
				{
					FString Left;
					FString Right;
					Definition.EquipmentSlot = Definition.Id.Split(TEXT("_"), &Left, &Right, ESearchCase::IgnoreCase, ESearchDir::FromEnd)
						? ArmorSlotIndexFromString(Right)
						: INDEX_NONE;
				}
			}
			else
			{
				Definition.EquipmentSlot = INDEX_NONE;
			}
			Definition.IconAssetPath = Row->IconTexture.ToSoftObjectPath().ToString();
			Definition.IconToken = BuildIconToken(Definition.Name);
			Definition.ModelPath.Reset();
			Definition.ModelPathMale.Reset();
			Definition.ModelPathFemale.Reset();
			AddDefinition(Definition);
		}

		return true;
	};

	const bool bLoadedAny =
		LoadDefinitionsFromTable(ItemsDataTablePath, TEXT("Items")) |
		LoadDefinitionsFromTable(WeaponsDataTablePath, TEXT("Weapons")) |
		LoadDefinitionsFromTable(ArmorDataTablePath, TEXT("Armor"));

	if (!bLoadedAny)
	{
		UE_LOG(LogFableForge, Warning, TEXT("No item definition DataTables were loaded. Expected '%s', '%s', '%s'."),
			ItemsDataTablePath, WeaponsDataTablePath, ArmorDataTablePath);
	}

	bItemDefinitionsLoaded = true;
}

void UFableCharacterMenuWidget::RefreshInventorySlotWidgets()
{
	for (TPair<FName, TObjectPtr<UFableInventorySlotWidget>>& Pair : SlotWidgets)
	{
		const FName SlotId = Pair.Key;
		UFableInventorySlotWidget* SlotWidget = Pair.Value;
		if (SlotWidget == nullptr)
		{
			continue;
		}

		bool bEquipmentSlot = false;
		int32 SlotIndex = INDEX_NONE;
		if (!ResolveSlotAddress(SlotId, bEquipmentSlot, SlotIndex))
		{
			continue;
		}

		const TArray<FString>& SourceArray = bEquipmentSlot ? EquippedSlots : InventorySlots;
		if (!SourceArray.IsValidIndex(SlotIndex))
		{
			continue;
		}

		const FString ItemId = SourceArray[SlotIndex];
		if (!bEquipmentSlot && ActiveInventoryCategory != CategoryAllAction && !ItemId.IsEmpty() && ResolveItemCategory(ItemId) != ActiveInventoryCategory)
		{
			SlotWidget->SetItemData(TEXT(""), TEXT(""), nullptr);
			continue;
		}

		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, bEquipmentSlot), GetItemIconForSlot(ItemId));
		SlotWidget->SetItemQuantity(!bEquipmentSlot && InventoryQuantities.IsValidIndex(SlotIndex) ? InventoryQuantities[SlotIndex] : 1);
	}
}

void UFableCharacterMenuWidget::RefreshInventoryPresentation()
{
	RefreshInventorySlotWidgets();
	for (const auto& Entry : InventoryCategoryButtons)
		if (Entry.Value) StyleJournalTab(Entry.Value, Entry.Key==ActiveInventoryCategory, true);
	int32 Occupied=0;
	TArray<int32> Visible;
	TArray<int32> Empty;
	int32 LastOccupied=INDEX_NONE;
	for (int32 Index=0;Index<InventorySlots.Num();++Index)
	{
		const FString& Item=InventorySlots[Index];
		if (Item.IsEmpty()) { Empty.Add(Index); continue; }
		++Occupied; LastOccupied=Index;
		if (ActiveInventoryCategory==CategoryAllAction || ResolveItemCategory(Item)==ActiveInventoryCategory) Visible.Add(Index);
	}
	if (ActiveInventoryCategory==CategoryAllAction)
	{
		// Stable physical bag positions: moving an item into an empty cell must
		// not sort it back to the start of the bag on the next frame.
		const int32 Count=FMath::Min(InventorySlots.Num(),FMath::Max(20,((LastOccupied+6+4)/5)*5));
		Visible.Reset();
		for (int32 Index=0;Index<Count;++Index) Visible.Add(Index);
	}
	else
	{
		const int32 Count=FMath::Min(InventorySlots.Num(),FMath::Max(20,((Visible.Num()+5+4)/5)*5));
		for (int32 Index : Empty) { if (Visible.Num()>=Count) break; Visible.Add(Index); }
	}
	for (const auto& Entry : InventoryCells)
	{
		USizeBox* Cell=Entry.Value;
		if (!Cell) continue;
		const int32 DisplayIndex=Visible.IndexOfByKey(Entry.Key);
		Cell->SetVisibility(DisplayIndex==INDEX_NONE ? ESlateVisibility::Collapsed : ESlateVisibility::SelfHitTestInvisible);
		if (DisplayIndex != INDEX_NONE)
			if (UFableInventorySlotWidget* SlotWidget = SlotWidgets.FindRef(FName(*FString::Printf(TEXT("inv_%d"), Entry.Key))))
				SlotWidget->SetJournalGridCell(DisplayIndex % 5, DisplayIndex / 5, 5, FMath::DivideAndRoundUp(Visible.Num(), 5));
		if (DisplayIndex!=INDEX_NONE)
			if (UUniformGridSlot* Slot=Cast<UUniformGridSlot>(Cell->Slot)) { Slot->SetRow(DisplayIndex/5); Slot->SetColumn(DisplayIndex%5); }
	}
	ControllerVisibleInventory = Visible;
	RefreshControllerSelection();
	if (InventoryHeading) InventoryHeading->SetText(FText::FromString(FString::Printf(TEXT("Inventory     %d / %d"),Occupied,InventorySlots.Num())));
	if (InventoryStatus)
	{
		InventoryStatus->SetVisibility(InventorySaveWarning.IsEmpty() ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
		InventoryStatus->SetText(FText::FromString(InventorySaveWarning.IsEmpty() ? TEXT("Drag items to move or equip them. Hover for details.") : InventorySaveWarning));
		InventoryStatus->SetColorAndOpacity(FSlateColor(InventorySaveWarning.IsEmpty() ? CharacterMenuUiMutedTextColor : FLinearColor(.48f,.065f,.025f,1.f)));
	}
}

void UFableCharacterMenuWidget::RefreshSkillsPresentation()
{
	TArray<FString> Visible;
	for (const FString& Id : DisplayedSkillOrder)
	{
		const FFableSkillDefinitionTableRow* Definition=FindSkillDefinition(Id);
		if (ActiveSkillCategory==SkillCategoryAllAction || (Definition && SkillCategoryActionFromEnum(Definition->Category)==ActiveSkillCategory)) Visible.Add(Id);
	}
	if (!Visible.Contains(ActiveSkillDetailsId)) ActiveSkillDetailsId=Visible.IsEmpty() ? FString() : Visible[0];
	for (const auto& Entry : SkillCategoryButtons)
		if (Entry.Value) StyleJournalTab(Entry.Value, Entry.Key==ActiveSkillCategory, true);
	for (const auto& Entry : SkillRows)
	{
		if (!Entry.Value) continue;
		Entry.Value->SetVisibility(Visible.Contains(Entry.Key) ? ESlateVisibility::SelfHitTestInvisible : ESlateVisibility::Collapsed);
		Entry.Value->SetBrushColor(Entry.Key==ActiveSkillDetailsId ? FLinearColor(.45f, .27f, .1f, .12f) : FLinearColor::Transparent);
	}
	RefreshSkillDetails();
}

bool UFableCharacterMenuWidget::ResolveSlotAddress(FName SlotId, bool& bOutEquipmentSlot, int32& OutSlotIndex) const
{
	bOutEquipmentSlot = false;
	OutSlotIndex = INDEX_NONE;

	const FString SlotString = SlotId.ToString();
	FString Prefix;
	FString IndexString;
	if (!SlotString.Split(TEXT("_"), &Prefix, &IndexString, ESearchCase::CaseSensitive, ESearchDir::FromEnd))
	{
		return false;
	}

	int32 ParsedIndex = INDEX_NONE;
	if (!LexTryParseString(ParsedIndex, *IndexString))
	{
		return false;
	}

	if (Prefix == TEXT("equip"))
	{
		bOutEquipmentSlot = true;
		OutSlotIndex = ParsedIndex;
		return true;
	}

	if (Prefix == TEXT("inv"))
	{
		bOutEquipmentSlot = false;
		OutSlotIndex = ParsedIndex;
		return true;
	}

	return false;
}

bool UFableCharacterMenuWidget::IsItemAllowedInEquipmentSlot(const FString& ItemId, int32 EquipmentSlotIndex) const
{
	if (ItemId.IsEmpty())
	{
		return true;
	}

	const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId);
	if (Definition != nullptr && !Definition->bEquipable)
	{
		return false;
	}

	// Keep the equip target usable even when a newly imported armor row has not
	// populated its derived slot yet. The item ids are authoritative for the
	// lower-body pieces and match the equipment layout (legs=5, feet=6).
	int32 ItemEquipmentSlot = Definition != nullptr ? Definition->EquipmentSlot : INDEX_NONE;
	if (ItemEquipmentSlot == INDEX_NONE)
	{
		FString Left;
		FString Right;
		if (ItemId.Split(TEXT("_"), &Left, &Right, ESearchCase::IgnoreCase, ESearchDir::FromEnd))
		{
			ItemEquipmentSlot = ArmorSlotIndexFromString(Right);
		}
	}

	if (ItemEquipmentSlot == EquipmentSlotIndex)
	{
		return true;
	}

	// Allow rings in either ring slot.
	if (IsRingEquipmentSlotIndex(ItemEquipmentSlot) && IsRingEquipmentSlotIndex(EquipmentSlotIndex))
	{
		return true;
	}

	return false;
}

FString UFableCharacterMenuWidget::GetItemLabelForSlot(const FString& ItemId, bool bEquipmentSlot) const
{
	if (ItemId.IsEmpty())
	{
		return TEXT("");
	}

	if (const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId))
	{
		if (!Definition->Name.IsEmpty())
		{
			return Definition->Name;
		}
	}

	return bEquipmentSlot ? ItemId : ItemId;
}

UTexture2D* UFableCharacterMenuWidget::GetItemIconForSlot(const FString& ItemId)
{
	if (ItemId.IsEmpty())
	{
		return nullptr;
	}

	if (TObjectPtr<UTexture2D>* CachedTexture = IconTextureCache.Find(ItemId))
	{
		return CachedTexture->Get();
	}

	const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId);
	if (Definition == nullptr || Definition->IconAssetPath.IsEmpty())
	{
		IconTextureCache.Add(ItemId, nullptr);
		return nullptr;
	}

	UTexture2D* Texture = LoadObject<UTexture2D>(nullptr, *Definition->IconAssetPath);
	IconTextureCache.Add(ItemId, Texture);
	return Texture;
}

FName UFableCharacterMenuWidget::ResolveItemCategory(const FString& ItemId) const
{
	if (ItemId.IsEmpty())
	{
		return CategoryMiscAction;
	}

	if (const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId))
	{
		return Definition->Category;
	}

	return CategoryMiscAction;
}

void UFableCharacterMenuWidget::HandleInventorySlotDropped(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel)
{
	(void)PayloadId;
	(void)PayloadLabel;
	// The menu owns the slot map, so it is the reliable place to clear the
	// source drag state even when Slate rejects the destination slot.
	if (UFableInventorySlotWidget* SourceWidget = SlotWidgets.FindRef(FromSlotId))
	{
		SourceWidget->ResetDragVisual();
	}

	bool bFromEquipment = false;
	int32 FromIndex = INDEX_NONE;
	bool bToEquipment = false;
	int32 ToIndex = INDEX_NONE;

	if (!ResolveSlotAddress(FromSlotId, bFromEquipment, FromIndex) || !ResolveSlotAddress(ToSlotId, bToEquipment, ToIndex))
	{
		UE_LOG(LogFableForge, Warning, TEXT("Inventory drop rejected: invalid slot address from=%s to=%s"), *FromSlotId.ToString(), *ToSlotId.ToString());
		return;
	}

	TArray<FString>& FromArray = bFromEquipment ? EquippedSlots : InventorySlots;
	TArray<FString>& ToArray = bToEquipment ? EquippedSlots : InventorySlots;
	if (!FromArray.IsValidIndex(FromIndex) || !ToArray.IsValidIndex(ToIndex))
	{
		UE_LOG(LogFableForge, Warning, TEXT("Inventory drop rejected: out-of-range slot from=%s to=%s"), *FromSlotId.ToString(), *ToSlotId.ToString());
		return;
	}

	const FString SourceItemId = FromArray[FromIndex];
	const FString DestinationItemId = ToArray[ToIndex];
	if (SourceItemId.IsEmpty() || FromSlotId == ToSlotId)
	{
		return;
	}

	if (bToEquipment && !IsItemAllowedInEquipmentSlot(SourceItemId, ToIndex))
	{
		UE_LOG(LogFableForge, Log, TEXT("Inventory drop rejected: item '%s' cannot equip in slot %d"), *SourceItemId, ToIndex);
		return;
	}

	if (bFromEquipment && !DestinationItemId.IsEmpty() && !IsItemAllowedInEquipmentSlot(DestinationItemId, FromIndex))
	{
		UE_LOG(LogFableForge, Log, TEXT("Inventory drop rejected: swap item '%s' cannot equip in slot %d"), *DestinationItemId, FromIndex);
		return;
	}

	InventoryQuantities.SetNum(InventorySlots.Num());
	const int32 SourceQuantity = bFromEquipment ? 1 : FMath::Max(1, InventoryQuantities[FromIndex]);
	const int32 DestinationQuantity = DestinationItemId.IsEmpty() ? 0 : (bToEquipment ? 1 : FMath::Max(1, InventoryQuantities[ToIndex]));
	const auto* Saves = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (!bFromEquipment && !bToEquipment && SourceItemId.Equals(DestinationItemId, ESearchCase::IgnoreCase)
		&& Saves && Saves->IsItemStackable(SourceItemId))
	{
		const int32 Moved = FMath::Min(SourceQuantity, MAX_int32 - DestinationQuantity);
		InventoryQuantities[ToIndex] = DestinationQuantity + Moved;
		InventoryQuantities[FromIndex] = SourceQuantity - Moved;
		if (InventoryQuantities[FromIndex] == 0) FromArray[FromIndex].Reset();
	}
	else
	{
		// Equipped slots hold one item; reject a multi-item stack rather than lose
		// the remainder if a future stackable definition also permits equipment.
		if ((bToEquipment && SourceQuantity > 1) || (bFromEquipment && DestinationQuantity > 1)) return;
		FromArray[FromIndex] = DestinationItemId;
		ToArray[ToIndex] = SourceItemId;
		if (!bFromEquipment) InventoryQuantities[FromIndex] = DestinationQuantity;
		if (!bToEquipment) InventoryQuantities[ToIndex] = SourceQuantity;
	}
	SaveInventoryToSaveSubsystem();

	RefreshInventoryPresentation();
}

void UFableCharacterMenuWidget::HandleActionClicked(FName ActionId)
{
	if (ActionId.ToString().StartsWith(TEXT("item_")))
	{
		if (!ItemActionsLayer) return;
		if (ActionId == TEXT("item_cancel")) { CloseItemActions(); return; }
		bool bEquipment = false; int32 Index = INDEX_NONE;
		if (!ResolveSlotAddress(ItemActionSource, bEquipment, Index)) { CloseItemActions(); return; }
		const auto& Slots = bEquipment ? EquippedSlots : InventorySlots;
		if (!Slots.IsValidIndex(Index) || Slots[Index] != ItemActionIdentity) { CloseItemActions(); return; }
		if (ActionId == TEXT("item_move"))
		{
			ControllerPickedSlot = ItemActionSource; ControllerSlotId = ItemActionSource;
			CloseItemActions(); RefreshControllerSelection(); return;
		}
		if (ActionId == TEXT("item_equip"))
		{
			int32 Destination = INDEX_NONE;
			if (bEquipment) Destination = InventorySlots.IndexOfByPredicate([](const FString& Value) { return Value.IsEmpty(); });
			else
			{
				for (int32 I=0; I<EquippedSlots.Num(); ++I)
				{
					if (!IsItemAllowedInEquipmentSlot(ItemActionIdentity,I)) continue;
					if (Destination == INDEX_NONE) Destination = I;
					if (EquippedSlots[I].IsEmpty()) { Destination = I; break; }
				}
			}
			if (Destination == INDEX_NONE)
			{
				ItemActionStatus = bEquipment ? TEXT("Your backpack is full.") : TEXT("This item has no matching equipment slot.");
				RebuildItemActions(); return;
			}
			const FName Target(*(bEquipment ? FString::Printf(TEXT("inv_%d"), Destination) : FString::Printf(TEXT("equip_%d"), Destination)));
			HandleInventorySlotDropped(ItemActionSource, Target, ItemActionIdentity, FString());
			// Keep the active square on the original inventory item after Equip;
			// moving focus to the destination equipment slot makes repeated actions
			// unexpectedly jump across the journal.
			ControllerSlotId = ItemActionSource; ControllerPickedSlot = NAME_None;
			CloseItemActions(); RefreshControllerSelection(); return;
		}
		if (ActionId == TEXT("item_consume"))
		{
			auto* PC = Cast<AFableForgePlayerController>(GetOwningPlayer());
			if (bEquipment || !PC || !PC->ConsumeInventoryItem(Index))
			{
				ItemActionStatus = TEXT("This item cannot be used right now. Its resource may already be full."); RebuildItemActions(); return;
			}
			bInventoryLoaded = false; LoadInventoryFromSave(); CloseItemActions(); RefreshInventoryPresentation(); return;
		}
		if (ActionId == TEXT("item_assign"))
		{
			const FString Payload = TEXT("item:") + ItemActionIdentity;
			CloseItemActions();
			if (auto* PC = Cast<AFableForgePlayerController>(GetOwningPlayer())) PC->OpenWheelAssignmentForPayload(Payload);
			return;
		}
		if (ActionId == TEXT("item_drop")) { bConfirmItemDrop = true; ItemActionSelection = 1; RebuildItemActions(); return; }
		if (ActionId == TEXT("item_drop_confirm"))
		{
			APawn* Pawn = GetOwningPlayerPawn();
			UFableSaveSubsystem* Saves = GetGameInstance()->GetSubsystem<UFableSaveSubsystem>();
			if (!Pawn || !Saves) return;
			const FVector Forward = Pawn->GetActorForwardVector().GetSafeNormal2D();
			FVector Position = Pawn->GetActorLocation() + Forward*100.f;
			FHitResult Floor; FCollisionQueryParams Params(SCENE_QUERY_STAT(ItemDrop),false,Pawn);
			FHitResult Obstruction;
			if (GetWorld()->SweepSingleByChannel(Obstruction, Pawn->GetActorLocation(), Position, FQuat::Identity, ECC_Visibility, FCollisionShape::MakeSphere(24.f), Params))
				Position = Obstruction.Location - Forward*24.f;
			if (!GetWorld()->LineTraceSingleByChannel(Floor, Position+FVector(0,0,40), Position-FVector(0,0,220), ECC_Visibility, Params)
				|| Floor.ImpactNormal.Z < .65f || FVector::Dist(Pawn->GetActorLocation(), Floor.ImpactPoint) > 180.f)
			{
				ItemActionStatus = TEXT("There is no safe ground nearby to drop this item."); RebuildItemActions(); return;
			}
			FActorSpawnParameters Spawn; Spawn.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
			const FVector DropPosition = Floor.ImpactPoint+FVector(0,0,26);
			AFFItemInteractable* Drop = GetWorld()->SpawnActor<AFFItemInteractable>(DropPosition, FRotator::ZeroRotator, Spawn);
			const int32 DropQuantity = !bEquipment && InventoryQuantities.IsValidIndex(Index) ? InventoryQuantities[Index] : 1;
			if (!Drop || !Drop->InitializeDroppedItem(ItemActionIdentity, DropQuantity))
			{
				if (Drop) Drop->Destroy(); ItemActionStatus = TEXT("Unable to place this item in the world."); RebuildItemActions(); return;
			}
			Params.AddIgnoredActor(Drop);
			FHitResult Visibility;
			if (GetWorld()->OverlapBlockingTestByChannel(DropPosition, FQuat::Identity, ECC_Visibility, FCollisionShape::MakeSphere(22.f), Params)
				|| GetWorld()->LineTraceSingleByChannel(Visibility, Pawn->GetActorLocation(), DropPosition, ECC_Visibility, Params))
			{
				Drop->Destroy(); ItemActionStatus = TEXT("There is not enough clear space to drop this item safely."); RebuildItemActions(); return;
			}
			TArray<FString> NewBag = InventorySlots, NewEquipment = EquippedSlots;
			TArray<int32> NewQuantities = InventoryQuantities;
			(bEquipment ? NewEquipment : NewBag)[Index].Reset();
			if (!bEquipment && NewQuantities.IsValidIndex(Index)) NewQuantities[Index] = 0;
			if (!Saves->SetActiveInventory(NewBag,NewEquipment,NewQuantities))
			{
				Drop->Destroy(); ItemActionStatus = TEXT("The drop could not be saved. Your item has not been removed."); RebuildItemActions(); return;
			}
			UE_LOG(LogFableForge,Display,TEXT("JOURNAL dropped=%s actor=%s"),*ItemActionIdentity,*Drop->GetName());
			bInventoryLoaded = false; LoadInventoryFromSave();
			CloseItemActions(); RefreshInventoryPresentation(); return;
		}
		return;
	}
	if (HasItemModal()) return;
	if (ActionId == SettingsAction)
	{
		ActiveTab = TEXT("settings"); SettingsPage = NAME_None; SettingsSelection = 0;
		ControllerPickedSlot = NAME_None; QueueTabContentRebuild(); return;
	}
	if (ActionId.ToString().StartsWith(TEXT("settings_")))
	{
		UFableSaveSubsystem* Saves = GetGameInstance()->GetSubsystem<UFableSaveSubsystem>();
		if (!Saves) return;
		if (ActionId == TEXT("settings_back")) { SettingsPage = NAME_None; SettingsStatus.Reset(); }
		else if (ActionId == TEXT("settings_save")) { SettingsPage = TEXT("save"); SettingsStatus.Reset(); }
		else if (ActionId == TEXT("settings_load")) { SettingsLoadCharacter = Saves->GetActiveCharacterId(); SettingsPage = TEXT("load"); SettingsStatus.Reset(); }
		else if (ActionId == TEXT("settings_quit")) { SettingsPage = TEXT("quit"); }
		else if (ActionId == TEXT("settings_quit_confirm"))
		{
			Close();
			if (auto* PC = Cast<AFableForgePlayerController>(GetOwningPlayer())) PC->ShowMainMenu();
			return;
		}
		else if (const int32* Slot = SettingsSlots.Find(ActionId))
		{
			if (SettingsPage == TEXT("save"))
			{
				const bool bSaved = Saves->SaveCharacterToSlot(Saves->GetActiveCharacterId(), *Slot, GetWorld()->GetMapName());
				SettingsStatus = bSaved ? TEXT("Game saved.") : TEXT("Save failed. Please check available disk space and permissions.");
			}
			else if (SettingsPage == TEXT("load"))
			{
				const int32 SlotIndex = *Slot;
				TArray<FFableSaveSlotMeta> Slots;
				Saves->GetSaveSlots(SettingsLoadCharacter, Slots);
				const FFableSaveSlotMeta* Meta = Slots.FindByPredicate([SlotIndex](const auto& Entry) { return Entry.SlotIndex == SlotIndex; });
				if (!Meta || !Meta->bHasSave)
				{
					SettingsStatus = TEXT("This slot is empty.");
					QueueTabContentRebuild(); return;
				}
				if (auto* PC = Cast<AFableForgePlayerController>(GetOwningPlayer())) PC->EnterGameFromCharacterSlot(SettingsLoadCharacter, SlotIndex, false);
				return;
			}
		}
		SettingsSelection = 0; QueueTabContentRebuild(); return;
	}
	if (ActionId == InventoryAction || ActionId == SkillsAction || ActionId == CompanionsAction || ActionId == BuildAction)
	{
		bSkillContextVisible = false;
		ContextSkillId.Reset();
		ControllerPickedSlot = NAME_None;
	}
	if (ActionId == CloseMenuAction)
	{
		if (AFableForgePlayerController* ForgePC = Cast<AFableForgePlayerController>(GetOwningPlayer()))
		{
			if (UWorld* World = GetWorld())
			{
				World->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateUObject(ForgePC, &AFableForgePlayerController::ToggleCharacterMenu));
			}
			else
			{
				ForgePC->ToggleCharacterMenu();
			}
		}
		else if (UWorld* World = GetWorld())
		{
			World->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateUObject(this, &UFableCharacterMenuWidget::Close));
		}
		else
		{
			Close();
		}
		return;
	}

	if (ActionId == InventoryAction)
	{
		if (ActiveTab == TEXT("inventory")) return;
		ActiveTab = TEXT("inventory");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == SkillsAction)
	{
		if (ActiveTab == TEXT("skills")) return;
		ActiveTab = TEXT("skills");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == CompanionsAction)
	{
		if (ActiveTab == TEXT("companions")) return;
		ActiveTab = TEXT("companions");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == BuildAction)
	{
		if (ActiveTab == TEXT("build")) return;
		ActiveTab = TEXT("build");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == CategoryAllAction || ActionId == CategoryWeaponsAction || ActionId == CategoryArmorAction || ActionId == CategoryConsumablesAction || ActionId == CategoryMiscAction || ActionId == CategoryKeyItemsAction)
	{
		if (ActiveInventoryCategory == ActionId) return;
		ActiveInventoryCategory = ActionId;
		if (ActiveTab == TEXT("inventory"))
		{
			RefreshInventoryPresentation();
		}
		return;
	}

	FName SkillCategoryAction;
	if (TryParseSkillCategoryAction(ActionId, SkillCategoryAction))
	{
		if (ActiveSkillCategory == SkillCategoryAction) return;
		ActiveSkillCategory = SkillCategoryAction;
		if (ActiveTab == TEXT("skills"))
		{
			RefreshSkillsPresentation();
		}
		return;
	}

	if (ActionId == CancelSkillContextAction)
	{
		bSkillContextVisible = false;
		ContextSkillId.Reset();
		QueueTabContentRebuild();
		return;
	}

	const FString ActionString = ActionId.ToString();
	if (ActionString.StartsWith(AssignSkillActionPrefix))
	{
		const FString SkillId = ActionString.RightChop(FCString::Strlen(AssignSkillActionPrefix));
		if (AFableForgePlayerController* ForgePC = Cast<AFableForgePlayerController>(GetOwningPlayer()))
		{
			bSkillContextVisible = false;
			ContextSkillId.Reset();
			ForgePC->OpenWheelAssignmentForPayload(TEXT("skill:") + SkillId);
		}
		return;
	}

	if (const FString* SkillId = SkillRowActions.Find(ActionId))
	{
		if (!SkillId->IsEmpty() && *SkillId != ActiveSkillDetailsId)
		{
			ActiveSkillDetailsId = *SkillId;
			RefreshSkillsPresentation();
		}
	}
}

void UFableCharacterMenuWidget::HandleSkillSlotHovered(FName SlotId, const FString& PayloadId)
{
	(void)SlotId;

	if (ActiveTab != TEXT("skills") || PayloadId.IsEmpty())
	{
		return;
	}

	FString SkillId = PayloadId;
	SkillId.RemoveFromStart(TEXT("skill:"));
	if (SkillId.IsEmpty() || SkillId == ActiveSkillDetailsId)
	{
		return;
	}

	ActiveSkillDetailsId = SkillId;
	RefreshSkillsPresentation();
}

void UFableCharacterMenuWidget::HandleSkillSlotClicked(FName SlotId, const FString& PayloadId)
{
	(void)SlotId;

	if (ActiveTab != TEXT("skills") || PayloadId.IsEmpty())
	{
		return;
	}

	FString SkillId = PayloadId;
	SkillId.RemoveFromStart(TEXT("skill:"));
	if (SkillId.IsEmpty() || SkillId == ActiveSkillDetailsId)
	{
		return;
	}

	ActiveSkillDetailsId = SkillId;
	RefreshSkillsPresentation();
}

void UFableCharacterMenuWidget::HandleSkillSlotRightClicked(FName SlotId, const FString& PayloadId)
{
	(void)SlotId;

	if (ActiveTab != TEXT("skills") || !PayloadId.StartsWith(TEXT("skill:")))
	{
		return;
	}

	ContextSkillId = PayloadId;
	ContextSkillId.RemoveFromStart(TEXT("skill:"));
	// Assignment is always visible beside the selected skill; no extra row
	// should push both pages downward when the skill is right-clicked.
	bSkillContextVisible = false;
	ActiveSkillDetailsId = ContextSkillId;
	if (auto* PC = Cast<AFableForgePlayerController>(GetOwningPlayer())) PC->OpenWheelAssignmentForPayload(PayloadId);
}


#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFableJournalStabilityTest,
 "FableForge.UI.JournalPreservesInteractiveWidgets",
 EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FFableJournalStabilityTest::RunTest(const FString& Parameters)
{
 UFableCharacterMenuWidget* Menu=NewObject<UFableCharacterMenuWidget>();
 Menu->WidgetTree=NewObject<UWidgetTree>(Menu);
 Menu->ContentRoot=Menu->WidgetTree->ConstructWidget<UVerticalBox>();
 Menu->WidgetTree->RootWidget=Menu->ContentRoot;
 Menu->bInventoryLoaded=true; Menu->bItemDefinitionsLoaded=true;
 Menu->InventorySlots.SetNum(UFableSaveSubsystem::InventorySlotsPerCharacter);
 Menu->EquippedSlots.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);
 Menu->InventorySlots[0]=TEXT("test_sword");
 FFableUiItemDefinition Item;Item.Id=TEXT("test_sword");Item.Name=TEXT("Sword");Item.Category=CategoryWeaponsAction;
 Menu->ItemDefinitions.Add(Item.Id,Item);
 Menu->BuildInventoryTab();
 UWidget* Page=Menu->ContentRoot->GetChildAt(0);
 USizeBox* Cell=Menu->InventoryCells.FindRef(0);
 UFableInventorySlotWidget* ItemWidget=Menu->SlotWidgets.FindRef(TEXT("inv_0"));
 UScrollBox* Scroll=Cast<UScrollBox>(Menu->WidgetTree->FindWidget(TEXT("InventoryGridScroll")));
 if (!TestNotNull(TEXT("Inventory has a persistent scroll container"),Scroll)) return false;
 const TSharedPtr<SWidget> ScrollSlate=Scroll->TakeWidget();
 Scroll->SetScrollOffset(82.f);
 Menu->HandleActionClicked(CategoryWeaponsAction);
 TestTrue(TEXT("Filtering preserves the page controls"),Menu->ContentRoot->GetChildAt(0)==Page);
 TestTrue(TEXT("Filtering preserves item widget identity"),Menu->SlotWidgets.FindRef(TEXT("inv_0"))==ItemWidget);
 TestTrue(TEXT("Filtering preserves inventory cells"),Menu->InventoryCells.FindRef(0)==Cell);
 TestEqual(TEXT("Filtering does not reset scroll offset"),Scroll->GetScrollOffset(),82.f);
 TestTrue(TEXT("Filtering retains the actual Slate scroll widget"),Scroll->GetCachedWidget()==ScrollSlate);
 Menu->HandleActionClicked(CategoryAllAction);
 Menu->InventorySlots[8]=Menu->InventorySlots[0];Menu->InventorySlots[0].Reset();
 Menu->RefreshInventoryPresentation();
 USizeBox* Destination=Menu->InventoryCells.FindRef(8);
 UUniformGridSlot* DestinationSlot=Destination ? Cast<UUniformGridSlot>(Destination->Slot) : nullptr;
 if (TestNotNull(TEXT("Moved items keep their physical bag cell"),DestinationSlot))
 {
  TestEqual(TEXT("Destination remains on row one"),DestinationSlot->GetRow(),1);
  TestEqual(TEXT("Destination remains in column three"),DestinationSlot->GetColumn(),3);
 }
 Menu->HandleActionClicked(InventoryAction);
 TestTrue(TEXT("Clicking the selected tab does not rebuild its page"),Menu->ContentRoot->GetChildAt(0)==Page);
 TestFalse(TEXT("Same-page interactions do not queue a rebuild"),Menu->bTabContentRebuildQueued);
 // Selection used to rebuild the clicked skill list. Exercise the actual handler
 // with a retained list row and passive details panel, without disk-backed saves.
 Menu->ActiveTab=TEXT("skills");Menu->DisplayedSkillOrder={TEXT("first"),TEXT("second")};
 UBorder* SkillRow=Menu->WidgetTree->ConstructWidget<UBorder>();
 Menu->SkillRows.Add(TEXT("second"),SkillRow);
 Menu->SkillDetailsContent=Menu->WidgetTree->ConstructWidget<UVerticalBox>();
 Menu->ActiveSkillDetailsId=TEXT("first");
 Menu->HandleSkillSlotClicked(TEXT("skill_1"),TEXT("skill:second"));
 TestEqual(TEXT("Skill selection updates details"),Menu->ActiveSkillDetailsId,FString(TEXT("second")));
 TestTrue(TEXT("The selected skill row survives its callback"),Menu->SkillRows.FindRef(TEXT("second"))==SkillRow);
 TestFalse(TEXT("Skill selection does not queue page destruction"),Menu->bTabContentRebuildQueued);
 return true;
}
#endif
