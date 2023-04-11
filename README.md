# EXIT10

EXIT10 is a protocol inspired by Chicken Bonds built on top of Uniswap V3. It amplifies fees for liquidity providers while enabling Open Bakery, the team behind the protocol, to raise funds and pursue future endeavors in Web3.

Visit [exit10.fi](https://exit10.fi/) to learn more about the protocol or check out our [documentation](https://open-bakery.gitbook.io/exit10).

# Local deployment

Make sure to [download the latest version of Foundry](https://github.com/foundry-rs) before you continue.

Clone the repo and install node dependencies.

    git clone git@github.com:open-bakery/exit10-protocol.git
    cd exit10-protocol
    yarn

Create a `.env.template` file with the initial deployment parameters.

    cp .env.example .env.template

Deploy locally.

    make dev

This will deploy a local instance of Uniswap v3 and any dependent contracts on a local Anvil testnet.

# Running Tests

After successfully deploying the dependencies locally you can run the following to run all tests.

    make testAll

The tests will run right after any remaining dependencies are finished downloading.
