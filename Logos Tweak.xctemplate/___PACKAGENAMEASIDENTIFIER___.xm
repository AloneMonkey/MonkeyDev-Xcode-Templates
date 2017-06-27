// See http://iphonedevwiki.net/index.php/Logos

#error MonkeyDev post-project creation from template requirements (remove these lines after completed) -- \
	Link to CydiaSubstrate.framework: \
	(1) go to TARGETS > Build Phases > Link Binary With Libraries and add /opt/theos/vendor/lib/CydiaSubstrate.framework \
	(2) remove these lines from *.xm files (not *.mm files as they're automatically generated from *.xm files)

%hook ClassName

+ (id)sharedInstance
{
	%log;

	return %orig;
}

- (void)messageWithNoReturnAndOneArgument:(id)originalArgument
{
	%log;

	%orig(originalArgument);
	
	// or, for exmaple, you could use a custom value instead of the original argument: %orig(customValue);
}

- (id)messageWithReturnAndNoArguments
{
	%log;

	id originalReturnOfMessage = %orig;
	
	// for example, you could modify the original return value before returning it: [SomeOtherClass doSomethingToThisObject:originalReturnOfMessage];

	return originalReturnOfMessage;
}

%end
