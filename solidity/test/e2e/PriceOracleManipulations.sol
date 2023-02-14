// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2EOracleManipulations is CommonE2EBase {
  uint256 public constant VUSD_ATTACK_BLOCK = 13537922;
  uint256 public constant FLOAT_ATTACK_BLOCK = 14006045;

  IUniswapV3Pool vusdUsdcPool = IUniswapV3Pool(label(0x8dDE0A1481b4A14bC1015A5a8b260ef059E9FD89, 'VUSD-USDC'));
  IUniswapV3Pool floatUsdcPool = IUniswapV3Pool(label(0x7EE092FD479185Dd741E3E6994F255bB3624f765, 'FLOAT-USDC'));

  function setUp() public override {
    super.setUp();

    // The deployed oracle will be accessible in all forks
    vm.makePersistent(address(priceOracle));
  }

  function testE2EDetectManipulation() public {
    // Make sure the pools are not manipulated in the current block
    assertFalse(priceOracle.isManipulated(daiEthPool));
    assertFalse(priceOracle.isManipulated(daiUsdtPool));
    assertFalse(priceOracle.isManipulated(vusdUsdcPool));
    assertFalse(priceOracle.isManipulated(floatUsdcPool));

    // Switch to the blocks where the attacks happened and test again
    _assertManipulated(VUSD_ATTACK_BLOCK, vusdUsdcPool);
    _assertManipulated(FLOAT_ATTACK_BLOCK, floatUsdcPool);
  }

  function _assertManipulated(uint256 _blockNumber, IUniswapV3Pool _pool) internal {
    vm.createSelectFork(vm.rpcUrl('mainnet'), _blockNumber);

    assertFalse(priceOracle.isManipulated(daiEthPool));
    assertFalse(priceOracle.isManipulated(daiUsdtPool));
    assertTrue(priceOracle.isManipulated(_pool));
  }
}
