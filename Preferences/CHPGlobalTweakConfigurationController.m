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

#import "CHPGlobalTweakConfigurationController.h"
#import "CHPTweakList.h"
#import "CHPTweakInfo.h"
#import "CHPRootListController.h"
#import "CHPDPKGFetcher.h"
#import "../Shared.h"

@implementation CHPGlobalTweakConfigurationController

- (NSString*)topTitle
{
	return localize(@"GLOBAL_TWEAK_CONFIGURATION");
}

- (NSString*)plistName
{
	return @"GlobalTweakConfiguration";
}

- (void)viewDidLoad
{
	[self applySearchControllerHideWhileScrolling:YES];
	[super viewDidLoad];
}

- (NSMutableArray*)specifiers
{
	if(![self valueForKey:@"_specifiers"])
	{
		NSMutableArray* specifiers = [super specifiers];

		[self loadGlobalTweakBlacklist];

		for(CHPTweakInfo* tweakInfo in [CHPTweakList sharedInstance].tweakList)
		{
			if([tweakInfo.dylibName containsString:@"Choicy"] || [tweakInfo.dylibName isEqualToString:@"PreferenceLoader"] || [tweakInfo.dylibName isEqualToString:@"AppList"])
			{
				continue;
			}
			if(_searchKey && ![_searchKey isEqualToString:@""])
			{
				if(![tweakInfo.dylibName localizedStandardContainsString:_searchKey])
				{
					continue;
				}
			}

			PSSpecifier* tweakSpecifier = [PSSpecifier preferenceSpecifierNamed:tweakInfo.dylibName
						  target:self
						  set:@selector(setValue:forTweakWithSpecifier:)
						  get:@selector(readValueForTweakWithSpecifier:)
						  detail:nil
						  cell:PSSwitchCell
						  edit:nil];

			BOOL enabled = YES;

			if([dylibsBeforeChoicy containsObject:tweakInfo.dylibName])
			{
				enabled = NO;
			}
			
			[tweakSpecifier setProperty:NSClassFromString(@"CHPSubtitleSwitch") forKey:@"cellClass"];
			[tweakSpecifier setProperty:@(enabled) forKey:@"enabled"];
			[tweakSpecifier setProperty:tweakInfo.dylibName forKey:@"key"];
			[tweakSpecifier setProperty:@YES forKey:@"default"];

			NSString* package = [[CHPDPKGFetcher sharedInstance] getPackageNameForDylibWithName:tweakInfo.dylibName];
			if(package)
			{
				[tweakSpecifier setProperty:[NSString stringWithFormat:@"%@: %@", localize(@"PACKAGE"), package] forKey:@"subtitle"];
			}

			[specifiers addObject:tweakSpecifier];
		}

		[self setValue:specifiers forKey:@"_specifiers"];
	}

	return [self valueForKey:@"_specifiers"];
}

- (void)setValue:(id)value forTweakWithSpecifier:(PSSpecifier*)specifier
{
	NSNumber* numberValue = value;

	if(numberValue.boolValue)
	{
		[_globalTweakBlacklist removeObject:[specifier propertyForKey:@"key"]];
	}
	else
	{
		[_globalTweakBlacklist addObject:[specifier propertyForKey:@"key"]];
	}

	[self saveGlobalTweakBlacklist];
	[self sendPostNotificationForSpecifier:specifier];
}

- (id)readValueForTweakWithSpecifier:(PSSpecifier*)specifier
{
	NSString* key = [specifier propertyForKey:@"key"];

	if([dylibsBeforeChoicy containsObject:key])
	{
		return @1;
	}

	if([_globalTweakBlacklist containsObject:key])
	{
		return @0;
	}
	else
	{
		return @1;
	}
}

- (void)loadGlobalTweakBlacklist
{
	NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	_globalTweakBlacklist = [[dict objectForKey:@"globalTweakBlacklist"] mutableCopy] ?: [NSMutableArray new];
}

- (void)saveGlobalTweakBlacklist
{
	NSMutableDictionary* mutableDict = [NSMutableDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	if(!mutableDict)
	{
		mutableDict = [NSMutableDictionary new];
	}

	[mutableDict setObject:[_globalTweakBlacklist copy] forKey:@"globalTweakBlacklist"];
	[mutableDict writeToFile:CHPPlistPath atomically:YES];
}

@end