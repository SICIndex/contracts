# SICI contracts

The on-chain side of SICI: the collateral cluster agents borrow against, the fee-weighted index and its share token, and the cross-chain job-delivery path.

**None of this has had a third-party security audit. Treat all of it as unaudited.**

## Layout

| Directory | What it is |
| --- | --- |
| [`cluster/`](./cluster) | Collateral vaults an AI agent borrows against, on the owner's behalf, once the owner names it as an operator. |
| [`index/`](./index) | The fee-weighted index price, the settlement path, and the tokenized share of the basket. |
| [`omnichain/`](./omnichain) | Carries a finished job's result id across chains via LayerZero. |

Each directory is its own Foundry project — see its own README for details.

## A naming note: "Set" and "Euler"

Two pieces here are intentionally built in the *shape* of well-known DeFi protocols, as a design reference — **neither is the real thing**:

- `index/src/set/` (`SetToken`, `BasicIssuanceModule`, `Controller`, `SetTokenCreator`, `ConstituentDesk`, `CompexSetIssuer`) borrows **Set Protocol v2**'s naming and design for turning a basket of tokens into one share. It's original code, not an import or fork of Set's actual contracts, and it isn't covered by any Set Protocol audit.
- `cluster/src/SiciEVC.sol` + `cluster/src/SiciVault.sol` borrow **Euler**'s Vault Connector pattern — deposit collateral once, name an operator that can then borrow against it on your behalf. Same idea, original code, no Euler dependency.

## Build

Each project builds independently with [Foundry](https://getfoundry.sh):

```bash
git clone --recurse-submodules <this repo>
cd cluster && forge build && forge test   # 11 tests
cd ../index && forge build && forge test  # 40 tests
cd ../omnichain && forge build && forge test  # 26 tests
```

`cluster` and `omnichain` share `index`'s `forge-std` via a relative remapping — keep the three directories as siblings.

## Third-party contracts these call into

This repo never imports or forks these — it only calls their live deployments. Their audits cover their own code, not this repo's usage of it.

- **Uniswap V3** — price reads and the swap pools used for testing. [Audits](https://docs.uniswap.org/contracts/v3/concepts/security).
- **LayerZero V2** — the cross-chain endpoint `DaiOFT` and the job-delivery path send through. [Certora report](https://www.certora.com/reports/layerzero-v2) · [ChainSecurity report](https://chainsecurity.com/security-audit/layerzero-oft-oapp).
