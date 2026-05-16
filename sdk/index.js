/**
 * ClearPact SDK v0.3.0
 *
 * ERC-8183 v2 (Phase 5). Immutable contract post-Phase 4 renounce.
 *
 * Contracts (Base Sepolia):
 *   ClearPactJob proxy:       0x7CDB80e9B154c99354d66604103fAEb148c6f5A8
 *   ClearPactEvaluator proxy: 0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6
 *   USDC Base Sepolia:        0x036CbD53842c5426634e7929541eC2318f3dCF7e
 *
 * Immutability commitment:
 *   No admin can freeze, no admin can decide, no admin can upgrade.
 *   PAUSER, OPERATOR, EVALUATOR, DEFAULT_ADMIN roles renounced on both contracts.
 *
 * Self-service evaluator pattern (Decision 9):
 *   Each job creator passes their own evaluator EOA at createJob().
 *   ClearPact does not appoint or arbitrate evaluators.
 *   The evaluator EOA calls clearpact.jobs.complete() / reject() directly.
 *   The SDK does NOT expose Evaluator contract methods.
 *
 * @example
 * const { ClearPact } = require('clearpact');
 * const client = new ClearPact({ apiKey: 'cpk_live_...' });
 *
 * // Create a job (ERC-8183)
 * const { job } = await client.jobs.create(
 *   '0xProviderWallet',
 *   '0xEvaluatorEOA',  // self-service: evaluator EOA chosen by job creator
 *   new Date(Date.now() + 7 * 86400_000).toISOString(),
 *   'Build landing page in Tailwind',
 *   null  // hook address (optional IACPHook)
 * );
 */

'use strict';

const DEFAULT_BASE_URL = 'https://clearpact.polsia.app';
const DEFAULT_NETWORK  = 'testnet';
const SDK_VERSION      = '0.3.0';

// Contract addresses (Phase 4 v2 deploy, Base Sepolia)
const CONTRACT_ADDRESSES = {
  jobProxy:       '0x7CDB80e9B154c99354d66604103fAEb148c6f5A8',
  evaluatorProxy: '0x1DDefFED6a9e28C37e1E10c292F6774D837a7Ab6',
  usdc:           '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
};

// ─── ClearPactError ────────────────────────────────────────────────────────────

/**
 * Typed error class for ClearPact API errors.
 *
 * @property {number}  status      HTTP status code
 * @property {string}  message     Human-readable error message
 * @property {string}  [error]     Machine-readable error code
 * @property {Array}   [errors]    Array of validation errors (400 responses)
 * @property {Object}  [raw]       Full raw response body
 */
class ClearPactError extends Error {
  constructor(message, status, body) {
    super(message);
    this.name    = 'ClearPactError';
    this.status  = status;
    this.error   = body?.error || null;
    this.errors  = body?.errors || null;
    this.raw     = body || null;
  }
}

// ─── Core HTTP client ─────────────────────────────────────────────────────────

class HttpClient {
  constructor({ apiKey, baseUrl }) {
    this._apiKey  = apiKey;
    this._baseUrl = baseUrl.replace(/\/$/, '');
  }

  async _request(method, path, body) {
    const url     = `${this._baseUrl}${path}`;
    const headers = {
      'Content-Type':  'application/json',
      'X-API-Key':     this._apiKey,
      'User-Agent':    `clearpact-sdk/${SDK_VERSION}`,
      'X-SDK-Version': SDK_VERSION,
    };

    const init = { method, headers };
    if (body !== undefined) init.body = JSON.stringify(body);

    let response;
    try {
      response = await fetch(url, init);
    } catch (err) {
      throw new ClearPactError(`Network error: ${err.message}`, 0, null);
    }

    let data;
    try {
      data = await response.json();
    } catch {
      throw new ClearPactError(`Failed to parse response (status ${response.status})`, response.status, null);
    }

    if (!response.ok) {
      const msg = data?.message
        || (Array.isArray(data?.errors) ? data.errors.join(', ') : null)
        || data?.error
        || `HTTP ${response.status}`;
      throw new ClearPactError(msg, response.status, data);
    }

    return data;
  }

