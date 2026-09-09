#import "BackplaneMarkdownTextRun.h"
#import "BackplaneMarkdownText.h"
#import "BackplaneMarkdownTextRunComponentDescriptor.h"
#import <react/renderer/components/BackplaneMarkdownTextSpec/EventEmitters.h>
#import <react/renderer/components/BackplaneMarkdownTextSpec/Props.h>
#import <react/renderer/components/BackplaneMarkdownTextSpec/RCTComponentViewHelpers.h>
#import "RCTFabricComponentsPlugins.h"
#import "Utils.h"

using namespace facebook::react;

@interface BackplaneMarkdownTextRun () <RCTBackplaneMarkdownTextRunViewProtocol>

@end

@implementation BackplaneMarkdownTextRun {
  NSString * _text;
  NSString * _contextMenuConfig;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
    return concreteComponentDescriptorProvider<BackplaneMarkdownTextRunComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const BackplaneMarkdownTextRunProps>();
    _props = defaultProps;
  }
  return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &oldViewProps = *std::static_pointer_cast<BackplaneMarkdownTextRunProps const>(_props);
  const auto &newViewProps = *std::static_pointer_cast<BackplaneMarkdownTextRunProps const>(props);

  if (newViewProps.text != oldViewProps.text) {
    NSString *text = [NSString stringWithUTF8String:newViewProps.text.c_str()];
    _text = text;
  }

  if (newViewProps.contextMenuConfig != oldViewProps.contextMenuConfig) {
    _contextMenuConfig = [NSString stringWithUTF8String:newViewProps.contextMenuConfig.c_str()];
  }

  [super updateProps:props oldProps:oldProps];
}

- (BOOL)hasContextMenu
{
  return _contextMenuConfig.length > 0;
}

- (nullable UIMenu *)contextMenu
{
  if (_contextMenuConfig.length == 0) {
    return nil;
  }

  NSData *data = [_contextMenuConfig dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *config = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![config isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  NSArray *actionConfigs = config[@"actions"];
  if (![actionConfigs isKindOfClass:[NSArray class]] || actionConfigs.count == 0) {
    return nil;
  }

  NSMutableArray<UIMenuElement *> *actions = [NSMutableArray arrayWithCapacity:actionConfigs.count];
  __weak BackplaneMarkdownTextRun *weakSelf = self;
  for (NSDictionary *actionConfig in actionConfigs) {
    if (![actionConfig isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *actionIdentifier = actionConfig[@"id"];
    NSString *title = actionConfig[@"title"];
    if (![actionIdentifier isKindOfClass:[NSString class]] ||
        ![title isKindOfClass:[NSString class]]) {
      continue;
    }

    UIAction *action = [UIAction actionWithTitle:title
                                           image:nil
                                      identifier:actionIdentifier
                                         handler:^(__kindof UIAction *selectedAction) {
      [weakSelf onContextMenuAction:selectedAction.identifier];
    }];
    if ([actionConfig[@"disabled"] boolValue]) {
      action.attributes = UIMenuElementAttributesDisabled;
    }
    [actions addObject:action];
  }

  if (actions.count == 0) {
    return nil;
  }
  NSString *title = [config[@"title"] isKindOfClass:[NSString class]] ? config[@"title"] : @"";
  return [UIMenu menuWithTitle:title children:actions];
}

- (void)onContextMenuAction:(NSString *)actionIdentifier
{
  if (_eventEmitter != nullptr) {
    std::dynamic_pointer_cast<const facebook::react::BackplaneMarkdownTextRunEventEmitter>(_eventEmitter)
    ->onContextMenuAction(facebook::react::BackplaneMarkdownTextRunEventEmitter::OnContextMenuAction{
      static_cast<int>(self.tag),
      actionIdentifier.UTF8String,
    });
  }
}

- (void)onPress {
  if (_eventEmitter != nullptr) {
    std::dynamic_pointer_cast<const facebook::react::BackplaneMarkdownTextRunEventEmitter>(_eventEmitter)
    ->onPress(facebook::react::BackplaneMarkdownTextRunEventEmitter::OnPress{});
  }
}

- (void)onLongPress {
  if (_eventEmitter != nullptr) {
    std::dynamic_pointer_cast<const facebook::react::BackplaneMarkdownTextRunEventEmitter>(_eventEmitter)
    ->onLongPress(facebook::react::BackplaneMarkdownTextRunEventEmitter::OnLongPress{});
  }
}

+ (BOOL)shouldBeRecycled {
  return NO;
}

Class<RCTComponentViewProtocol> BackplaneMarkdownTextRunCls(void)
{
    return BackplaneMarkdownTextRun.class;
}

@end
