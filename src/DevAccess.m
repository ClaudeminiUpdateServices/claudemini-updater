#import "DevAccess.h"
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

// File format of an encrypted developer build:
//   "CMDEV1" (6) | salt (16) | iv (16) | AES-256-CBC ciphertext (PKCS7) | HMAC-SHA256 (32)
//   keys = PBKDF2-HMAC-SHA256(password, salt, 250000) -> 64 bytes: [0..31] AES key, [32..63] MAC key
//   tag  = HMAC-SHA256(macKey, "CMDEV1" | salt | iv | ciphertext)
static const char kMagic[6] = { 'C', 'M', 'D', 'E', 'V', '1' };
static const uint32_t kFileRounds = 250000;

// Verifiers made from the password (see tools/make_dev_gate.py in the developer's own notes; the password is not in the repo).
static NSString *const kSaltA = @"350db8ac2a8a8be0523c8a8ba3de5492";
static NSString *const kHashA = @"18283db76002ce5ab617a16c683f1761dca635a8bd40c90ccdf4ed92ad0a6730";
static const uint32_t kRoundsA = 210000;
static NSString *const kSaltB = @"4a5d99608ebc1817c1ede4f6fc72a808";
static NSString *const kHashB = @"1f7f3211a81a051dc5c89c4ad50df1f37fe5b6d73df095b4565e83fa1e422acdf1c6fd181e8a178cc6090d683f19755fa1e5c8d3223f52aeb4e09d4177c0d48d";
static const uint32_t kRoundsB = 150000;
static NSString *const kSaltC = @"e4e719973fdc6bdd18e874538facee32";
static NSString *const kSealIV = @"df9a6450516ecd5f5f5d1151727fbc1f";
static NSString *const kSealCT = @"8c23d3c9f3afe2e8920b23f7f55b96c1c63cb4d91234b7b36d511d4f07669d1fecca96fbfc46f0ff8bf7f2196208a03d";
static NSString *const kSealTag = @"16a9e2441c49aeb970c24bc8edae65d9e13e3a63676d35be0fe6b30ee0e394ad";
static const uint32_t kRoundsC = 120000;
static const char kSealPrefix[] = "CMDEV-GATE-OPEN-";

static const NSUInteger kMaxPasswordBytes = 256;
static const NSTimeInterval kSessionLifetime = 15 * 60;
static NSString *const kKeychainService = @"com.claudemini.devgate";
static NSString *const kKeychainAccount = @"attempts";

#pragma mark - Helpers

static NSData *DataFromHex(NSString *hex) {
    NSMutableData *out = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        unsigned int v = 0;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&v];
        uint8_t b = (uint8_t)v;
        [out appendBytes:&b length:1];
    }
    return out;
}

// Compares in constant time: the running time does not depend on where the bytes differ.
static BOOL ConstantTimeEqual(const uint8_t *a, const uint8_t *b, size_t len) {
    uint8_t diff = 0;
    for (size_t i = 0; i < len; i++) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

static BOOL Pbkdf2(const uint8_t *pw, size_t pwLen, const uint8_t *salt, size_t saltLen, CCPseudoRandomAlgorithm prf,
                   uint32_t rounds, uint8_t *out, size_t outLen) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)pw, pwLen, salt, saltLen, prf, rounds, out, outLen) == kCCSuccess;
}

#pragma mark - Keychain (attempt counter)

static NSDictionary *KeychainQuery(void) {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: kKeychainService,
              (__bridge id)kSecAttrAccount: kKeychainAccount };
}

static void LoadAttempts(NSInteger *fails, NSTimeInterval *until) {
    *fails = 0; *until = 0;
    NSMutableDictionary *q = [KeychainQuery() mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess || !result) return;
    NSData *data = (__bridge_transfer NSData *)result;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([json isKindOfClass:[NSDictionary class]]) {
        *fails = MAX(0, [json[@"f"] integerValue]);
        *until = [json[@"u"] doubleValue];
    }
}

static void SaveAttempts(NSInteger fails, NSTimeInterval until) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"f": @(fails), @"u": @(until) } options:0 error:nil];
    if (!data) return;
    NSDictionary *query = KeychainQuery();
    NSDictionary *update = @{ (__bridge id)kSecValueData: data };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

static NSTimeInterval DelayForFailures(NSInteger fails) {
    if (fails < 3) return 0;
    double delay = 30.0 * pow(2.0, (double)MIN(fails - 3, 7));
    return MIN(delay, 3600.0);
}

#pragma mark - DevAccess