  get(path)        { return this._request('GET',    path); }
  post(path, body) { return this._request('POST',   path, body); }
  del(path)        { return this._request('DELETE', path); }
}

// ─── Jobs namespace (ERC-8183 v2) ─────────────────────────────────────────────

/**
 * ERC-8183 job lifecycle methods.
 *
 * State machine: Open → Funded → Submitted → Completed
 *                                          ↘ Rejected (E3: 3-path ACL, symmetric refund)
 *                Open/Funded → Expired (claimRefund after expiredAt)
 *
 * Decision 6: complete() and reject() callable by evaluator OR client at Submitted.
 * Decision 9: This SDK does NOT expose Evaluator contract methods. The evaluator EOA
 *             calls complete()/reject() directly on this jobs namespace.
 */
class JobsNamespace {
  constructor(http) {
    this._http = http;
  }

  /**
   * Create a new job (ERC-8183 createJob).
   *
   * Self-service evaluator pattern: pass your own evaluator EOA.
   * ClearPact never appoints or arbitrates evaluators.
   *
   * @param {string} provider    Provider wallet address
   * @param {string} evaluator   Evaluator EOA (self-service — chosen by job creator)
   * @param {string} expiredAt   ISO 8601 expiry datetime
   * @param {string} [description] Job description
   * @param {string} [hook]      IACPHook contract address (optional, must be whitelisted)
   * @returns {Promise<JobCreateResponse>}
   */
  create(provider, evaluator, expiredAt, description, hook) {
    return this._http.post('/api/job', { provider, evaluator, expiredAt, description, hook });
  }

  /**
   * Update the provider address (setProvider).
   * Only valid in Open state.
   *
   * @param {string} jobId     Job UUID
   * @param {string} provider  New provider address
   * @returns {Promise<JobResponse>}
   */
  setProvider(jobId, provider) {
    return this._http.post(`/api/job/${jobId}/provider`, { provider });
  }

  /**
   * Set the budget (setBudget).
   * Only valid in Open state.
   *
   * Phase 2bis: pass conditionRef to emit ClearPactJobMetadata with conditional reference hash.
   * Pass token to override the per-job payment token (defaults to USDC).
   *
   * @param {string} jobId     Job UUID
   * @param {number} amount    Budget in token units
   * @param {Object} [opts]
   * @param {string} [opts.token]        ERC-20 token address (default: USDC)
   * @param {string} [opts.conditionRef] bytes32 conditional reference hash
   * @returns {Promise<JobResponse>}
   */
  setBudget(jobId, amount, opts = {}) {
    return this._http.post(`/api/job/${jobId}/budget`, { amount, ...opts });
  }

  /**
   * Fund the job on-chain (fund).
   * Valid in Open state. Transitions to Funded.
   *
   * @param {string} jobId      Job UUID
   * @param {Object} [opts]
   * @param {string} [opts.tx_hash]  On-chain funding transaction hash
   * @returns {Promise<JobResponse>}
   */
  fund(jobId, opts = {}) {
    return this._http.post(`/api/job/${jobId}/fund`, opts);
  }

  /**
   * Submit work deliverable (submit).
   * Valid in Funded state. Transitions to Submitted.
   * Provider calls this to signal work is complete and ready for evaluation.
   *
   * @param {string} jobId        Job UUID
   * @param {string} deliverable  Reference to deliverable (URL, IPFS hash, etc.)
   * @param {Object} [opts]
   * @param {string} [opts.tx_hash]  On-chain transaction hash
   * @returns {Promise<JobResponse>}
   */
  submit(jobId, deliverable, opts = {}) {
    return this._http.post(`/api/job/${jobId}/submit`, { deliverable, ...opts });
  }

  /**
   * Approve and complete the job (complete).
   * Valid in Submitted state. Transitions to Completed. Releases payment to provider.
   *
   * Decision 6: callable by evaluator EOA OR client.
   * This is the evaluator's approveResult action — called directly here, NOT via Evaluator contract.
   *
   * @param {string} jobId    Job UUID
   * @param {string} reason   Completion reason / evaluation notes
   * @param {Object} [opts]
   * @param {string} [opts.tx_hash]  On-chain transaction hash
   * @returns {Promise<JobResponse>}
   */
  complete(jobId, reason, opts = {}) {
    return this._http.post(`/api/job/${jobId}/complete`, { reason, ...opts });
  }

