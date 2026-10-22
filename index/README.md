# @compex/index

On-chain SICI index and the set share. DAI is the coin. `CompexIndex` stores fee weights and the chain-linked level. It does not hold tokens. The contracts in `src/set` buy the constituent tokens and mint shares. A buyer's balance is set shares, not a claim on the treasury.

| Contract | Role |
| --- | --- |
| `CompexIndex` | Weights, chain-linked level, `rebalance` |
| `CompexTreasury` | Fee tokens only. `bookFee` is callable by the settle module |
| `CompexSettle` | Pulls a quote from the payer, books the fee, pays the rest |
| `CompexTopUp` | Forwards a token to a WaaP address in the same call |
| `UniPriceSource` | Uniswap DAI pairs, a USD pool, and the AKT / RITUAL push |
| `FixturePrices` | Local prices for tests. Not a production oracle |
| `ManualPriceSource` | Admin USD marks for a chain that has no constituent pools |
| `CompexSetIssuer` | One USDT payment. Buys the fee-weighted tokens and mints set shares |

`rebalance` is permissionless. The caller pays the gas. The level starts at `100e18` (100.00 points) on the first print that has a non-zero enabled fee notional. Later prints use

`level_t = level_{t-1} × Σ(w_t × p_t) / Σ(w_t × p_{t-1})`.

A constituent with no stored price uses its current price as the previous one for that print, so turning it on does not jump the level by itself. Disabled constituents keep their notional and are left out of the weights and the ratio. `RITUAL` starts disabled.

Weights are basis points of enabled fee notionals and sum to 10000. The leftover basis point goes to the enabled constituent with the largest notional. A tie keeps the earliest of DAI, TRAC, RENDER, LPT, IRYS, AKT, RITUAL.

The remainder of a settled leg must leave this contract inside `payData` (the callee pulls the approved amount). Nothing of the payer's balance stays on the settle contract. `topUp` sends the full amount to `waap` and does not charge a fee.

## Constructor and admin arguments

No pool address, DAI address, or USD pair is set in the source. They are unset until the deploy transaction passes them.

`CompexIndex(admin, priceSource)`

- `admin` — may call `setEnabled`, `setPriceSource`, `setNotionalWriter`, `pushAndRebalance`
- `priceSource` — `UniPriceSource` in production, `FixturePrices` in local tests

`CompexTreasury(admin, index)`

- `setSettle(settle)` once, before any fee

`CompexSettle(treasury, index)`

`CompexTopUp()` — no arguments

`UniPriceSource(admin)`, then, from `admin`:

- `setDai(dai, decimals)` — the DAI token. Not hardcoded.
- `setConstituentPool(id, token, decimals, pool, v3)` — TRAC, RENDER, LPT, IRYS against DAI. `v3 = true` reads a 30-minute TWAP. `v3 = false` reads V2 reserves.
- `setUsdPoolDirect(pool, v3, quote, quoteDecimals)` — DAI against a USD quote such as USDT.
- `setUsdPoolViaWeth(...)` — DAI/WETH plus WETH/USDT, used instead of the direct pool.
- `setIndex(index)` once, so `pushAndRebalance` can write AKT and RITUAL.
- `pushDaiPerToken(AKT or RITUAL, daiPerWholeToken)` — 1e18-scaled DAI per one whole token. `CompexIndex.pushAndRebalance` does this and `rebalance()` in one transaction.

Call `setDai` before the USD pool setters.

## Build

```bash
forge install
forge test
```

`forge build` writes ABI JSON under `out/`. The four interface ABIs are copied to `abi/`.

## Trust

`settle` books the `notionalDai` value in the leg. It does not prove that number against an off-chain quote. The wallet should send only the calldata from the API. Binding a quote hash is not in the frozen interface.

Fee tokens sit in the treasury. This package has no withdraw function.