@interface DevAccess ()
@property (assign, nonatomic) BOOL unlocked;
@property (assign, nonatomic) BOOL busy;
@property (strong, nonatomic) NSMutableData *sessionPassword;   // only while unlocked
@property (strong, nonatomic) NSTimer *lockTimer;
@property (strong, nonatomic) dispatch_queue_t queue;
@end

@implementation DevAccess

+ (instancetype)shared {
    static DevAccess *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[DevAccess alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.claudemini.devaccess", DISPATCH_QUEUE_SERIAL);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appLeft) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)appLeft { [self lock]; }

- (void)lock {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self lock]; }); return; }
    [self.lockTimer invalidate];
    self.lockTimer = nil;
    @synchronized (self) {
        if (self.sessionPassword.length > 0) memset_s(self.sessionPassword.mutableBytes, self.sessionPassword.length, 0, self.sessionPassword.length);
        self.sessionPassword = nil;
    }
    self.unlocked = NO;
}

// The three independent checks. All of them always run; the verdict is combined at the end.
- (BOOL)verifyPasswordBytes:(const uint8_t *)pw length:(size_t)len {
    NSData *saltA = DataFromHex(kSaltA), *hashA = DataFromHex(kHashA);
    NSData *saltB = DataFromHex(kSaltB), *hashB = DataFromHex(kHashB);
    NSData *saltC = DataFromHex(kSaltC), *iv = DataFromHex(kSealIV), *ct = DataFromHex(kSealCT), *tag = DataFromHex(kSealTag);

    uint8_t outA[32], outB[64], keyC[64];
    BOOL okA = Pbkdf2(pw, len, saltA.bytes, saltA.length, kCCPRFHmacAlgSHA256, kRoundsA, outA, sizeof(outA));
    BOOL okB = Pbkdf2(pw, len, saltB.bytes, saltB.length, kCCPRFHmacAlgSHA512, kRoundsB, outB, sizeof(outB));
    BOOL okC = Pbkdf2(pw, len, saltC.bytes, saltC.length, kCCPRFHmacAlgSHA256, kRoundsC, keyC, sizeof(keyC));

    BOOL a = okA && hashA.length == sizeof(outA) && ConstantTimeEqual(outA, hashA.bytes, sizeof(outA));
    BOOL b = okB && hashB.length == sizeof(outB) && ConstantTimeEqual(outB, hashB.bytes, sizeof(outB));

    BOOL c = NO;
    if (okC && tag.length == CC_SHA256_DIGEST_LENGTH && iv.length == 16 && ct.length > 0) {
        uint8_t mac[CC_SHA256_DIGEST_LENGTH];
        CCHmacContext ctx;
        CCHmacInit(&ctx, kCCHmacAlgSHA256, keyC + 32, 32);
        CCHmacUpdate(&ctx, "CMDEV-SEAL", 10);
        CCHmacUpdate(&ctx, iv.bytes, iv.length);
        CCHmacUpdate(&ctx, ct.bytes, ct.length);
        CCHmacFinal(&ctx, mac);
        BOOL tagOK = ConstantTimeEqual(mac, tag.bytes, sizeof(mac));
        uint8_t plain[128];
        size_t plainLen = 0;
        CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, keyC, 32, iv.bytes,
                                     ct.bytes, ct.length, plain, sizeof(plain), &plainLen);
        BOOL plainOK = st == kCCSuccess && plainLen >= strlen(kSealPrefix) && memcmp(plain, kSealPrefix, strlen(kSealPrefix)) == 0;
        c = tagOK && plainOK;
        memset_s(plain, sizeof(plain), 0, sizeof(plain));
        memset_s(mac, sizeof(mac), 0, sizeof(mac));
    }
    BOOL verdict = a & b & c;
    memset_s(outA, sizeof(outA), 0, sizeof(outA));
    memset_s(outB, sizeof(outB), 0, sizeof(outB));
    memset_s(keyC, sizeof(keyC), 0, sizeof(keyC));
    return verdict;
}

