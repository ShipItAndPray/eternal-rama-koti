// Chain and contract configuration. Edit `koti` and `deployBlock` after each deployment.
export const CHAIN = {
  id: 1,
  name: "Ethereum",
  testnet: false,
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcs: [
    "https://ethereum-rpc.publicnode.com",
    "https://cloudflare-eth.com",
    "https://eth.blockscout.com/api/eth-rpc",
  ],
  explorer: "https://etherscan.io",
  blockscout: "https://eth.blockscout.com",   // renders on-chain NFT images
  koti: "0x664ddc51552c5ccb142443d0116bb7b24e9fda92",
  deployBlock: 26022509,
};

// Sepolia test deployment, kept for reference:
// id 11155111, rpcs ethereum-sepolia-rpc.publicnode.com / sepolia.gateway.tenderly.co / eth-sepolia.blockscout.com/api/eth-rpc,
// explorer sepolia.etherscan.io, blockscout eth-sepolia.blockscout.com, koti 0x1d47d28174a6c0d2876415894da9ddd6c4f7a952, block 11746594
