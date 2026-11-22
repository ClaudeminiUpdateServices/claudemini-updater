#import "DevAccess.h"
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <time.h>
#import <unistd.h>

#ifndef P_TRACED
#define P_TRACED 0x00000800   // the process is being debugged (sys/proc.h is not in the iOS SDK)
#endif

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

// Release codes: whoever types one of these while the gate is shut ends the wait (each works once). Only salted SHA-256 hashes
// are here; the codes themselves are not in the app or in the repository.
static NSString *const kSkipSalt = @"fbb152d7b89462068826ac8b5d0bed89";
static NSString *const kSkipHashes[50] = {
    @"2bd85cd962802bb0907e020c699aff79966738c99fedd92c44b5f45aac66a954",
    @"48ce88a4101cd7301f879fea5828de8ef95f91ae6504a7d6845dc13a6b79e417",
    @"7ef6e2c3d83f52998ffaa671b7f67bf0f8d937d80ad0b90ca4c3bbe72e72217d",
    @"ef856ca4777ea6e23575e33ad09fc35bb84789772f3bc6ddcc2887920f5ffaae",
    @"e1f7e7f155acd58b1c491db3d4e39578a01fd7003863ff3aae601bd535dbbcfd",
    @"a15845a44dfb61b1b1d642202764607554e7f913946e4bac91314028eba9fba7",
    @"b6a269f0929243e4f57bbfed31931ced58fda511901620be7ceb3d1fa80ff4d3",
    @"0d461b075d4bef38c5867e6080dc4b8514bd4003c9d23811375d334163f9441e",
    @"deb24362c12660fd49055486e4a84e10ffa313de4bf4a7eb4b8bc372fbb9704c",
    @"c9b7c0f042c6354b5af99ee4188b9182f7ea0d8308a4adda48b502ca14adf338",
    @"1e6a110f14208117a2efd7a96251cc4c03494b08a4da02feeb04164a7db27305",
    @"000420c3c81f6f334e632e5b7aba4f7c0e3c6c22ce73a04ecfbe265370a1d8d8",
    @"e6376c259a2065c567cf4abf5393d7d4e0e4d8bdb27ec9371f7a196d92d76df7",
    @"cc4a1f646bf6459fe9bcfd9ef22d31fddbc8cb2797f155787755401b6f1d3b3d",
    @"e50a7d269d53d28cda3c14b64a6ff89f138d37a856f53db0c2bb261bb066906f",
    @"4916c86bcfcd935b53ef780c01bcc884f66ab1f0f30f15ac42731f75e04a7335",
    @"efb5ba4807d5d5eb7f63c0e491f62bd217b439017f754f40aa8c66f8978abe74",
    @"79ab2415b5c40726783bc6146ff721c10b035ba23da2c7e618037557574821e4",
    @"8d143b4b522bd391a198d37a42872eb108e707fc1a8fe308dbd258a7b04ac7a7",
    @"ca907f0b47c687713a6025614dee48139653af9d8c45634e4d7e88b31aa9dc76",
    @"1416e2db33588c1d3fa63027e92939161fccb6d1345e9b88c80d8b582dc356e6",
    @"d7f734072ff249be339bcc26e74f2746680817919bd9debb020dc0d5c4ce6a82",
    @"2e7190e0d55574439cf5b7ef6f5bc1812b2ece557318179edfc0a36d12ca9100",
    @"8fa787b8140c1cdb7479166dfeacc67ed8e9e5d41e9fa408fdddc0a43031141a",
    @"6010077af3f30eff70aa2574ce08afca8666a8f072ae0ff81a00be04623090fd",
    @"06e6a52228af62eb2eb6cd1007bf0c2effe830d5b80ac276995ccfb0ac15a2bc",
    @"b55aa81530a3862270517758e4cd4938926b2ff3063e37646dc8422b3718e5a7",
    @"b4be5a0b933a5526d1213da0151fb173f8171d3c678946fc6f777f5c6b978859",
    @"e297d3026ecb90aa37c1729673ef08ce70e9abda74d161d1e313db4049aaa4c0",
    @"43a840d52a1ad38700a16bf96067b11888b95287381f7b976f76954bc0766df7",
    @"b5fe92eb144546f67ce9092cff646c14231f40778cb66752ab96ed0532e54fd9",
    @"10d5d795b0872d8cf3d6a608a9351f0a6330e821e8e746493f36d725e7c71fb4",
    @"8fc3c4c0a8cb6f9c034f67a71114825d16307221f86520c4d5da231ab28b6a10",
    @"e46051115b9dd610271b93ad23166807085fd501b97869f0689a453c45f0ee50",
    @"506aaaf4643665878595931506611bef1f641296f44d4a2c2c23928665a0bfc0",
    @"dcab911728f67747fa95dd4c038a085c33eb9aa0af15e9feab61816eab9a76eb",
    @"0c8b4d5a11028a2efd6551b55cdb5aeab76a23554146cff0c91ab756a823d324",
    @"4d6328c2186f420a30328dfbba993cfd918efe03f7c0815ce8538bd245fab40a",
    @"bbfa76e6c8ce346ce950d5f579b7253577a88e15998f74c0175a1efa8db6ef85",
    @"e46d13a2c7589f3f97f03f24568be38bf1cfdeb70e9fba706c41c0c7e8ad7d03",
    @"a96a4fe9a11ceb779550a9e026a2fb7e17661a0d5faf5653835353d39f287afa",
    @"e6ec4a1c3cc5c1511bb5611c1ee21cce04fb1b305d15d36500bbd805fe3f6a4b",
    @"654f56725fe16acdd3e0b9cbcfd672a45dae0271538e36ddb4d5c62d9cf16984",
    @"a93decfccb6f3da1fa8bba3330337398c839fc611b74b39d024b011f36c56790",
    @"f9dd7c9c4226db67bd5faff8aa5b72a40260e752c08dbba29745e21876446aa4",
    @"11d4f5b0736990f6917ae75710ce11a9abc49e8e84c07fe402e4b9210459a7c7",
    @"cb831560a4507648814fb4439c9f754fb20bb100ee2154b1c503c6f435f31ae4",
    @"e4f1e895ece63e826c891366fa07633fa88e30a806e31fec77a4c2fdffa35fbd",
    @"13cfd034669973a3d0bd3583b2e41b5c52a8a934017d3379d9c474b01c78965e",
    @"27cca11d89be4a26628249fe3eb450e2f17a98873f73e0dafa7aa7abd9fb951a"
};

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

