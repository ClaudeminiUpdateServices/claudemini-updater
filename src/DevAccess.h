#import <Foundation/Foundation.h>

// Gate for the developer update channel.
//
// Protection layers (the password itself is never stored, neither in the app nor in the repository):
//   1. Only salted verifiers are in the binary, no password, no plain hash.
//   2. Verifier A: PBKDF2-HMAC-SHA256, 210 000 rounds, own salt.
//   3. Verifier B: PBKDF2-HMAC-SHA512, 150 000 rounds, independent salt.
//   4. Verifier C: an AES-256-CBC sealed blob with an HMAC-SHA256 tag; the key comes from a third PBKDF2 run.
//      A, B and C are always all computed and combined in constant time, so no single early exit leaks anything.
//   5. Developer builds in the repository are AES-256-CBC + HMAC-SHA256 encrypted (encrypt-then-MAC) with a key
//      derived from the password and a fresh salt per file. Without the password the file is useless, even to
//      someone who patches the app or downloads the release by hand.
//   6. Wrong passwords are throttled (3 free tries, then 30 s doubling up to 1 h). The counter lives in the Keychain.
//   7. The unlocked session exists only in memory, the password bytes are wiped on lock, when the app goes to the
//      background, when the device locks, when the update screen is left and after 15 minutes.
//   8. The attempt record is kept in three independent places (Keychain, a file, user defaults), each sealed with an
//      HMAC made with a per-install key. The worst of the three counts, a missing copy is restored from the others and
//      a copy that was edited by hand is punished (15 minutes locked) instead of trusted.
//   9. Clock tricks do not shorten a lock: the last time seen is remembered (the clock cannot go back) and, within one
//      boot, a monotonic clock is used as well.
//  10. Escalating throttle for good: 3 free tries, 30 s doubling up to 1 h, 6 h after 12 failures, 24 h after 20.
//  11. A debugger attached to the process, or Frida / Cycript style instrumentation in the process, blocks the unlock
//      and the decryption.
//  12. Every attempt takes at least 1.5 s, so scripted guessing through the interface gains nothing.
//  13. The decrypted build is written with complete file protection and removed as soon as the channel is left.
//  14. Before a developer build is checked, downloaded or opened, the session must still be unlocked (checked again at
//      each step, not only at the door).

typedef NS_ENUM(NSInteger, DevAccessResult) {
    DevAccessResultOK = 0,
    DevAccessResultWrong,
    DevAccessResultLockedOut,   // wait = seconds left
    DevAccessResultBusy,
    DevAccessResultInvalid,     // empty or absurdly long input
    DevAccessResultTampered,    // a debugger or instrumentation is attached: refused without trying the password
};

@interface DevAccess : NSObject
+ (instancetype)shared;
@property (assign, nonatomic, readonly) BOOL unlocked;

// Checks the password off the main thread; the completion runs on the main thread.
- (void)unlockWithPassword:(NSString *)password completion:(void (^)(DevAccessResult result, NSTimeInterval wait))completion;
- (void)lock;

// Decrypts a developer build (format below) with the session password. Blocking: call it off the main thread.
// Returns NO and fills `reason` (a short English text for the log) when the session is locked, the file is damaged
// or has been tampered with.
- (BOOL)decryptFileAtPath:(NSString *)source toPath:(NSString *)destination reason:(NSString **)reason;
@end
