# MoneyCanBuy.fun (YOLO)

`src/MoneyCanBuyToken.sol:MoneyCanBuyToken` is an ERC-20 with exactly 1,000,000,000 YOLO,
18 decimals, and a fixed supply of `1000000000000000000000000000` minor units. Its constructor
takes no arguments, accepts no ETH, and mints the entire supply to `msg.sender` once.
For the IMD launch, that sender is the launch factory.

## Behavior and interface

The token uses the locally vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation.
There are no transfer taxes, burns, transfer limits, owner, pause, blocklist, upgrade mechanism,
or public mint function. Transfers move exactly the requested amount and cannot change supply.
No external contract is called during construction or a token operation.

| Function | Behavior |
| --- | --- |
| `name()` / `symbol()` / `decimals()` | `MoneyCanBuy.fun` / `YOLO` / `18` |
| `INITIAL_SUPPLY()` / `totalSupply()` | `1000000000000000000000000000` |
| `balanceOf(account)` | Balance in minor units |
| `transfer(to, amount)` | Move the caller's tokens; return `true` on success |
| `approve(spender, amount)` | Replace the caller's allowance; return `true` |
| `allowance(holder, spender)` | Remaining spending authorization |
| `transferFrom(from, to, amount)` | Spend the caller's allowance from `from`; return `true` |

Zero-value transfers between nonzero addresses and self-transfers are supported. A transfer to
the zero address or an approval to the zero spender reverts. Insufficient balance or allowance
reverts with OpenZeppelin's ERC-6093 custom errors. A reverted transfer also rolls back allowance
changes. Even a holder calling `transferFrom` on its own balance needs allowance; use `transfer`
for ordinary holder transfers.

Finite allowances decrease when spent. The maximum `uint256` approval is unlimited and does not
decrease. `Transfer` is emitted for minting and every successful transfer, including zero amounts;
`Approval` is emitted by `approve`. This version does not emit an `Approval` when `transferFrom`
spends allowance. Integrators should read `allowance` when they need its current value.

## Build and test offline

Run from the repository root with Foundry and Solidity 0.8.26 already available:

```sh
forge build --offline
forge test --offline --fuzz-seed 0x487e7e1ed1316e9b2dcda291b662dfdb58f4de97b536648b62941ce75a1ad6e2
forge fmt --check
forge build --offline --sizes
slither . --exclude-informational --exclude-optimization --exclude-low --exclude-medium
```

The root configuration pins Solidity 0.8.26, Cancun, optimizer runs 200, and disables metadata
hashes and CBOR metadata. FFI and filesystem permissions are disabled. All imports are ordinary
files in `lib/`; see `DEPENDENCIES.md` for versions, provenance, and licences.

Tests use fresh deployments without RPC, environment variables, filesystem access, or shared
state. Unit and fuzz tests cover minting, factory deployment, full-value distribution, transfers,
approvals, failures, rollback, and absent administrative entry points. A stateful handler tracks
four holders against an independent balance and allowance model over randomized valid and invalid
operations. The defaults are 1,000 runs per fuzz test and 256 invariant runs of depth 128.

## Deployment parameters and responsibilities

This is the token implementation step for a `custom_token` launch on Ethereum (chain ID 1).
The artifact is `out/MoneyCanBuyToken.sol/MoneyCanBuyToken.json`; use its creation bytecode
with an empty constructor argument list and zero call value. There are no linked libraries,
initializers, application contracts, or post-deployment settings. No chain-specific address is
embedded in the token. No deployment transaction is part of this deliverable.

The separate manifest step must select Solidity identifier `MoneyCanBuyToken`, the exact metadata
and minor-unit supply above, and no constructor arguments. It owns `launch.json`. The network
deployer runs the reviewed launch through `ProjectFactory.launchCustom`; direct deployment from
an EOA would instead give that EOA the full supply and is not the IMD launch procedure.

The launch terms supplied in the brief are:

| Parameter | Value |
| --- | --- |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Manifest initial price | `79228162514264337593543950336` |
| Pool allocation | `poolBps: 8000`, 800,000,000 YOLO |
| Initial market cap | `initialMarketCapWei: "4000000000000000000000"` (4,000 IMD) |
| Remainder recipient | `0x612a9bb008e16ef2d24f41dae9fc661831d93367` |
| Remainder allocation | 100,000,000 YOLO |
| Swarm allocation | 100,000,000 YOLO, sent by the factory to its MerkleDistributor |

The factory handles all allocation and pool operations after receiving the whole supply.
The deployed opening price is derived by the launch system from the market cap, supply, and
currency ordering. The token does not allocate shares or calculate a price itself.
The manifest author must preserve the supplied economics exactly:

```json
{"poolBps":8000,"initialMarketCapWei":"4000000000000000000000","remainderTo":"0x612a9bb008e16ef2d24f41dae9fc661831d93367"}
```

The operator must use the reviewed factory launch workflow, verify the deployed code and metadata,
and confirm allocation receipts and pool initialization. No standalone broadcast command is
provided because it would bypass this factory workflow.

## After launch

No owner action, service, key, external oracle, or configuration is required for token transfers.
Holders control their tokens through their wallet and spending approvals. They should authorize
only trusted spenders, prefer limited approvals, and revoke unused approvals. Replacing a nonzero
allowance carries the standard ERC-20 transaction-ordering risk; revoke it first and confirm
before setting a replacement.

Transfers to contracts do not invoke a recipient callback or verify that the recipient can recover
the tokens. Tokens sent to this token contract itself, or another contract without a withdrawal
path, may be permanently inaccessible. There is no administrative rescue mechanism.
The immutable design means any future change requires a different token deployment.
Local tests and static analysis do not replace the network's independent review and launch checks;
see `REVIEW.md` for the validation scope and results.
