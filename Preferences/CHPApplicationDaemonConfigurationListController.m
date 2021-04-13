// Copyright (c) 2019-2021 Lars Fröder

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import "CHPApplicationDaemonConfigurationListController.h"

#import <AppList/AppList.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared.h"
#import "CHPTweakList.h"
#import "CHPTweakInfo.h"
#import "CHPMachoParser.h"
#import "CHPRootListController.h"
#import "CHPDPKGFetcher.h"

@interface PSSpecifier ()
@property (nonatomic,retain) NSArray* values;
@end

@implementation CHPApplicationDaemonConfigurationListController

- (void)respring
{
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.opa334.choicy/respring"), NULL, NULL, YES);
}

- (void)viewDidLoad;
{
	_isApplication = ((NSNumber*)[[self specifier] propertyForKey:@"isApplication"]).boolValue;
	_isSpringboard = ((NSNumber*)[[self specifier] propertyForKey:@"isSpringboard"]).boolValue;

	if(_isSpringboard)
	{
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"RESPRING") style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
	}

	[super viewDidLoad];

	[self updateTopSwitchesAvailability];
}

- (NSString*)topTitle
{
	if(_isSpringboard)
	{
		return @"SpringBoard";
	}
	else if(_isApplication)
	{
		return [[ALApplicationList sharedApplicationList] valueForKey:@"displayName" forDisplayIdentifier:[[[self specifier] properties] objectForKey:@"key"]];
	}
	else
	{
		return [[self specifier] propertyForKey:@"key"];
	}
}

- (NSString*)dictionaryName
{
	if(_isApplication)
	{
		return @"appSettings";
	}
	else
	{
		return @"daemonSettings";
	}
}

- (NSString*)plistName
{
	return @"ApplicationDaemon";
}

- (NSMutableArray*)specifiers
{
	if(![self valueForKey:@"_specifiers"])
	{
		[self readAppDaemonSettingsFromMainPropertyList];

		_tweakWhitelist = [[_appDaemonSettings objectForKey:@"tweakWhitelist"] mutableCopy] ?: [NSMutableArray new];
		_tweakBlacklist = [[_appDaemonSettings objectForKey:@"tweakBlacklist"] mutableCopy] ?: [NSMutableArray new];		

		NSMutableArray* specifiers = [super specifiers];

		NSArray* tweakList;

		//Get tweak list
		if(_isApplication)
		{
			NSString* applicationIdentifier = [[self specifier] propertyForKey:@"key"];
			NSString* applicationExecutablePath = [[ALApplicationList sharedApplicationList] valueForKeyPath:@"info.executableURL.path" forDisplayIdentifier:applicationIdentifier];
			if(!applicationExecutablePath)
			{
				NSString* bundlePath = [[ALApplicationList sharedApplicationList] valueForKeyPath:@"path" forDisplayIdentifier:applicationIdentifier];
				if(bundlePath)
				{
					NSBundle* applicationBundle = [NSBundle bundleWithPath:bundlePath];
					if(applicationBundle)
					{
						applicationExecutablePath = applicationBundle.executablePath;
					}
				}				
			}

			//Applist fails to provide the executable path for springboard, so we just set it manually
			if([applicationIdentifier isEqualToString:@"com.apple.springboard"])
			{
				applicationExecutablePath = @"/System/Library/CoreServices/SpringBoard.app/SpringBoard";
			}

			NSSet* linkedFrameworkIdentifiers = frameworkBundleIDsForMachoAtPath(applicationExecutablePath);
			tweakList = [[CHPTweakList sharedInstance] tweakListForApplicationWithIdentifier:applicationIdentifier executableName:applicationExecutablePath.lastPathComponent linkedFrameworkIdentifiers:linkedFrameworkIdentifiers];
		}
		else
		{
			tweakList = [[CHPTweakList sharedInstance] tweakListForDaemon:[[self specifier] propertyForKey:@"daemonInfo"]];
		}

		_customConfigurationSpecifiers = [NSMutableArray new];

		_segmentSpecifier = [PSSpecifier preferenceSpecifierNamed:nil
						  target:self
						  set:@selector(setPreferenceValue:specifier:)
						  get:@selector(readPreferenceValue:)
						  detail:nil
						  cell:PSSegmentCell
						  edit:nil];

		[_segmentSpecifier setProperty:@YES forKey:@"enabled"];
		_segmentSpecifier.values = @[@1,@2];
		_segmentSpecifier.titleDictionary = @{@1 : localize(@"WHITELIST"), @2 : localize(@"BLACKLIST")};
		[_segmentSpecifier setProperty:@1 forKey:@"default"];
		[_segmentSpecifier setProperty:@"whitelistBlacklistSegment" forKey:@"key"];
		
		[_customConfigurationSpecifiers addObject:_segmentSpecifier];

		PSSpecifier* groupSpecifier = [PSSpecifier preferenceSpecifierNamed:nil
						  target:self
						  set:nil
						  get:nil
						  detail:nil
						  cell:PSGroupCell
						  edit:nil];

		[groupSpecifier setProperty:@YES forKey:@"enabled"];

		[_customConfigurationSpecifiers addObject:groupSpecifier];

		for(CHPTweakInfo* tweakInfo in tweakList)
		{
			if([tweakInfo.dylibName containsString:@"Choicy"] || [tweakInfo.dylibName isEqualToString:@"PreferenceLoader"] || [tweakInfo.dylibName isEqualToString:@"AppList"])
			{
				continue;
			}

			BOOL enabled = YES;

			if([dylibsBeforeChoicy containsObject:tweakInfo.dylibName])
			{
				enabled = NO;
			}

			PSSpecifier* tweakSpecifier = [PSSpecifier preferenceSpecifierNamed:tweakInfo.dylibName
						  target:self
						  set:@selector(setValue:forTweakWithSpecifier:)
						  get:@selector(readValueForTweakWithSpecifier:)
						  detail:nil
						  cell:PSSwitchCell
						  edit:nil];
			
			[tweakSpecifier setProperty:NSClassFromString(@"CHPSubtitleSwitch") forKey:@"cellClass"];
			[tweakSpecifier setProperty:@(enabled) forKey:@"enabled"];
			[tweakSpecifier setProperty:tweakInfo.dylibName forKey:@"key"];
			[tweakSpecifier setProperty:@NO forKey:@"default"];

			NSString* package = [[CHPDPKGFetcher sharedInstance] getPackageNameForDylibWithName:tweakInfo.dylibName];
			if(package)
			{
				[tweakSpecifier setProperty:[NSString stringWithFormat:@"%@: %@", localize(@"PACKAGE"), package] forKey:@"subtitle"];
			}

			[_customConfigurationSpecifiers addObject:tweakSpecifier];
		}

		PSSpecifier* customTweakConfigurationSpecifier = [self specifierForID:@"CUSTOM_TWEAK_CONFIGURATION"];

		if(((NSNumber*)[self readPreferenceValue:customTweakConfigurationSpecifier]).boolValue)
		{
			[specifiers addObjectsFromArray:_customConfigurationSpecifiers];
		}

		[self setValue:specifiers forKey:@"_specifiers"];
	}

	return [self valueForKey:@"_specifiers"];
}

