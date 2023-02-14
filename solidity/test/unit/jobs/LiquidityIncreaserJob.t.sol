// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-periphery/libraries/OracleLibrary.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/IPoolManager.sol';
import '@interfaces/IFeeManager.sol';
import '@contracts/jobs/LiquidityIncreaserJob.sol';
import '@test/utils/TestConstants.sol';

contract LiquidityIncreaserJobForTest is LiquidityIncreaserJob {
  address public upkeepKeeperForTest;

  constructor(
    IPoolManagerFactory _poolManagerFactory,
    address _governor,
    IERC20 _weth
  ) LiquidityIncreaserJob(_poolManagerFactory, _governor, _weth) {}

  function pauseForTest() external {
    paused = true;
  }

  function setMinIncreaseWethForTest(uint256 _minIncreaseWeth) external {
    minIncreaseWeth = _minIncreaseWeth;
  }

  modifier upkeep(address _keeper) override {
    upkeepKeeperForTest = _keeper;
    _;
  }
}

contract Base is DSTestPlus, TestConstants {
  address keeper = label(address(100), 'keeper');
  address governor = label(address(101), 'governor');

  IKeep3r keep3r;
  LiquidityIncreaserJobForTest job;

  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  IPoolManager mockPoolManager = IPoolManager(mockContract('poolManager'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));
  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));

  function setUp() public virtual {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(true)
    );

    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManagerGovernor.priceOracle.selector), abi.encode(mockPriceOracle));

    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.POOL.selector), abi.encode(mockPool));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.TOKEN.selector), abi.encode(mockToken));

    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(false));
    vm.mockCall(address(mockPriceOracle), abi.encodeWithSelector(IPriceOracle.quoteCache.selector), abi.encode(1));
    vm.mockCall(address(mockPriceOracle), abi.encodeWithSelector(IPriceOracle.MIN_CORRECTION_PERIOD.selector), abi.encode(10 minutes));

    job = new LiquidityIncreaserJobForTest(mockPoolManagerFactory, governor, mockWeth);
    keep3r = job.keep3r();
  }
}

contract UnitLiquidityIncreaserJobWork is Base {
  event Worked(IPoolManager _poolManager, uint256 amountWeth, uint256 amountToken);

  function setUp() public override {
    super.setUp();
    job.setMinIncreaseWethForTest(0);
  }

  function testUpkeep(uint128 amountWeth, uint128 amountToken) external {
    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSignature('increaseFullRangePosition(uint256,uint256)', amountWeth, amountToken),
      abi.encode(amountWeth, amountToken)
    );
    vm.prank(keeper);
    job.work(mockPoolManager, amountWeth, amountToken);

    assertEq(job.upkeepKeeperForTest(), keeper);
  }

  function testRevertIfPaused(
    IPoolManager poolManager,
    uint256 amountWeth,
    uint256 amountToken
  ) external {
    job.pauseForTest();

    vm.expectRevert(IPausable.Paused.selector);

    job.work(poolManager, amountWeth, amountToken);
  }

  function testRevertIfNotValidPoolManager(
    IPoolManager poolManager,
    uint256 amountWeth,
    uint256 amountToken
  ) external {
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, poolManager), abi.encode(false));
    vm.expectRevert(ILiquidityIncreaserJob.LiquidityIncreaserJob_InvalidPoolManager.selector);
    job.work(poolManager, amountWeth, amountToken);
  }

  function testRevertIfInsufficientIncrease(
    uint256 minIncreaseWeth,
    uint128 amountWeth,
    uint128 amountToken
  ) external {
    vm.assume(amountWeth > 0 && amountToken > 0);
    vm.assume(amountWeth < type(uint128).max && amountToken < type(uint128).max);
    vm.assume(minIncreaseWeth > uint256(amountWeth) + uint256(amountToken));

    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSignature('increaseFullRangePosition(uint256,uint256)', amountWeth, amountToken),
      abi.encode(amountWeth, amountToken)
    );

    job.setMinIncreaseWethForTest(minIncreaseWeth);

    vm.expectRevert(ILiquidityIncreaserJob.LiquidityIncreaserJob_InsufficientIncrease.selector);
    job.work(mockPoolManager, amountWeth, amountToken);
  }

  function testRevertIfPoolManipulated(uint256 amountWeth, uint256 amountToken) external {
    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSignature('increaseFullRangePosition(uint256,uint256)', amountWeth, amountToken),
      abi.encode(amountWeth, amountToken)
    );

    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(true));

    vm.expectRevert(ILiquidityIncreaserJob.LiquidityIncreaserJob_PoolManipulated.selector);
    job.work(mockPoolManager, amountWeth, amountToken);
  }

  function testIncreaseFullRangePosition(uint128 amountWeth, uint128 amountToken) external {
    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSignature('increaseFullRangePosition(uint256,uint256)', amountWeth, amountToken),
      abi.encode(amountWeth, amountToken)
    );

    vm.expectCall(address(mockPoolManager), abi.encodeWithSignature('increaseFullRangePosition(uint256,uint256)', amountWeth, amountToken));

    job.work(mockPoolManager, amountWeth, amountToken);
  }

  function testEmitEvent(uint128 amountWeth, uint128 amountToken) external {
    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSignature('increaseFullRangePosition(uint256,uint256)', amountWeth, amountToken),
      abi.encode(amountWeth, amountToken)
    );

    vm.expectEmit(false, false, false, true);
    emit Worked(mockPoolManager, amountWeth, amountToken);

    job.work(mockPoolManager, amountWeth, amountToken);
  }
}

