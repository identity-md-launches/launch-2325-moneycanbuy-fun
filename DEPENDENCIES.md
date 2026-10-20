# Vendored dependencies

Builds and tests use only the ordinary files under `lib/`; no install step, submodules, or network
access is required. Upstream source files and their licences are preserved without modifications.
Only the transitive Solidity imports of the entry points below are included.

| Package | Version | Entry point | Solidity files |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.0.2 | `contracts/token/ERC20/ERC20.sol` | 5 |
| forge-std | v1.9.7 | `src/Test.sol` | 19 |

Source archives:

- [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2)
  downloaded from `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`.
  Archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.
- [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7)
  downloaded from `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`.
  Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

OpenZeppelin is MIT licensed. forge-std includes MIT and Apache-2.0 licences. All are retained
beside the corresponding sources. The dependency versions are pinned by the delivered bytes,
not downloaded during compilation.
