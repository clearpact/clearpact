/**
 * ClearPact SDK — TypeScript type definitions
 *
 * These types describe every request parameter and response shape for the
 * ClearPact API. Import them for full autocomplete and type safety.
 *
 * @example
 * import type { EscrowObject, ClearPactOptions } from 'clearpact/types';
 */

// ─── Configuration ────────────────────────────────────────────────────────────

export type Network = 'testnet' | 'mainnet';

export interface ClearPactOptions {
  /** ClearPact API key. Get one at https://clearpact.polsia.app/docs */
  apiKey: string;
  /** Target network. Defaults to 'testnet'. */
  network?: Network;
  /** Override the API base URL. Defaults to https://clearpact.polsia.app */
  baseUrl?: string;
}

// ─── Condition types ──────────────────────────────────────────────────────────

export type ConditionType =
  | 'task_completion'
  | 'approval'
  | 'deadline'
  | 'threshold'
  | 'oracle'
  | 'custom';

export interface EscrowCondition {
  type: ConditionType;
  /** Deadline (ISO 8601) for 'deadline' conditions */
  deadline?: string;
  /** Minimum value for 'threshold' conditions */
  min_value?: number;
  /** Required approver address for 'approval' conditions */
  approver?: string;
  /** Oracle configuration for 'oracle' conditions */
  oracle_url?: string;
  /** Any additional condition parameters */
  [key: string]: unknown;
}

// ─── Escrow objects ───────────────────────────────────────────────────────────

export type EscrowStatus =
  | 'pending_funding'
  | 'funded'
  | 'awaiting_verification'
  | 'active'
  | 'settling'
  | 'settled'
  | 'cancelled'
  | 'refunded'
  | 'expired'
  | 'expiry_failed';

export interface EscrowTxHashes {
  create: string | null;
  fund:   string | null;
  settle: string | null;
  refund: string | null;
}

export interface EscrowERC8004 {
  external_job_id:     string;
  verification_source: string;
}

export interface EscrowObject {
  id:                 string;
  network:            Network;
  payer:              string;
  payee:              string;
  amount:             number;
  token:              string;
  status:             EscrowStatus;
  conditions:         EscrowCondition[];
  metadata:           Record<string, unknown>;
  created_at:         string;
  updated_at:         string;
  funded_at:          string | null;
  settled_at:         string | null;
  expires_at:         string | null;
  chain_id:           number | null;
  contract_address:   string | null;
  onchain_escrow_id:  number | null;
  asset_address:      string | null;
  payer_address:      string | null;
  payee_address:      string | null;
  tx_hashes:          EscrowTxHashes;
  erc8004:            EscrowERC8004 | null;
}

/**
 * On-chain contract state enum (Solidity `Status`).
 * Maps directly to the contract's uint8 enum:
 *   0 → pending_funding, 1 → funded, 2 → awaiting_verification,
 *   3 → settled, 4 → refunded, 5 → cancelled
 */
export type OnchainStatus =
  | 'pending_funding'
  | 'funded'
  | 'awaiting_verification'
  | 'settled'
  | 'refunded'
  | 'cancelled';

export interface BlockchainInfo {
  network:            Network;
  chain_id:           number;
  contract_address:   string;
  onchain_escrow_id:  number;
  asset_address:      string;
  create_tx_hash?:    string | null;
  explorer:           string | null;
  explorer_contract?: string | null;
  /**
   * Current state as read from the on-chain contract enum.
   * `null` when the escrow has not been created on-chain yet.
   * Note: the contract has 6 states; the API adds 4 more (active, settling,
   * expired, expiry_failed) that have no direct on-chain analog.
   */
  onchain_status:     OnchainStatus | null;
  tx_hashes?: EscrowTxHashes;
}

// ─── Escrow request params ────────────────────────────────────────────────────

export interface CreateEscrowParams {
  payer:           string;
  payee:           string;
  amount:          number;
  token?:          string;
  conditions?:     EscrowCondition[];
  metadata?:       Record<string, unknown>;
  expires_at?:     string;
  external_job_id?: string;
  network?:        Network;
}

export interface FundEscrowParams {
  tx_hash?: string;
  actor?:   string;
}

export interface SettleEscrowParams {
  verifications?: Record<string | number, ConditionVerification>;
  actor?:         string;
}

export interface ConditionVerification {
  completed?:        boolean;
  approved?:         boolean;
  approver?:         string;
  value?:            number;
  oracle_confirmed?: boolean;
  met?:              boolean;
  [key: string]: unknown;
}

export interface CancelEscrowParams {
  actor?:  string;
  reason?: string;
}

// ─── Escrow response types ────────────────────────────────────────────────────

export interface EscrowCreateResponse {
  success:    boolean;
  network:    Network;
  escrow:     EscrowObject;
  blockchain: BlockchainInfo | null;
  erc8004:    { external_job_id: string; status: string; note: string } | null;
}

export interface EscrowGetResponse {
  success:    boolean;
  network:    Network;
  escrow:     EscrowObject;
  blockchain: BlockchainInfo | null;
  events:     EscrowEvent[];
}

export interface EscrowEvent {
  event_type: string;
  actor:      string | null;
  details:    Record<string, unknown>;
  created_at: string;
}

export interface EscrowFundResponse {
  success:   boolean;
  network:   Network;
  message:   string;
  explorer:  string | null;
  escrow:    EscrowObject;
}

export interface EscrowSettleResponse {
  success:           boolean;
  deprecated_notice?: string;
  network:           Network;
  message:           string;
  escrow:            EscrowObject;
  settlement:        {
    amount:          number;
    token:           string;
    from:            string;
    to:              string;
    network:         Network;
    conditions:      ConditionResult[];
    settled_at:      string;
    settle_tx_hash:  string | null;
    explorer:        string | null;
  };
}

