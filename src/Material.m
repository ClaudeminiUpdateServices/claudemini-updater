#import "Material.h"
#import "Theme.h"
#import "Strings.h"

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

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect rect = UIEdgeInsetsInsetRect(self.bounds, self.cardInsets);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shape.frame = self.bounds;
    self.shape.path = RoundedPath(rect, self.topRadius, self.bottomRadius).CGPath;
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

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self updateFromTouch:touch]; return YES; }
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self updateFromTouch:touch]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { if (touch) [self updateFromTouch:touch]; }

@end

#pragma mark - MaterialMascotView

@implementation MaterialMascotView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.backgroundColor = [UIColor clearColor]; self.userInteractionEnabled = NO; _shapeColor = [UIColor colorWithWhite:1 alpha:0.35]; }
    return self;
}

- (void)setHue:(CGFloat)hue { _hue = hue; [self setNeedsDisplay]; }
- (void)setShapeColor:(UIColor *)shapeColor { _shapeColor = shapeColor; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2.0 * 0.94;
    NSInteger lobes = 5 + (NSInteger)floor(MAX(0, MIN(0.999, self.hue)) * 7.0);   // 5...11 lobes
    CGFloat amplitude = lobes <= 6 ? 0.17 : (lobes <= 8 ? 0.13 : 0.09);
    CGFloat turn = self.hue * M_PI;
    UIBezierPath *path = [UIBezierPath bezierPath];
    const int steps = 240;
    for (int i = 0; i <= steps; i++) {
        CGFloat angle = (CGFloat)i / steps * 2 * M_PI;
        CGFloat r = radius * (1 - amplitude + amplitude * cos(lobes * angle));
        CGPoint pt = CGPointMake(center.x + r * cos(angle + turn), center.y + r * sin(angle + turn));
        if (i == 0) [path moveToPoint:pt]; else [path addLineToPoint:pt];
    }
    [path closePath];
    [self.shapeColor setFill];
    [path fill];
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
        _label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
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
    if (table.rowHeight < 60) table.rowHeight = 68;
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
    selected.fillColor = Mix([Theme surface], [Theme accent], 0.16);
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
    if (cell.detailTextLabel.text.length > 0) cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
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