#pragma mark - Attempt record (three sealed copies)

typedef struct {
    NSInteger fails;          // wrong passwords since the last success
    NSTimeInterval until;     // wall-clock time until which the gate is shut
    NSTimeInterval seen;      // latest wall-clock time ever observed here (the clock cannot be turned back)
    NSTimeInterval boot;      // boot time of the device when `mono` was written
    NSTimeInterval mono;      // monotonic-clock time (seconds) until which the gate is shut
    BOOL valid;
    unsigned long long used;  // bit i set = release code number i was used (each code works once)
} AttemptRecord;

static NSString *const kInstallKeyAccount = @"installkey";
static NSString *const kDefaultsKey = @"cm.gate.v2";

static NSDictionary *KeychainQueryFor(NSString *account) {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: kKeychainService,
              (__bridge id)kSecAttrAccount: account };
}

static NSData *KeychainRead(NSString *account) {
    NSMutableDictionary *q = [KeychainQueryFor(account) mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess || !result) return nil;
    return (__bridge_transfer NSData *)result;
}

static void KeychainWrite(NSString *account, NSData *data) {
    if (!data) return;
    NSDictionary *query = KeychainQueryFor(account);
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

// A random per-install key that seals the attempt records. It lives in the Keychain, this device only.
static NSData *InstallKey(void) {
    NSData *key = KeychainRead(kInstallKeyAccount);
    if (key.length == 32) return key;
    uint8_t bytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;
    key = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    memset_s(bytes, sizeof(bytes), 0, sizeof(bytes));
    KeychainWrite(kInstallKeyAccount, key);
    return key;
}

static NSString *RecordFilePath(void) {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    if (dir.length == 0) return nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@".cmgate"];
}

static NSTimeInterval MonotonicSeconds(void) {
    return (NSTimeInterval)clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9;
}

static NSTimeInterval BootTime(void) {
    struct timeval boot;
    size_t size = sizeof(boot);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boot, &size, NULL, 0) != 0) return 0;
    return (NSTimeInterval)boot.tv_sec;
}

static NSData *SealRecord(AttemptRecord r, NSData *key) {
    NSDictionary *dict = @{ @"f": @(r.fails), @"u": @(r.until), @"t": @(r.seen), @"b": @(r.boot), @"m": @(r.mono), @"k": @(r.used), @"v": @2 };
    NSData *json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingSortedKeys error:nil];
    if (!json || key.length != 32) return nil;
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, json.bytes, json.length, mac);
    NSMutableData *out = [json mutableCopy];
    [out appendBytes:mac length:sizeof(mac)];
    return out;
}

