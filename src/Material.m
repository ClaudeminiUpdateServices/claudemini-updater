#import "Material.h"
#import "Theme.h"
#import "Strings.h"
#import <objc/runtime.h>

static UIColor *Mix(UIColor *a, UIColor *b, CGFloat t) {
    CGFloat ar = 0, ag = 0, ab = 0, aa = 0, br = 0, bg = 0, bb = 0, ba = 0;
    [a getRed:&ar green:&ag blue:&ab alpha:&aa];
    [b getRed:&br green:&bg blue:&bb alpha:&ba];
    return [UIColor colorWithRed:ar + (br - ar) * t green:ag + (bg - ag) * t blue:ab + (bb - ab) * t alpha:1];
}

static UIBezierPath *RoundedPath(CGRect r, CGFloat top, CGFloat bottom) {
    top = MAX(0, MIN(top, r.size.height / 2.0));
    bottom = MAX(0, MIN(bottom, r.size.height / 2.0));
    CGFloat minX = CGRectGetMinX(r), maxX = CGRectGetMaxX(r), minY = CGRectGetMinY(r), maxY = CGRectGetMaxY(r);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(minX + top, minY)];
    [p addLineToPoint:CGPointMake(maxX - top, minY)];
    [p addArcWithCenter:CGPointMake(maxX - top, minY + top) radius:top startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(maxX, maxY - bottom)];
    [p addArcWithCenter:CGPointMake(maxX - bottom, maxY - bottom) radius:bottom startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(minX + bottom, maxY)];
    [p addArcWithCenter:CGPointMake(minX + bottom, maxY - bottom) radius:bottom startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(minX, minY + top)];
    [p addArcWithCenter:CGPointMake(minX + top, minY + top) radius:top startAngle:M_PI endAngle:1.5 * M_PI clockwise:YES];
    [p closePath];
    return p;
}

#pragma mark - MaterialCardView

@interface MaterialCardView ()
@property (strong, nonatomic) CAShapeLayer *shape;
@property (assign, nonatomic) BOOL pressedState;
@end

@implementation MaterialCardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _shape = [CAShapeLayer layer];
        [self.layer addSublayer:_shape];
        _topRadius = 6;
        _bottomRadius = 6;
        _cardInsets = UIEdgeInsetsMake(1.5, 0, 1.5, 0);
    }
    return self;
}

- (UIBezierPath *)pathForPressed:(BOOL)pressed {
    CGRect rect = UIEdgeInsetsInsetRect(self.bounds, self.cardInsets);
    if (pressed) {
        CGFloat round = MIN(28, rect.size.height / 2.0);   // fully round when pressed
        return RoundedPath(rect, round, round);
    }
    return RoundedPath(rect, self.topRadius, self.bottomRadius);
}

- (void)setPressed:(BOOL)pressed animated:(BOOL)animated {
    if (pressed == self.pressedState) return;
    self.pressedState = pressed;
    UIBezierPath *target = [self pressedStatePath];
    if (animated) {
        CASpringAnimation *morph = [CASpringAnimation animationWithKeyPath:@"path"];
        morph.fromValue = (__bridge id)(self.shape.presentationLayer ? ((CAShapeLayer *)self.shape.presentationLayer).path : self.shape.path);
        morph.toValue = (__bridge id)target.CGPath;
        morph.mass = 1; morph.stiffness = 420; morph.damping = 24; morph.initialVelocity = 0;
        morph.duration = morph.settlingDuration;
        [self.shape addAnimation:morph forKey:@"morph"];

        CASpringAnimation *dip = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
        dip.fromValue = @([[self.layer.presentationLayer valueForKeyPath:@"transform.scale"] doubleValue] ?: 1);
        dip.toValue = @(pressed ? 0.975 : 1.0);
        dip.mass = 1; dip.stiffness = 480; dip.damping = 18; dip.initialVelocity = 0;
        dip.duration = dip.settlingDuration;
        [self.layer addAnimation:dip forKey:@"dip"];
    }
    self.shape.path = target.CGPath;
    self.layer.transform = pressed ? CATransform3DMakeScale(0.975, 0.975, 1) : CATransform3DIdentity;
}

- (UIBezierPath *)pressedStatePath { return [self pathForPressed:self.pressedState]; }

