//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;
import './ERC721Permit.sol';
import '../interfaces/IChinchiro.sol';
import '../interfaces/INonFungibleTokenGameDescriptor.sol';
import '@chainlink/contracts/src/v0.8/ConfirmedOwner.sol';
import '../interfaces/IDiceRoll.sol';
import '../interfaces/IRules.sol';

contract Chinchiro is ERC721Permit, IChinchiro, ConfirmedOwner {
    address private _tokenDescriptor;
    address private _diceRoller;

    uint256 public constant DECIMALS = 18;
    uint256 public constant UNIT = 10 ** DECIMALS;

    struct Game {
        // the nonce for permits
        uint96 nonce;
        // the address that is approved for spending this token
        address operator;
        uint256 variant;
        uint256 minBet;
        uint256 maxBet;
        uint8 maxRounds;
        uint8 minPlayers;
        uint8 maxPlayers;
        bool isRunning;
    }

    struct Round {
        uint256 id;
        uint256 bank; // index of bank in players array
        BankStatus bankStatus;
        uint256 bets; // number of bets in this round
        uint256 throws; // number of throws in this round
        uint256 lastAction; // timestamp of last throw
    }

    struct Variant {
        address settler;
        string name;
    }

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId = 1;

    mapping(uint256 => Variant) public variants;
    mapping(uint256 => Game) public games;
    mapping(uint256 => Round) public currentRound;
    mapping(bytes32 => uint256) public indexOf; // (game id, address) => index in players array
    mapping(uint256 => uint256) public treasury; // game id => treasury (sum of entry fees)
    mapping(uint256 => address[]) public players; // game id => player addresses
    mapping(uint256 => uint256[]) public playerBalances; // game id => player balances
    mapping(uint256 => uint256[]) public playerBets; // game id => player bets for current round
    mapping(uint256 => uint256[]) public playerRolls; // game id => player chainlink request ids for current round
    mapping(uint256 => uint256) public currentBankRequest; // request id => game id

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _version
    ) ERC721Permit(_name, _symbol, _version) ConfirmedOwner(msg.sender) {}

    function setTokenDescriptor(address tokenDescriptor) external onlyOwner {
        _tokenDescriptor = tokenDescriptor;
    }

    function setDiceRoller(address diceRoller) external onlyOwner {
        _diceRoller = diceRoller;
    }

    function addVariant(uint256 variant, address settler, string calldata name) external onlyOwner {
        variants[variant] = Variant(settler, name);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(tokenId));
        return INonFungibleTokenGameDescriptor(_tokenDescriptor).tokenURI(this, tokenId);
    }

    function mint(MintParams calldata params) external payable override returns (uint256 tokenId) {
        uint256 _tokenId = _nextId++;
        createGame(
            _tokenId,
            params.variant,
            params.minBet,
            params.maxBet,
            params.minPlayers,
            params.maxPlayers,
            params.maxRounds
        );
        _mint(address(this), _tokenId); // mint to contract and when game is ended, transfer to winner

        emit GameCreated(_tokenId, params);
        return _tokenId;
    }

    function createGame(
        uint256 tokenId,
        uint256 variant,
        uint256 minBet,
        uint256 maxBet,
        uint8 minPlayers,
        uint8 maxPlayers,
        uint8 maxRounds
    ) internal {
        require(variants[variant].settler != address(0), '!variant');
        require(0 != maxPlayers, '!maxPlayers');
        require(0 != minPlayers, '!minPlayers');
        require(minPlayers <= maxPlayers, '!minPlayers');
        require(0 != maxBet, '!maxBet');
        require(0 != minBet, '!minBet');
        require(minBet < maxBet, '!minBet');
        require(0 != maxRounds, '!maxRounds');

        games[tokenId] = Game(0, address(0), variant, minBet, maxBet, maxRounds, minPlayers, maxPlayers, true);
        currentRound[tokenId] = Round(0, 0, BankStatus.notStarted, 0, 0, 0);
    }

    function play(uint256 _gameId) external isBank(_gameId, msg.sender) {
        Game memory game = games[_gameId];
        Round storage round = currentRound[_gameId];
        require(round.bankStatus == BankStatus.notStarted, '!started');
        require(game.minPlayers <= players[_gameId].length, '!minPlayers');
        playerBets[_gameId] = new uint256[](players[_gameId].length);
        playerRolls[_gameId] = new uint256[](players[_gameId].length);
        round.bankStatus = BankStatus.none;
    }

    function _getBetAmount(uint256 _gameId, uint256 _balance, uint256 _betAmount) internal view returns (uint256) {
        Game memory game = games[_gameId];
        if (game.minBet > _betAmount) {
            _betAmount = game.minBet;
        }
        if (game.maxBet < _betAmount) {
            _betAmount = game.maxBet;
        }
        if (_betAmount > _balance) {
            _betAmount = _balance;
        }
        return _betAmount;
    }

    function bet(uint256 _gameId, uint256 betAmount) external isNotBank(_gameId, msg.sender) {
        Game memory game = games[_gameId];
        require(game.isRunning, '!ended');

        Round storage round = currentRound[_gameId]; // storage coz we will modify bet counter
        require(round.bankStatus == BankStatus.none, '!bankRequested');

        uint256 index = getIndex(_gameId, msg.sender);
        uint256 balance = playerBalances[_gameId][index];

        if (playerBets[_gameId][index] == 0) {
            round.bets++;
        }

        playerBets[_gameId][index] = _getBetAmount(_gameId, balance, betAmount);
        round.lastAction = block.timestamp;
        emit Bet(_gameId, round.id, msg.sender, betAmount);
    }

    function start(uint256 _gameId) external isRunning(_gameId) isBank(_gameId, msg.sender) {
        Round storage round = currentRound[_gameId];
        if (round.bets < players[_gameId].length - 1) {
            require(block.timestamp > (round.lastAction + 2 minutes), '!early');
            _setMinimumBets(_gameId);
        }
        require(round.bankStatus == BankStatus.none, '!bankRequested');
        uint256 requestId = _requestRoll(true);
        currentBankRequest[requestId] = _gameId;
        playerRolls[_gameId][round.bank] = requestId;
        round.bankStatus = BankStatus.requested;
        round.lastAction = block.timestamp;
        round.throws++;
        emit NewRound(_gameId, round.id, requestId);
    }

    function roll(uint256 _gameId) external isNotBank(_gameId, msg.sender) {
        Round storage round = currentRound[_gameId];
        require(round.bankStatus == BankStatus.fulfilled, '!bankFulfilled');
        require(round.throws < players[_gameId].length, '!thrown');

        uint256 index = indexOf[_getPlayerIndex(_gameId, msg.sender)];
        require(playerRolls[_gameId][index] == 0, '!thrown');
        uint256 requestId = _requestRoll(false);
        playerRolls[_gameId][index] = requestId;
        round.lastAction = block.timestamp;
        round.throws++;
        emit Roll(_gameId, round.id, msg.sender, requestId);
    }

    function fulfillDice(uint256 _requestId) external onlyDiceRoller(_requestId) {
        uint256 _gameId = currentBankRequest[_requestId];
        Game memory game = games[_gameId];
        Round storage round = currentRound[_gameId];
        (bool canSettle, IRules.Result result) = IRules(variants[game.variant].settler).canSettleAutomatically(
            _requestId
        );
        if (canSettle) {
            round.bankStatus = BankStatus.automatic;
        } else {
            round.bankStatus = BankStatus.fulfilled;
        }

        emit BankFulfilled(_gameId, round.id, round.bankStatus, uint8(result));
    }

    function getRollId(uint256 _gameId, uint256 _playerIndex) public view returns (uint256) {
        return playerRolls[_gameId][_playerIndex];
    }

    function _requestRoll(bool withCallback) internal returns (uint256 requestId) {
        return IDiceRoll(_diceRoller).requestRandomWords(true, withCallback, 9);
    }

    function settleRound(uint256 _gameId) external {
        Game storage game = games[_gameId];
        require(game.isRunning, '!ended');
        Round storage round = currentRound[_gameId];
        uint256 playersLength = players[_gameId].length;

        IRules settler = IRules(variants[game.variant].settler);
        IRules.Result[] memory results = new IRules.Result[](playersLength);

        if (round.bankStatus == BankStatus.automatic) {
            // settle without further requirements
            results = settler.settle(round.bank, playerRolls[_gameId]);
        } else {
            require(block.timestamp > (round.lastAction + 2 minutes) || round.throws == playersLength, '!early');
            results = settler.settle(round.bank, playerRolls[_gameId]);
        }

        (uint256[] memory balances, bool[] memory bankrupt) = settler.getNewBalances(
            results,
            round.bank,
            game.minBet,
            playerBalances[_gameId],
            playerBets[_gameId]
        );

        playerBalances[_gameId] = balances;
        // remove failed players and then get next bank index
        for (uint256 i; i < playersLength; ++i) {
            if (bankrupt[i]) {
                _removePlayer(_gameId, players[_gameId][i]);
            }
        }

        delete round.bankStatus;
        delete round.bets;
        delete round.throws;
        delete round.lastAction;
        playerBets[_gameId] = new uint256[](players[_gameId].length);
        playerRolls[_gameId] = new uint256[](players[_gameId].length);

        if (round.id == game.maxRounds) {
            _endGame(_gameId);
            return;
        } else {
            round.id += 1;
            if (!bankrupt[round.bank]) {
                round.bank = _getNextIndex(round.bank, playersLength);
            }
            emit NewRound(_gameId, round.id, 0);
        }
    }

    function _endGame(uint256 _gameId) internal {
        games[_gameId].isRunning = false;
        address winner = _getWinner(_gameId);
        _safeTransfer(address(this), winner, _gameId, 'A WINNER IS YOU');
        delete currentRound[_gameId];
        delete playerBets[_gameId];
        delete playerRolls[_gameId];
    }

    function _getWinner(uint256 _gameId) internal view returns (address winner) {
        uint256[] memory _playerBalances = playerBalances[_gameId];
        uint256 topBalance;
        uint256 balancesLength = _playerBalances.length;
        for (uint256 i; i < balancesLength; ++i) {
            if (_playerBalances[i] > topBalance) {
                topBalance = _playerBalances[i];
                winner = players[_gameId][i];
            }
        }
        return winner;
    }

    function _getPlayerIndex(uint256 _gameId, address _player) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_gameId, _player));
    }

    function joinGame(uint256 _gameId) external {
        // add entry fee stuff
        _addPlayer(_gameId, msg.sender);
    }

    function _setMinimumBets(uint256 _gameId) internal {
        uint256[] storage bets = playerBets[_gameId];
        uint256 minBet = games[_gameId].minBet;
        uint256 playersLength = players[_gameId].length;
        for (uint256 i; i < playersLength; ++i) {
            bets[i] = 0 != bets[i] ? bets[i] : minBet;
        }
    }

    function _addPlayer(uint256 _gameId, address _player) internal isNotPlayer(_gameId, _player) {
        Game memory game = games[_gameId];
        require(game.isRunning, '!ended');
        require(players[_gameId].length < game.maxPlayers, '!maxPlayers');
        players[_gameId].push(_player);
        playerBalances[_gameId].push(10000 * 10 ** 18);
        indexOf[_getPlayerIndex(_gameId, _player)] = players[_gameId].length - 1;
    }

    function _removePlayer(uint256 _gameId, address _player) internal {
        address[] memory oldPlayers = players[_gameId];
        uint256[] memory oldBalances = playerBalances[_gameId];

        delete players[_gameId];
        delete playerBalances[_gameId];

        address[] storage newPlayers = players[_gameId];
        uint256[] storage newBalances = playerBalances[_gameId];

        delete indexOf[_getPlayerIndex(_gameId, _player)];
        uint256 newPlayersLength = oldPlayers.length - 1;
        for (uint256 i; i < newPlayersLength; ++i) {
            if (oldPlayers[i] == _player) continue;
            newPlayers.push(oldPlayers[i]);
            newBalances.push(oldBalances[i]);
            indexOf[_getPlayerIndex(_gameId, oldPlayers[i])] = i;
        }
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(_exists(tokenId), 'ERC721: approved query for nonexistent token');

        return games[tokenId].operator;
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    function _approve(address to, uint256 tokenId) internal override(ERC721) {
        games[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return uint256(games[tokenId].nonce++);
    }

    function getPlayers(uint256 _gameId) external view returns (address[] memory) {
        return players[_gameId];
    }

    function getIndex(uint256 _gameId, address _address) internal view returns (uint256) {
        return indexOf[_getPlayerIndex(_gameId, _address)];
    }

    modifier isPlayer(uint256 _gameId, address _address) {
        require(players[_gameId][getIndex(_gameId, _address)] == _address, '!player');
        _;
    }

    modifier isNotPlayer(uint256 _gameId, address _address) {
        require(players[_gameId].length == 0 || players[_gameId][getIndex(_gameId, _address)] != _address, '!player');
        _;
    }

    modifier onlyDiceRoller(uint256 _gameId) {
        require(msg.sender == _diceRoller, '!diceRoller');
        _;
    }

    modifier isBank(uint256 _gameId, address _address) {
        uint256 index = getIndex(_gameId, _address);
        require(players[_gameId][index] == _address, '!player');
        require(currentRound[_gameId].bank == index, '!isBank');
        _;
    }

    modifier isNotBank(uint256 _gameId, address _address) {
        uint256 index = getIndex(_gameId, _address);
        require(players[_gameId][index] == _address, '!player');
        require(currentRound[_gameId].bank != index, '!bank');
        _;
    }

    modifier isRunning(uint256 _gameId) {
        require(games[_gameId].isRunning, '!ended');
        _;
    }

    function getPlayerRolls(uint256 _gameId) external view returns (uint256[] memory) {
        return playerRolls[_gameId];
    }

    function getPlayerBets(uint256 _gameId) external view returns (uint256[] memory) {
        return playerBets[_gameId];
    }

    function getPlayerBalances(uint256 _gameId) external view returns (uint256[] memory) {
        return playerBalances[_gameId];
    }

    function _getNextIndex(uint256 currentIndex, uint256 length) internal pure returns (uint256) {
        return currentIndex == length - 1 ? 0 : currentIndex + 1;
    }

    function getNextIndex(uint256 _gameId, uint256 _currentIndex) external view returns (uint256) {
        uint256 length = players[_gameId].length;
        return _getNextIndex(_currentIndex, length);
    }

    function getGame(uint256 _gameId) external view returns (Game memory) {
        return games[_gameId];
    }

    function getRound(uint256 _gameId) external view returns (Round memory) {
        return currentRound[_gameId];
    }
}

// Concept: (potential) gas and time optimization by single announcement of the initial bets (inspired by ERC721Permit by Uniswap)
// what if we use a signed permit that is relayed to the bank by the other players via xmtp in order to set the initial bets at the start of the round?
//
// Problem: malicious player might not want to send signature to bank and slow down the game
// Solution: bank can send a partially empty signature array to the contract after a delay
//
// Problem: malicious bank might not want to send the full signature array to the contract
// Solution: empty signatures are evaluated as minimum bet
//
// Still might be an edge for the malicious bank to exploit if they are running low on money
// Solution(?): every player can post the bets by themselves (a further delay is introduced, not optimal)
// Solution 2:
// Assumption: the round players have in their best interest that all the bets are posted
// Hencefort: maybe we can chain (or merkletree'd? whatevs) user signatures one after the other and then send the last signature to the bank
// Result: the bank can now either send all signatures or no signatures at all
// Conclusion: if no signatures (or wrong signatures) are sent, a intermediary phase with cooldown is introduced where the players can post their bets by transaction, otherwise the game proceeds as normal
// uh, this might just have the equivalent effect of just going to the intermediary phase with cooldown if some signatures are missing in the first place, unnecessary
// If the user doesn't send a bet their turn will be automatically lost for the minimum bet value

// Re: result check
// sort array to standardize against the comparisons
// save all permutations of the array in order to check if the result matches one of them // 216 outcomes
// sum all the values in order to remove possible permutations and then check against saved permutations
