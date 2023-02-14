// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/interfaces/IGovernable.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/IFeeManager.sol';
import '@interfaces/IPoolManagerGovernor.sol';

import '@contracts/jobs/CardinalityJob.sol';

import '@test/utils/TestConstants.sol';

contract CardinalityJobForTest is CardinalityJob {
  address public upkeepKeeperForTest;

  constructor(
    IPoolManagerFactory _poolManagerFactory,
    address _governor,
    uint16 _minCardinalityIncrease
  ) CardinalityJob(_poolManagerFactory, _minCardinalityIncrease, _governor) {}

  function pauseForTest() external {
    paused = true;
  }

  modifier upkeep(address _keeper) override {
    upkeepKeeperForTest = _keeper;
    _;
  }
}

contract Base is DSTestPlus, TestConstants {
  address caller = label(address(100), 'caller');
  address governor = label(address(101), 'governor');
  address keeper = label(address(102), 'keeper');

  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));
  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  IPoolManager mockPoolManager = IPoolManager(mockContract('mockPoolManager'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));

  uint16 minCardinalityIncrease = 10;
  CardinalityJobForTest job;
  IKeep3r keep3r;

  function setUp() public virtual {
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.POOL.selector), abi.encode(address(mockPool)));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManagerGovernor.feeManager.selector), abi.encode(address(mockFeeManager)));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(true)
    );

    vm.mockCall(address(mockFeeManager), abi.encodeWithSelector(IFeeManager.getMaxCardinalityForPool.selector), abi.encode(20));

    job = new CardinalityJobForTest(mockPoolManagerFactory, governor, minCardinalityIncrease);
    keep3r = job.keep3r();
  }
}

contract UnitCardinalityJobWork is Base {
  event Worked(IPoolManager _poolManager, uint16 _increaseAmount);

  uint256 priceDeposited = 10 ether;
  uint16 currentCardinality = 10;

  function setUp() public override {
    super.setUp();

    // for WETH transfer always to work
    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    // mock the current cardinality from the slot0 method
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(
        uint160(0), // sqrtPriceX96,
        int24(0), // tick,
        uint16(0), // observationIndex,
        uint16(0), // observationCardinality,
        currentCardinality, // observationCardinalityNext,
        uint8(0), // feeProtocol,
        true // unlocked
      )
    );

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector), abi.encode(true));

    vm.mockCall(address(mockFeeManager), abi.encodeWithSelector(IFeeManager.increaseCardinality.selector), abi.encode(true));
  }

  function testRevertIfPaused(uint16 increaseAmount) external {
    job.pauseForTest();

    vm.expectRevert(IPausable.Paused.selector);
    job.work(mockPoolManager, increaseAmount);
  }

  function testRevertIfLessThatMinCardinalityIncrease(uint16 increaseAmount) external {
    vm.assume(increaseAmount < minCardinalityIncrease);

    vm.expectRevert(ICardinalityJob.CardinalityJob_MinCardinality.selector);
    job.work(mockPoolManager, increaseAmount);
  }

  function testRevertIfInvalidPoolManager(uint16 increaseAmount) external {
    assumeIncreaseAmount(increaseAmount);
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, address(mockPoolManager)),
      abi.encode(false)
    );
    vm.expectRevert(ICardinalityJob.CardinalityJob_InvalidPoolManager.selector);
    job.work(mockPoolManager, increaseAmount);
  }

  function testIncreaseCardinality(uint16 increaseAmount) external {
    assumeIncreaseAmount(increaseAmount);

    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector, currentCardinality + increaseAmount)
    );

    job.work(mockPoolManager, increaseAmount);
  }

  function testReduceFeeManagerWethBalance(uint16 increaseAmount) external {
    assumeIncreaseAmount(increaseAmount);

    vm.expectCall(address(mockFeeManager), abi.encodeWithSelector(IFeeManager.increaseCardinality.selector));

    job.work(mockPoolManager, increaseAmount);
  }

  function testEmitEvent(uint16 increaseAmount) external {
    assumeIncreaseAmount(increaseAmount);

    expectEmitNoIndex();
    emit Worked(mockPoolManager, increaseAmount);

    job.work(mockPoolManager, increaseAmount);
  }

  function assumeIncreaseAmount(uint16 increaseAmount) private {
    vm.assume(increaseAmount >= minCardinalityIncrease && (uint256(increaseAmount) + uint256(currentCardinality)) < type(uint16).max);
  }
}

contract UnitCardinalityJobSetMinCardinalityIncrease is Base {
  event MinCardinalityIncreaseChanged(uint16 minCardinalityIncrease);

  function testRevertIfNotGovernor(uint16 minCardinalityIncrease) public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));
    job.setMinCardinalityIncrease(minCardinalityIncrease);
  }

  function testSetMinCardinalityIncrease(uint16 minCardinalityIncrease) public {
    vm.prank(governor);
    job.setMinCardinalityIncrease(minCardinalityIncrease);

    assertEq(job.minCardinalityIncrease(), minCardinalityIncrease);
  }

  function testEmitEvent(uint16 minCardinalityIncrease) public {
    expectEmitNoIndex();
    emit MinCardinalityIncreaseChanged(minCardinalityIncrease);

    vm.prank(governor);
    job.setMinCardinalityIncrease(minCardinalityIncrease);
  }
}