- (void)rippleFrom:(CGPoint)point {
    CGRect rect = UIEdgeInsetsInsetRect(self.bounds, self.cardInsets);
    if (rect.size.width < 2) return;
    CALayer *host = [CALayer layer];
    host.frame = self.bounds;
    CAShapeLayer *clip = [CAShapeLayer layer];
    clip.frame = self.bounds;
    clip.path = [self pathForPressed:self.pressedState].CGPath;
    host.mask = clip;
    CGFloat maxDistance = 0;
    CGPoint corners[4] = { rect.origin, CGPointMake(CGRectGetMaxX(rect), rect.origin.y), CGPointMake(rect.origin.x, CGRectGetMaxY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)) };
    for (int i = 0; i < 4; i++) maxDistance = MAX(maxDistance, hypot(corners[i].x - point.x, corners[i].y - point.y));
    CAShapeLayer *circle = [CAShapeLayer layer];
    circle.fillColor = [([Theme darkMode] ? [UIColor whiteColor] : [UIColor blackColor]) colorWithAlphaComponent:0.07].CGColor;   // neutral, no coloured flash
    UIBezierPath *start = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x - 1, point.y - 1, 2, 2)];
    UIBezierPath *end = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x - maxDistance, point.y - maxDistance, maxDistance * 2, maxDistance * 2)];
    circle.path = end.CGPath;
    [host addSublayer:circle];
    [self.layer addSublayer:host];

    CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"path"];
    grow.fromValue = (__bridge id)start.CGPath; grow.toValue = (__bridge id)end.CGPath;
    grow.duration = 0.55;
    grow.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.05 :0.7 :0.1 :1.0];   // emphasized decelerate
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1; fade.toValue = @0; fade.beginTime = CACurrentMediaTime() + 0.18; fade.fillMode = kCAFillModeBackwards;
    fade.duration = 0.42;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[grow, fade];
    group.duration = 0.62;
    group.removedOnCompletion = YES;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{ [host removeFromSuperlayer]; }];
    [circle addAnimation:group forKey:@"ripple"];
    circle.opacity = 0;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect rect = UIEdgeInsetsInsetRect(self.bounds, self.cardInsets);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shape.frame = self.bounds;
    self.shape.path = [self pathForPressed:self.pressedState].CGPath;
    (void)rect;
    self.shape.fillColor = (self.fillColor ?: [Theme surface]).CGColor;
    [CATransaction commit];
}

@end

#pragma mark - MaterialSwitch

@interface MaterialSwitch ()
@property (strong, nonatomic) UIView *track;
@property (strong, nonatomic) UIView *thumb;
@end

@implementation MaterialSwitch

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, 52, 32)];
    if (self) {
        _track = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 52, 32)];
        _track.layer.cornerRadius = 16;
        _track.userInteractionEnabled = NO;
        [self addSubview:_track];
        _thumb = [[UIView alloc] init];
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        [self applyState];
    }
    return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(52, 32); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(52, 32); }

- (void)tapped { [self setOn:!self.on animated:YES]; [self sendActionsForControlEvents:UIControlEventValueChanged]; }

- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    if (animated) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ [self applyState]; } completion:nil];
    else [self applyState];
}

- (void)applyState {
    UIColor *accent = [Theme accent];
    CGFloat d = self.on ? 24 : 16;
    CGFloat x = self.on ? 52 - 4 - d : 8;
    self.thumb.frame = CGRectMake(x, (32 - d) / 2.0, d, d);
    self.thumb.layer.cornerRadius = d / 2.0;
    if (self.on) {
        self.track.backgroundColor = accent;
        self.track.layer.borderWidth = 2;
        self.track.layer.borderColor = accent.CGColor;
        self.thumb.backgroundColor = [Theme background];
        self.thumb.layer.borderWidth = 2;
        self.thumb.layer.borderColor = Mix(accent, [UIColor whiteColor], 0.45).CGColor;
    } else {
        self.track.backgroundColor = [UIColor clearColor];
        self.track.layer.borderWidth = 2;
        self.track.layer.borderColor = [Theme secondaryText].CGColor;
        self.thumb.backgroundColor = [Theme secondaryText];
        self.thumb.layer.borderWidth = 0;
    }
}

@end

#pragma mark - MaterialSlider

static const CGFloat kSliderThumb = 40;
static const CGFloat kSliderTrackHeight = 28;