  /**
   * Reject the job result (reject).
   * Valid in Open, Funded, or Submitted state (E3: 3-path ACL).
   * Transitions to Rejected. Symmetric automatic refund from Funded/Submitted states.
   *
   * Decision 6: callable by evaluator EOA OR client at Submitted state.
   * This is the evaluator's rejectResult action — called directly here, NOT via Evaluator contract.
   * (NOT resolveDispute — see Decision 7)
   *
   * @param {string} jobId    Job UUID
   * @param {string} reason   Rejection reason
   * @param {Object} [opts]
   * @param {string} [opts.tx_hash]  On-chain transaction hash
   * @returns {Promise<JobRejectResponse>}
   */
  reject(jobId, reason, opts = {}) {
    return this._http.post(`/api/job/${jobId}/reject`, { reason, ...opts });
  }

  /**
   * Claim refund after expiry (claimRefund).
   * Valid in Funded or Submitted state, after expiredAt has passed.
   * Unconditional, non-hookable, non-pausable (PAUSER_ROLE renounced post-Phase 4).
   *
   * @param {string} jobId  Job UUID
   * @returns {Promise<JobRefundResponse>}
   */
  claimRefund(jobId) {
    return this._http.post(`/api/job/${jobId}/claim-refund`, {});
  }

  /**
   * Get job state (getJob).
   *
   * @param {string} jobId  Job UUID
   * @returns {Promise<JobGetResponse>}
   */
  get(jobId) {
    return this._http.get(`/api/job/${jobId}`);
  }

  /**
   * List jobs for the current API key.
   *
   * @param {Object} [filters]
   * @param {string} [filters.status]  JobStatus filter: Open|Funded|Submitted|Completed|Rejected|Expired
   * @param {number} [filters.limit]   Max results (default 20, max 100)
   * @param {number} [filters.offset]  Pagination offset
   * @returns {Promise<JobListResponse>}
   */
  list(filters = {}) {
    const qs = new URLSearchParams();
    if (filters.status) qs.set('status', filters.status);
    if (filters.limit)  qs.set('limit',  String(filters.limit));
    if (filters.offset) qs.set('offset', String(filters.offset));
    const query = qs.toString() ? `?${qs.toString()}` : '';
    return this._http.get(`/api/job${query}`);
  }
}

// ─── Escrow namespace (v1 — deprecated, drainage aliases) ─────────────────────

/**
 * @deprecated Use `client.jobs` instead (ERC-8183 v2).
 * Preserved for 7-day v1 drainage period. Will be removed in v0.4.0.
 */
class EscrowNamespace {
  constructor(http, defaultNetwork) {
    this._http    = http;
    this._network = defaultNetwork;
    if (typeof console !== 'undefined') {
      console.warn('[ClearPact SDK] client.escrow is deprecated. Migrate to client.jobs — see https://clearpact.polsia.app/docs#migration-v1-to-v2');
    }
  }

  /** @deprecated */
  create(params) {
    return this._http.post('/api/escrow', { network: this._network, ...params });
  }

  /** @deprecated */
  get(id) {
    return this._http.get(`/api/escrow/${id}`);
  }

  /** @deprecated */
  fund(id, params = {}) {
    return this._http.post(`/api/escrow/${id}/fund`, params);
  }

  /** @deprecated */
  settle(id, params = {}) {
    return this._http.post(`/api/escrow/${id}/settle`, params);
  }

  /** @deprecated */
  cancel(id, params = {}) {
    return this._http.post(`/api/escrow/${id}/cancel`, params);
  }
}

// ─── x402 namespace ───────────────────────────────────────────────────────────

class X402Namespace {
  constructor(http, defaultNetwork) {
    this._http    = http;
    this._network = defaultNetwork;
  }

