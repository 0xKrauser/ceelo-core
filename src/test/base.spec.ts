import '@nomiclabs/hardhat-ethers'
import '@nomicfoundation/hardhat-chai-matchers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import chai from 'chai'
import { chaiEthers } from 'chai-ethers'
import crypto from 'crypto'
import { BaseContract, BigNumber, BigNumberish, ContractReceipt } from 'ethers'
import hre from 'hardhat'

import {
  Chinchiro,
  CoordinatorHelper,
  DiceRoll,
  DiceRollHelper,
  DragonRules,
  MockToken,
  VRFCoordinatorV2Mock,
} from '../../typechain-types'
import { MintParamsStruct } from '../../typechain-types/IChinchiroGame'
import permutationsJson from './permutations.json'
import combObject from './combObject.json'

import { equals, ether, Results, toEther, USDC, ZERO, ZERO_ADDRESS } from './utils'
import { parseUnits } from 'ethers/lib/utils'

chai.use(chaiEthers)
const { expect } = chai

const toBytes32 = function (string: string) {
  return hre.ethers.utils.formatBytes32String(string)
}

const getRandomWords = (numWords: number) => {
  let result: string[] = []
  for (let i = 0; i < numWords; i++) {
    const rand = crypto.randomBytes(32)
    result.push(BigNumber.from(rand).toString())
  }
  return result
}

const BASE_FEE = '100000000000000000'
const GAS_PRICE_LINK = '1000000000' // 0.000000001 LINK per gas

