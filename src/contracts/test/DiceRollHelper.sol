// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import '../interfaces/IDiceRoll.sol';

contract DiceRollHelper {
    address public immutable diceRoller;
    bool public fulfilled;

    event Request(uint256 requestId);

    constructor(address _diceroller) {
        diceRoller = _diceroller;
    }

    function requestDiceRolls(uint16 _dice) external {
        uint256 requestId = IDiceRoll(diceRoller).requestRandomWords(true, true, _dice);
        fulfilled = false;
        emit Request(requestId);
    }

    function fulfillDice(uint256 _requestId) external onlyDiceRoller(_requestId) {
        fulfilled = true;
    }

    modifier onlyDiceRoller(uint256 _gameId) {
        require(msg.sender == diceRoller, '!diceRoller');
        _;
    }
}
