#import <UIKit/UIKit.h>

// A list of choices in the ClaudeMini pop-up style (rounded card, dimmed background, accent buttons), used in place of the
// iOS action sheets. It is built like UIAlertController: add actions, then present. Tapping outside the card cancels.
@interface ChoiceAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(id action))handler;
@end

@interface ChoicePopupViewController : UIViewController <UIGestureRecognizerDelegate>
+ (instancetype)popupWithTitle:(NSString *)title message:(NSString *)message;
- (void)addAction:(ChoiceAction *)action;
- (void)presentFromViewController:(UIViewController *)host;
@end