@interface MaterialSlider ()
@property (strong, nonatomic) CAGradientLayer *trackLayer;
@property (strong, nonatomic) UIView *thumbView;
@end

@implementation MaterialSlider

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _trackLayer = [CAGradientLayer layer];
        _trackLayer.startPoint = CGPointMake(0, 0.5);
        _trackLayer.endPoint = CGPointMake(1, 0.5);
        _trackLayer.cornerRadius = kSliderTrackHeight / 2.0;
        [self.layer addSublayer:_trackLayer];
        _thumbView = [[UIView alloc] init];
        _thumbView.userInteractionEnabled = NO;
        _thumbView.layer.cornerRadius = kSliderThumb / 2.0;
        _thumbView.layer.borderWidth = 4;
        _thumbView.layer.borderColor = [UIColor whiteColor].CGColor;
        [self addSubview:_thumbView];
        _thumbColor = [UIColor grayColor];
        _trackColors = @[[UIColor blackColor], [UIColor whiteColor]];
        [self applyColors];
    }
    return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, kSliderThumb + 4); }

- (void)applyColors {
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *c in self.trackColors) [cg addObject:(id)c.CGColor];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.trackLayer.colors = cg;
    [CATransaction commit];
    self.thumbView.backgroundColor = self.thumbColor;
}

- (void)setTrackColors:(NSArray<UIColor *> *)trackColors { _trackColors = [trackColors copy]; [self applyColors]; }
- (void)setThumbColor:(UIColor *)thumbColor { _thumbColor = thumbColor; self.thumbView.backgroundColor = thumbColor; }

- (CGFloat)travelStart { return kSliderThumb / 2.0; }
- (CGFloat)travelLength { return MAX(1, self.bounds.size.width - kSliderThumb); }

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.trackLayer.frame = CGRectMake(0, (self.bounds.size.height - kSliderTrackHeight) / 2.0, self.bounds.size.width, kSliderTrackHeight);
    [CATransaction commit];
    [self placeThumb];
}

- (void)placeThumb {
    CGFloat cx = [self travelStart] + self.value * [self travelLength];
    self.thumbView.frame = CGRectMake(cx - kSliderThumb / 2.0, (self.bounds.size.height - kSliderThumb) / 2.0, kSliderThumb, kSliderThumb);
}

- (void)setValue:(CGFloat)value { [self setValue:value animated:NO]; }

- (void)setValue:(CGFloat)value animated:(BOOL)animated {
    _value = MAX(0, MIN(1, value));
    if (animated) [UIView animateWithDuration:0.2 animations:^{ [self placeThumb]; }];
    else [self placeThumb];
}

- (void)updateFromTouch:(UITouch *)touch {
    CGFloat x = [touch locationInView:self].x;
    CGFloat v = (x - [self travelStart]) / [self travelLength];
    v = MAX(0, MIN(1, v));
    if (fabs(v - _value) < 0.0005) return;
    _value = v;
    [self placeThumb];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self updateFromTouch:touch];
    [self growThumb:YES];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self updateFromTouch:touch]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { if (touch) [self updateFromTouch:touch]; [self growThumb:NO]; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { [self growThumb:NO]; }

// The thumb swells under the finger and springs back (Expressive slider feel).
- (void)growThumb:(BOOL)grow {
    CGAffineTransform target = grow ? CGAffineTransformMakeScale(1.18, 1.18) : CGAffineTransformIdentity;
    if (UIAccessibilityIsReduceMotionEnabled()) { self.thumbView.transform = target; return; }
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.thumbView.transform = target;
    } completion:nil];
}

// A generous touch area: the whole row of the slider, a little beyond its edges.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -8, -10), point);
}

@end

#pragma mark - MaterialMascotView

// Proxy so the display link does not retain the view (a retained view would never be released).
@interface MascotLinkProxy : NSObject
@property (weak, nonatomic) MaterialMascotView *view;
- (void)tick:(CADisplayLink *)link;
@end

#define MASCOT_SAMPLES 160
#define MASCOT_SHAPES 8

