// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;

public class FableForge : ModuleRules
{
	public FableForge(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore",
			"EnhancedInput",
			"AIModule",
			"NavigationSystem",
			"StateTreeModule",
			"GameplayStateTreeModule",
			"UMG",
			"Slate",
			"SlateCore",
			"Json",
			"JsonUtilities"
		});

		PrivateDependencyModuleNames.AddRange(new string[] { });

		PublicIncludePaths.AddRange(new string[] {
			"FableForge",
			"FableForge/RPG",
			"FableForge/RPG/Data",
			"FableForge/RPG/Save",
			"FableForge/RPG/UI",
			"FableForge/Variant_Platforming",
			"FableForge/Variant_Platforming/Animation",
			"FableForge/Variant_Combat",
			"FableForge/Variant_Combat/AI",
			"FableForge/Variant_Combat/Animation",
			"FableForge/Variant_Combat/Gameplay",
			"FableForge/Variant_Combat/Interfaces",
			"FableForge/Variant_Combat/UI",
			"FableForge/Variant_SideScrolling",
			"FableForge/Variant_SideScrolling/AI",
			"FableForge/Variant_SideScrolling/Gameplay",
			"FableForge/Variant_SideScrolling/Interfaces",
			"FableForge/Variant_SideScrolling/UI"
		});

		// Uncomment if you are using Slate UI
		// PrivateDependencyModuleNames.AddRange(new string[] { "Slate", "SlateCore" });

		// Uncomment if you are using online features
		// PrivateDependencyModuleNames.Add("OnlineSubsystem");

		// To include OnlineSubsystemSteam, add it to the plugins section in your uproject file with the Enabled attribute set to true
	}
}
