import '@nomiclabs/hardhat-ethers'
import { parseUnits } from 'ethers/lib/utils'
import { network, ethers } from 'hardhat'
import {
  VRFCoordinatorV2Mock,
  CoordinatorHelper,
  DiceRoll,
  MockToken,
  Chinchiro,
  DragonRules,
  Multicall,
} from '../../typechain-types'
import permutationsJson from '../test/permutations.json'
import combObject from '../test/combObject.json'

import { equals, Results } from '../test/utils'
import { ContractFactory } from 'ethers'

const BASE_FEE = '100000000000000000'
const GAS_PRICE_LINK = '1000000000' // 0.000000001 LINK per gas

async function deploy(factory: ContractFactory, contractName: string, args: any[]) {
  const contract = await factory.deploy(...args)
  await contract.deployed()
  return { contractName: contractName, address: contract.address }
}

async function main() {
  const contractOwner = await ethers.getSigner(network.config.from!)
  let mockCoordinator: VRFCoordinatorV2Mock
  let subId: number
  let diceRoll: DiceRoll
  let mockUSDC: MockToken
  let chinchiro: Chinchiro
  let dragonRules: DragonRules
  let multicall: Multicall

  const baseFunding = parseUnits('10', 18)
  const keyHash = '0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15'
  const defaultConfirmations = 3

  network.provider.send('hardhat_reset')
  // Deploy mockUSDC
  const MockUSDC = await ethers.getContractFactory('MockToken')
  mockUSDC = <MockToken>await MockUSDC.deploy('mUSDC', 'mUSDC', 6)
  await mockUSDC.deployed()

  console.log('MockUSDC deployed to:', mockUSDC.address)

  // Mint 10000 mUSDC to contract owner
  await mockUSDC.mint(ethers.utils.parseEther('10000').toString(), contractOwner.address)
  console.log('Minted 10000 mUSDC to:', contractOwner.address)

  // Deploy mockCoordinator
  const MockCoordinator = await ethers.getContractFactory('VRFCoordinatorV2Mock')
  mockCoordinator = <VRFCoordinatorV2Mock>await MockCoordinator.deploy(BASE_FEE, GAS_PRICE_LINK)

  console.log('MockCoordinator deployed to:', mockCoordinator.address)

  // Create subscription
  const mockCoordinatorTx = await mockCoordinator.createSubscription()
  const receipt = await mockCoordinatorTx.wait()
  if (!receipt.events) {
    return
  }

  const subCreatedEvent = receipt.events.filter((e) => e.event === 'SubscriptionCreated')[0]
  if (!subCreatedEvent.args) {
    return
  }
  subId = subCreatedEvent.args.subId.toNumber()
  console.log('Created VRF subscription with Id:', subId)

  // Fund subscription
  await mockCoordinator.fundSubscription(subId, baseFunding)
  console.log('Funded subscription with:', baseFunding.toString())

  // Deploy DiceRoll
  const DiceRoll = await ethers.getContractFactory('DiceRoll')
  diceRoll = <DiceRoll>await DiceRoll.deploy(mockCoordinator.address, keyHash, subId)

  console.log('DiceRoll deployed to:', diceRoll.address)

  // Set the callback gas limit
  await diceRoll.setCallbackGasLimit('20000', '20000')

  // Set the confirmations
  await diceRoll.setConfirmations(defaultConfirmations)

  // Add the diceRoll contract as consumer to the mockCoordinator
  await mockCoordinator.addConsumer(subId, diceRoll.address)

  // Add the contract owner as consumer to the diceRoll contract
  await diceRoll.addConsumer(contractOwner.address)

  // Deploy Chinchiro
  const Chinchiro = await ethers.getContractFactory('Chinchiro')
  chinchiro = <Chinchiro>await Chinchiro.deploy('Hibiki: Ceelo', 'CEELO', '1')

  console.log('Chinchiro deployed to:', chinchiro.address)

  // Add the chinchiro contract as consumer to the diceRoll contract
  await diceRoll.addConsumer(chinchiro.address)
  console.log('Added Chinchiro as consumer to DiceRoll')

  // Set the diceRoll contract as diceRoller on the chinchiro contract
  await chinchiro.setDiceRoller(diceRoll.address)
  console.log('Set diceRoller on Chinchiro')

  // Deploy the rules contract
  const DragonRules = await ethers.getContractFactory('DragonRules')
  dragonRules = <DragonRules>await DragonRules.deploy(diceRoll.address)

  console.log('DragonRules deployed to:', dragonRules.address)

  // Set the rules contract as variant
  await chinchiro.addVariant(1, dragonRules.address, 'Dragon')
  console.log('DragonRules set as variant')
  // Calculate the outcomes
  const outcomes = {}
  permutationsJson.forEach((item) => {
    const object = combObject.find((comb) => equals(item, comb.roll))
    if (object?.outcome) {
      const packed = ethers.utils.solidityKeccak256(
        ['bytes'],
        [ethers.utils.solidityPack(['uint8', 'uint8', 'uint8'], item)]
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
    // Set the outcomes on the rules contract
    const tx = await dragonRules.setOutcome(Results[key], outcomes[key])
  })
  console.log('Outcomes set on the rules contract')

  // Deploys multicall contract
  const Multicall = await ethers.getContractFactory('Multicall')
  multicall = <Multicall>await Multicall.deploy()
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
