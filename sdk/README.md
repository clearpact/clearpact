# ClearPact SDK

Lightweight JavaScript/TypeScript client for the [ClearPact](https://clearpact.polsia.app) escrow API.

- **Zero dependencies** — uses native `fetch` (Node 18+ / modern browsers)
- **Full TypeScript types** for autocomplete and type safety
- **Testnet by default** — safe for development, flip `network: 'mainnet'` when ready

## Install

```bash
npm install clearpact
```

Or use the browser CDN build:

```html
<script src="https://clearpact.polsia.app/sdk"></script>
```

## Quick Start

```js
const { ClearPact } = require('clearpact');

const client = new ClearPact({
  apiKey:  'cpk_live_...',   // from https://clearpact.polsia.app/docs
  network: 'testnet',       // 'testnet' | 'mainnet'
});

// Create an escrow
const { escrow } = await client.escrow.create({
  payer:  '0xPayerWalletAddress',
  payee:  '0xPayeeWalletAddress',
  amount: 100,              // USDC
  conditions: [
    { type: 'task_completion' },
  ],
});

console.log(escrow.id, escrow.status);
// → "3f2ac1d0-..." "pending_funding"

// Fund it
await client.escrow.fund(escrow.id, { tx_hash: '0x...' });

// Settle (manual — or use ERC-8004 external_job_id for auto-settlement)
await client.escrow.settle(escrow.id, {
  verifications: {
    task_completion: { completed: true },
  },
});

// Cancel / refund
await client.escrow.cancel(escrow.id, { reason: 'Work not delivered' });
```

## ESM

```js
import { ClearPact } from 'clearpact';
```

## TypeScript

```ts
import { ClearPact, ClearPactError } from 'clearpact';
import type { EscrowObject, CreateEscrowParams } from 'clearpact/types';

const client = new ClearPact({ apiKey: 'cpk_live_...' });

try {
  const { escrow } = await client.escrow.create({ payer: '0x...', payee: '0x...', amount: 50 });
} catch (err) {
  if (err instanceof ClearPactError) {
    console.error(err.status, err.message);
  }
}
```

## API Reference

### `new ClearPact(options)`

| Option    | Type      | Default                          | Description                    |
|-----------|-----------|----------------------------------|--------------------------------|
| `apiKey`  | `string`  | **required**                     | Your ClearPact API key         |
| `network` | `string`  | `'testnet'`                      | `'testnet'` or `'mainnet'`     |
| `baseUrl` | `string`  | `https://clearpact.polsia.app`   | Override API base URL          |

---

### `client.escrow`

| Method                          | Description                                        |
|---------------------------------|----------------------------------------------------|
| `create(params)`                | Create a new escrow                                |
| `get(id)`                       | Get escrow status + audit trail                    |
| `fund(id, params?)`             | Record a funding event                             |
| `settle(id, params?)`           | Manually settle (prefer ERC-8004 auto-settlement)  |
| `cancel(id, params?)`           | Cancel or refund                                   |

#### `create` params

```ts
{
  payer:           string;    // Payer wallet address
  payee:           string;    // Payee wallet address
  amount:          number;    // USDC amount
  token?:          string;    // Default: 'USDC'
  conditions?:     Condition[];
  metadata?:       Record<string, unknown>;
  expires_at?:     string;    // ISO 8601
  external_job_id?: string;   // Links to ERC-8004 auto-settlement
  network?:        'testnet' | 'mainnet';
}
```

#### Condition types

| Type              | Required fields              |
|-------------------|------------------------------|
| `task_completion` | —                            |
| `approval`        | `approver?` (address)        |
| `deadline`        | `deadline` (ISO 8601)        |
| `threshold`       | `min_value` (number)         |
| `oracle`          | `oracle_url`                 |
| `custom`          | —                            |

---

### `client.x402`

| Method                      | Description                          |
|-----------------------------|--------------------------------------|
| `verify(payload, options?)` | Verify an x402 payment authorization |
| `settle(params?)`           | Settle a verified x402 payment       |
| `health()`                  | Facilitator health + config          |
| `listTransactions(filters?)`| List x402 transaction records        |
| `getTransaction(id)`        | Get single x402 transaction          |

---

### `client.webhooks`

| Method           | Description                     |
|------------------|---------------------------------|
| `create(params)` | Register a webhook endpoint     |
| `list()`         | List registered webhooks        |
| `delete(id)`     | Remove a webhook                |

Webhook payload envelope:

```json
{
  "id": "uuid",
  "type": "escrow.created",
  "created_at": "2025-01-01T00:00:00.000Z",
  "data": { ...escrow }
}
```

Verify payloads using the `X-ClearPact-Signature: sha256=<hex>` header (HMAC-SHA256).

---

### Error handling

All errors throw a `ClearPactError`:

```js
const { ClearPactError } = require('clearpact');

try {
  await client.escrow.get('bad-id');
} catch (err) {
  if (err instanceof ClearPactError) {
    console.error(err.status);  // 400
    console.error(err.message); // "Invalid escrow ID format"
    console.error(err.raw);     // Full response body
  }
}
```

## ERC-8004 Auto-Settlement

Link an escrow to an external job for automatic settlement:

```js
const { escrow } = await client.escrow.create({
  payer:           '0x...',
  payee:           '0x...',
  amount:          500,
  external_job_id: 'job_abc123',   // Your external job reference
  conditions: [{ type: 'task_completion' }],
});

// When the job finishes, POST /api/validation/submit with external_job_id: 'job_abc123'
// The escrow settles automatically — no polling needed.
```

## License

MIT — © ClearPact