// valid = the seal is correct. `tampered` is set when data was there but the seal does not match.
static AttemptRecord OpenRecord(NSData *blob, NSData *key, BOOL *tampered) {
    AttemptRecord r = {0, 0, 0, 0, 0, NO};
    if (blob.length == 0) return r;
    if (blob.length <= CC_SHA256_DIGEST_LENGTH || key.length != 32) { if (tampered) *tampered = YES; return r; }
    NSData *json = [blob subdataWithRange:NSMakeRange(0, blob.length - CC_SHA256_DIGEST_LENGTH)];
    const uint8_t *tag = (const uint8_t *)blob.bytes + blob.length - CC_SHA256_DIGEST_LENGTH;
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, json.bytes, json.length, mac);
    if (!ConstantTimeEqual(mac, tag, sizeof(mac))) { if (tampered) *tampered = YES; return r; }
    id obj = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) { if (tampered) *tampered = YES; return r; }
    r.fails = MAX(0, [obj[@"f"] integerValue]);
    r.until = [obj[@"u"] doubleValue];
    r.seen = [obj[@"t"] doubleValue];
    r.boot = [obj[@"b"] doubleValue];
    r.mono = [obj[@"m"] doubleValue];
    r.used = [obj[@"k"] unsignedLongLongValue] & ((1ull << 50) - 1);
    r.valid = YES;
    return r;
}

// 3 free tries, then 30 s doubling (30 s ... 32 min), and from the 10th wrong password on the gate is shut for 1 hour each time.
static NSTimeInterval PenaltyForFailures(NSInteger fails) {
    if (fails < 3) return 0;
    if (fails >= 10) return 3600.0;
    return 30.0 * pow(2.0, (double)(fails - 3));
}

// Reads the three copies, keeps the worst of them and restores the ones that are missing.
static AttemptRecord LoadAttempts(void) {
    NSData *key = InstallKey();
    NSString *path = RecordFilePath();
    NSData *copies[3] = { KeychainRead(kKeychainAccount),
                          path ? [NSData dataWithContentsOfFile:path] : nil,
                          [[NSUserDefaults standardUserDefaults] dataForKey:kDefaultsKey] };
    AttemptRecord worst = {0, 0, 0, 0, 0, NO};
    BOOL tampered = NO, anyMissing = NO, anyData = NO;
    NSTimeInterval bootNow = BootTime();
    for (int i = 0; i < 3; i++) {
        if (copies[i].length == 0) { anyMissing = YES; continue; }
        anyData = YES;
        BOOL bad = NO;
        AttemptRecord r = OpenRecord(copies[i], key, &bad);
        if (bad) {
            // The Keychain copy of an older build is plain JSON: accept it once and seal it again below.
            if (i == 0) {
                id legacy = [NSJSONSerialization JSONObjectWithData:copies[i] options:0 error:nil];
                if ([legacy isKindOfClass:[NSDictionary class]]) {
                    r.fails = MAX(0, [legacy[@"f"] integerValue]);
                    r.until = [legacy[@"u"] doubleValue];
                    r.valid = YES;
                    bad = NO;
                }
            }
            if (bad) tampered = YES;
        }
        if (!r.valid) continue;
        worst.valid = YES;
        worst.fails = MAX(worst.fails, r.fails);
        worst.until = MAX(worst.until, r.until);
        worst.seen = MAX(worst.seen, r.seen);
        worst.used |= r.used;   // a code that was used in any copy stays used
        if (r.mono > 0 && r.boot > 0 && fabs(r.boot - bootNow) < 3.0) {
            worst.mono = MAX(worst.mono, r.mono);
            worst.boot = r.boot;
        }
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (tampered) {
        // A record that was edited by hand is not believed: a heavy fixed penalty instead.
        worst.valid = YES;
        worst.fails = MAX(worst.fails, 5);
        worst.until = MAX(worst.until, MAX(now, worst.seen) + 900);
    }
    (void)anyData;
    if (tampered || (worst.valid && anyMissing)) {
        // Self-heal: write the combined record back to every place.
        worst.seen = MAX(worst.seen, now);
        NSData *blob = SealRecord(worst, key);
        if (blob) {
            KeychainWrite(kKeychainAccount, blob);
            if (path) [blob writeToFile:path options:NSDataWritingAtomic error:nil];
            [[NSUserDefaults standardUserDefaults] setObject:blob forKey:kDefaultsKey];
        }
    }
    return worst;
}

static void SaveAttempts(NSInteger fails, NSTimeInterval wait, unsigned long long used) {
    NSData *key = InstallKey();
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    AttemptRecord r = {0, 0, 0, 0, 0, YES};
    r.fails = fails;
    r.used = used;
    r.seen = now;
    if (wait > 0) {
        r.until = now + wait;
        r.boot = BootTime();
        r.mono = MonotonicSeconds() + wait;
    }
    NSData *blob = SealRecord(r, key);
    if (!blob) return;
    KeychainWrite(kKeychainAccount, blob);
    NSString *path = RecordFilePath();
    if (path) [blob writeToFile:path options:NSDataWritingAtomic error:nil];
    [[NSUserDefaults standardUserDefaults] setObject:blob forKey:kDefaultsKey];
}

// Seconds the gate is still shut (0 = open). The longest of the wall-clock and the monotonic view counts, and the
// wall clock can never be behind the latest time that was seen.
static NSTimeInterval RemainingLock(AttemptRecord r) {
    NSTimeInterval now = MAX([[NSDate date] timeIntervalSince1970], r.seen);
    NSTimeInterval remaining = r.until > now ? r.until - now : 0;
    if (r.mono > 0 && r.boot > 0 && fabs(r.boot - BootTime()) < 3.0) {
        NSTimeInterval m = r.mono - MonotonicSeconds();
        if (m > remaining) remaining = m;
    }
    return remaining;
}

#pragma mark - Hostile environment

// A debugger on the process, or instrumentation frameworks loaded into it. A jailbreak itself is not a reason to refuse.
static BOOL HostileEnvironment(void) {
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) == 0 && (info.kp_proc.p_flag & P_TRACED) != 0) return YES;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *lower = [[NSString stringWithUTF8String:name] lowercaseString];
        if ([lower containsString:@"frida"] || [lower containsString:@"cycript"] || [lower containsString:@"gadget"]) return YES;
    }
    return NO;
}

