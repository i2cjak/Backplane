#pragma once

#include <react/renderer/components/BackplaneMarkdownTextSpec/EventEmitters.h>
#include <react/renderer/components/BackplaneMarkdownTextSpec/Props.h>
#include <react/renderer/components/BackplaneMarkdownTextSpec/States.h>
#include <react/renderer/components/view/ConcreteViewShadowNode.h>

namespace facebook::react {
extern const char BackplaneMarkdownTextRunComponentName[];

using BackplaneMarkdownTextRunShadowNode = ConcreteViewShadowNode<
    BackplaneMarkdownTextRunComponentName,
    BackplaneMarkdownTextRunProps,
    BackplaneMarkdownTextRunEventEmitter,
    BackplaneMarkdownTextRunState>;
}
