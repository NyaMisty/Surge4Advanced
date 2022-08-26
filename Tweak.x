#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <assert.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#include <mach-o/dyld.h>

@implementation NSMutableURLRequest(Curl)

- (NSString *)description {
  
  __block NSMutableString *displayString = [NSMutableString stringWithFormat:@"curl -v -X %@", self.HTTPMethod];
  
  [displayString appendFormat:@" \'%@\'",  self.URL.absoluteString];
  
  [self.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
    [displayString appendFormat:@" -H \'%@: %@\'", key, val];
  }];
  
  if ([self.HTTPMethod isEqualToString:@"POST"] ||
      [self.HTTPMethod isEqualToString:@"PUT"] ||
      [self.HTTPMethod isEqualToString:@"PATCH"]) {
    
    [displayString appendFormat:@" -d \'%@\'",
     [[NSString alloc] initWithData:self.HTTPBody encoding:NSUTF8StringEncoding]];
  }
  
  return displayString;
}

@end

@implementation NSString (SHA256)

- (NSData *)SHA256
{
    const char *s = [self cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *keyData = [NSData dataWithBytes:s length:strlen(s)];

    uint8_t digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(keyData.bytes, (CC_LONG)keyData.length, digest);
    NSData *out = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    return out;
}

@end

char LicEncContent[] = "\x03\x04\x02NSExtension";

%hook SGNSARequestHelper 

// Hooking a class method
- (id)request:(NSMutableURLRequest *)req completeBlock:(void (^)(NSData *body, NSURLResponse *resp, NSError *err))completeBlock {
    __auto_type reqRawUrl = [req URL];
    __auto_type reqUrl = [[req URL] absoluteString];
    if (![reqUrl hasPrefix:@"https://www.surge-activation.com/ios/v3/"]) { return %orig; }
    if (!completeBlock) { return %orig; }
    
    __auto_type wrapper = ^(NSError *error, NSDictionary *data) {
        __auto_type resp = [[NSHTTPURLResponse alloc] initWithURL:reqRawUrl statusCode:200 HTTPVersion:@"1.1" headerFields:@{}];
        NSData *body = [NSJSONSerialization dataWithJSONObject:data options:0 error: &error];
        completeBlock(body, resp, error);
    };

    //NSLog(@"Surge License Request: %@ %@ %@", req, [req allHTTPHeaderFields], );
    NSLog(@"Surge License Request: %@", [req description]);
    if ([reqUrl hasSuffix:@"refresh"]) { // fake refresh req
        NSError *err = nil;
        NSDictionary *reqDict = [NSJSONSerialization JSONObjectWithData:req.HTTPBody
                                    options:kNilOptions
                                    error:&err];
        NSString *deviceID = reqDict[@"deviceID"];
        __auto_type keydata = [deviceID SHA256];
        const char *keybytes = [keydata bytes];
        char licEncOut[32] = { 0 };
        size_t encRet = 0;
        
        NSLog(@"key: %@ %x", keydata, *(uint32_t *)keybytes);

        CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, 
            keybytes, 0x20, keybytes + 16, 
            LicEncContent, sizeof(LicEncContent),
            licEncOut, 32, 
            &encRet);
        NSLog(@"encRet: %zu", encRet);

        __auto_type p = [[NSData dataWithBytes:(const void *)licEncOut length:16] base64EncodedStringWithOptions:0];
        NSLog(@"p: %@", p);
        
        [req setURL:[NSURL URLWithString:@"http://127.0.0.1:65536"]];
        void (^handler)(NSError *error, NSDictionary *data) = ^(NSError *error, NSDictionary *data){
            NSDictionary *licInfo = @{
                    @"deviceID": deviceID,
                    @"expirationDate": @4070880000, // 2099-01-01 00:00:00
                    @"fusDate": @4070880000,
                    @"type": @"licensed",
                    @"issueDate": [NSNumber numberWithInt:(long)[[NSDate date] timeIntervalSince1970]],
                    @"p": p,
                };
            NSLog(@"generated licInfo: %@", licInfo);
            NSData *licInfoData = [NSJSONSerialization dataWithJSONObject:licInfo options:0 error: &error];
            NSString *licInfoStr = [[NSString alloc] initWithData:licInfoData encoding:NSUTF8StringEncoding];
            NSLog(@"generated licInfoJson: %@", licInfoStr);

            NSString *licInfoBase64 = [licInfoData base64EncodedStringWithOptions:0];
            wrapper(nil, @{
                @"license": @{
                    @"policy": licInfoBase64,
                    @"sign": @""
                }
            });
            
            //exit(0);
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil, nil);
        });
    }
    
    if ([reqUrl hasSuffix:@"ac"]) { // disable refresh req
        [req setURL:[NSURL URLWithString:@"http://127.0.0.1:65536"]];
        void (^handler)(NSError *error, NSDictionary *data) = ^(NSError *error, NSDictionary *data){
            wrapper(nil, @{});
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil, nil);
        });
    }
    
	return %orig;
}

