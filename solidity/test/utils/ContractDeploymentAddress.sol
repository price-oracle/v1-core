// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Factory.sol';
import '@contracts/PoolManager.sol';

library ContractDeploymentAddress {
  /// @notice          compute the future address where a contract will be deployed, based on the deployer nonce and address
  ///                  see https://ethereum.stackexchange.com/questions/24248/how-to-calculate-an-ethereum-contracts-address-during-its-creation-using-the-so
  /// @dev             this works for standard CREATE deployment
  /// @param  _origin  the deployer address
  /// @param  _nonce   the deployer nonce for which the corresponding address is computed
  /// @return _address the deployment address
  function addressFrom(address _origin, uint256 _nonce) internal pure returns (address _address) {
    bytes memory _data;
    if (_nonce == 0x00) _data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
    else if (_nonce <= 0x7f) _data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
    else if (_nonce <= 0xff) _data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
    else if (_nonce <= 0xffff) _data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
    else if (_nonce <= 0xffffff) _data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
    else _data = abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));

    bytes32 _hash = keccak256(_data);
    assembly {
      mstore(0, _hash)
      _address := mload(0)
    }
  }

  /// @notice                   calculate the theoretical address of a UniswapV3 pool, taking into account the given parameters
  /// @dev                      the bytecode hash of the UniswapV3 factory is hardcoded into the function
  /// @param  _token0           one of the two tokens of the pool pair
  /// @param  _token1           the other token of the pair
  /// @param  _fee              pool fee
  /// @param  _uniswapV3Factory address of the UniswapV3 factory
  /// @return _pool             theoretical address of the UniswapV3 pool
  function getTheoreticalUniPool(
    IERC20 _token0,
    IERC20 _token1,
    uint24 _fee,
    IUniswapV3Factory _uniswapV3Factory
  ) internal pure returns (IUniswapV3Pool _pool) {
    if (_token0 > _token1) (_token0, _token1) = (_token1, _token0);

    _pool = IUniswapV3Pool(
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xff),
                address(_uniswapV3Factory), // UniswapV3 factory
                keccak256(abi.encode(_token0, _token1, _fee)), // salt
                bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // BYTECODE HASH
              )
            )
          )
        )
      )
    );
  }

  /// @notice              calculate the theoretical address of a pool manager, taking into account the given parameters
  /// @param  _deployer     address of the pool manager deployer
  /// @param  _pool        address of the underlying UniswapV3 pool
  /// @return _poolManager theoretical address of the pool manager
  function getTheoreticalPoolManager(IPoolManagerDeployer _deployer, IUniswapV3Pool _pool) internal pure returns (IPoolManager _poolManager) {
    _poolManager = IPoolManager(
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xff),
                address(_deployer), // deployer
                keccak256(abi.encode(_pool)), // salt
                keccak256(abi.encodePacked(type(PoolManager).creationCode))
              )
            )
          )
        )
      )
    );
  }
}