- (void)unlockWithPassword:(NSString *)password completion:(void (^)(DevAccessResult, NSTimeInterval))completion {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self unlockWithPassword:password completion:completion]; }); return; }
    void (^finish)(DevAccessResult, NSTimeInterval) = ^(DevAccessResult r, NSTimeInterval w) { if (completion) completion(r, w); };
    if (self.busy) { finish(DevAccessResultBusy, 0); return; }

    NSMutableData *bytes = [[(password ?: @"") dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (bytes.length == 0 || bytes.length > kMaxPasswordBytes) {
        if (bytes.length > 0) memset_s(bytes.mutableBytes, bytes.length, 0, bytes.length);
        finish(DevAccessResultInvalid, 0);
        return;
    }
    self.busy = YES;
    dispatch_async(self.queue, ^{
        NSInteger fails = 0; NSTimeInterval until = 0;
        LoadAttempts(&fails, &until);
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (until > now) {
            memset_s(bytes.mutableBytes, bytes.length, 0, bytes.length);
            dispatch_async(dispatch_get_main_queue(), ^{ self.busy = NO; finish(DevAccessResultLockedOut, until - now); });
            return;
        }
        BOOL ok = [self verifyPasswordBytes:bytes.bytes length:bytes.length];
        NSTimeInterval wait = 0;
        if (ok) {
            SaveAttempts(0, 0);
        } else {
            fails += 1;
            wait = DelayForFailures(fails);
            SaveAttempts(fails, wait > 0 ? [[NSDate date] timeIntervalSince1970] + wait : 0);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (ok) {
                [self.lockTimer invalidate];
                @synchronized (self) { self.sessionPassword = bytes; }
                self.unlocked = YES;
                __weak typeof(self) weakSelf = self;
                self.lockTimer = [NSTimer scheduledTimerWithTimeInterval:kSessionLifetime repeats:NO block:^(NSTimer *t) { [weakSelf lock]; }];
                finish(DevAccessResultOK, 0);
            } else {
                memset_s(bytes.mutableBytes, bytes.length, 0, bytes.length);
                finish(wait > 0 ? DevAccessResultLockedOut : DevAccessResultWrong, wait);
            }
        });
    });
}

- (BOOL)decryptFileAtPath:(NSString *)source toPath:(NSString *)destination reason:(NSString **)reason {
    NSData *password;
    @synchronized (self) { password = [self.sessionPassword copy]; }
    if (password.length == 0) { if (reason) *reason = @"locked"; return NO; }

    NSError *error = nil;
    NSData *file = [NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:&error];
    const size_t header = sizeof(kMagic) + 16 + 16;
    if (!file || file.length < header + 16 + CC_SHA256_DIGEST_LENGTH) { if (reason) *reason = @"too short"; return NO; }
    const uint8_t *bytes = file.bytes;
    if (memcmp(bytes, kMagic, sizeof(kMagic)) != 0) { if (reason) *reason = @"bad magic"; return NO; }
    const uint8_t *salt = bytes + sizeof(kMagic);
    const uint8_t *iv = salt + 16;
    const uint8_t *ct = bytes + header;
    size_t ctLen = file.length - header - CC_SHA256_DIGEST_LENGTH;
    const uint8_t *tag = bytes + file.length - CC_SHA256_DIGEST_LENGTH;
    if (ctLen == 0 || ctLen % 16 != 0) { if (reason) *reason = @"bad length"; return NO; }

    uint8_t keys[64];
    if (!Pbkdf2(password.bytes, password.length, salt, 16, kCCPRFHmacAlgSHA256, kFileRounds, keys, sizeof(keys))) { if (reason) *reason = @"kdf"; return NO; }

    // Authenticate first, decrypt only a file that carries a valid tag.
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmacContext ctx;
    CCHmacInit(&ctx, kCCHmacAlgSHA256, keys + 32, 32);
    CCHmacUpdate(&ctx, bytes, header + ctLen);
    CCHmacFinal(&ctx, mac);
    BOOL authentic = ConstantTimeEqual(mac, tag, sizeof(mac));
    if (!authentic) {
        memset_s(keys, sizeof(keys), 0, sizeof(keys));
        if (reason) *reason = @"authentication failed (wrong key or modified file)";
        return NO;
    }
    NSMutableData *plain = [NSMutableData dataWithLength:ctLen + kCCBlockSizeAES128];
    size_t plainLen = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, keys, 32, iv, ct, ctLen,
                                 plain.mutableBytes, plain.length, &plainLen);
    memset_s(keys, sizeof(keys), 0, sizeof(keys));
    if (st != kCCSuccess) { if (reason) *reason = @"decrypt failed"; return NO; }
    plain.length = plainLen;
    BOOL wrote = [plain writeToFile:destination options:NSDataWritingAtomic error:&error];
    if (plain.length > 0) memset_s(plain.mutableBytes, plain.length, 0, plain.length);
    if (!wrote) { if (reason) *reason = @"could not save"; return NO; }
    return YES;
}

@end