@interface MaterialMascotView ()
@property (strong, nonatomic) CAShapeLayer *shapeLayer;
@property (strong, nonatomic) CADisplayLink *link;
@property (assign, nonatomic) CFTimeInterval lastTime;
@property (assign, nonatomic) CFTimeInterval idleTime;   // time since the last morph, for the automatic cycle
@property (assign, nonatomic) NSInteger shapeIndex;
@property (assign, nonatomic) CGFloat progress;          // 0...1 of the running morph (1 = finished)
@property (assign, nonatomic) CGFloat angle;
@property (assign, nonatomic) CGFloat spin;              // extra angular speed that fades out after a morph
@end

@implementation MascotLinkProxy
- (void)tick:(CADisplayLink *)link { [self.view step:link]; }
@end

static CGFloat gMascotFrom[MASCOT_SAMPLES], gMascotTo[MASCOT_SAMPLES];

// Radius of shape `index` (before normalising) at angle t. The set walks through the Material 3 Expressive
// shapes: circle, cookie, clover, burst, soft square, flower, soft triangle, sunny.
static CGFloat MascotRadius(NSInteger index, CGFloat t) {
    switch (index % MASCOT_SHAPES) {
        case 0: return 1.0;
        case 1: return 1.0 + 0.085 * cos(9 * t);
        case 2: return 1.0 + 0.24 * cos(4 * t);
        case 3: { CGFloat c = fabs(cos(6 * t)); return 0.80 + 0.20 * pow(c, 0.55); }
        case 4: { CGFloat c = fabs(cos(t)), s = fabs(sin(t)); return 1.0 / pow(pow(c, 4.5) + pow(s, 4.5), 1.0 / 4.5); }
        case 5: return 1.0 + 0.18 * cos(5 * t);
        case 6: return 1.0 + 0.30 * cos(3 * t);
        default: return 1.0 + 0.10 * cos(12 * t) + 0.04 * cos(24 * t);
    }
}

static void MascotFill(CGFloat *out, NSInteger index) {
    CGFloat peak = 0;
    for (int i = 0; i < MASCOT_SAMPLES; i++) {
        out[i] = MascotRadius(index, (CGFloat)i / MASCOT_SAMPLES * 2 * M_PI);
        if (out[i] > peak) peak = out[i];
    }
    if (peak > 0) for (int i = 0; i < MASCOT_SAMPLES; i++) out[i] /= peak;
}

@implementation MaterialMascotView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _shapeColor = [UIColor colorWithWhite:1 alpha:0.35];
        _shapeLayer = [CAShapeLayer layer];
        _shapeLayer.fillColor = _shapeColor.CGColor;
        [self.layer addSublayer:_shapeLayer];
        _shapeIndex = 1;
        _progress = 1;
        MascotFill(gMascotTo, 1);
        memcpy(gMascotFrom, gMascotTo, sizeof(gMascotTo));
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        [self rebuildPath];
    }
    return self;
}

- (void)dealloc { [self.link invalidate]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)appBecameActive { if (self.window) [self startLink]; }

- (void)startLink {
    if (self.link || UIAccessibilityIsReduceMotionEnabled()) return;
    MascotLinkProxy *proxy = [[MascotLinkProxy alloc] init];
    proxy.view = self;
    self.link = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    self.link.preferredFramesPerSecond = 60;
    self.lastTime = 0;
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopLink { [self.link invalidate]; self.link = nil; }

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self startLink]; else [self stopLink];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shapeLayer.frame = self.bounds;
    [CATransaction commit];
    [self rebuildPath];
}

- (void)setShapeColor:(UIColor *)shapeColor {
    _shapeColor = shapeColor;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shapeLayer.fillColor = shapeColor.CGColor;
    [CATransaction commit];
}

// The hue picks the shape, so dragging the hue slider morphs the figure from one shape to the next.
- (void)setHue:(CGFloat)hue {
    _hue = hue;
    NSInteger target = (NSInteger)floor(MAX(0, MIN(0.999, hue)) * MASCOT_SHAPES);
    if (target != self.shapeIndex) [self morphToShape:target];
}

- (void)morphToShape:(NSInteger)index {
    // start from what is on screen right now, so a morph interrupted half-way continues smoothly
    CGFloat s = [self easedProgress];
    for (int i = 0; i < MASCOT_SAMPLES; i++) gMascotFrom[i] = gMascotFrom[i] + (gMascotTo[i] - gMascotFrom[i]) * s;
    self.shapeIndex = index;
    MascotFill(gMascotTo, index);
    self.progress = 0;
    self.idleTime = 0;
    self.spin = 5.5;   // the figure turns quickly while it changes, then settles to a slow turn
    if (!self.link || UIAccessibilityIsReduceMotionEnabled()) { self.progress = 1; [self rebuildPath]; }
}

