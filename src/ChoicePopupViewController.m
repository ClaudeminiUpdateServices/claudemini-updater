#import "ChoicePopupViewController.h"
#import "Strings.h"
#import "Theme.h"

@interface ChoiceAction ()
@property (copy, nonatomic) NSString *title;
@property (assign, nonatomic) UIAlertActionStyle style;
@property (copy, nonatomic) void (^handler)(id action);
@end

@implementation ChoiceAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(id))handler {
    ChoiceAction *action = [[ChoiceAction alloc] init];
    action.title = title ?: @"";
    action.style = style;
    action.handler = handler;
    return action;
}
@end

@interface ChoicePopupViewController ()
@property (copy, nonatomic) NSString *titleText;
@property (copy, nonatomic) NSString *messageText;
@property (strong, nonatomic) NSMutableArray<ChoiceAction *> *options;   // everything except the cancel action
@property (strong, nonatomic) ChoiceAction *cancelAction;
@property (strong, nonatomic) UIView *card;
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *messageLabel;
@property (strong, nonatomic) UIScrollView *list;
@property (strong, nonatomic) UIButton *cancelButton;
@property (assign, nonatomic) BOOL finished;   // a second tap while closing does nothing
@end

static const CGFloat kRowHeight = 50;
static const CGFloat kRowGap = 8;

@implementation ChoicePopupViewController

+ (instancetype)popupWithTitle:(NSString *)title message:(NSString *)message {
    ChoicePopupViewController *popup = [[ChoicePopupViewController alloc] init];
    popup.titleText = title;
    popup.messageText = message;
    return popup;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _options = [NSMutableArray array];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)addAction:(ChoiceAction *)action {
    if (!action) return;
    if (action.style == UIAlertActionStyleCancel) self.cancelAction = action;
    else [self.options addObject:action];
}

- (void)presentFromViewController:(UIViewController *)host {
    // Over a pop-up that is still on screen the new one goes on top of it.
    UIViewController *top = host;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    [top presentViewController:self animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];

    self.card = [[UIView alloc] init];
    self.card.backgroundColor = [Theme background];
    self.card.layer.cornerRadius = 24;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [Theme border].CGColor;
    self.card.layer.shadowColor = [UIColor blackColor].CGColor;
    self.card.layer.shadowOpacity = 0.28;
    self.card.layer.shadowRadius = 24;
    self.card.layer.shadowOffset = CGSizeMake(0, 10);
    [self.view addSubview:self.card];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [Theme serifFontOfSize:22];
    self.titleLabel.textColor = [Theme text];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.text = self.titleText;
    [self.card addSubview:self.titleLabel];

    self.messageLabel = [[UILabel alloc] init];
    self.messageLabel.font = [UIFont systemFontOfSize:14];
    self.messageLabel.textColor = [Theme secondaryText];
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.text = self.messageText;
    [self.card addSubview:self.messageLabel];

    self.list = [[UIScrollView alloc] init];
    self.list.showsVerticalScrollIndicator = NO;
    self.list.alwaysBounceVertical = NO;
    [self.card addSubview:self.list];

    for (NSUInteger i = 0; i < self.options.count; i++) {
        ChoiceAction *action = self.options[i];
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.tag = (NSInteger)i;
        row.backgroundColor = [Theme surface];
        row.layer.cornerRadius = 14;
        row.layer.borderWidth = 1;
        row.layer.borderColor = [Theme border].CGColor;
        UIColor *color = action.style == UIAlertActionStyleDestructive ? [UIColor colorWithRed:0.90 green:0.22 blue:0.22 alpha:1.0] : [Theme text];
        [row setTitleColor:color forState:UIControlStateNormal];
        [row setTitle:action.title forState:UIControlStateNormal];
        row.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        row.titleLabel.numberOfLines = 2;
        row.titleLabel.textAlignment = NSTextAlignmentCenter;
        row.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        [row addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [row addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [self.list addSubview:row];
    }

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.cancelButton setTitle:self.cancelAction.title.length > 0 ? self.cancelAction.title : L(@"cancel") forState:UIControlStateNormal];
    [self.cancelButton setTitleColor:[Theme accent] forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.cancelButton.layer.cornerRadius = 14;
    self.cancelButton.layer.borderWidth = 1.5;
    self.cancelButton.layer.borderColor = [Theme accent].CGColor;
    [self.cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:self.cancelButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelTapped)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat cardWidth = MIN(bounds.size.width - 48, 340);
    CGFloat inner = cardWidth - 32;
    CGFloat available = bounds.size.height - safe.top - safe.bottom - 40;

    CGFloat y = 22;
    if (self.titleText.length > 0) {
        CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
        self.titleLabel.frame = CGRectMake(16, y, inner, ceil(titleSize.height));
        y += ceil(titleSize.height) + 6;
    } else {
        self.titleLabel.frame = CGRectZero;
    }
    if (self.messageText.length > 0) {
        CGSize messageSize = [self.messageLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
        self.messageLabel.frame = CGRectMake(16, y, inner, ceil(messageSize.height));
        y += ceil(messageSize.height) + 6;
    } else {
        self.messageLabel.frame = CGRectZero;
    }
    y += 10;

    CGFloat contentHeight = self.options.count > 0 ? self.options.count * kRowHeight + (self.options.count - 1) * kRowGap : 0;
    CGFloat footer = 12 + 48 + 18;   // gap, cancel button, bottom margin
    CGFloat listHeight = MIN(contentHeight, MAX(kRowHeight, available - y - footer));
    self.list.frame = CGRectMake(16, y, inner, listHeight);
    self.list.contentSize = CGSizeMake(inner, contentHeight);
    self.list.scrollEnabled = contentHeight > listHeight + 0.5;
    for (UIView *view in self.list.subviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        view.frame = CGRectMake(0, view.tag * (kRowHeight + kRowGap), inner, kRowHeight);
    }
    y += listHeight + 12;

    self.cancelButton.frame = CGRectMake(16, y, inner, 48);
    y += 48 + 18;

    CGFloat centerY = safe.top + (bounds.size.height - safe.top - safe.bottom) / 2;
    self.card.frame = CGRectMake((bounds.size.width - cardWidth) / 2, centerY - y / 2, cardWidth, y);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.card.transform = CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
        self.card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)rowDown:(UIButton *)row { row.backgroundColor = [[Theme accent] colorWithAlphaComponent:0.14]; }
- (void)rowUp:(UIButton *)row { row.backgroundColor = [Theme surface]; }

- (void)optionTapped:(UIButton *)row {
    if (self.finished || row.tag < 0 || row.tag >= (NSInteger)self.options.count) return;
    ChoiceAction *action = self.options[(NSUInteger)row.tag];
    [self closeThenRun:action.handler action:action];
}

- (void)cancelTapped {
    if (self.finished) return;
    [self closeThenRun:self.cancelAction.handler action:self.cancelAction];
}

- (void)closeThenRun:(void (^)(id))handler action:(ChoiceAction *)action {
    self.finished = YES;
    [self dismissViewControllerAnimated:YES completion:^{
        if (handler) handler(action);
    }];
}

// A tap outside the card cancels; taps on the card do not.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return touch.view == self.view;
}

@end
