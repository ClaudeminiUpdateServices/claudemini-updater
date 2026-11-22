#import <UIKit/UIKit.h>

// Material 3 building blocks: tonal cards for list rows, section headers, switch, slider, the cookie-shaped mascot of
// the accent colour screen and the moving gradient used as chat wallpaper. Everything is drawn in code.

#pragma mark - Card behind a list row

@interface MaterialCardView : UIView
@property (strong, nonatomic) UIColor *fillColor;
@property (assign, nonatomic) CGFloat topRadius;
@property (assign, nonatomic) CGFloat bottomRadius;
@property (assign, nonatomic) UIEdgeInsets cardInsets;   // gap between the cards of two rows
@end

#pragma mark - Switch (52 x 32, thumb grows when on)

@interface MaterialSwitch : UIControl
@property (assign, nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

#pragma mark - Slider with a gradient track and a big ring-shaped thumb (hue / saturation / brightness)

@interface MaterialSlider : UIControl
@property (assign, nonatomic) CGFloat value;                       // 0...1
@property (copy, nonatomic) NSArray<UIColor *> *trackColors;       // left to right
@property (strong, nonatomic) UIColor *thumbColor;
- (void)setValue:(CGFloat)value animated:(BOOL)animated;
@end

#pragma mark - Cookie-shaped mascot (the shape changes with the hue)

@interface MaterialMascotView : UIView
@property (strong, nonatomic) UIColor *shapeColor;
@property (assign, nonatomic) CGFloat hue;   // 0...1: decides the number of lobes and the turn
@end

#pragma mark - Moving gradient made from the accent colour

@interface MaterialGradientView : UIView
- (void)refreshColors;   // read the colours from Theme again and (re)start the movement
@end

#pragma mark - Helpers

@interface Material : NSObject
+ (BOOL)active;                                                    // Material 3 design is switched on
+ (UITableViewCellStyle)cellStyle:(UITableViewCellStyle)classic;   // Subtitle (text under the title) when active
+ (void)decorateTable:(UITableView *)table;                        // no separators, taller rows
+ (void)layoutTable:(UITableView *)table inBounds:(CGRect)bounds;  // side margins so the rows look like cards
+ (void)decorateCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath inTable:(UITableView *)table;
+ (CGFloat)headerHeight;
+ (UIView *)headerViewWithTitle:(NSString *)title collapsed:(BOOL)collapsed collapsible:(BOOL)collapsible tap:(void (^)(void))tap;
+ (void)styleTitleForController:(UIViewController *)controller;    // left-aligned bold title
+ (UIImage *)chevronImageRight;
+ (UIImage *)circleIconWithGlyph:(void (^)(CGContextRef ctx))glyph;   // 40 pt tonal circle; the glyph is drawn in a 30 x 30 box in the accent colour
@end
