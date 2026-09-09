#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import "RCTBridge.h"
#import "Utils.h"

@interface BackplaneMarkdownTextManager : RCTViewManager
@end

@implementation BackplaneMarkdownTextManager

RCT_EXPORT_MODULE(BackplaneMarkdownText)

- (UIView *)view
{
  return [[UIView alloc] init];
}

RCT_CUSTOM_VIEW_PROPERTY(color, NSString, UIView)
{
}

@end

@interface BackplaneMarkdownTextRunManager : RCTViewManager
@end

@implementation BackplaneMarkdownTextRunManager

RCT_EXPORT_MODULE(BackplaneMarkdownTextRun)

- (UIView *)view
{
  return nil;
}

@end
