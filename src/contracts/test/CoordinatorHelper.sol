pragma solidity ^0.8.17;
//SPDX-License-Identifier: MIT

import '@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol';
import '@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol';
import 'hardhat/console.sol';

/**
 * Demonstrates how to consume random number in a more complex scenario.
 *
 * Any user can be a dice roller.
 * They may perform exactly one set of 6 dice rolls, with a single request.
 *
 * All dice rolls are stored and can be retrieved by the roller address.
 * Roll results are also emitted via events.
 *
 */
contract CoordinatorHelper is VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 subscriptionId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 keyHash;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 20000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    struct Request {
        uint16 length;
        bool fulfilled;
        uint256[] values;
    }

    Request public request;

    event RequestSent(uint256 requestId, uint16 length);
    event RequestFulfilled(uint256 requestId, uint256[] words);

    constructor(
        address _coordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) VRFConsumerBaseV2(_coordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(_coordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
    }

    /**
     * Requests randomness
     */
    // Assumes the subscription is funded sufficiently.
    function requestRandomWords(uint16 _length) external returns (uint256 requestId) {
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit * (_length + 2),
            _length
        );

        request = Request(_length, false, new uint256[](_length));
        emit RequestSent(requestId, _length);
    }

    // fulfillRandomWords function
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        // assign the transformed value to the address in the s_results mapping variable
        request.fulfilled = true;
        request.values = _randomWords;
        // emitting event to signal that dice landed
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getValues() external view returns (uint256[] memory) {
        Request memory i_request = request;
        return i_request.values;
    }
}