- (void)morphToNext { [self morphToShape:(self.shapeIndex + 1) % MASCOT_SHAPES]; }

// Spring-like curve with a small overshoot, like the Expressive "spatial" motion.
- (CGFloat)easedProgress {
    CGFloat t = MAX(0, MIN(1, self.progress));
    if (t >= 1) return 1;
    return 1 - exp(-7.5 * t) * cos(10.5 * t);
}

- (void)step:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CFTimeInterval dt = self.lastTime > 0 ? MIN(0.05, now - self.lastTime) : 1.0 / 60.0;
    self.lastTime = now;
    if (self.window == nil || self.bounds.size.width < 1) return;

    self.angle += (0.55 + self.spin) * dt;                       // always turning
    if (self.angle > 2 * M_PI) self.angle -= 2 * M_PI;
    self.spin = MAX(0, self.spin - dt * 5.0);
    if (self.progress < 1) {
        self.progress = MIN(1, self.progress + dt / 0.85);
    } else {
        self.idleTime += dt;
        if (self.idleTime > 2.6) [self morphToNext];             // keeps changing by itself while you look at it
    }
    [self rebuildPath];
}

- (void)rebuildPath {
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w < 1 || h < 1) return;
    CGFloat s = [self easedProgress];
    CGPoint center = CGPointMake(w / 2.0, h / 2.0);
    CGFloat radius = MIN(w, h) / 2.0 * 0.94;
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (int i = 0; i <= MASCOT_SAMPLES; i++) {
        int k = i % MASCOT_SAMPLES;
        CGFloat r = radius * (gMascotFrom[k] + (gMascotTo[k] - gMascotFrom[k]) * s);
        CGFloat a = (CGFloat)k / MASCOT_SAMPLES * 2 * M_PI + self.angle;
        CGPoint pt = CGPointMake(center.x + r * cos(a), center.y + r * sin(a));
        if (i == 0) [path moveToPoint:pt]; else [path addLineToPoint:pt];
    }
    [path closePath];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shapeLayer.path = path.CGPath;
    [CATransaction commit];
}

@end

#pragma mark - MaterialGradientView

@implementation MaterialGradientView

+ (Class)layerClass { return [CAGradientLayer class]; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        CAGradientLayer *layer = (CAGradientLayer *)self.layer;
        layer.startPoint = CGPointMake(0, 0);
        layer.endPoint = CGPointMake(1, 1);
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(refreshColors) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(stopMoving) name:UIApplicationWillResignActiveNotification object:nil];
        [self refreshColors];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self refreshColors]; else [self stopMoving];
}

- (void)stopMoving {
    [self.layer removeAllAnimations];
}

- (void)refreshColors {
    CAGradientLayer *layer = (CAGradientLayer *)self.layer;
    NSArray<UIColor *> *colors = [Theme gradientWallpaperColors];
    NSMutableArray *a = [NSMutableArray array], *b = [NSMutableArray array];
    for (UIColor *c in colors) [a addObject:(id)c.CGColor];
    for (NSUInteger i = 0; i < colors.count; i++) [b addObject:(id)colors[(i + 2) % colors.count].CGColor];
    [self.layer removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.colors = a;
    [CATransaction commit];
    if (!self.window || UIAccessibilityIsReduceMotionEnabled()) return;

    CABasicAnimation *shift = [CABasicAnimation animationWithKeyPath:@"colors"];
    shift.fromValue = a; shift.toValue = b;
    shift.duration = 9; shift.autoreverses = YES; shift.repeatCount = HUGE_VALF;
    shift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:shift forKey:@"colors"];

    CABasicAnimation *start = [CABasicAnimation animationWithKeyPath:@"startPoint"];
    start.fromValue = [NSValue valueWithCGPoint:CGPointMake(0, 0)]; start.toValue = [NSValue valueWithCGPoint:CGPointMake(1, 0.25)];
    start.duration = 11; start.autoreverses = YES; start.repeatCount = HUGE_VALF;
    start.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:start forKey:@"start"];

    CABasicAnimation *end = [CABasicAnimation animationWithKeyPath:@"endPoint"];
    end.fromValue = [NSValue valueWithCGPoint:CGPointMake(1, 1)]; end.toValue = [NSValue valueWithCGPoint:CGPointMake(0.2, 0.8)];
    end.duration = 13; end.autoreverses = YES; end.repeatCount = HUGE_VALF;
    end.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:end forKey:@"end"];
}

