//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IDiceRoll {
    function requestRandomWords(
        bool _isMulti,
        bool withCallback,
        uint16 _length
    ) external returns (uint256 requestId);

    function getRollValues(uint256 _requestId) external view returns (uint8[] memory);
}
