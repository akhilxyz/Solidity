>>> Important for deploying the dex contracts from shushiswap:

1. Change the ownership of Anchor Token to Masterchef for harvesting.
2. Change name of the lp token in the rabbit swap token contract file for signature verification UniswapV2ERC20.sol.
3. UniswapV2Library.sol file to change the hash before deploying router contract
