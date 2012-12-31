//
//  main.m
//  recodesign
//
//  Created by hayashi on 12/31/12.
//  Copyright (c) 2012 hayashi. All rights reserved.
//
#import <Foundation/Foundation.h>

#define PrintUsageWithError(...) PrintUsage([NSString stringWithFormat:@__VA_ARGS__]);
static void PrintUsage(NSString *message);
static void PrintError(NSString *message);
static BOOL ReCodesign(NSString *srcIPA, NSString *p12File, NSString *passwd, NSString *provFile, NSString *dstIPA);

int main(int argc, const char * argv[])
{
	@autoreleasepool {
		if( argc <= 1 ){
			PrintUsage(nil);
			return -1;
		}
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *srcIPA = [NSString stringWithUTF8String:argv[1]];
		if( ![fm fileExistsAtPath:srcIPA] ){
			PrintUsageWithError("IPA '%@' not found",srcIPA);
			return -1;
		}
		if( ![srcIPA hasSuffix:@".ipa"] && ![srcIPA hasSuffix:@".IPA"] ){
			PrintUsageWithError("%@ does not seem to be ipa file",[srcIPA lastPathComponent]);
			return -1;
		}
		
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		NSString *p12File = nil;
		if( [ud objectForKey:@"p12"] ){
			p12File = [ud stringForKey:@"p12"];
		}
		if( !p12File ){
			PrintUsageWithError("P12 is not specified");
			return -1;
		}
		if( ![fm fileExistsAtPath:p12File] ){
			PrintUsageWithError("P12 '%@' not found",p12File);
			return -1;
		}
		if( ![p12File hasSuffix:@".p12"] && ![p12File hasSuffix:@".P12"] ){
			PrintUsageWithError("%@ does not seem to be p12 file",[p12File lastPathComponent]);
			return -1;
		}
		
		NSString *provFile = nil;
		if( [ud objectForKey:@"mp"] ){
			provFile = [ud stringForKey:@"mp"];
		}else{
			provFile = [[p12File stringByDeletingPathExtension]
						stringByAppendingPathExtension:@"mobileprovision"];
		}
		if( ![fm fileExistsAtPath:provFile] ){
			PrintUsageWithError("Provisioning profile '%@' not found",provFile);
			return -1;
		}
		
		NSString *p12Password = nil;
		if( [ud objectForKey:@"p"] ){
			p12Password = [ud stringForKey:@"p"];
		}
		
		NSString *dstIPA = nil;
		if( [ud objectForKey:@"o"] ){
			dstIPA = [ud stringForKey:@"o"];
		}else{
			dstIPA = [[srcIPA stringByDeletingPathExtension] stringByAppendingString:@"_rc.ipa"];
		}
				
		if( !ReCodesign(srcIPA, p12File, p12Password, provFile, dstIPA) ){
			return -1;
		}
	}
	return 0;
}

static void PrintUsage(NSString *message){
	if( message ){
		printf("Error:\n");
		printf("  %s\n",[message UTF8String]);
	}
	printf("Usage:\n");
	printf("  recodesign <ipa_path> -p12 <p12_path> [-mp <prov_path>] [-o <out_ipa_path>]\n");
}

static void PrintError(NSString *message){
	if( message ){
		printf("Error:\n");
		printf("  %s\n",[message UTF8String]);
	}
}

static void DeleteTempKeychain(SecKeychainRef keychain){
	if( keychain ){
		SecKeychainDelete(keychain);
	}
}

static SecKeychainRef CreateTempKeychain(NSString *path){
	if( [[NSFileManager defaultManager] fileExistsAtPath:path] ){
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	}
	SecKeychainRef keychain = NULL;
	SecKeychainCreate ([path UTF8String],0,"",NO,NULL,&keychain);
	return keychain;
}

static void MakeIPA(NSString *workDir,NSString* dstPath){
	NSArray *arguments = [NSArray arrayWithObjects:dstPath,@"-r",@"Payload",nil];
	NSTask *zipTask = [[NSTask alloc] init];
	[zipTask setLaunchPath:@"/usr/bin/zip"];
	[zipTask setCurrentDirectoryPath:workDir];
	[zipTask setArguments:arguments];
	[zipTask launch];
	[zipTask waitUntilExit];
	[zipTask release];
}

static void UnzipFile(NSString* zipPath, NSString* dstDir){
	NSArray *arguments = [NSArray arrayWithObject:zipPath];
	NSTask *unzipTask = [[NSTask alloc] init];
	[unzipTask setLaunchPath:@"/usr/bin/unzip"];
	[unzipTask setCurrentDirectoryPath:dstDir];
	[unzipTask setArguments:arguments];
	[unzipTask launch];
	[unzipTask waitUntilExit];
	[unzipTask release];
}

static NSString* CreateTempDir(){
	NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
	if( ![[NSFileManager defaultManager] fileExistsAtPath:path] ){
		[[NSFileManager defaultManager] createDirectoryAtPath:path
								  withIntermediateDirectories:NO
												   attributes:nil error:nil];
	}
	path = [path stringByAppendingPathComponent:guid];
	if( [[NSFileManager defaultManager] fileExistsAtPath:path] ){
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	}
	[[NSFileManager defaultManager] createDirectoryAtPath:path
							  withIntermediateDirectories:NO
											   attributes:nil error:nil];
	return path;
}

