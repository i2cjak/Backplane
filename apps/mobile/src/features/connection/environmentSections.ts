import type { EnvironmentId } from "@backplane/contracts";
import type { RelayClientEnvironmentRecord } from "@backplane/contracts/relay";
import type { ConnectedEnvironmentSummary } from "../../state/remote-runtime-types";

export interface EnvironmentSectionsInput {
  readonly connectedEnvironments: ReadonlyArray<ConnectedEnvironmentSummary>;
  readonly cloudEnvironments: ReadonlyArray<RelayClientEnvironmentRecord> | null;
}

export interface EnvironmentSections {
  readonly localEnvironments: ReadonlyArray<ConnectedEnvironmentSummary>;
  readonly connectedCloudEnvironments: ReadonlyArray<ConnectedEnvironmentSummary>;
  readonly availableCloudEnvironments: ReadonlyArray<RelayClientEnvironmentRecord>;
}

/**
 * Ids of the environments that already occupy a Backplane Connect slot. A backend saved directly is
 * not one of them, so it must not suppress the cloud environment that happens to share its id.
 */
export function relayManagedEnvironmentIds(
  environments: ReadonlyArray<{
    readonly environmentId: EnvironmentId;
    readonly isRelayManaged: boolean;
  }>,
): ReadonlySet<EnvironmentId> {
  return new Set(
    environments
      .filter((environment) => environment.isRelayManaged)
      .map((environment) => environment.environmentId),
  );
}

export function splitEnvironmentSections(input: EnvironmentSectionsInput): EnvironmentSections {
  const savedEnvironmentIds = relayManagedEnvironmentIds(input.connectedEnvironments);

  return {
    localEnvironments: input.connectedEnvironments.filter(
      (environment) => !environment.isRelayManaged,
    ),
    connectedCloudEnvironments: input.connectedEnvironments.filter(
      (environment) => environment.isRelayManaged,
    ),
    availableCloudEnvironments: (input.cloudEnvironments ?? []).filter(
      (environment) => !savedEnvironmentIds.has(environment.environmentId),
    ),
  };
}
