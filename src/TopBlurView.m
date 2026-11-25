#import "TopBlurView.h"
#import "Theme.h"
#import "Strings.h"

static UIBlurEffect *CurrentBlur(void) {
    return [UIBlurEffect effectWithStyle:[Theme darkMode] ? UIBlurEffectStyleDark : UIBlurEffectStyleLight];
}

#pragma mark - Progressive blur

@interface TopBlurView ()
@property (strong, nonatomic) NSArray<UIView *> *layersHost;   // containers, each masked with its own fade
@property (strong, nonatomic) NSArray<UIVisualEffectView *> *effects;
@end

@implementation TopBlurView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        // Three blurs on top of each other, each fading out at a different depth: the sum is strongest at the top edge and
        // reaches nothing at the bottom, so the blur gets lighter step by step without any colour gradient.
        NSMutableArray *hosts = [NSMutableArray array], *effects = [NSMutableArray array];
        for (NSInteger i = 0; i < 3; i++) {
            UIView *host = [[UIView alloc] init];
            host.clipsToBounds = YES;
            UIVisualEffectView *effect = [[UIVisualEffectView alloc] initWithEffect:CurrentBlur()];
            effect.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [host addSubview:effect];
            CAGradientLayer *mask = [CAGradientLayer layer];
            mask.startPoint = CGPointMake(0.5, 0);
            mask.endPoint = CGPointMake(0.5, 1);
            mask.colors = @[(id)[UIColor blackColor].CGColor, (id)[UIColor blackColor].CGColor, (id)[UIColor clearColor].CGColor];
            host.layer.mask = mask;
            [self addSubview:host];
            [hosts addObject:host];
            [effects addObject:effect];
        }
        _layersHost = hosts;
        _effects = effects;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // where each blur starts to fade and where it is gone (fractions of the height)
    static const CGFloat solid[3] = {0.55, 0.28, 0.0};
    static const CGFloat gone[3]  = {1.0, 0.78, 0.5};
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSInteger i = 0; i < 3; i++) {
        UIView *host = self.layersHost[i];
        host.frame = self.bounds;
        self.effects[i].frame = host.bounds;
        CAGradientLayer *mask = (CAGradientLayer *)host.layer.mask;
        mask.frame = host.bounds;
        mask.locations = @[@0, @(solid[i]), @(gone[i])];
    }
    [CATransaction commit];
}

- (void)refreshStyle {
    for (UIVisualEffectView *effect in self.effects) effect.effect = CurrentBlur();
}

@end

#pragma mark - Glass button

@interface GlassBarButton ()
@property (strong, nonatomic) UIVisualEffectView *glass;
@property (strong, nonatomic) UIView *tint;
@property (strong, nonatomic) UIImageView *iconView;
@end

@implementation GlassBarButton

+ (instancetype)buttonWithIcon:(UIImage *)icon label:(NSString *)label target:(id)target action:(SEL)action {
    GlassBarButton *button = [[GlassBarButton alloc] initWithFrame:CGRectMake(0, 0, 38, 38)];
    button.iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    button.accessibilityLabel = label;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityTraits = UIAccessibilityTraitButton;
        _glass = [[UIVisualEffectView alloc] initWithEffect:CurrentBlur()];
        _glass.userInteractionEnabled = NO;
        _glass.clipsToBounds = YES;
        [self addSubview:_glass];
        _tint = [[UIView alloc] init];
        _tint.userInteractionEnabled = NO;
        [_glass.contentView addSubview:_tint];
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeCenter;
        _iconView.userInteractionEnabled = NO;
        [self addSubview:_iconView];
        self.layer.borderWidth = 1;
        [self addTarget:self action:@selector(down) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kNotifThemeChanged object:nil];
        [self refresh];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (CGSize)intrinsicContentSize { return CGSizeMake(38, 38); }

- (void)layoutSubviews {
    [super layoutSubviews];
    self.glass.frame = self.bounds;
    self.tint.frame = self.glass.bounds;
    self.iconView.frame = self.bounds;
    self.layer.cornerRadius = self.bounds.size.height / 2;
    self.glass.layer.cornerRadius = self.bounds.size.height / 2;
}

- (void)refresh {
    BOOL dark = [Theme darkMode];
    self.glass.effect = CurrentBlur();
    self.tint.backgroundColor = [[Theme accent] colorWithAlphaComponent:dark ? 0.14 : 0.10];   // a hint of the accent in the glass
    self.layer.borderColor = (dark ? [UIColor colorWithWhite:1 alpha:0.18] : [UIColor colorWithWhite:0 alpha:0.10]).CGColor;
    self.iconView.tintColor = [Theme accent];
}

- (void)down {
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:nil];
}

- (void)up {
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