contract UnitCardinalityJobSetPoolManagerFactory is Base {
  event PoolManagerFactoryChanged(IPoolManagerFactory poolManagerFactory);

  IPoolManagerFactory newPoolManagerFactory = IPoolManagerFactory(mockContract('newPoolManagerFactory'));

  function testRevertIfNotGovernor() public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));
    job.setPoolManagerFactory(newPoolManagerFactory);
  }

  function testSetPoolManagerFactory() public {
    vm.prank(governor);
    job.setPoolManagerFactory(newPoolManagerFactory);

    assertEq(address(job.poolManagerFactory()), address(newPoolManagerFactory));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();
    emit PoolManagerFactoryChanged(newPoolManagerFactory);

    vm.prank(governor);
    job.setPoolManagerFactory(newPoolManagerFactory);
  }
}

contract UnitCardinalityJobIsWorkable is Base {
  function setUp() public override {
    super.setUp();

    uint16 currentCardinality = 10;
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(
        uint160(0), // sqrtPriceX96,
        int24(0), // tick,
        uint16(0), // observationIndex,
        uint16(0), // observationCardinality,
        currentCardinality, // observationCardinalityNext,
        uint8(0), // feeProtocol,
        true // unlocked
      )
    );
  }

  function testCardinalityJobIsWorkable(uint16 increaseAmount) public {
    vm.assume(
      increaseAmount >= job.getMinCardinalityIncreaseForPool(mockPoolManager) &&
        increaseAmount <= job.getMinCardinalityIncreaseForPool(mockPoolManager) * 2
    );

    assertEq(job.isWorkable(mockPoolManager, increaseAmount), true);
  }

  function testCardinalityJobIsNotWorkableMinCardinality(uint16 increaseAmount) public {
    vm.assume(increaseAmount < job.getMinCardinalityIncreaseForPool(mockPoolManager));

    assertEq(job.isWorkable(mockPoolManager, increaseAmount), false);
  }

  function testCardinalityJobIsNotWorkableInvalidChild(uint16 increaseAmount) public {
    vm.assume(increaseAmount >= job.getMinCardinalityIncreaseForPool(mockPoolManager));
    IPoolManager mockPoolManager2 = IPoolManager(mockContract('mockPoolManager2'));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager2),
      abi.encode(false)
    );

    assertEq(job.isWorkable(mockPoolManager2, increaseAmount), false);
  }

  function testCardinalityJobIsNotWorkableInvalidKeeper(uint16 increaseAmount) public {
    vm.assume(increaseAmount >= job.getMinCardinalityIncreaseForPool(mockPoolManager));
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector, keeper), abi.encode(false));

    assertEq(job.isWorkable(mockPoolManager, increaseAmount, keeper), false);
  }

  function testCardinalityJobWorkableWithKeeper(uint16 increaseAmount) public {
    vm.assume(
      increaseAmount >= job.getMinCardinalityIncreaseForPool(mockPoolManager) &&
        increaseAmount <= job.getMinCardinalityIncreaseForPool(mockPoolManager) * 2
    );
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector, keeper), abi.encode(true));

    vm.prank(keeper);
    assertEq(job.isWorkable(mockPoolManager, increaseAmount, keeper), true);
  }
}

contract UnitCardinalityJobGetMinCardinalityIncreaseForPool is Base {
  uint16 currentCardinality = 10;

  function setUp() public override {
    super.setUp();

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(
        uint160(0), // sqrtPriceX96,
        int24(0), // tick,
        uint16(0), // observationIndex,
        uint16(0), // observationCardinality,
        currentCardinality, // observationCardinalityNext,
        uint8(0), // feeProtocol,
        true // unlocked
      )
    );
  }

  function testCardinalityJobMinCardinalityIncreaseForPool() public {
    uint256 _minCardinalityIncrease = job.getMinCardinalityIncreaseForPool(mockPoolManager);
    assertEq(_minCardinalityIncrease, job.minCardinalityIncrease());
  }

  function testCardinalityJobMinCardinalityIncreaseForPoolWhenCardinalityIsClose(uint16 _maxCardinalityForPool) public {
    vm.assume(_maxCardinalityForPool > currentCardinality);
    vm.assume(_maxCardinalityForPool - currentCardinality < job.minCardinalityIncrease());
    vm.mockCall(
      address(mockFeeManager),
      abi.encodeWithSelector(IFeeManager.getMaxCardinalityForPool.selector),
      abi.encode(_maxCardinalityForPool)
    );
    uint256 _minCardinalityIncrease = job.getMinCardinalityIncreaseForPool(mockPoolManager);

    assertEq(_minCardinalityIncrease, _maxCardinalityForPool - currentCardinality);
  }
}
