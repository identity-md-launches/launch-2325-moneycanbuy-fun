// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MoneyCanBuy.fun (YOLO)
/// @notice Fixed-supply ERC-20 with the entire supply minted once to its deployer.
/// @dev The launch factory is msg.sender during deployment. No administrative powers are exposed.
contract MoneyCanBuyToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("MoneyCanBuy.fun", "YOLO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
