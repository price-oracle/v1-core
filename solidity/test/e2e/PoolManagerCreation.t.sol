// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2EPoolManagerCreation is CommonE2EBase {
  function testE2ERevertExistingPoolManager() public {
    vm.startPrank(governance);
    // Pre-calculate the address of UniswapV3 Pool and the pool manager to approve the pool.
    IUniswapV3Pool wethDaiPool = ContractDeploymentAddress.getTheoreticalUniPool(weth, dai, poolFee, UNISWAP_V3_FACTORY);
    poolManagerDai = ContractDeploymentAddress.getTheoreticalPoolManager(poolManagerFactory.POOL_MANAGER_DEPLOYER(), wethDaiPool);

    // Increase allowance for the pool manager
    dai.approve(address(poolManagerDai), liquidity);
    weth.approve(address(poolManagerDai), liquidity);

    // Should revert because we are trying to create 2 pool managers with the same token
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_ExistingPoolManager.selector);

    // Creates the pool manager WETH/Token
    poolManagerDai = poolManagerFactory.createPoolManager(dai, poolFee, liquidity, sqrtPriceX96);
    vm.stopPrank();
  }

  function testE2ECreatesPoolManagerWithKP3R() public {
    vm.startPrank(governance);

    // Creates the pool manager WETH/KP3R
    IPoolManager poolManagerKp3r = _createPoolManager(kp3r);

    // Gets the lock manager that has been created
    ILockManager lockManagerKp3r = poolManagerKp3r.lockManager();

    // Gets initial cardinality
    (, , , , uint16 observationCardinalityNext, , ) = poolManagerKp3r.POOL().slot0();

    vm.stopPrank();

    // Obtains the key params of the lock manager to check that are corrects
    assertEq(address(lockManagerKp3r.POOL_MANAGER()), address(poolManagerKp3r));
    assertEq(lockManagerKp3r.FEE(), poolFee);
    assertEq(poolManagerKp3r.POOL().liquidity(), liquidity);
    assertEq(STARTING_CARDINALITY, observationCardinalityNext);
  }

  function testE2ECreatesPoolManagerForUninitializedPool() public {
    vm.startPrank(governance);
    uint24 fee = 100;
    uint160 sqrtPriceX96Yfi = 1 << 96;

    IUniswapV3Pool uniPoolYfi = ContractDeploymentAddress.getTheoreticalUniPool(weth, yfi, fee, UNISWAP_V3_FACTORY);
    IPoolManager poolManagerYfi = ContractDeploymentAddress.getTheoreticalPoolManager(poolManagerDeployer, uniPoolYfi);

    (address token0, address token1) = address(weth) < address(yfi) ? (address(yfi), address(weth)) : (address(weth), address(yfi));

    // Creates pool WETH/Yfi without initializing and increases the full-range position
    uniPoolYfi = IUniswapV3Pool(UNISWAP_V3_FACTORY.createPool(token0, token1, fee));

    // Gets initial cardinality
    (, , , , uint16 observationCardinalityNext, , ) = uniPoolYfi.slot0();

    // Cardinality should be 0 because we have not initialized the pool
    assertEq(0, observationCardinalityNext);

    // Should call initialize
    vm.expectCall(address(uniPoolYfi), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96Yfi));

    // Increases allowance for the pool manager
    yfi.approve(address(poolManagerYfi), type(uint256).max);
    weth.approve(address(poolManagerYfi), type(uint256).max);

    // Creates the pool manager WETH/YFI
    poolManagerYfi = poolManagerFactory.createPoolManager(yfi, fee, liquidity, sqrtPriceX96Yfi);

    // Gets initial cardinality
    (, , , , observationCardinalityNext, , ) = uniPoolYfi.slot0();

    // Cardinality should be 0 because we had not initialize the pool
    assertEq(STARTING_CARDINALITY, observationCardinalityNext);
    vm.stopPrank();
  }
}
