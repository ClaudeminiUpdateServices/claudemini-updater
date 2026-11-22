#import "FontStyle.h"
#import "AppSettings.h"
#import <objc/runtime.h>

NSString *CMWebFontStack(void) {
    if ([AppSettings fontStyle] == 2) return @"ui-rounded, \"SF Pro Rounded\", -apple-system, \"Helvetica Neue\", sans-serif";
    return @"-apple-system, \"Helvetica Neue\", Helvetica, sans-serif";
}

NSInteger CMWebFontWeight(void) {
    return 400 + 100 * [AppSettings fontWeightStep];   // 100...700
}

static CGFloat AdjustedWeight(CGFloat weight) {
    CGFloat w = weight + 0.14 * (CGFloat)[AppSettings fontWeightStep];
    return MAX(UIFontWeightUltraLight, MIN(UIFontWeightBlack, w));
}

@implementation UIFont (ClaudeMiniStyle)

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method original = class_getClassMethod(self, @selector(systemFontOfSize:weight:));
        Method replacement = class_getClassMethod(self, @selector(cm_systemFontOfSize:weight:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
        Method plain = class_getClassMethod(self, @selector(systemFontOfSize:));
        Method plainNew = class_getClassMethod(self, @selector(cm_systemFontOfSize:));
        if (plain && plainNew) method_exchangeImplementations(plain, plainNew);
        Method bold = class_getClassMethod(self, @selector(boldSystemFontOfSize:));
        Method boldNew = class_getClassMethod(self, @selector(cm_boldSystemFontOfSize:));
        if (bold && boldNew) method_exchangeImplementations(bold, boldNew);
    });
}

// After the exchange, this body runs for [UIFont systemFontOfSize:weight:] and calling cm_... runs the original.
+ (UIFont *)cm_systemFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont *base = [self cm_systemFontOfSize:size weight:AdjustedWeight(weight)];
    if ([AppSettings fontStyle] == 2) {
        if (@available(iOS 13.0, *)) {
            UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
            if (descriptor) return [UIFont fontWithDescriptor:descriptor size:size];
        }
    }
    return base;
}

+ (UIFont *)cm_systemFontOfSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];   // goes through the replacement above
}

+ (UIFont *)cm_boldSystemFontOfSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightBold];
}

@end
