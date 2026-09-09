#pragma once

#include "BackplaneMarkdownTextShadowNode.h"

#include <react/renderer/core/ConcreteComponentDescriptor.h>
#include <react/renderer/componentregistry/ComponentDescriptorProviderRegistry.h>

namespace facebook::react {
using BackplaneMarkdownTextComponentDescriptor = ConcreteComponentDescriptor<BackplaneMarkdownTextShadowNode>;

void BackplaneMarkdownTextSpec_registerComponentDescriptorsFromCodegen(
  std::shared_ptr<const ComponentDescriptorProviderRegistry> registry);
}
