## How will Price work?

Price is built on top of Uniswap V3, thus inheriting all its decentralization and sustainability but solving its main problems:

- **Trust issues**: We make liquidity a trustworthy and predictable asset for the oracle's users.
- **Complexity**: Neither the protocol nor the user need to handle anything. Contracts will manage positions, fees, pool parameters, and security.
- **Multi-block attack**: We use automation to detect and correct price manipulations, including multi-block attacks. This correction will unlock the use of safe and precise price data.

We plan on deploying all contracts on every Uniswap V3-supported network.

Any party that wishes to use Price for a specific TOKEN will have to seed WETH and TOKEN into a contract. This contract will initialize the WETH-TOKEN pool if it does not exist and then add liquidity as a full-range position. This liquidity will work as a security deposit for oracle's users and cannot be withdrawn by the depositing protocol, only migrated.

Part of the **fees** from this position will automatically improve the oracle's health by increasing cardinality, full-range liquidity, and paying for **automation** jobs that defend the oracle.

We will introduce an **oracle contract**, which lowers the cost of queries by performing shared and optimized computation. The oracle contract also introduces signal processing jobs that filter potential TWAP manipulations, including the notorious PoS multiblock attack.

This works by introducing a 2-minute delay that enables us to capture up to a 9-block manipulation. The automated job detects and corrects the observation array with the proper non-manipulated values in case of manipulation-like movements. The oracle contract is manipulation-cost agnostic. This change unlocks the safe use of higher precision queries (shorter TWAPs).

Protocols can further incentivize external lockers to concentrate liquidity on the pools, which Price will share and manage as a low-risk profile hedge fund. This liquidity will aim at increasing both the trading volume, which will increase the fees and the precision of the oracle.

Important disclaimers:

- Price will not charge any fees for the service.
- There will not be any Price ERC-20 at the moment. Any such listing is a scam.

> One can think of the full-range liquidity with the TWAP length as the safety net against price manipulation and the concentrated liquidity to ensure trading volume, providing fees and improving oracle precision. The fees will increase the security and reliability of the oracle.