static void Codesign(NSString *appPath, NSArray*provInfo){
	NSString *identity = [provInfo objectAtIndex:0];
	NSString *provFile = [provInfo objectAtIndex:1];
	NSString *keychainPath = [provInfo objectAtIndex:2];
	
	NSString *embededPath = [appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
	if( [[NSFileManager defaultManager] fileExistsAtPath:embededPath]){
		[[NSFileManager defaultManager] removeItemAtPath:embededPath error:nil];
	}
	[[NSFileManager defaultManager] copyItemAtPath:provFile toPath:embededPath error:nil];
	NSString *crPath = [appPath stringByAppendingPathComponent:@"ResourceRules.plist"];
	
	NSString *crLink = [appPath stringByAppendingPathComponent:@"CodeResources"];
	if( [[NSFileManager defaultManager] fileExistsAtPath:crLink] ){
		[[NSFileManager defaultManager] removeItemAtPath:crLink error:nil];
	}
	NSString *crLink2 = [appPath stringByAppendingPathComponent:@"_CodeSignature/CodeResources"];
	if( [[NSFileManager defaultManager] fileExistsAtPath:crLink2] ){
		[[NSFileManager defaultManager] removeItemAtPath:crLink2 error:nil];
	}
	
	NSArray *arguments = [NSArray arrayWithObjects:@"-f",@"-s",identity,
						  @"--resource-rules",crPath,
						  @"--keychain",keychainPath,
						  appPath,nil];
	NSTask *codesignTask = [[NSTask alloc] init];
	[codesignTask setLaunchPath:@"/usr/bin/codesign"];
	[codesignTask setArguments:arguments];
	[codesignTask launch];
	[codesignTask waitUntilExit];
	[codesignTask release];
}

static BOOL ReCodesign(NSString *srcIPA, NSString *p12File, NSString *passwd, NSString *provFile, NSString *dstIPA)
{
	NSData *p12Data = [NSData dataWithContentsOfFile:p12File];
	if( !p12Data ){
		return FALSE;
	}
	
	SecItemImportExportKeyParameters param;
	if( passwd ){
		param.flags = 0;
		param.alertPrompt = NULL;
		param.passphrase = (CFStringRef)passwd;
	}else{
		param.flags = kSecKeySecurePassphrase;
		param.alertPrompt = CFSTR("P12 Password");
		param.passphrase = NULL;
	}
	param.accessRef = NULL;
	param.alertTitle = NULL;
	param.version = 0;
	param.keyUsage = NULL;
	param.keyAttributes = NULL;
	
	SecExternalFormat format = kSecFormatPKCS12;
	
	NSString *workDir = CreateTempDir();
	NSString *keychainPath = [workDir stringByAppendingPathComponent:@"recodesign.keychain"];
	SecKeychainRef keychain = CreateTempKeychain(keychainPath);
	
	CFArrayRef results = CFArrayCreate(NULL, NULL, 0, NULL);
	OSStatus err= SecItemImport((CFDataRef)p12Data, NULL, &format, NULL, 0, &param, keychain, &results);
	if( err != 0 ){
		DeleteTempKeychain(keychain);
		PrintError(@"Failed to import P12");
		return FALSE;
	}
	NSString *commonName = nil;
	NSArray *result2 = (NSArray*)results;
	for(id item in result2) {
		if( SecIdentityGetTypeID() == CFGetTypeID(item) ){
			SecCertificateRef cert = NULL;
			SecIdentityCopyCertificate((SecIdentityRef)item, &cert);
			if( cert ){
				CFStringRef name = NULL;
				SecCertificateCopyCommonName(cert, &name);
				NSString *name2 = (NSString*)name;
				if( [name2 hasPrefix:@"iPhone Distribution:"] || [name2 hasPrefix:@"iPhone Developer:"] ){
					commonName = [NSString stringWithString:name2];
					NSLog(@"P12Cert: [%@]",commonName);
				}
				CFRelease(name);
				CFRelease(cert);
				if( commonName ){
					break;
				}
			}
		}
	}
	CFRelease(results);
	
	if( !commonName ){
		DeleteTempKeychain(keychain);
		PrintError(@"Failed to obtain certificate data from P12");
		return FALSE;
	}
	
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *payloadPath = [workDir stringByAppendingPathComponent:@"Payload"];
	NSString *zipFile = [workDir stringByAppendingPathComponent:@"Payload.zip"];
	
	[fm copyItemAtPath:srcIPA toPath:zipFile error:nil];
	
	UnzipFile(zipFile, workDir);
	NSString *appName = [[fm enumeratorAtPath:payloadPath] nextObject];
	NSString *appPath = [workDir stringByAppendingFormat:@"/Payload/%@",appName];
	NSArray *provInfo = @[commonName,provFile,keychainPath];	
	Codesign(appPath, provInfo);
	
	NSString *tmpDstIPA = [workDir stringByAppendingPathComponent:[appName stringByAppendingPathExtension:@"ipa"]];
	MakeIPA(workDir,tmpDstIPA);
	
	[fm moveItemAtPath:tmpDstIPA toPath:dstIPA error:nil];
	
	[[NSFileManager defaultManager] removeItemAtPath:workDir error:nil];
	DeleteTempKeychain(keychain);
	
	return TRUE;
}