describe('test suite', () => {
  let owner: SignerWithAddress
  let tester1: SignerWithAddress
  let tester2: SignerWithAddress
  let tester3: SignerWithAddress
  let tester4: SignerWithAddress
  let tester5: SignerWithAddress

  let usdc: MockToken

  let mockCoordinator: VRFCoordinatorV2Mock
  let subId: number

  let coordinatorHelper: CoordinatorHelper
  let requestId: number

  let diceRoll: DiceRoll

  let diceRollHelper: DiceRollHelper

  const baseFunding = parseUnits('10', 18)

  const keyHash = '0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15'
  const defaultConfirmations = 3

  const numberOfRandomWords = 4 * 3 * 3

  const getArgumentFromEvent = (receipt: ContractReceipt, event: string, arg: string): any => {
    if (!receipt.events) {
      expect.fail('No events emitted')
      return
    }

    const requestEvent = receipt.events.filter((e) => e.event === event)[0]
    if (!requestEvent.args) {
      expect.fail('No args in event')
      return
    }

    return requestEvent.args[arg]
  }

  before(async () => {
    const signers = await hre.ethers.getSigners()
    owner = signers[0]
    tester1 = signers[1]
    tester2 = signers[2]
    tester3 = signers[3]
    tester4 = signers[4]
    tester5 = signers[5]

    // Mock USDC
    const MockUSDC = await hre.ethers.getContractFactory('MockToken')
    const mockUSDC = <MockToken>await MockUSDC.deploy('mUSDC', 'mUSDC', 6)
    await mockUSDC.deployed()
    console.log('MockUSDC deployed to:', mockUSDC.address)

    await mockUSDC.mint(hre.ethers.utils.parseEther('10000').toString(), owner.address)
    usdc = mockUSDC

    // Mock Coordinator
    const MockCoordinator = await hre.ethers.getContractFactory('VRFCoordinatorV2Mock')
    mockCoordinator = <VRFCoordinatorV2Mock>await MockCoordinator.deploy(BASE_FEE, GAS_PRICE_LINK)
    console.log('MockCoordinator deployed to:', mockCoordinator.address)

    // Create subscriber on mock coordinator
  })
  describe('Coordinator', () => {
    it('should create subscriber', async () => {
      const mockCoordinatorTx = await mockCoordinator.createSubscription()
      const receipt = await mockCoordinatorTx.wait()
      if (!receipt.events) {
        expect.fail('No events emitted')
        return
      }

      const subCreatedEvent = receipt.events.filter((e) => e.event === 'SubscriptionCreated')[0]
      if (!subCreatedEvent.args) {
        expect.fail('No args in event')
        return
      }
      subId = subCreatedEvent.args.subId.toNumber()
      console.log('Created VRF subscription with Id:', subId)
    })

    it('should fund subscription', async () => {
      await mockCoordinator.fundSubscription(subId, baseFunding)
      const subscriptionCall = await mockCoordinator.getSubscription(subId)

      expect(subscriptionCall.balance).to.eq(baseFunding)
    })

    it('should instantiate CoordinatorHelper', async () => {
      const CoordinatorHelper = await hre.ethers.getContractFactory('CoordinatorHelper')
      coordinatorHelper = <CoordinatorHelper>await CoordinatorHelper.deploy(mockCoordinator.address, keyHash, subId)

      expect(coordinatorHelper.address).to.not.eq(ZERO_ADDRESS)
    })
    it('should add CoordinatorHelper as consumer', async () => {
      await mockCoordinator.addConsumer(subId, coordinatorHelper.address)

      const requestTx = await mockCoordinator.getSubscription(subId)
      expect(requestTx.consumers[0]).to.eq(coordinatorHelper.address)
    })

    const randomWordsLength = 9
    it('sends a request to the coordinator', async () => {
      const requestTx = await coordinatorHelper.requestRandomWords(randomWordsLength)
      const receipt = await requestTx.wait()
      if (!receipt.events) {
        expect.fail('No events emitted')
        return
      }

      const requestEvent = receipt.events.filter((e) => e.event === 'RequestSent')[0]
      if (!requestEvent.args) {
        expect.fail('No args in event')
        return
      }

      requestId = requestEvent.args.requestId.toNumber()
      console.log('Request Id:', requestId)
    })

    it('fulfills the request', async () => {
      // Real Chainlink node returns:
      // 84252055385675751429136304121489587551851953408630557332378808915120851229596
      // 39141357207579658880769923697995481976897126820363963653945252219999718371304
      // 15061586442750865406770198791015942488802698065163056671166585088540047206947
      const words = getRandomWords(randomWordsLength)
      const coordinatorTx = await mockCoordinator.fulfillRandomWordsWithOverride(
        requestId,
        coordinatorHelper.address,
        words
      )

      const requestTx = await coordinatorHelper.getValues()

      console.log('Values: ', requestTx)
      expect(requestTx).to.be.an('array').that.is.not.empty
      expect(requestTx[0]).to.be.equal(words[0])
    })
  })
  describe('DiceRoll', () => {
    before(async () => {
      // Dice Roll
      const DiceRoll = await hre.ethers.getContractFactory('DiceRoll')
      diceRoll = <DiceRoll>await DiceRoll.deploy(mockCoordinator.address, keyHash, subId)

      await diceRoll.setCallbackGasLimit('20000', '20000')
      await diceRoll.setConfirmations(defaultConfirmations)

      await mockCoordinator.addConsumer(subId, diceRoll.address)
      await diceRoll.addConsumer(owner.address)

      const DiceRollHelper = await hre.ethers.getContractFactory('DiceRollHelper')
      diceRollHelper = <DiceRollHelper>await DiceRollHelper.deploy(diceRoll.address)
      await diceRoll.addConsumer(diceRollHelper.address)
    })

    it('should request a single dice roll', async () => {
      const requestTx = await diceRoll.requestRandomWords(false, false, numberOfRandomWords)
      const receipt = await requestTx.wait()
      if (!receipt.events) {
        expect.fail('No events emitted')
        return
      }

      const requestEvent = receipt.events.filter((e) => e.event === 'RequestSent')[0]
      if (!requestEvent.args) {
        expect.fail('No args in event')
        return
      }

      requestId = requestEvent.args.requestId.toNumber()
      console.log('Request Id:', requestId)
    })

    it('should fulfill the request', async () => {
      const words = getRandomWords(numberOfRandomWords)
      const coordinatorTx = await mockCoordinator.fulfillRandomWordsWithOverride(requestId, diceRoll.address, words)
      const receipt = await coordinatorTx.wait()
      console.log('gas for fulfillment: ', receipt.gasUsed.toString())
      const requestTx = await diceRoll.getRollValues(requestId)

      console.log('Values: ', requestTx)
      expect(requestTx).to.be.an('array').that.is.not.empty
      expect(requestTx[0]).to.be.equal(BigNumber.from(words[0]).mod(6).add(1))
    })

    it('should request multiple dice rolls', async () => {
      const requestTx = await diceRoll.requestRandomWords(true, false, numberOfRandomWords)
      const receipt = await requestTx.wait()
      if (!receipt.events) {
        expect.fail('No events emitted')
        return
      }

      const requestEvent = receipt.events.filter((e) => e.event === 'RequestSent')[0]
      if (!requestEvent.args) {
        expect.fail('No args in event')
        return
      }

      requestId = requestEvent.args.requestId.toNumber()
      console.log('Request Id:', requestId)
    })

    it('should fulfill the request', async () => {
      const words = getRandomWords(1)
      const coordinatorTx = await mockCoordinator.fulfillRandomWordsWithOverride(requestId, diceRoll.address, words)
      const receipt = await coordinatorTx.wait()
      console.log('gas for fulfillment: ', receipt.gasUsed.toString())
      const requestTx = await diceRoll.getRollValues(requestId)

      console.log('Values: ', requestTx)
      expect(requestTx).to.be.an('array').that.is.not.empty
      expect(requestTx[0]).to.be.greaterThan(0)
    })

    it('requests a dice roll with a callback', async () => {
      const requestTx = await diceRollHelper.requestDiceRolls(9)
      const receipt = await requestTx.wait()
      const requestId = getArgumentFromEvent(receipt, 'Request', 'requestId').toNumber()

      const words = getRandomWords(1)
      await mockCoordinator.fulfillRandomWordsWithOverride(requestId, diceRoll.address, words)

      const tx = await diceRollHelper.fulfilled()

      expect(tx).to.be.equal(true)
    })
  })
  describe('Chinchiro', () => {
    let chinchiro: Chinchiro
    let dragonRules: DragonRules

    let roundOneRequestId: number
    const outcomes: Record<string, string[]> = {}

    before(async () => {
      const Chinchiro = await hre.ethers.getContractFactory('Chinchiro')
      chinchiro = <Chinchiro>await Chinchiro.deploy('Hibiki: Ceelo', 'CEELO', '1')

      await diceRoll.addConsumer(chinchiro.address)
      await chinchiro.setDiceRoller(diceRoll.address)

      const DragonRules = await hre.ethers.getContractFactory('DragonRules')
      dragonRules = <DragonRules>await DragonRules.deploy(diceRoll.address)

      permutationsJson.forEach((item) => {
        const object = combObject.find((comb) => equals(item, comb.roll))
        if (object?.outcome) {
          const packed = hre.ethers.utils.solidityKeccak256(
            ['bytes'],
            [hre.ethers.utils.solidityPack(['uint8', 'uint8', 'uint8'], item)]
          )
          if (object.outcome === 'point') {
            if (!outcomes[object.name]) outcomes[object.name] = []
            outcomes[object.name].push(packed)
          } else {
            if (!outcomes[object.outcome]) outcomes[object.outcome] = []
            outcomes[object.outcome].push(packed)
          }
        }
      })

      delete outcomes['matches_next']
      delete outcomes['matches_previous']
      Object.keys(outcomes).forEach(async (key) => {
        const tx = await dragonRules.setOutcome(Results[key as unknown as Results], outcomes[key])
      })
    })

    it('should add the dragon rules variant', async () => {
      await chinchiro.addVariant(1, dragonRules.address, 'Dragon')
      const settler = (await chinchiro.variants(1)).settler
      expect(settler).to.be.equal(dragonRules.address)
    })

    it('should create a new game', async () => {
      const params: MintParamsStruct = {
        variant: 1,
        minBet: parseUnits('100'),
        maxBet: parseUnits('1000'),
        maxPlayers: 4,
        minPlayers: 4,
        maxRounds: 12,
      }
      const tx = await chinchiro.mint(params)
      const receipt = await tx.wait()
      const gameId = getArgumentFromEvent(receipt, 'GameCreated', 'tokenId').toNumber()
      expect(gameId).to.be.equal(1)
    })

    it('should join the game', async () => {
      const tx = await chinchiro.connect(tester1).joinGame(1)
      await chinchiro.connect(tester2).joinGame(1)
      await chinchiro.connect(tester3).joinGame(1)
      await chinchiro.connect(tester4).joinGame(1)

      const players = await chinchiro.getPlayers(1)
      expect(players[0]).to.be.equal(tester1.address)
      expect(players[1]).to.be.equal(tester2.address)
      expect(players[2]).to.be.equal(tester3.address)
      expect(players[3]).to.be.equal(tester4.address)
    })
    it('should test that player is actually a player and index has been correctly set', async () => {
      const isPlayerTx = await chinchiro.getPlayers(1)
      const isPlayer = isPlayerTx.indexOf(tester1.address)
      expect(isPlayer).to.not.be.equal(-1)

      expect(await chinchiro.getPlayers(1)).to.not.include(tester5.address)
    })

    it('should test a player that joins after limit has been reached', async () => {
      await expect(chinchiro.connect(tester5).joinGame(1)).to.be.revertedWith('!maxPlayers')
    })

    it('should test that a player cannot join twice', async () => {
      await expect(chinchiro.connect(tester1).joinGame(1)).to.be.revertedWith('!player')
      await expect(chinchiro.connect(tester2).joinGame(1)).to.be.revertedWith('!player')
    })
    it('should start to play', async () => {
      await chinchiro.connect(tester1).play(1)
    })
    it('should bet for the round', async () => {
      const bet = parseUnits('100')
      const tx = await chinchiro.connect(tester2).bet(1, bet)
      await chinchiro.connect(tester3).bet(1, bet)
      await chinchiro.connect(tester4).bet(1, bet)
      const receipt = await tx.wait()
      const betAmount = getArgumentFromEvent(receipt, 'Bet', 'bet')
      expect(betAmount).to.be.eq(bet)
    })
    it('should not let banker bet', async () => {
      const bet = parseUnits('100')
      await expect(chinchiro.connect(tester1).bet(1, bet)).to.be.revertedWith('!bank')
    })
    it('should not let player bet twice', async () => {
      // Considerations: as long as the bank has not thrown the dice, the player can bet again, just don't let the counter go up
      /*
      const bet = parseUnits('100')
      await expect(chinchiro.connect(tester2).bet(1, bet)).to.be.revertedWith('!player')
      */
    })
    it('should not let player bet more than max', async () => {})
    it('should not let player bet less than min', async () => {})
    it('should not let player bet more than they have', async () => {})
    it('should not let bank start round if not all players have bet', async () => {})
    it('should let bank start if cooldown has passed', async () => {})

    it('should not let normal player start round', async () => {
      expect(chinchiro.connect(tester2).start(1)).to.be.revertedWith('!isBank')
    })

    it('should start the round', async () => {
      const tx = await chinchiro.connect(tester1).start(1)
      const receipt = await tx.wait()
      roundOneRequestId = getArgumentFromEvent(receipt, 'NewRound', 'requestId').toNumber()
      console.log('Round 1 Request Id:', roundOneRequestId)
      expect(roundOneRequestId).to.not.be.undefined
    })

    it('should fulfill the bank roll', async () => {
      // const words = getRandomWords(1)
      const words = ['25586001098121059547575749682307116970265149543399314594174863020603371254265'] // point three
      console.log('Words:', words)
      const coordinatorTx = mockCoordinator.fulfillRandomWordsWithOverride(roundOneRequestId, diceRoll.address, words)
      await expect(coordinatorTx).to.emit(chinchiro, 'BankFulfilled')

      /*       
      const result = getArgumentFromEvent(receipt, 'BankThrowFulfilled', 'result')
      console.log('Result:', result)
      const bankStatus = getArgumentFromEvent(receipt, 'BankThrowFulfilled', 'status')
      console.log('Bank Status:', bankStatus) 
      */
    })
    it('should throw for everyone else', async () => {
      await chinchiro.connect(tester3).roll(1) // 6
      await chinchiro.connect(tester2).roll(1) // 7
      await chinchiro.connect(tester4).roll(1) // 8

      const tx = await chinchiro.getPlayerRolls(1)
    })
    it('should fulfill the player rolls', async () => {
      const words = getRandomWords(3)
      await mockCoordinator.fulfillRandomWordsWithOverride(6, diceRoll.address, [
        '12242088809920869776962488266305177229268362237665704498327292033995507251112',
      ]) // musashi
      await mockCoordinator.fulfillRandomWordsWithOverride(7, diceRoll.address, [
        '66289837356293306327442447321290696770628497463588538488442553639712958567066',
      ]) // point two
      await mockCoordinator.fulfillRandomWordsWithOverride(8, diceRoll.address, [
        '14979798941803201285550177978088241648705772543328409111124076749423861322394',
      ]) // point five
    })
    it('should settle the round', async () => {
      await chinchiro.connect(tester1).settleRound(1)
      const balances = await chinchiro.getPlayerBalances(1)
      expect(balances[0]).to.be.eq(parseUnits((10000 - 100).toString()))
      expect(balances[1]).to.be.eq(parseUnits((10000 + 100).toString()))
      expect(balances[2]).to.be.eq(parseUnits((10000 - 100).toString()))
      expect(balances[3]).to.be.eq(parseUnits((10000 + 100).toString()))
    })
  })
})