- (void)reloadSpecifiers
{
	[super reloadSpecifiers];
	[self updateTopSwitchesAvailability];
	[self updateTweakConfigurationAvailability];
}

- (void)updateTopSwitchesAvailability
{
	PSSpecifier* disableTweakInjectionSpecifier = [self specifierForID:@"DISABLE_TWEAK_INJECTION"];
	PSSpecifier* customTweakConfigurationSpecifier = [self specifierForID:@"CUSTOM_TWEAK_CONFIGURATION"];

	NSNumber* disableTweakInjectionNum = [self readPreferenceValue:disableTweakInjectionSpecifier];
	NSNumber* customTweakConfigurationNum = [self readPreferenceValue:customTweakConfigurationSpecifier];

	//handle the edge case where a user managed to enable both at the same time
	if([disableTweakInjectionNum boolValue] && [customTweakConfigurationNum boolValue])
	{
		[disableTweakInjectionSpecifier setProperty:@(YES) forKey:@"enabled"];
		[customTweakConfigurationSpecifier setProperty:@(YES) forKey:@"enabled"];
	}
	else
	{
		[disableTweakInjectionSpecifier setProperty:@(!customTweakConfigurationNum.boolValue) forKey:@"enabled"];
		[customTweakConfigurationSpecifier setProperty:@(!disableTweakInjectionNum.boolValue) forKey:@"enabled"];
	}

	NSString* applicationIdentifier = [[self specifier] propertyForKey:@"key"];
	if([applicationIdentifier isEqualToString:@"com.apple.Preferences"])
	{
		if(![disableTweakInjectionNum boolValue])
		{
			[disableTweakInjectionSpecifier setProperty:@(NO) forKey:@"enabled"];
		}
	}

	[self reloadSpecifier:disableTweakInjectionSpecifier];
	[self reloadSpecifier:customTweakConfigurationSpecifier];
}

