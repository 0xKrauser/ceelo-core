//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import '@chainlink/contracts/src/v0.8/ConfirmedOwner.sol';
import '../interfaces/IRules.sol';
import '../interfaces/IDiceRoll.sol';
import 'hardhat/console.sol';

contract DragonRules is IRules, ConfirmedOwner {
    address public immutable diceroller;

    mapping(bytes32 => Result) public outcomes;

    constructor(address _diceRoller) ConfirmedOwner(msg.sender) {
        diceroller = _diceRoller;
    }

    function setOutcome(Result _result, bytes32[] calldata _keys) external onlyOwner {
        for (uint256 i; i < _keys.length; ++i) {
            outcomes[_keys[i]] = _result;
        }
    }

    function getOutcome(bytes32 _key) public view returns (Result) {
        return outcomes[_key];
    }

    function getOutcomeFromArray(uint8 one, uint8 two, uint8 three) public view returns (Result) {
        return outcomes[keccak256(abi.encodePacked(one, two, three))];
    }

    function _canSettleAutomatically(uint256 bankRequest) internal view returns (bool, Result) {
        Result bankResult = _evalBankRoll(bankRequest);
        if (uint8(bankResult) > 7) {
            return (true, bankResult);
        }
        if (uint8(bankResult) < 4) {
            return (true, bankResult);
        }
        return (false, bankResult);
    }

    function canSettleAutomatically(uint256 request) external view override returns (bool, Result) {
        return _canSettleAutomatically(request);
    }

    function settle(uint256 bankIndex, uint256[] calldata requests) external view returns (Result[] memory) {
        uint256 length = requests.length;
        uint256 bankRequest = requests[bankIndex];
        Result[] memory results = new Result[](length);
        (bool canSettle, Result bankResult) = _canSettleAutomatically(bankRequest);
        if (canSettle) {
            results = _setPlayerResults(bankResult, length);
        } else {
            results = _evalPlayerRolls(bankIndex, bankResult, requests);
        }

        return results;
    }

    function _setPlayerResults(Result bankResult, uint256 length) internal pure returns (Result[] memory) {
        Result[] memory results = new Result[](length);
        uint8 resultNumber = uint8(bankResult);
        Result newResult;
        if (resultNumber > 2) {
            newResult = Result.win;
        } else if (resultNumber == 8) {
            return results; // we return a zero array, on bet settlement it will be interpreted as a simple loss anyway
        } else if (resultNumber == 9) {
            newResult = Result.lose_two;
        } else if (resultNumber == 10) {
            newResult = Result.lose_three;
        } else if (resultNumber == 2) {
            newResult = Result.win_two;
        } else if (resultNumber == 3) {
            newResult = Result.win_three;
        }

        for (uint256 i; i < length; ++i) {
            results[i] = newResult;
        }
        return results;
    }

    function _evalPlayerRolls(
        uint256 bankIndex,
        Result bankResult,
        uint256[] calldata requests
    ) internal view returns (Result[] memory) {
        uint256 length = requests.length;
        Result[] memory results = new Result[](length);
        for (uint256 i; i < requests.length; ++i) {
            if (requests[i] == 0) results[i] = Result.nopoint; // if player hasn't rolled, we set the result to nopoint
            if (i == bankIndex) continue;
            uint8[] memory throws = IDiceRoll(diceroller).getRollValues(requests[i]);
            for (uint256 j; j < 3; ++j) {
                results[i] = getOutcomeFromArray(throws[j * 3], throws[j * 3 + 1], throws[j * 3 + 2]);
                if (uint8(results[i]) != 0) break;
            }
            uint8 result = uint8(results[i]);
            if (result > 3 && result < 8) {
                if (results[i] > bankResult) {
                    results[i] = Result.win;
                } else if (results[i] == bankResult) {
                    results[i] = Result.draw;
                } else {
                    results[i] = Result.lose;
                }
            }
        }

        // handles matches_previous and matches_next
        // quite dangerous, possibly has to be run multiple times or worse, recursive
        /*
        for (uint256 i; i < length; ++i) {
            if (uint8(results[i]) == 11) {
                if (i == 0) {
                    results[i] = results[length - 1];
                } else {
                    results[i] = results[i - 1];
                }
            }
            if (uint8(results[i]) == 12) {
                if (i == length - 1) {
                    results[i] = results[0];
                } else {
                    results[i] = results[i + 1];
                }
            }
        }
        */
        return results;
    }

    function _evalBankRoll(uint256 bankRequest) internal view returns (Result) {
        if (bankRequest == 0) return Result.nopoint; // if bank hasn't rolled, we set the result to nopoint
        uint8[] memory throws = IDiceRoll(diceroller).getRollValues(bankRequest);
        Result result = Result.nopoint;
        for (uint256 j; j < 3; ++j) {
            result = getOutcomeFromArray(throws[j * 3], throws[j * 3 + 1], throws[j * 3 + 2]);
            // if (uint8(result) > 10) result = Result.nopoint;
            if (uint8(result) != 0) return result;
        }
        return result;
    }

    function getNewBalances(
        Result[] calldata results,
        uint256 bankIndex,
        uint256 minBet,
        uint256[] memory playerBalances,
        uint256[] calldata playerBets
    ) external pure returns (uint256[] memory, bool[] memory bankrupt_) {
        uint256 bankBalance = playerBalances[bankIndex];

        bool[] memory bankrupt = new bool[](playerBalances.length);

        for (uint256 i; i < results.length; ++i) {
            if (i == bankIndex) continue;
            uint8 result = uint8(results[i]);

            if (bankBalance == 0) {
                break;
            }
            if (result < 2) {
                (uint256 bet, bool isFirst) = _getSmall(playerBalances[i], playerBets[i], minBet);
                bankrupt[i] = isFirst;
                bankBalance += bet;
                playerBalances[i] -= bet;
                continue;
            }
            if (result == 2) {
                (uint256 bet, bool isFirst) = _getSmall(playerBalances[i], playerBets[i] * 2, minBet * 2);
                bankrupt[i] = isFirst;
                bankBalance += bet;
                playerBalances[i] -= bet;
                continue;
            }
            if (result == 3) {
                (uint256 bet, bool isFirst) = _getSmall(playerBalances[i], playerBets[i] * 3, minBet * 3);
                bankrupt[i] = isFirst;
                bankBalance += bet;
                playerBalances[i] -= bet;
                continue;
            }
            if (result == 8) {
                (uint256 bet, ) = _getSmall(bankBalance, playerBets[i], minBet);
                bankBalance -= bet;
                playerBalances[i] += bet;
                continue;
            }
            if (result == 9) {
                (uint256 bet, ) = _getSmall(bankBalance, playerBets[i] * 2, minBet * 2);
                bankBalance -= bet;
                playerBalances[i] += bet;
                continue;
            }
            if (result == 10) {
                (uint256 bet, ) = _getSmall(bankBalance, playerBets[i] * 3, minBet * 3);
                bankBalance -= bet;
                playerBalances[i] += bet;
                continue;
            }
        }
        playerBalances[bankIndex] = bankBalance;
        if (bankBalance == 0) {
            bankrupt[bankIndex] = true;
        }

        return (playerBalances, bankrupt);
    }

    function _getSmall(uint256 _balance, uint256 _bet, uint256 _minBet) internal pure returns (uint256, bool) {
        uint256 bet = _minBet > _bet ? _minBet : _bet;
        return _balance > bet ? (bet, false) : (_balance, true);
    }
}