%end


// For unknown reason, on some of my device, the unlockTime also returns 94665600000
// I really can't find out what happened, I'll just patch it here
%hook SGUProFeatureDefine

- (int64_t) unlockTime {
    return 0;
}

%end


void *pEVP_DigestVerifyFinal = NULL;

%hookf(uint64_t, pEVP_DigestVerifyFinal, void *ctx, uint64_t a2, uint64_t a3) {
    %orig;
    NSLog(@"Bypassed surge lic sign check!");
    return 1;
}

#include <dlfcn.h>

%ctor {
    // In Surge >= v4.14.0, OpenSSL is no longer statically linked

    NSString *execPath = [[NSBundle mainBundle] executablePath].stringByDeletingLastPathComponent;
    while ([execPath containsString:@"/PlugIns"]) {
        execPath = execPath.stringByDeletingLastPathComponent;
    }
    NSString *openSSLPath = [NSString stringWithFormat:@"%@/%@", execPath, @"Frameworks/OpenSSL.framework/OpenSSL"];
    NSLog(@"OpenSSL Framework: %@", openSSLPath);
    if (![[NSFileManager defaultManager] fileExistsAtPath:openSSLPath]) {
        // Static OpenSSL version (<= 4.13.0)
        NSLog(@"Retriving EVP_DigestVerifyFinal using pattern because there's no OpenSSL framework");
        unsigned char needle[] = "\x08\x01\x40\xF9\xA8\x83\x1C\xF8\xFF\x07\x00\xB9\x00\x10\x40\xF9\x08\x00\x40\xF9\x18\x45\x40\xF9\xA8\x46\x40\x39\x08\x02\x08\x37";
        intptr_t imgBase = (intptr_t)_dyld_get_image_vmaddr_slide(0) + 0x100000000LL;
        intptr_t imgBase2 = (intptr_t)_dyld_get_image_header(0);
        NSLog(@"Surge image base at %p %p", (void *)imgBase, (void *)imgBase2);
        //NSLog(@"Surge hdr %x %x %x %x %x", *(uint32_t *)(imgBase + 0x236730), *(uint32_t *)(imgBase + 0x236734), *(uint32_t *)(imgBase + 0x236738), *(uint32_t *)(imgBase + 0x23673c), *(uint32_t *)(imgBase + 0x236740));
        char *pNeedle = (char *)memmem((void *)imgBase, 0x400000, needle, sizeof(needle) - 1);
        NSLog(@"found pNeedle at %p", pNeedle);
        if(pNeedle == NULL) {
            exit(0);
        }
        pEVP_DigestVerifyFinal = pNeedle - 0x2c;
    } else {
        NSLog(@"OpenSSL framework exists!");
        void *ret = dlopen([openSSLPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
        NSLog(@"OpenSSL framework load result: %p", ret);

        MSImageRef image = MSGetImageByName([openSSLPath UTF8String]);
        // Dylib OpenSSL version (>= 4.14)
        NSLog(@"Retriving EVP_DigestVerifyFinal using symbol because there's OpenSSL framework: %p", image);
        pEVP_DigestVerifyFinal = MSFindSymbol(image, "_EVP_DigestVerifyFinal");
    }
    NSLog(@"Got EVP_DigestVerifyFinal: %p", pEVP_DigestVerifyFinal);

    
    NSLog(@"Surge3ProLicenseEmail: %@", [[NSUbiquitousKeyValueStore defaultStore] stringForKey: @"Surge3ProLicenseEmail"]);
    NSLog(@"Surge3ProLicenseKey: %@", [[NSUbiquitousKeyValueStore defaultStore] stringForKey: @"Surge3ProLicenseKey"]);
    if (![[NSUbiquitousKeyValueStore defaultStore] stringForKey: @"Surge3ProLicenseEmail"]) {
        [[NSUbiquitousKeyValueStore defaultStore] setString:@"example@example.com" forKey:@"Surge3ProLicenseEmail"];
        [[NSUbiquitousKeyValueStore defaultStore] setString:@"ABCDEFGH" forKey: @"Surge3ProLicenseKey"];
    }

    %init;
}
