// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IConsumer {
    function fulfillDice(uint256 _requestId) external;
}
