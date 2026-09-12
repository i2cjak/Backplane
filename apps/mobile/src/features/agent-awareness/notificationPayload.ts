function dataFromNotificationResponse(response: unknown): Record<string, unknown> | null {
  if (typeof response !== "object" || response === null) {
    return null;
  }
  const notification = (response as { readonly notification?: unknown }).notification;
  if (typeof notification !== "object" || notification === null) {
    return null;
  }
  const request = (notification as { readonly request?: unknown }).request;
  if (typeof request !== "object" || request === null) {
    return null;
  }
  const content = (request as { readonly content?: unknown }).content;
  if (typeof content !== "object" || content === null) {
    return null;
  }
  const data = (content as { readonly data?: unknown }).data;
  if (typeof data === "object" && data !== null) {
    return data as Record<string, unknown>;
  }

  // Expo's iOS remote notification serializer only copies userInfo["body"]
  // into content.data. Direct APNs payloads from Backplane keep the routing
  // fields at the top level, which remains available on the push trigger.
  const trigger = (request as { readonly trigger?: unknown }).trigger;
  if (typeof trigger !== "object" || trigger === null) {
    return null;
  }
  const payload = (trigger as { readonly payload?: unknown }).payload;
  return typeof payload === "object" && payload !== null
    ? (payload as Record<string, unknown>)
    : null;
}

function identifierFromNotificationResponse(response: unknown): string | null {
  if (typeof response !== "object" || response === null) {
    return null;
  }
  const notification = (response as { readonly notification?: unknown }).notification;
  if (typeof notification !== "object" || notification === null) {
    return null;
  }
  const request = (notification as { readonly request?: unknown }).request;
  if (typeof request !== "object" || request === null) {
    return null;
  }
  const identifier = (request as { readonly identifier?: unknown }).identifier;
  return typeof identifier === "string" ? identifier : null;
}

function encodeThreadDeepLink(input: {
  readonly environmentId: string;
  readonly threadId: string;
}): string | null {
  if (input.environmentId.length === 0 || input.threadId.length === 0) {
    return null;
  }
  return `/threads/${encodeURIComponent(input.environmentId)}/${encodeURIComponent(input.threadId)}`;
}

function normalizeThreadDeepLink(value: string): string | null {
  if (
    value.trim() !== value ||
    value.startsWith("//") ||
    value.includes("?") ||
    value.includes("#")
  ) {
    return null;
  }

  const parts = value.split("/");
  if (parts.length !== 4 || parts[0] !== "" || parts[1] !== "threads") {
    return null;
  }

  try {
    return encodeThreadDeepLink({
      environmentId: decodeURIComponent(parts[2] ?? ""),
      threadId: decodeURIComponent(parts[3] ?? ""),
    });
  } catch {
    return null;
  }
}

export function extractAgentNotificationDeepLink(response: unknown): string | null {
  const target = extractAgentNotificationThreadTarget(response);
  return target ? encodeThreadDeepLink(target) : null;
}

/**
 * Returns route params separately from the URL representation. Notification
 * taps are already inside the native navigation tree, so consumers can use
 * the typed route directly and avoid asking the linking layer to dispatch an
 * action while a cold-start navigator is still settling.
 */
export type AgentNotificationThreadTarget = Readonly<{
  environmentId: string;
  threadId: string;
}>;

export function extractAgentNotificationThreadTarget(
  response: unknown,
): AgentNotificationThreadTarget | null {
  const data = dataFromNotificationResponse(response);
  const deepLink = data?.deepLink;
  if (typeof deepLink === "string") {
    const normalizedDeepLink = normalizeThreadDeepLink(deepLink);
    if (normalizedDeepLink) {
      const parts = normalizedDeepLink.split("/");
      try {
        return {
          environmentId: decodeURIComponent(parts[2] ?? ""),
          threadId: decodeURIComponent(parts[3] ?? ""),
        };
      } catch {
        return null;
      }
    }
  }

  const environmentId = data?.environmentId;
  const threadId = data?.threadId;
  if (typeof environmentId === "string" && typeof threadId === "string") {
    return encodeThreadTarget({ environmentId, threadId });
  }
  return null;
}

function encodeThreadTarget(input: {
  readonly environmentId: string;
  readonly threadId: string;
}): AgentNotificationThreadTarget | null {
  return input.environmentId.length > 0 && input.threadId.length > 0 ? input : null;
}

export function routeAgentNotificationResponseOnce(input: {
  readonly handledResponseIds: Set<string>;
  readonly response: unknown;
  readonly navigate: (target: AgentNotificationThreadTarget) => void;
}): void {
  const responseId = identifierFromNotificationResponse(input.response);
  if (responseId && input.handledResponseIds.has(responseId)) {
    return;
  }
  const target = extractAgentNotificationThreadTarget(input.response);
  if (target) {
    input.navigate(target);
    // Keep failed navigation retryable. This matters during cold start, when
    // the notification listener can receive the same response before the
    // native navigation tree has finished mounting.
    if (responseId) {
      input.handledResponseIds.add(responseId);
    }
  }
}