contract UnitLiquidityIncreaserJobSetMinIncreaseWeth is Base {
  event MinIncreaseWethSet(uint256 minIncreaseWeth);

  function testRevertIfNotGovernor(uint256 minIncreaseWeth) public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));
    job.setMinIncreaseWeth(minIncreaseWeth);
  }

  function testSetMinIncreaseWeth(uint256 minIncreaseWeth) external {
    vm.assume(minIncreaseWeth != job.minIncreaseWeth());

    vm.prank(governor);
    job.setMinIncreaseWeth(minIncreaseWeth);

    assertEq(minIncreaseWeth, job.minIncreaseWeth());
  }

  function testEmitEvent(uint256 minIncreaseWeth) external {
    expectEmitNoIndex();
    emit MinIncreaseWethSet(minIncreaseWeth);

    vm.prank(governor);
    job.setMinIncreaseWeth(minIncreaseWeth);
  }
}

contract UnitLiquidityIncreaserJobIsWorkable is Base {
  function setUp() public override {
    super.setUp();
    uint256 _amountWeth = type(uint128).max;
    uint256 _amountToken = type(uint128).max;

    vm.mockCall(
      address(mockFeeManager),
      abi.encodeWithSelector(IFeeManager.poolManagerDeposits.selector, mockPoolManager),
      abi.encode(_amountWeth, _amountToken)
    );

    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManagerGovernor.feeManager.selector), abi.encode(mockFeeManager));
  }

  function testLiquidityIncreaserIsWorkable() public {
    assertEq(job.isWorkable(mockPoolManager), true);
  }

  function testLiquidityIncreaserIsNotWorkable() public {
    uint256 _amountWeth = 100;
    uint256 _amountToken = 100;

    vm.mockCall(
      address(mockFeeManager),
      abi.encodeWithSelector(IFeeManager.poolManagerDeposits.selector, mockPoolManager),
      abi.encode(_amountWeth, _amountToken)
    );

    assertEq(job.isWorkable(mockPoolManager), false);
  }

  function testLiquidityIncreaserIsNotWorkablePaused() public {
    vm.prank(governor);
    job.setPaused(true);
    assertEq(job.isWorkable(mockPoolManager), false);
  }
}
