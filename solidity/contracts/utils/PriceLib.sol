// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import 'uni-v3-core/interfaces/IUniswapV3Factory.sol';
import '@interfaces/IPoolManagerDeployer.sol';
import '@interfaces/IPoolManager.sol';

library PriceLib {
  /**
    @notice Computes the deterministic address of a UniswapV3 pool with WETH, given the token addresses and its fee tier
    @param  _weth Address of weth token
    @param  _tokenB Other token of the pool
    @param  _fee The UniswapV3 fee tier
    @param  _uniswapV3Factory Address of the UniswapV3 factory
    @param  _poolBytecodeHash Bytecode hash of the UniswapV3 pool
    @return _theoreticalAddress Address of the theoretical address of the UniswapV3 pool
    @return _isWethToken0 If WETH is token0
   */
  // solhint-disable private-vars-leading-underscore
  function _calculateTheoreticalAddress(
    IERC20 _weth,
    IERC20 _tokenB,
    uint24 _fee,
    IUniswapV3Factory _uniswapV3Factory,
    bytes32 _poolBytecodeHash
  ) internal pure returns (IUniswapV3Pool _theoreticalAddress, bool _isWethToken0) {
    IERC20 _tokenA = IERC20(_weth);

    if (_tokenA > _tokenB) {
      (_tokenA, _tokenB) = (_tokenB, _tokenA);
    } else {
      _isWethToken0 = true;
    }

    _theoreticalAddress = IUniswapV3Pool(
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xff),
                _uniswapV3Factory, // deployer
                keccak256(abi.encode(_tokenA, _tokenB, _fee)), // salt
                _poolBytecodeHash
              )
            )
          )
        )
      )
    );
  }

  /**
    @notice Computes the deterministic address of a pool manager for a UniswapV3 pool
    @param  _deployer The pool manager deployer address
    @param  _poolManagerBytecodeHash The pool manager bytecode hash
    @param  _pool The UniswapV3 pool
    @return _poolManager The theoretical address of the pool manager
   */
  // solhint-disable private-vars-leading-underscore
  function _getPoolManager(
    IPoolManagerDeployer _deployer,
    bytes32 _poolManagerBytecodeHash,
    IUniswapV3Pool _pool
  ) internal pure returns (IPoolManager _poolManager) {
    _poolManager = IPoolManager(
      address(
        uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(_deployer), keccak256(abi.encode(_pool)), _poolManagerBytecodeHash))))
      )
    );
  }
}
