#pragma once

#include <react/renderer/components/BackplaneMarkdownTextSpec/EventEmitters.h>
#include <react/renderer/components/BackplaneMarkdownTextSpec/Props.h>
#include <react/renderer/components/view/ConcreteViewShadowNode.h>
#include <react/renderer/textlayoutmanager/TextLayoutManager.h>
#include <react/renderer/core/LayoutContext.h>
#include <react/renderer/core/ShadowNode.h>

#include <string>
#include <vector>

namespace facebook::react {

extern const char BackplaneMarkdownTextComponentName[];

struct BackplaneMarkdownTextParagraphStyleRange {
  size_t location;
  size_t length;
  Float firstLineHeadIndent;
  Float headIndent;
  Float paragraphSpacing;
};

struct BackplaneMarkdownTextAttachmentRange {
  size_t location;
  size_t length;
  std::string imageUri;
  /// Recolor the loaded image with the run's foreground color, like `sf:` symbols.
  bool tintWithForeground;
};

inline Float BackplaneMarkdownTextAttachmentSize(const BackplaneMarkdownTextAttachmentRange &) {
  return 14;
}

inline Float BackplaneMarkdownTextAttachmentBaselineOffset(
    const BackplaneMarkdownTextAttachmentRange &) {
  return -2;
}

class BackplaneMarkdownTextStateReal final {
 public:
  AttributedString attributedString;
  std::vector<BackplaneMarkdownTextParagraphStyleRange> paragraphStyleRanges;
  std::vector<BackplaneMarkdownTextAttachmentRange> attachmentRanges;
};

class BackplaneMarkdownTextShadowNode final : public ConcreteViewShadowNode<
BackplaneMarkdownTextComponentName,
BackplaneMarkdownTextProps,
BackplaneMarkdownTextEventEmitter,
BackplaneMarkdownTextStateReal> {
public:
  using ConcreteViewShadowNode::ConcreteViewShadowNode;

  BackplaneMarkdownTextShadowNode(
   const ShadowNode& sourceShadowNode,
   const ShadowNodeFragment& fragment
  );

  static ShadowNodeTraits BaseTraits() {
    auto traits = ConcreteViewShadowNode::BaseTraits();
    traits.set(ShadowNodeTraits::Trait::LeafYogaNode);
    traits.set(ShadowNodeTraits::Trait::MeasurableYogaNode);
    return traits;
  }

  void layout(LayoutContext layoutContext) override;

  Size measureContent(
      const LayoutContext& layoutContext,
      const LayoutConstraints& layoutConstraints) const override;

private:
  mutable AttributedString _attributedString;
  mutable std::vector<BackplaneMarkdownTextParagraphStyleRange> _paragraphStyleRanges;
  mutable std::vector<BackplaneMarkdownTextAttachmentRange> _attachmentRanges;
};
} // namespace facebook::React
