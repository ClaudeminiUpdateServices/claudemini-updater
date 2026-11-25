#import "TopBlurView.h"
#import "Theme.h"
#import "Strings.h"

static UIBlurEffect *CurrentBlur(void) {
    return [UIBlurEffect effectWithStyle:[Theme darkMode] ? UIBlurEffectStyleDark : UIBlurEffectStyleLight];
}

#pragma mark - Progressive blur

// A real blur whose strength changes with the height: the bar is cut into thin strips, every strip is a live
// UIVisualEffectView, and the strength of its blur is set with a paused UIViewPropertyAnimator (fractionComplete 1 = the
// full blur of the style, 0 = none). The strongest strip is at the top edge and the strength goes down strip by strip.
// (No colour gradient and no mask: a mask over a blur view makes the blur disappear and leaves only a tint.)
static const NSInteger kStrips = 16;

@interface TopBlurView ()
@property (strong, nonatomic) NSMutableArray<UIVisualEffectView *> *strips;
@property (strong, nonatomic) NSMutableArray<UIViewPropertyAnimator *> *animators;
@property (assign, nonatomic) BOOL darkBuilt;
@end

@implementation TopBlurView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
        _strips = [NSMutableArray array];
        _animators = [NSMutableArray array];
        // The blur of a view is reset by the system when the app comes back from the background: build it again.
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self tearDown];
}

- (void)tearDown {
    for (UIViewPropertyAnimator *animator in self.animators) [animator stopAnimation:YES];
    [self.animators removeAllObjects];
    for (UIView *strip in self.strips) [strip removeFromSuperview];
    [self.strips removeAllObjects];
}

- (void)rebuild {
    [self tearDown];
    if (self.bounds.size.height < 2) return;
    self.darkBuilt = [Theme darkMode];
    UIBlurEffect *blur = CurrentBlur();
    for (NSInteger i = 0; i < kStrips; i++) {
        UIVisualEffectView *strip = [[UIVisualEffectView alloc] initWithEffect:nil];
        [self addSubview:strip];
        [self.strips addObject:strip];
        __weak UIVisualEffectView *weakStrip = strip;
        UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
            weakStrip.effect = blur;
        }];
        animator.pausesOnCompletion = YES;
        // strength: full at the top edge, then falling off smoothly to almost nothing at the bottom
        CGFloat x = ((CGFloat)i + 0.5) / kStrips;
        animator.fractionComplete = MAX(0.0, MIN(1.0, pow(1.0 - x, 1.35)));
        [self.animators addObject:animator];
    }
    [self setNeedsLayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self rebuild];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.strips.count != kStrips || self.darkBuilt != [Theme darkMode]) { [self rebuild]; }
    CGFloat height = self.bounds.size.height, width = self.bounds.size.width;
    CGFloat step = height / kStrips;
    for (NSInteger i = 0; i < (NSInteger)self.strips.count; i++) {
        // each strip reaches a little into the next one so that no seam shows
        self.strips[i].frame = CGRectMake(0, floor(i * step), width, ceil(step) + 1);
    }
}

- (void)refreshStyle { [self rebuild]; }

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
