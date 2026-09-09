#pragma once

#include "BackplaneMarkdownTextRunShadowNode.h"

#include <react/renderer/core/ConcreteComponentDescriptor.h>
#include <react/renderer/componentregistry/ComponentDescriptorProviderRegistry.h>

namespace facebook::react {
using BackplaneMarkdownTextRunComponentDescriptor = ConcreteComponentDescriptor<BackplaneMarkdownTextRunShadowNode>;

void BackplaneMarkdownTextRunSpec_registerComponentDescriptorsFromCodegen(
  std::shared_ptr<const ComponentDescriptorProviderRegistry> registry);
}