  verify(payload, options = {}) {
    const body = typeof payload === 'string'
      ? { _raw_signature: payload, network: this._network, ...options }
      : { ...payload, network: this._network, ...options };
    return this._http.post('/api/x402/verify', body);
  }

  settle(params = {}) {
    return this._http.post('/api/x402/settle', { network: this._network, ...params });
  }

  health() {
    return this._http.get('/api/x402/health');
  }

  listTransactions(filters = {}) {
    const qs = new URLSearchParams();
    if (filters.limit)   qs.set('limit',   String(filters.limit));
    if (filters.status)  qs.set('status',  filters.status);
    if (filters.from)    qs.set('from',    filters.from);
    if (filters.network) qs.set('network', filters.network);
    const query = qs.toString() ? `?${qs.toString()}` : '';
    return this._http.get(`/api/x402/transactions${query}`);
  }

  getTransaction(id) {
    return this._http.get(`/api/x402/transactions/${id}`);
  }
}

// ─── Webhooks namespace ───────────────────────────────────────────────────────

class WebhooksNamespace {
  constructor(http) {
    this._http = http;
  }

  create(params) {
    return this._http.post('/api/webhooks', params);
  }

  list() {
    return this._http.get('/api/webhooks');
  }

  delete(id) {
    return this._http.del(`/api/webhooks/${id}`);
  }

  deliveries(webhookId, opts = {}) {
    const qs = new URLSearchParams();
    if (opts.from)       qs.set('from',       opts.from);
    if (opts.to)         qs.set('to',         opts.to);
    if (opts.status)     qs.set('status',     opts.status);
    if (opts.event_type) qs.set('event_type', opts.event_type);
    if (opts.limit)      qs.set('limit',      String(opts.limit));
    if (opts.cursor)     qs.set('cursor',     opts.cursor);
    const query = qs.toString() ? `?${qs.toString()}` : '';
    return this._http.get(`/api/webhooks/${webhookId}/deliveries${query}`);
  }
}

// ─── Keys namespace ───────────────────────────────────────────────────────────

class KeysNamespace {
  constructor(http) {
    this._http = http;
  }

  usage(keyId, opts = {}) {
    const qs = new URLSearchParams();
    if (opts.from)     qs.set('from',     opts.from);
    if (opts.to)       qs.set('to',       opts.to);
    if (opts.status)   qs.set('status',   opts.status);
    if (opts.endpoint) qs.set('endpoint', opts.endpoint);
    if (opts.limit)    qs.set('limit',    String(opts.limit));
    if (opts.cursor)   qs.set('cursor',   opts.cursor);
    const query = qs.toString() ? `?${qs.toString()}` : '';
    return this._http.get(`/api/keys/${keyId}/usage${query}`);
  }
}

// ─── Main ClearPact client ────────────────────────────────────────────────────

/**
 * ClearPact API client v0.3.0 (ERC-8183 v2).
 *
 * @example
 * const { ClearPact } = require('clearpact');
 * const client = new ClearPact({ apiKey: 'cpk_live_...' });
 *
 * // ERC-8183 job lifecycle (v2)
 * const { job } = await client.jobs.create(
 *   '0xProvider',
 *   '0xEvaluatorEOA',
 *   new Date(Date.now() + 7 * 86400_000).toISOString(),
 *   'Build and deploy landing page'
 * );
 * await client.jobs.setBudget(job.id, 500);
 * await client.jobs.fund(job.id, { tx_hash: '0x...' });
 * await client.jobs.submit(job.id, 'https://deliverable.url/output');
 * await client.jobs.complete(job.id, 'Work accepted');
 */
class ClearPact {
  constructor({ apiKey, network = DEFAULT_NETWORK, baseUrl = DEFAULT_BASE_URL } = {}) {
    if (!apiKey) {
      throw new ClearPactError('apiKey is required. Get one at https://clearpact.polsia.app/docs', 0, null);
    }

    if (network !== 'testnet' && network !== 'mainnet') {
      throw new ClearPactError(`network must be "testnet" or "mainnet", got "${network}"`, 0, null);
    }

    this._http    = new HttpClient({ apiKey, baseUrl });
    this._network = network;

    /** @type {JobsNamespace} ERC-8183 v2 job lifecycle */
    this.jobs     = new JobsNamespace(this._http);

    /** @deprecated Use client.jobs */
    this.escrow   = new EscrowNamespace(this._http, this._network);

    /** @type {X402Namespace} */
    this.x402     = new X402Namespace(this._http, this._network);

    /** @type {WebhooksNamespace} */
    this.webhooks = new WebhooksNamespace(this._http);

    /** @type {KeysNamespace} */
    this.keys     = new KeysNamespace(this._http);
  }

