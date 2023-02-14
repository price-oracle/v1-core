# Fee Management

[Seeders](seeders.md) and [lockers](lockers.md) are eligible for the trading fees generated in the pool. Seeders will pay 50% of their fees as "taxes" and the lockers pay 20%. The rest of the fees will be claimable as rewards.

Price will use the taxes to improve the oracle quality and maintain the strategies. The taxes will be 100% reinvested in the system, and this reinvestment should come back to the users in the long term while improving the oracle quality in the short term. In no way the Price protocol will profit from the whole process.

Note that the tax percentage will probably get tuned in future versions.

## How is Price using these fees?

![fee-management.png](/images/fee-management.png)

Taxes will go to a FeeManager, a hub for tax distribution, that will

- Increase the full-range position
- Pay keepers for automatic fee collection, position management, liquidity increases and manipulation detection, increasing the pool's cardinality

New pools will have their manipulation detection covered by other pools until they reach enough funds. Eventually, they will also help new pools to be safe after having enough.

Cardinality will not be increased forever, but only up to a point. After reaching this value, maintenance will use 100% of its capital for automation.

Fee collection will occur periodically upon job execution, and users can claim afterwards. As a result, users who lock between jobs will not see any difference at the time of deposit. Users could wait to see how many fees are due for the following collection before depositing, but they would risk being front-ran by the job.

As a pool generates more fees, these jobs will start paying for themselves. Fees will cover the IL of the credits and subsidize the jobs from other pools.
