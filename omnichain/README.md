# @compex/omnichain

Delivery of a finished SICI job. The chain carries ids. The body stays on Irys at `https://gateway.irys.xyz/<id>`.

SICI providers do not run in this package. The hub's v1 callback is the Infernet hello-world container, and it only proves that the hop reached Base.

## Contracts

- `DaiOFT` — Ethereum. LayerZero OFT named Decentralized Artificial Intelligence, symbol DAI, 18 decimals. Minted to the deployer and listed in the `../cluster` collateral cluster at deploy time. It is not MakerDAO DAI.
- `JobSender` — source chain. `deliver(bytes32 jobId, bytes32 irysId, uint32 dstEid, address dstContract, bytes4 method)` quotes LayerZero, sends the payload to the hub, and refunds unused native value to the caller in the same transaction.
- `InfernetHub` — Base. Accepts the sender's message, takes the Infernet hello-world callback, then forwards the same ids.
- `JobReceiver` — destination chain. The hub is the only peer. It calls `dstContract` with two 32-byte words.

## Payload

Five words, 160 bytes: `jobId`, `irysId`, `dstEid`, `dstContract`, `method`. The default method is the selector of `onJobDelivered(bytes32,bytes32)`. A zero method is replaced with that selector on the sender. The receiver never appends a third argument.

`dstEid` has to be allowed on `JobSender` and on `InfernetHub`. The hub's container allowlist starts as `bytes32("hello-world")` only.

## Callback

`rawReceiveCompute` is the nine-argument Infernet entry. Only the configured coordinator may call it. An output of 32 bytes or fewer is stored as `keccak256(output)`. A longer output emits `WorkerMustUpload` and is not stored. The callback does not upload to Irys.

`commitResponse(jobId, irysId)` is owner-only. It fills a missing id, then sends LayerZero. If the hub cannot pay the fee, or the send fails, it emits `Undeliverable` and returns. The callback itself does not revert for that.

The hub's `receive()` holds the operator's fee float. It is not a user deposit. `JobSender` does not keep leftover value. `JobReceiver` has no `receive()`.

## Receiver failure

If `dstContract` reverts, the receiver stores `failedIds[jobId] = irysId`, emits `DeliveryFailed`, and returns. The LayerZero receive does not revert. Nonces are not checked.

## Port

`createDeliveryPort({ to, sign })` encodes `JobSender.deliver`. `to` is the sender contract. `sign` is supplied by the caller. This package has no key.

With no `sign`, `deliver` returns `{ tx: undefined, data }` and `data` is the calldata. With `sign`, it returns `{ tx }` from that signer.

Ids: a 32-byte hex string is used as-is. An unpadded base64url string of 32 bytes (an Irys id) is decoded. Any other non-empty string, including a sequence id such as `brief-the-team`, is `keccak256` of its UTF-8 bytes.

## LayerZero

Sends are unordered. Options are type 3, executor worker, lzReceive gas 800000. Option type 4 is not encoded. `payInLzToken` is false. The endpoint address is a constructor argument. The receiver forwards 500000 gas to `dstContract`. A target that still reverts, including by running out of gas, is stored as `DeliveryFailed`.

## Tests

From this directory, `forge test` runs the contract tests.
