// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol';

import './IERC721Permit.sol';
import './IPeripheryPayments.sol';
import './IPeripheryImmutableState.sol';

interface IChinchiro is IERC721Metadata, IERC721Permit {
    event GameCreated(uint256 tokenId, MintParams params);
    event NewRound(uint256 indexed gameId, uint256 indexed roundId, uint256 requestId);
    event BankFulfilled(uint256 indexed gameId, uint256 indexed roundId, BankStatus status, uint8 result);
    event Bet(uint256 indexed gameId, uint256 indexed roundId, address indexed from, uint256 bet);
    event Roll(uint256 indexed gameId, uint256 indexed roundId, address indexed from, uint256 requestId);

    enum BankStatus {
        none,
        notStarted,
        requested,
        automatic,
        fulfilled
    }

    struct MintParams {
        uint256 variant;
        uint256 minBet;
        uint256 maxBet;
        uint8 minPlayers;
        uint8 maxPlayers;
        uint8 maxRounds;
    }

    /// @notice Creates a new game wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position

    function mint(
        MintParams calldata params // TODO:
    ) external payable returns (uint256 tokenId);
}
