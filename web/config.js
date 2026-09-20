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
  koti: "0x3d23391e3d44b74a26a7cf5f22d50f2af50202ef",
  deployBlock: 11746350,
};
