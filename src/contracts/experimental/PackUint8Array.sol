// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;
pragma abicoder v2;

contract PackUint8Array {
    constructor() {}

    uint8[] public array = [1, 2, 3];

    function pack() public view returns (bytes32) {
        return keccak256(abi.encodePacked(array));
    }

    function testArray(uint256 _length) public pure returns (uint8[] memory) {
        uint8[] memory result = new uint8[](_length);
        return result;
    }

    function assemblyPack(
        uint8 one,
        uint8 two,
        uint8 three
    ) public pure returns (bytes memory result) {
        assembly {
            result := mload(add(one, 32))
        }
    }
}
