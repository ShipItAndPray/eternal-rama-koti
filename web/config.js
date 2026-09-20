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
  blockscout: "https://eth-sepolia.blockscout.com",   // renders on-chain NFT images
  koti: "0x32e2b577f4ab66b3ecc35bfc214e5cdaf800356e",
  deployBlock: 11746488,
};