export interface ConditionResult {
  index:   number;
  type:    ConditionType;
  met:     boolean;
  details: Record<string, unknown> | null;
}

export interface EscrowCancelResponse {
  success:   boolean;
  network:   Network;
  message:   string;
  escrow:    EscrowObject;
  tx_hash:   string | null;
  explorer:  string | null;
}

// ─── x402 types ───────────────────────────────────────────────────────────────

export interface X402VerifyOptions {
  expected_to?:    string;
  min_amount_raw?: string;
  network?:        Network;
  chain_id?:       number;
  usdc_address?:   string;
}

export interface X402VerifyResponse {
  success:              boolean;
  valid:                boolean;
  network:              string;
  escrow_id:            string | null;
  transaction_id:       string;
  from:                 string;
  to:                   string;
  amount_raw:           string;
  amount_usdc:          string;
  nonce:                string;
  recovered_address:    string;
  signer_matches_payer: boolean;
  chain_id:             number;
  x402_version:         string;
  valid_after:          number;
  valid_before:         number;
  message:              string;
  next_step:            string;
}

export interface X402SettleParams {
  transaction_id?: string;
  network?:        Network;
}

export interface X402SettleResponse {
  success:             boolean;
  settled:             boolean;
  transaction_id:      string;
  settlement_tx_hash:  string;
  block_number:        number;
  amount_usdc:         string;
  from:                string;
  to:                  string;
  escrow_id:           string | null;
  verified?:           boolean;
  phase?:              string;
}

export interface X402HealthResponse {
  status:        string;
  phase:         string;
  x402_version:  string;
  scheme:        string;
  chain_id?:     number;
  network?:      string;
  usdc_contract?: string;
  features: {
    verify:            boolean;
    settle:            boolean;
    settle_enabled:    boolean;
    replay_protection: boolean;
    mainnet:           boolean;
  };
  networks: {
    testnet: X402NetworkInfo;
    mainnet: X402NetworkInfo;
  };
  docs: string;
}

export interface X402NetworkInfo {
  network:         Network;
  chain_id:        number;
  label:           string;
  usdc:            string;
  settle:          boolean;
  settle_enabled:  boolean;
  active?:         boolean;
  contract?:       string | null;
}

export interface X402TransactionFilter {
  limit?:   number;
  status?:  'verified' | 'failed' | 'replay_rejected' | 'expired';
  from?:    string;
  network?: Network;
}

export interface X402TransactionRecord {
  id:               string;
  agent_address:    string;
  recipient_address: string;
  amount:           string;
  token:            string;
  chain_id:         number;
  nonce:            string;
  status:           string;
  verified_at:      string | null;
  failure_reason:   string | null;
  escrow_id:        string | null;
  tx_hash:          string | null;
  x402_version:     string;
  created_at:       string;
  amount_usdc:      string;
  network:          Network;
}

export interface X402TransactionsResponse {
  success:      boolean;
  count:        number;
  transactions: X402TransactionRecord[];
}

export interface X402TransactionResponse {
  success:     boolean;
  network:     Network;
  transaction: X402TransactionRecord;
}

// ─── Webhooks types ───────────────────────────────────────────────────────────

export type WebhookEvent =
  | 'escrow.created'
  | 'escrow.funded'
  | 'escrow.settled'
  | 'escrow.cancelled'
  | 'escrow.expired';

export interface CreateWebhookParams {
  url:          string;
  event_types:  WebhookEvent[];
}

export interface WebhookObject {
  id:           string;
  url:          string;
  event_types:  WebhookEvent[];
  created_at:   string;
}

export interface WebhookCreateResponse {
  success:        boolean;
  id:             string;
  url:            string;
  event_types:    WebhookEvent[];
  signing_secret: string;
}

export interface WebhookListResponse {
  success:  boolean;
  webhooks: WebhookObject[];
}

// ─── Error ────────────────────────────────────────────────────────────────────

export declare class ClearPactError extends Error {
  readonly name:    'ClearPactError';
  readonly status:  number;
  readonly error:   string | null;
  readonly errors:  string[] | null;
  readonly raw:     Record<string, unknown> | null;
}

// ─── Client namespaces ────────────────────────────────────────────────────────

export interface EscrowNamespace {
  create(params: CreateEscrowParams):                   Promise<EscrowCreateResponse>;
  get(id: string):                                      Promise<EscrowGetResponse>;
  fund(id: string, params?: FundEscrowParams):          Promise<EscrowFundResponse>;
  settle(id: string, params?: SettleEscrowParams):      Promise<EscrowSettleResponse>;
  cancel(id: string, params?: CancelEscrowParams):      Promise<EscrowCancelResponse>;
}

export interface X402Namespace {
  verify(payload: object | string, options?: X402VerifyOptions): Promise<X402VerifyResponse>;
  settle(params?: X402SettleParams):                             Promise<X402SettleResponse>;
  health():                                                      Promise<X402HealthResponse>;
  listTransactions(filters?: X402TransactionFilter):            Promise<X402TransactionsResponse>;
  getTransaction(id: string):                                   Promise<X402TransactionResponse>;
}

export interface WebhooksNamespace {
  create(params: CreateWebhookParams): Promise<WebhookCreateResponse>;
  list():                              Promise<WebhookListResponse>;
  delete(id: string):                  Promise<{ success: boolean }>;
}

// ─── Main export ──────────────────────────────────────────────────────────────

export declare class ClearPact {
  readonly escrow:   EscrowNamespace;
  readonly x402:     X402Namespace;
  readonly webhooks: WebhooksNamespace;

  static readonly version: string;

  constructor(options: ClearPactOptions);
}

export default ClearPact;