@end

#pragma mark - Section header

@interface MaterialSectionHeader : UIView
@property (strong, nonatomic) UILabel *label;
@property (strong, nonatomic) UIImageView *chevron;
@property (copy, nonatomic) void (^tap)(void);
@end

@implementation MaterialSectionHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [[UILabel alloc] init];
        _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        _label.textColor = [Theme accent];
        [self addSubview:_label];
        _chevron = [[UIImageView alloc] init];
        _chevron.tintColor = [Theme secondaryText];
        [self addSubview:_chevron];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    }
    return self;
}

- (void)tapped { if (self.tap) self.tap(); }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    self.label.frame = CGRectMake(10, h - 34, w - 60, 24);
    self.chevron.frame = CGRectMake(w - 38, h - 34, 24, 24);
}

@end

#pragma mark - Title

@interface MaterialTitleLabel : UILabel
@end
@implementation MaterialTitleLabel
- (CGSize)intrinsicContentSize { return CGSizeMake(10000, 44); }
@end

#pragma mark - Press handling of table rows

@interface MaterialPressHandler : NSObject <UIGestureRecognizerDelegate>
@property (weak, nonatomic) UITableView *table;
@property (weak, nonatomic) MaterialCardView *pressedCard;
@property (assign, nonatomic) CGPoint start;
@end

@implementation MaterialPressHandler

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

- (void)release_ {
    [self.pressedCard setPressed:NO animated:YES];
    self.pressedCard = nil;
}

- (void)pressed:(UILongPressGestureRecognizer *)gesture {
    if (![Material active]) { [self release_]; return; }
    CGPoint point = [gesture locationInView:self.table];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.start = point;
        NSIndexPath *path = [self.table indexPathForRowAtPoint:point];
        UITableViewCell *cell = path ? [self.table cellForRowAtIndexPath:path] : nil;
        if ([cell.backgroundView isKindOfClass:[MaterialCardView class]]) {
            MaterialCardView *card = (MaterialCardView *)cell.backgroundView;
            self.pressedCard = card;
            [card setPressed:YES animated:YES];
            [card rippleFrom:[gesture locationInView:card]];
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (hypot(point.x - self.start.x, point.y - self.start.y) > 12) [self release_];   // it became a scroll
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self release_];
    }
}

@end

#pragma mark - Buttons: spring dip while pressed (Material design only)

@interface UIButton (MaterialPress)
@end

@implementation UIButton (MaterialPress)

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method original = class_getInstanceMethod(self, @selector(setHighlighted:));
        Method replacement = class_getInstanceMethod(self, @selector(mat_setHighlighted:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

- (void)mat_setHighlighted:(BOOL)highlighted {
    BOOL changed = self.highlighted != highlighted;
    [self mat_setHighlighted:highlighted];   // the original
    if (!changed || ![Theme materialDesign] || UIAccessibilityIsReduceMotionEnabled()) return;
    if (!CATransform3DIsIdentity(self.layer.transform) && ![self.layer animationForKey:@"matpress"]) return;   // a button that is rotated / scaled on purpose keeps its own transform
    if (self.bounds.size.width < 24 || self.bounds.size.height < 24) return;
    CALayer *layer = self.layer;
    CGFloat current = [[layer.presentationLayer valueForKeyPath:@"transform.scale"] doubleValue];
    if (current < 0.5) current = 1;
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    spring.fromValue = @(current);
    spring.toValue = @(highlighted ? 0.93 : 1.0);
    spring.mass = 1; spring.stiffness = highlighted ? 520 : 380; spring.damping = highlighted ? 26 : 15;
    spring.duration = spring.settlingDuration;
    spring.fillMode = kCAFillModeForwards;
    spring.removedOnCompletion = !highlighted;
    [layer removeAnimationForKey:@"matpress"];
    [layer addAnimation:spring forKey:@"matpress"];
}

@end

#pragma mark - Material

@implementation Material

+ (BOOL)active { return [Theme materialDesign]; }

+ (UITableViewCellStyle)cellStyle:(UITableViewCellStyle)classic {
    return [self active] ? UITableViewCellStyleSubtitle : classic;
}

+ (void)decorateTable:(UITableView *)table {
    if (![self active]) return;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.showsVerticalScrollIndicator = NO;
    if (table.rowHeight < 60) table.rowHeight = 64;
    [self installTableEffects:table];
}

+ (void)layoutTable:(UITableView *)table inBounds:(CGRect)bounds {
    CGRect frame = [self active] ? CGRectInset(bounds, 12, 0) : bounds;
    if (!CGRectEqualToRect(table.frame, frame)) table.frame = frame;
}

+ (UIImage *)chevronImageRight {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(14, 20)];
        image = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(4, 3)];
            [p addLineToPoint:CGPointMake(10.5, 10)];
            [p addLineToPoint:CGPointMake(4, 17)];
            p.lineWidth = 2.2; p.lineCapStyle = kCGLineCapRound; p.lineJoinStyle = kCGLineJoinRound;
            [[UIColor blackColor] setStroke];
            [p stroke];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return image;
}

