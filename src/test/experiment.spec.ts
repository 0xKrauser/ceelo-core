import '@nomiclabs/hardhat-ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import chai from 'chai'
import crypto from 'crypto'
import { BigNumber, BigNumberish } from 'ethers'
import hre from 'hardhat'

import {
  CoordinatorHelper,
  DiceRoll,
  DragonRules,
  MockToken,
  PackUint8Array,
  VRFCoordinatorV2Mock,
} from '../../typechain-types'
import { equals, ether, Results, toEther, USDC, ZERO, ZERO_ADDRESS } from './utils'
import permutationsJson from './permutations.json'
import combObject from './combObject.json'

const { expect } = chai

// hibiki // echo // game name? // token name?
// sachiko/sachi/sacchan protagonist name

describe('test suite', () => {
  let owner: SignerWithAddress
  let tester1: SignerWithAddress
  let tester2: SignerWithAddress
  let tester3: SignerWithAddress
  let tester4: SignerWithAddress
  let tester5: SignerWithAddress

  let packUint8Array: PackUint8Array
  let dragonRules: DragonRules
  const outcomes = {}

  before(async () => {
    const signers = await hre.ethers.getSigners()
    owner = signers[0]
    tester1 = signers[1]
    tester2 = signers[2]
    tester3 = signers[3]
    tester4 = signers[4]
    tester5 = signers[5]
    const PackUint8Array = await hre.ethers.getContractFactory('PackUint8Array')
    packUint8Array = <PackUint8Array>await PackUint8Array.deploy()

    const DragonRules = await hre.ethers.getContractFactory('DragonRules')
    dragonRules = <DragonRules>await DragonRules.deploy(ZERO_ADDRESS)

    permutationsJson.forEach((item) => {
      const object = combObject.find((comb) => equals(item, comb.roll))
      if (object?.outcome) {
        console.log(item)
        console.log(object.outcome)
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

    console.log(Object.keys(outcomes))
  })
  describe('PackUint8Array', () => {
    it('pack', async () => {
      const tx = await packUint8Array.pack()
      console.log(tx)
      const packed = hre.ethers.utils.solidityKeccak256(
        ['bytes'],
        [hre.ethers.utils.solidityPack(['uint8', 'uint8', 'uint8'], [1, 2, 3])]
      )
      console.log('packed', packed)
    })
    it('tests array behavior', async () => {
      const tx = await packUint8Array.testArray(9)
      console.log(tx)
    })

    it('sets results for each roll', async () => {
      delete outcomes['matches_next']
      delete outcomes['matches_previous']
      Object.keys(outcomes).forEach(async (key) => {
        const tx = await dragonRules.setOutcome(Results[key], outcomes[key])
      })
      const tx = await dragonRules.getOutcomeFromArray(2, 4, 6)
      console.log(tx)
    })
  })
})
