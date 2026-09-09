import {
  EnvironmentHttpBadRequestError,
  EnvironmentHttpConflictError,
  EnvironmentHttpForbiddenError,
  EnvironmentHttpInternalServerError,
  EnvironmentHttpUnauthorizedError,
} from "@backplane/contracts";
import { RelayProtectedError } from "@backplane/contracts/relay";
import * as Effect from "effect/Effect";
import * as Option from "effect/Option";
import * as Schema from "effect/Schema";
import * as HttpClientResponse from "effect/unstable/http/HttpClientResponse";
import { isHttpClientError } from "effect/unstable/http/HttpClientError";

const isRelayResponseError = Schema.is(
  Schema.Union([
    EnvironmentHttpBadRequestError,
    EnvironmentHttpForbiddenError,
    EnvironmentHttpInternalServerError,
    EnvironmentHttpUnauthorizedError,
  ]),
);

export function relayRequestError(cause: unknown) {
  return isRelayResponseError(cause)
    ? cause
    : new EnvironmentHttpInternalServerError({
        message: `Could not complete the Backplane Connect relay request. ${isHttpClientError(cause) ? `The relay request failed (${cause.reason._tag}).` : "The relay returned an unexpected response."} Check this machine's network connection and relay availability, then retry.`,
      });
}

const isPermanentCloudLinkError = Schema.is(
  Schema.Union([
    EnvironmentHttpBadRequestError,
    EnvironmentHttpForbiddenError,
    EnvironmentHttpUnauthorizedError,
    EnvironmentHttpConflictError,
  ]),
);

export const shouldRetryCloudLink = (error: unknown): boolean => !isPermanentCloudLinkError(error);

function recoveryHint(error: RelayProtectedError): string {
  switch (error._tag) {
    case "RelayEnvironmentLinkLimitExceededError":
      return "Unlink an unused environment in Backplane Connect, then restart Backplane on this machine.";
    case "RelayAuthInvalidError":
      return "Run `backplane connect login` to check this machine's authorization. If the stored credential was revoked, sign out with `backplane connect logout`, then run `backplane connect` again. Restart Backplane after signing in.";
    case "RelayEnvironmentLinkProofExpiredError":
    case "RelayEnvironmentLinkProofInvalidError":
      return "Check this machine's date and time, update Backplane, then restart it.";
    default:
      return "Retry when the relay is available. If this continues, include the trace ID when reporting it.";
  }
}

/** Preserve relay diagnostics before converting permanent rejections into non-retryable errors. */
export const filterRelayResponse = Effect.fn("cloud.filter_relay_response")(function* (
  response: HttpClientResponse.HttpClientResponse,
) {
  if (response.status >= 200 && response.status < 300) return response;
  const decoded = yield* HttpClientResponse.schemaBodyJson(RelayProtectedError)(response).pipe(
    Effect.option,
  );
  const ray = response.headers["cf-ray"];
  const requestId = ray && /^[a-zA-Z0-9-]{1,128}$/.test(ray) ? ` Cloudflare Ray ID: ${ray}.` : "";
  const message = Option.isSome(decoded)
    ? `Backplane Connect: ${decoded.value.message}. ${recoveryHint(decoded.value)} Trace ID: ${decoded.value.traceId}.`
    : `Backplane Connect relay returned HTTP ${response.status} without a recognized error response. Check relay access and any proxy or firewall restrictions, then restart Backplane.${requestId}`;

  if (response.status === 401) return yield* new EnvironmentHttpUnauthorizedError({ message });
  if (response.status === 403) return yield* new EnvironmentHttpForbiddenError({ message });
  if (
    response.status >= 400 &&
    response.status < 500 &&
    response.status !== 408 &&
    response.status !== 429
  ) {
    return yield* new EnvironmentHttpBadRequestError({ message });
  }
  return yield* new EnvironmentHttpInternalServerError({ message });
});