+ (void)decorateCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath inTable:(UITableView *)table {
    if (![self active]) return;
    NSInteger count = [table numberOfRowsInSection:indexPath.section];
    BOOL first = indexPath.row == 0, last = indexPath.row == count - 1;
    const CGFloat big = 26, small = 6;

    MaterialCardView *card = [[MaterialCardView alloc] init];
    card.fillColor = [Theme surface];
    card.topRadius = first ? big : small;
    card.bottomRadius = last ? big : small;
    cell.backgroundView = card;

    MaterialCardView *selected = [[MaterialCardView alloc] init];
    selected.fillColor = [Theme surface];   // no coloured highlight while touching; the press is shown by the shape and the ripple
    selected.topRadius = card.topRadius;
    selected.bottomRadius = card.bottomRadius;
    cell.selectedBackgroundView = selected;
    cell.backgroundColor = [UIColor clearColor];

    if (cell.accessoryType == UITableViewCellAccessoryDisclosureIndicator) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[self chevronImageRight]];
        chevron.tintColor = [Theme secondaryText];
        cell.accessoryView = chevron;
    }
    // Balanced sizes: 16 pt title, 13 pt supporting text (the reference app uses small, calm text).
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    if (cell.detailTextLabel.text.length > 0) cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    [self enterCell:cell atIndexPath:indexPath inTable:table];
}

#pragma mark - Expressive motion

static const void *kEntranceKey = &kEntranceKey;
static const void *kPressHandlerKey = &kPressHandlerKey;

+ (CGFloat)classic:(CGFloat)classic material:(CGFloat)material { return [self active] ? material : classic; }

+ (void)springAnimations:(void (^)(void))animations {
    if (UIAccessibilityIsReduceMotionEnabled()) { animations(); return; }
    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:animations completion:nil];
}

// The rows that appear in the next moment spring up one after another (first screen opening, or after a reload).
+ (void)markTableForEntrance:(UITableView *)table {
    if (![self active] || UIAccessibilityIsReduceMotionEnabled()) return;
    objc_setAssociatedObject(table, kEntranceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UITableView *weakTable = table;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakTable) objc_setAssociatedObject(weakTable, kEntranceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

+ (void)enterCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath inTable:(UITableView *)table {
    if (![objc_getAssociatedObject(table, kEntranceKey) boolValue]) return;
    NSInteger order = 0;
    for (NSInteger section = 0; section < indexPath.section; section++) order += [table numberOfRowsInSection:section];
    order += indexPath.row;
    if (order > 14) return;
    cell.alpha = 0;
    cell.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.94, 0.94), CGAffineTransformMakeTranslation(0, 26));
    [UIView animateWithDuration:0.62 delay:0.035 * order usingSpringWithDamping:0.74 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ cell.alpha = 1; cell.transform = CGAffineTransformIdentity; } completion:nil];
}

