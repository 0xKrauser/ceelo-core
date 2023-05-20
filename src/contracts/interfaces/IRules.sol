// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRules {
    enum Result {
        nopoint, // 0
        lose, // 1
        lose_two, // 2
        lose_three, // 3
        point_two, // 4
        point_three, // 5
        point_four, // 6
        point_five, // 7
        win, // 8
        win_two, // 9
        win_three, // 10
        matches_previous, // 11
        matches_next, // 12
        draw // 13
    }

    function canSettleAutomatically(uint256 bankRequest) external view returns (bool, Result);

    function settle(uint256 bankIndex, uint256[] memory requests) external view returns (Result[] memory);

    function getNewBalances(
        Result[] memory results,
        uint256 bankIndex,
        uint256 minBet,
        uint256[] memory playerBalances,
        uint256[] memory playerBets
    ) external pure returns (uint256[] memory, bool[] memory bankruptcies);
}
