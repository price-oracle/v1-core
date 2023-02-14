# Why Price?

As we all know, oracles can make or break a DeFi protocol. They are a single point of failure for the biggest protocols out there. We think oracles are reliable until a black swan event happens. Unfortunately, crypto is a flock of black swans, so you've got to be prepared.

The main goal of an oracle is to deliver data that is as trustworthy as possible. To do this, it has to be:

- **Reliable**: it must be challenging to manipulate.
- **Decentralized**: it cannot depend on just a few participants.
- **Sustainable**: it must be cheap to maintain and scale.

But current solutions are not able to deliver the three of these simultaneously.

The most widely used solutions in DeFi rely on nodes updating the prices from off-chain liquid sources. But these nodes must be somehow incentivized to do the work. The more nodes and data feeds in the system, and the more incentives are needed. This creates a scaling tension that current solutions solve by centralizing rewards and whitelisting incentivized feeds.

Uniswap V3 introduced a novel way of querying price data. It is decentralized and sustainable (thanks to swappers and LP's subsidies), but it is complicated to rely on due to liquidity's unpredictability.

Uniswap has the most decentralized and sustainable solution for oracles, but it also has a long track of exploits and manipulations. This issue improved after v3, but it's [still happening](https://twitter.com/raricapital/status/1455569653820973057). Additionally, with the switch to PoS consensus in Ethereum, a new attack vector was unlocked: the multi-block attack.

- **Trust issues:** Oracle's quality depends on the pool's liquidity, but that depends on external providers. As a result, it is impossible to predict the future oracle's status.

  - Most [LPs stay as long as it's profitable](https://twitter.com/FloatProtocol/status/1482184042850263042)
  - Even protocols that provide liquidity for their token might decide to remove liquidity for whatever reason.

- **Complexity:** Concentrated liquidity is a double-edged sword. It enormously increases LPs' capital efficiency but also makes manipulation easier. Think of it as more capital being sold close to the current price.

  - Many protocols willing to have an oracle do not fully understand how Uniswap works. They either opt out or get rekt.

- **Multi-block attack:** With the recent move from PoW to PoS consensus on Ethereum, predictability on block proposers was also introduced. Chances are that some big players will propose multiple blocks in a row with [high frequency](https://alrevuelta.github.io/posts/ethereum-mev-multiblock). A potential attack on Uniswap TWAP could consist of price manipulation while leaving out of the blocks any external arbitrage, reducing enormously an attack's cost.

Medians were [suggested](https://github.com/euler-xyz/median-oracle) several times as an alternative to the standard TWAP to filter away multi-block attacks. But they are laggy, imprecise and would require a dedicated AMM.

## The solution

_**Price** is a permissionless and reliable oracle solution that leverages Uniswap V3 and automation to provide safe price quotes on any existing token._

Price is built on top of Uniswap V3, thus inheriting all its decentralization and sustainability but solving its main problems:

- **Trust issues**: We make liquidity a trustworthy and predictable asset for the oracle's users.

- **Complexity**: Neither the protocol nor the user need to handle anything. Contracts will manage positions, fees, pool parameters, and security.

- **Multi-block attack**: We use automation to detect and correct price manipulations, including multi-block attacks. This correction will unlock the use of safe and precise price data.