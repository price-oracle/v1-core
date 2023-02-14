// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'forge-std/Script.sol';

import '@contracts/LockManagerFactory.sol';
import '@contracts/PoolManagerFactory.sol';
import '@contracts/PoolManagerDeployer.sol';
import '@contracts/FeeManager.sol';
import '@contracts/strategies/Strategy.sol';
import '@contracts/periphery/PriceOracle.sol';

import '@contracts/jobs/CardinalityJob.sol';
import '@contracts/jobs/FeeCollectorJob.sol';
import '@contracts/jobs/LiquidityIncreaserJob.sol';
import '@contracts/jobs/PositionMinterJob.sol';
import '@contracts/jobs/PositionBurnerJob.sol';
import '@contracts/jobs/CorrectionsApplierJob.sol';
import '@contracts/jobs/CorrectionsRemoverJob.sol';

contract Deploy is Script {
  // IERC20 constant WETH = IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6); // Goerli
  IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Mainnet
  IUniswapV3Factory constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984); // Goerli/Mainnet
  bytes32 constant POOL_BYTECODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54; // Goerli/Mainnet
  uint16 minCardinalityIncrease = 10; // TODO: Define this number

  LockManagerFactory lockManagerFactory;
  PoolManagerFactory poolManagerFactory;
  PoolManagerDeployer poolManagerDeployer;
  Strategy strategy;
  FeeManager feeManager;
  PriceOracle priceOracle;

  CardinalityJob cardinalityJob;
  FeeCollectorJob feeCollectorJob;
  LiquidityIncreaserJob liquidityIncreaserJob;
  PositionMinterJob positionMinterJob;
  PositionBurnerJob positionBurnerJob;
  CorrectionsApplierJob correctionsApplierJob;
  CorrectionsRemoverJob correctionsRemoverJob;

  function run() public {
    address deployer = vm.rememberKey(vm.envUint('DEPLOYER_PRIVATE_KEY'));
    address governance = deployer; // TODO: Change to actual governance
    uint256 currentNonce = vm.getNonce(deployer);

    vm.startBroadcast(deployer);

    // Deploy lock manager factory
    lockManagerFactory = new LockManagerFactory();
    console.log('LOCK_MANAGER_FACTORY:', address(lockManagerFactory));

    // Deploy strategy
    strategy = new Strategy();
    console.log('STRATEGY:', address(strategy));

    // Pre-calculate fee manager factory address
    address feeManagerAddress = computeCreateAddress(deployer, currentNonce + 3);
    address priceOracleAddress = computeCreateAddress(deployer, currentNonce + 4);
    address poolManagerDeployerAddress = computeCreateAddress(deployer, currentNonce + 5);

    // Deploy pool manager factory
    poolManagerFactory = new PoolManagerFactory(
      strategy,
      IFeeManager(feeManagerAddress),
      lockManagerFactory,
      IPriceOracle(priceOracleAddress),
      IPoolManagerDeployer(poolManagerDeployerAddress),
      UNISWAP_V3_FACTORY,
      POOL_BYTECODE_HASH,
      WETH,
      governance
    );
    console.log('POOL_MANAGER_FACTORY:', address(poolManagerFactory));

    // Deploy fee manager
    feeManager = new FeeManager(poolManagerFactory, governance, WETH);
    console.log('FEE_MANAGER:', address(feeManager));

    // Deploy price oracle
    priceOracle = new PriceOracle(poolManagerFactory, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, WETH);
    console.log('PRICE_ORACLE:', address(priceOracle));

    // Deploy the pool manager deployer
    poolManagerDeployer = new PoolManagerDeployer(poolManagerFactory);
    console.log('POOL_MANAGER_DEPLOYER:', address(poolManagerDeployer));

    // Deploy cardinality job
    cardinalityJob = new CardinalityJob(poolManagerFactory, minCardinalityIncrease, governance);
    console.log('CARDINALITY_JOB:', address(cardinalityJob));

    // Deploy fee collector job
    feeCollectorJob = new FeeCollectorJob(poolManagerFactory, governance);
    console.log('FEE_COLLECTOR_JOB:', address(feeCollectorJob));

    // Deploy liquidity increaser job
    liquidityIncreaserJob = new LiquidityIncreaserJob(poolManagerFactory, governance, WETH);
    console.log('LIQUIDITY_INCREASER_JOB:', address(liquidityIncreaserJob));

    // Deploy position minter job
    positionMinterJob = new PositionMinterJob(poolManagerFactory, governance);
    console.log('POSITION_MINTER_JOB:', address(positionMinterJob));

    // Deploy position burner job
    positionBurnerJob = new PositionBurnerJob(poolManagerFactory, governance);
    console.log('POSITION_BURNER_JOB:', address(positionBurnerJob));

    // Deploy corrections applier job
    correctionsApplierJob = new CorrectionsApplierJob(poolManagerFactory, governance);
    console.log('CORRECTIONS_APPLIER_JOB:', address(correctionsApplierJob));

    // Deploy corrections remover job
    correctionsRemoverJob = new CorrectionsRemoverJob(poolManagerFactory, governance);
    console.log('CORRECTIONS_REMOVER_JOB:', address(correctionsRemoverJob));

    vm.stopBroadcast();
  }
}