  /** SDK version */
  static get version() { return SDK_VERSION; }

  /** Contract addresses (Phase 4 v2 deploy, immutable) */
  static get contracts() { return CONTRACT_ADDRESSES; }
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = { ClearPact, ClearPactError, CONTRACT_ADDRESSES };
module.exports.default = ClearPact;

/**
 * @typedef {'Open'|'Funded'|'Submitted'|'Completed'|'Rejected'|'Expired'} JobStatus
 * ERC-8183 JobStatus enum — exactly 6 values.
 */

/**
 * @typedef {Object} Job
 * ERC-8183 Job struct (9 fields) + ClearPact extensions.
 * @property {string}    id
 * @property {string}    client       Job initiator wallet address
 * @property {string}    provider     Service provider wallet address
 * @property {string}    evaluator    Self-service evaluator EOA
 * @property {string}    description
 * @property {number}    budget       Amount in token units
 * @property {string}    expiredAt    ISO 8601
 * @property {JobStatus} status
 * @property {string}    hook         IACPHook contract address (if set)
 * @property {string}    token        ERC-20 payment token address
 * @property {string}    conditionRef bytes32 conditional reference hash (if set)
 * @property {string}    contract_address  ClearPactJob proxy address
 * @property {number}    chain_id
 * @property {Object}    tx_hashes
 * @property {string}    created_at
 * @property {string}    updated_at
 */

/**
 * @typedef {Object} JobCreateResponse
 * @property {boolean} success
 * @property {Job}     job
 * @property {Object}  contract  { address, chain_id, network, explorer }
 */

/**
 * @typedef {Object} JobResponse
 * @property {boolean} success
 * @property {Job}     job
 */

/**
 * @typedef {Object} JobRejectResponse
 * @property {boolean}     success
 * @property {Job}         job
 * @property {Object|null} refund  Symmetric refund info (if Funded or Submitted)
 */

/**
 * @typedef {Object} JobRefundResponse
 * @property {boolean} success
 * @property {Job}     job
 * @property {Object}  refund  { status: 'claimed', guarantee: string }
 */

/**
 * @typedef {Object} JobGetResponse
 * @property {boolean} success
 * @property {Job}     job
 * @property {Array}   events
 * @property {Object}  contract
 */

/**
 * @typedef {Object} JobListResponse
 * @property {boolean}  success
 * @property {Job[]}    jobs
 * @property {Object}   pagination
 */

// ─── Deprecated type aliases (v1 → v2, drainage period) ─────────────────────

/**
 * @deprecated Use Job instead.
 * @typedef {Job} EscrowObject
 */

/**
 * @deprecated Use JobCreateResponse instead.
 * @typedef {JobCreateResponse} EscrowCreateResponse
 */

/**
 * @deprecated Use JobResponse instead.
 * @typedef {JobResponse} EscrowGetResponse
 */

/**
 * @typedef {Object} X402VerifyResponse
 * @property {boolean} success
 * @property {boolean} valid
 * @property {string}  transaction_id
 * @property {string}  from
 * @property {string}  to
 * @property {string}  amount_usdc
 * @property {number}  chain_id
 */

/**
 * @typedef {Object} X402SettleResponse
 * @property {boolean} success
 * @property {boolean} settled
 * @property {string}  transaction_id
 * @property {string}  settlement_tx_hash
 * @property {string}  amount_usdc
 */

/**
 * @typedef {Object} WebhookCreateResponse
 * @property {boolean}  success
 * @property {string}   id
 * @property {string}   url
 * @property {string[]} event_types
 * @property {string}   signing_secret  Keep this safe — shown only once
 */
