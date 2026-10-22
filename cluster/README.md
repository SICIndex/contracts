# @compex/cluster

Ethereum cluster for SICI. One ERC-4626 vault per collateral, an operator controller in the shape of Euler's EVC, and a governor that can add another asset later.

Supply and borrow are both on for every vault. The connected wallet deposits. It names the WaaP agent as an operator. The agent then borrows against that collateral through `SiciEVC.call`.

DAI itself is not in this package. It is `DaiOFT` in `@compex/omnichain`: name **Decentralized Artificial Intelligence**, symbol DAI, 18 decimals, minted to the deployer, sent across chains with LayerZero once a peer is set.

## Deployed collateral

| Asset | Address | LTV |
| --- | --- | --- |
| LPT | `0x58b6a8a3302369daec383334672404ee733ab239` | 40% |
| TRAC | `0xaa7a9ca87d3694b5755f213b5d04094b8d0f0a6f` | 50% |
| IRYS | `0x50f41F589aFACa2EF41FDF590FE7b90cD26DEe64` | 40% |
| RENDER | `0x6de037ef9ad2725eb40118bb1702ebb27e4aeb24` | 60% |
| USDT | `0xdac17f958d2ee523a2206206994597c13d831ec7` | 90% |
| WETH | `0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2` | 80% |
| DAI | the OFT this script deploys | 80% unless `DAI_LTV_BPS` is set |

`INITIAL_MINT` is whole tokens minted to the deployer. The default is `1000000000`. The brief left the amount blank.

An asset with no price cannot support a borrow until the governor calls `setPrice`.

`deployments/` holds the addresses from each deployment this cluster has gone through (`ethereum.json`, plus the Sepolia testnet deployment). Deploy tooling itself (private-key-handling scripts) isn't part of this repo.

`forge test` covers operator borrow, the LTV ceiling, repay, withdraw, and adding a second vault.
