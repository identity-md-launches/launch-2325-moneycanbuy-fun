// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MoneyCanBuyToken} from "../../src/MoneyCanBuyToken.sol";

/// @dev Test-only token holder. It does not model Uniswap pricing, liquidity, or swaps.
contract TokenHolder {
    function send(MoneyCanBuyToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

/// @dev Test-only factory used to verify CREATE/CREATE2 ownership of the initial supply.
contract LaunchHarness is TokenHolder {
    function deploy() external returns (MoneyCanBuyToken) {
        return new MoneyCanBuyToken();
    }

    function deployDeterministically(bytes32 salt) external returns (MoneyCanBuyToken) {
        return new MoneyCanBuyToken{salt: salt}();
    }
}

contract RejectingRecipient {
    fallback() external {
        revert("no callbacks accepted");
    }
}