#pragma mark - Release codes

// Index (0...49) of the release code that was typed, or -1. All 50 are always compared, in constant time.
static NSInteger ReleaseCodeIndex(NSData *typed) {
    NSData *trimmed = typed;
    NSString *text = [[NSString alloc] initWithData:typed encoding:NSUTF8StringEncoding];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length > 0) trimmed = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSData *salt = DataFromHex(kSkipSalt);
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, salt.bytes, (CC_LONG)salt.length);
    CC_SHA256_Update(&ctx, trimmed.bytes, (CC_LONG)trimmed.length);
    CC_SHA256_Final(digest, &ctx);
    NSInteger found = -1;
    for (NSInteger i = 0; i < 50; i++) {
        NSData *expected = DataFromHex(kSkipHashes[i]);
        BOOL same = expected.length == sizeof(digest) && ConstantTimeEqual(digest, expected.bytes, sizeof(digest));
        if (same) found = i;
    }
    memset_s(digest, sizeof(digest), 0, sizeof(digest));
    return found;
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appLeft) name:UIApplicationProtectedDataWillBecomeUnavailable object:nil];   // device locked
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
    if (HostileEnvironment()) {
        memset_s(bytes.mutableBytes, bytes.length, 0, bytes.length);
        finish(DevAccessResultTampered, 0);
        return;
    }
    self.busy = YES;
    dispatch_async(self.queue, ^{
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        AttemptRecord record = LoadAttempts();
        NSInteger fails = record.fails;
        NSTimeInterval locked = RemainingLock(record);
        if (locked > 0) {
            // A release code (each works once) ends the wait; the password is still needed afterwards.
            NSInteger code = ReleaseCodeIndex(bytes);
            BOOL fresh = code >= 0 && ((record.used >> code) & 1ull) == 0;
            if (fresh) SaveAttempts(0, 0, record.used | (1ull << code));
            memset_s(bytes.mutableBytes, bytes.length, 0, bytes.length);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                if (fresh) finish(DevAccessResultSkipped, 0); else finish(DevAccessResultLockedOut, locked);
            });
            return;
        }
        BOOL ok = [self verifyPasswordBytes:bytes.bytes length:bytes.length];
        NSTimeInterval wait = 0;
        if (ok) {
            SaveAttempts(0, 0, record.used);
        } else {
            fails += 1;
            wait = PenaltyForFailures(fails);
            SaveAttempts(fails, wait, record.used);
        }
        // Every attempt takes at least 1.5 s, right or wrong, so guessing through the interface is slow.
        NSTimeInterval spent = CFAbsoluteTimeGetCurrent() - started;
        if (spent < 1.5) usleep((useconds_t)((1.5 - spent) * 1e6));
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
    if (HostileEnvironment()) { if (reason) *reason = @"instrumentation detected"; return NO; }

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
    BOOL wrote = [plain writeToFile:destination options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:&error];
    if (plain.length > 0) memset_s(plain.mutableBytes, plain.length, 0, plain.length);
    if (!wrote) { if (reason) *reason = @"could not save"; return NO; }
    return YES;
}

@end
