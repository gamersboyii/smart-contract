// MIT — Typed client for DAOReadHub. Hand-maintained; names mirror the
// on-chain `READY…RESERVE` constants so integrators never hardcode numbers.
// Regenerate the ABI with: forge inspect DAOReadHub abi > frontend/dao-readhub.abi.json

export const BLOCKED_REASON = {
  READY: 0,
  FINALIZED: 1,
  NOT_READY: 2,
  EXPIRED: 3,
  PREDECESSOR: 4,
  PAUSED: 5,
  RESERVE: 6,
} as const;

export type BlockedReason = (typeof BLOCKED_REASON)[keyof typeof BLOCKED_REASON];

export const BLOCKED_REASON_LABEL: Record<BlockedReason, string> = {
  [BLOCKED_REASON.READY]: "Ready — anyone may execute",
  [BLOCKED_REASON.FINALIZED]: "Finalized — executed or cancelled",
  [BLOCKED_REASON.NOT_READY]: "Quarantine — not yet executable",
  [BLOCKED_REASON.EXPIRED]: "Expired — anyone may close it",
  [BLOCKED_REASON.PREDECESSOR]: "Blocked — predecessor not executed",
  [BLOCKED_REASON.PAUSED]: "Paused — guardian halt in effect",
  [BLOCKED_REASON.RESERVE]: "Blocked — would breach the reserve floor",
};

export interface ProposalCard {
  snapshot: bigint;
  deadline: bigint;
  state: number;
  forVotes: bigint;
  againstVotes: bigint;
  abstainVotes: bigint;
  quorumRequired: bigint;
  accountWeight: bigint;
  hasVoted: boolean;
  needsQueuing: boolean;
}

export interface PackageStatus {
  target: string;
  value: bigint;
  tier: number;
  executeAfter: number;
  expiresAt: number;
  predecessor: string;
  executed: boolean;
  cancelled: boolean;
  predecessorExecuted: boolean;
  predecessorCancelled: boolean;
  executable: boolean;
  blockedReason: BlockedReason;
  secondsToReady: number;
}

export interface TreasurySnapshot {
  ethBalance: bigint;
  nativeFloor: bigint;
  spendable: bigint;
  paused: boolean;
  nextNonce: bigint;
  allowlistEnabled: boolean;
}

export interface AssetPosition {
  token: string;
  balance: bigint;
  floor: bigint;
  spendable: bigint;
}

export interface TimelockStatus {
  operationId: string;
  pending: boolean;
  ready: boolean;
  done: boolean;
  eta: bigint;
}

export function describePackage(s: PackageStatus): string {
  if (s.executable) return BLOCKED_REASON_LABEL[BLOCKED_REASON.READY];
  const label = BLOCKED_REASON_LABEL[s.blockedReason] ?? "Unknown state";
  if (s.blockedReason === BLOCKED_REASON.NOT_READY) return `${label} (${s.secondsToReady}s left)`;
  return label;
}

export function isTerminalPackage(s: PackageStatus): boolean {
  return s.blockedReason === BLOCKED_REASON.FINALIZED || s.blockedReason === BLOCKED_REASON.EXPIRED;
}
