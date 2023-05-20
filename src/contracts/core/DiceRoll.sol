//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import '@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol';
import '@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol';
import '@chainlink/contracts/src/v0.8/ConfirmedOwner.sol';
import '../libraries/Utilities.sol';
import '../interfaces/IDiceRoll.sol';
import '../interfaces/IConsumer.sol';
import 'hardhat/console.sol';

contract DiceRoll is IDiceRoll, VRFConsumerBaseV2, ConfirmedOwner {
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 subscriptionId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 keyHash;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations;

    enum Type {
        Single,
        Multi
    }

    uint32 gasSingle;
    uint32 gasMulti;

    struct Request {
        address consumer;
        bool fulfilled;
        bool withCallback;
        uint16 length;
        uint8[] values;
    }
    mapping(address => bool) private consumers;
    mapping(uint256 => Request) public requests;
    mapping(uint256 => bool) public isMulti;

    event RequestSent(uint256 requestId, bool multi, uint16 length);
    event RequestFulfilled(uint256 requestId, uint8[] rollValue);

    constructor(
        address _coordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) VRFConsumerBaseV2(_coordinator) ConfirmedOwner(msg.sender) {
        COORDINATOR = VRFCoordinatorV2Interface(_coordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
    }

    /**
     * Requests randomness
     */
    // Assumes the subscription is funded sufficiently.
    function requestRandomWords(
        bool _isMulti,
        bool _withCallback,
        uint16 _length
    ) external onlyConsumer(msg.sender) returns (uint256 requestId) {
        // Will revert if subscription is not set and funded.
        uint16 words = _isMulti ? 1 : _length;
        uint32 wordGasLimit = _isMulti ? gasMulti : gasSingle;

        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            wordGasLimit * _length,
            words
        );
        requests[requestId] = Request(msg.sender, false, _withCallback, _length, new uint8[](_length));
        isMulti[requestId] = _isMulti;

        emit RequestSent(requestId, _isMulti, _length);
        return (requestId);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        if (isMulti[_requestId]) {
            fulfillRandomWordsMulti(_requestId, _randomWords);
        } else {
            fulfillRandomWordsSingle(_requestId, _randomWords);
        }
        if (requests[_requestId].withCallback) {
            IConsumer(requests[_requestId].consumer).fulfillDice(_requestId);
        }
    }

    // fulfillRandomWords function
    function fulfillRandomWordsSingle(uint256 _requestId, uint256[] memory _randomWords) internal {
        // transform the result to a number between 1 and 6 inclusively
        Request storage request = requests[_requestId];
        uint8[] memory rollValues = new uint8[](request.length);

        for (uint256 i; i < _randomWords.length; ++i) {
            rollValues[i] = uint8((_randomWords[i] % 6) + 1);
        }

        // assign the transformed value to the address in the s_results mapping variable
        requests[_requestId].fulfilled = true;
        requests[_requestId].values = rollValues;
        // emitting event to signal that dice landed
        emit RequestFulfilled(_requestId, rollValues);
    }

    function fulfillRandomWordsMulti(uint256 _requestId, uint256[] memory _randomWords) internal {
        Request storage request = requests[_requestId];
        uint8[] memory rollValues = Utilities.expand(_randomWords[0], request.length);

        requests[_requestId].fulfilled = true;
        requests[_requestId].values = rollValues;

        emit RequestFulfilled(_requestId, rollValues);
    }

    function getRollValues(uint256 _requestId) external view returns (uint8[] memory) {
        Request memory request = requests[_requestId];
        require(request.fulfilled, '!fulfilled');
        return request.values;
    }

    function setCallbackGasLimit(uint32 _gasSingle, uint32 _gasMulti) external onlyOwner {
        gasSingle = _gasSingle;
        gasMulti = _gasMulti;
    }

    function setConfirmations(uint16 _confirmations) external onlyOwner {
        requestConfirmations = _confirmations;
    }

    function addConsumer(address _consumer) external onlyOwner {
        consumers[_consumer] = true;
    }

    function removeConsumer(address _consumer) external onlyOwner {
        consumers[_consumer] = false;
    }

    modifier onlyConsumer(address _consumer) {
        require(consumers[_consumer], '!consumer');
        _;
    }
}
