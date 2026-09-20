// Chain and contract configuration. Edit `koti` and `deployBlock` after each deployment.
export const CHAIN = {
  id: 11155111,
  name: "Sepolia",
  testnet: true,
  nativeCurrency: { name: "Sepolia Ether", symbol: "ETH", decimals: 18 },
  rpcs: [
    "https://ethereum-sepolia-rpc.publicnode.com",
    "https://sepolia.gateway.tenderly.co",
    "https://eth-sepolia.blockscout.com/api/eth-rpc",
  ],
  explorer: "https://sepolia.etherscan.io",
  koti: null,        // contract address, set after deploy
  deployBlock: 0,    // block the contract was deployed in
};