- (void)updateTweakConfigurationAvailability
{
	PSSpecifier* customTweakConfigurationSpecifier = [self specifierForID:@"CUSTOM_TWEAK_CONFIGURATION"];
	NSNumber* customTweakConfigurationNum = [self readPreferenceValue:customTweakConfigurationSpecifier];

	if(customTweakConfigurationNum.boolValue)
	{
		for(PSSpecifier* specifier in _customConfigurationSpecifiers)
		{
			NSString* key = [specifier propertyForKey:@"key"];
			if([dylibsBeforeChoicy containsObject:key])
			{
				[customTweakConfigurationSpecifier setProperty:@NO forKey:@"enabled"];
				[self reloadSpecifier:customTweakConfigurationSpecifier];
			}
		}
	}
}

- (void)setValue:(id)value forTweakWithSpecifier:(PSSpecifier*)specifier
{
	BOOL bValue = ((NSNumber*)value).boolValue;
	NSString* key = [specifier propertyForKey:@"key"];

	if(((NSNumber*)[self readPreferenceValue:_segmentSpecifier]).intValue == 1)
	{
		if(bValue)
		{
			[_tweakWhitelist addObject:key];
		}
		else
		{
			[_tweakWhitelist removeObject:key];
		}

		[_appDaemonSettings setObject:[_tweakWhitelist copy] forKey:@"tweakWhitelist"];
	}
	else
	{
		if(bValue)
		{
			[_tweakBlacklist addObject:key];
		}
		else
		{
			[_tweakBlacklist removeObject:key];
		}

		[_appDaemonSettings setObject:[_tweakBlacklist copy] forKey:@"tweakBlacklist"];
	}

	[self writeAppDaemonSettingsToMainPropertyList];
	[self sendPostNotificationForSpecifier:specifier];
}

- (id)readValueForTweakWithSpecifier:(PSSpecifier*)specifier
{
	BOOL tweakEnabled;
	NSString* key = [specifier propertyForKey:@"key"];
	NSInteger segmentValue = ((NSNumber*)[self readPreferenceValue:_segmentSpecifier]).intValue;

	if([dylibsBeforeChoicy containsObject:key])
	{
		if(segmentValue == 1)
		{
			return @1;
		}
		else
		{
			return @0;
		}
	}

	if(segmentValue == 1)
	{
		tweakEnabled = [_tweakWhitelist containsObject:key];
	}
	else
	{
		tweakEnabled = [_tweakBlacklist containsObject:key];
	}

	return [NSNumber numberWithBool:tweakEnabled];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier
{
	NSString* key = [specifier propertyForKey:@"key"];

	if([key isEqualToString:@"customTweakConfigurationEnabled"])
	{
		NSNumber* num = value;

		if(num.boolValue)
		{
			[self insertContiguousSpecifiers:_customConfigurationSpecifiers afterSpecifier:specifier animated:YES];
		}
		else
		{
			[self removeContiguousSpecifiers:_customConfigurationSpecifiers animated:YES];
		}
	}

	[_appDaemonSettings setValue:value forKey:key];
	[self writeAppDaemonSettingsToMainPropertyList];
	[self sendPostNotificationForSpecifier:specifier];

	if([key isEqualToString:@"tweakInjectionDisabled"] || [key isEqualToString:@"customTweakConfigurationEnabled"])
	{
		[self updateTopSwitchesAvailability];
	}

	if([key isEqualToString:@"whitelistBlacklistSegment"])
	{
		for(PSSpecifier* specifier in _customConfigurationSpecifiers)
		{
			[self reloadSpecifier:specifier];
		}
	}
}

- (id)readPreferenceValue:(PSSpecifier*)specifier
{
	id obj = [_appDaemonSettings objectForKey:[[specifier properties] objectForKey:@"key"]];
	if(!obj)
	{
		obj = [specifier propertyForKey:@"default"];
	}
	return obj;
}

- (void)readAppDaemonSettingsFromMainPropertyList
{
	NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	NSDictionary* appDaemonSettingsDict = [dict objectForKey:[self dictionaryName]];

	_appDaemonSettings = [[appDaemonSettingsDict objectForKey:[[[self specifier] properties] objectForKey:@"key"]] mutableCopy];
	if(!_appDaemonSettings)
	{
		_appDaemonSettings = [NSMutableDictionary new];
	}
}

- (void)writeAppDaemonSettingsToMainPropertyList
{
	NSMutableDictionary* mutableDict = [NSMutableDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	if(!mutableDict)
	{
		mutableDict = [NSMutableDictionary new];
	}
	NSMutableDictionary* appDaemonSettingsDict = [mutableDict objectForKey:[self dictionaryName]];
	if(!appDaemonSettingsDict)
	{
		appDaemonSettingsDict = [NSMutableDictionary new];
	}

	[appDaemonSettingsDict setObject:[_appDaemonSettings copy] forKey:[[[self specifier] properties] objectForKey:@"key"]];
	[mutableDict setObject:[appDaemonSettingsDict copy] forKey:[self dictionaryName]];
	[mutableDict writeToFile:CHPPlistPath atomically:YES];
}

@end