+ (void)installTableEffects:(UITableView *)table {
    if (objc_getAssociatedObject(table, kPressHandlerKey)) return;
    MaterialPressHandler *handler = [[MaterialPressHandler alloc] init];
    handler.table = table;
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(pressed:)];
    press.minimumPressDuration = 0;
    press.cancelsTouchesInView = NO;
    press.delaysTouchesBegan = NO;
    press.delaysTouchesEnded = NO;
    press.delegate = handler;
    [table addGestureRecognizer:press];
    objc_setAssociatedObject(table, kPressHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (CGFloat)headerHeight { return 54; }

+ (UIView *)headerViewWithTitle:(NSString *)title collapsed:(BOOL)collapsed collapsible:(BOOL)collapsible tap:(void (^)(void))tap {
    MaterialSectionHeader *header = [[MaterialSectionHeader alloc] initWithFrame:CGRectMake(0, 0, 320, [self headerHeight])];
    header.label.text = title;
    header.label.textColor = [Theme accent];
    header.chevron.hidden = !collapsible;
    UIImage *base = [self chevronImageRight];
    header.chevron.image = base;
    header.chevron.contentMode = UIViewContentModeCenter;
    header.chevron.transform = CGAffineTransformMakeRotation(collapsed ? 0 : M_PI_2);   // right when closed, down when open
    header.chevron.tintColor = [Theme secondaryText];
    header.tap = collapsible ? tap : nil;
    return header;
}

+ (void)toggleSection:(NSInteger)section collapsed:(NSMutableSet<NSNumber *> *)collapsed inTable:(UITableView *)table header:(UIView *)header {
    NSNumber *key = @(section);
    BOOL willCollapse = ![collapsed containsObject:key];
    // The table view's own numberOfRowsInSection: answers from a cache of the last update (0 while folded),
    // so the count is asked from the data source directly.
    NSInteger count;
    if (willCollapse) {
        count = [table.dataSource tableView:table numberOfRowsInSection:section];   // rows on screen now
        [collapsed addObject:key];
    } else {
        [collapsed removeObject:key];
        count = [table.dataSource tableView:table numberOfRowsInSection:section];   // rows that come back
    }
    NSMutableArray<NSIndexPath *> *paths = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) [paths addObject:[NSIndexPath indexPathForRow:i inSection:section]];

    if ([header isKindOfClass:[MaterialSectionHeader class]]) {
        UIImageView *chevron = ((MaterialSectionHeader *)header).chevron;
        CGAffineTransform target = CGAffineTransformMakeRotation(willCollapse ? 0 : M_PI_2);
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.6 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ chevron.transform = target; } completion:nil];
    }
    if (count == 0 || UIAccessibilityIsReduceMotionEnabled()) { [table reloadData]; return; }

    if (willCollapse) {
        [table beginUpdates];
        [table deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationFade];
        [table endUpdates];
        return;
    }
    // Unfolding: the rows below slide down while the new rows spring in one after another.
    [table beginUpdates];
    [table insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
    [table endUpdates];
    NSInteger order = 0;
    for (NSIndexPath *path in paths) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:path];
        if (!cell) continue;
        cell.alpha = 0;
        cell.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.92, 0.92), CGAffineTransformMakeTranslation(0, -22));
        [UIView animateWithDuration:0.62 delay:0.05 * order usingSpringWithDamping:0.72 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ cell.alpha = 1; cell.transform = CGAffineTransformIdentity; } completion:nil];
        order++;
    }
}

+ (void)styleTitleForController:(UIViewController *)controller {
    UINavigationItem *item = controller.navigationItem;
    if (![self active]) {
        if ([item.titleView isKindOfClass:[MaterialTitleLabel class]]) item.titleView = nil;
        return;
    }
    MaterialTitleLabel *label = [item.titleView isKindOfClass:[MaterialTitleLabel class]] ? (MaterialTitleLabel *)item.titleView : [[MaterialTitleLabel alloc] init];
    label.text = controller.title;
    label.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    label.textColor = [Theme text];
    label.textAlignment = NSTextAlignmentLeft;
    [label sizeToFit];
    item.titleView = label;
}

+ (UIImage *)circleIconWithGlyph:(void (^)(CGContextRef ctx))glyph {
    const CGFloat side = 40;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [Mix([Theme surface], [Theme accent], 0.24) setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
        CGContextTranslateCTM(ctx.CGContext, 5, 5);
        if (glyph) glyph(ctx.CGContext);
    }];
}

@end
