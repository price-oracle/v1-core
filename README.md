# Price Oracle v1 Core

![Tests](https://github.com/price-oracle/v1-core/actions/workflows/ci.yml/badge.svg)
[![License: BUSL 1.1](https://img.shields.io/badge/License-BUSL%201.1-blue.svg)](https://github.com/price-oracle/v1-core/blob/main/LICENSE.BSL-1.1)

⚠️ The code has not been audited yet, tread with caution.

## Overview

Core v1 repository contains the smart contracts in charge of powering Price Oracle — a permissionless and reliable oracle solution that leverages Uniswap V3 and automation to provide safe price quotes on any existing token.

- App: [oracles.rip](https://oracles.rip/)
- Documentation: [docs.oracles.rip](https://docs.oracles.rip/)
- Discord: [Price Oracle](https://discord.gg/c9KSUgu3vt)

## Setup

This project uses [Foundry](https://book.getfoundry.sh/). To build it locally, run:

```sh
git clone git@github.com:price-oracle/v1-core.git
cd v1-core
yarn install
yarn build
```

### Available Commands

Make sure to set `MAINNET_RPC` environment variable before running end-to-end tests.

| Yarn Command      | Description                                                                                                                |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `yarn build`      | Compile all contracts and export them as [a node package](https://www.npmjs.com/package/@price-oracle/v1-core-interfaces). |
| `yarn docs:build` | Generate documentation with [`forge doc`](https://book.getfoundry.sh/reference/forge/forge-doc).                           |
| `yarn docs:run`   | Start the documentation server.                                                                                            |
| `yarn test`       | Run all unit and e2e tests.                                                                                                |
| `yarn test:unit`  | Run unit tests.                                                                                                            |
| `yarn test:e2e`   | Run end-to-end tests.                                                                                                      |
| `yarn test:gas`   | Run all unit and e2e tests, and make a gas report.                                                                         |

## Licensing

The primary license for Price Oracle v1 Core is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE.BSL-1.1`](./LICENSE.BSL-1.1). However, some files are dual licensed under `AGPL-3.0-only` or `MIT`:

- All files in `contracts/interfaces/` may also be licensed under `AGPL-3.0-only` (as indicated in their SPDX headers), see [`LICENSE.AGPL-3.0`](./LICENSE.AGPL-3.0)

- All files in `contracts/test/` may also be licensed under `MIT` (as indicated in their SPDX headers), see [`LICENSE.MIT`](./LICENSE.MIT)

## Contributors

Price Oracle was built with ❤️ by [DeFi Wonderland](https://defi.sucks).

DeFi Wonderland is a team of top Web3 researchers, developers, and operators who believe that the future needs to be open-source, permissionless, and decentralized.

[DeFi sucks](https://defi.sucks), but DeFi Wonderland is here to make it better.
