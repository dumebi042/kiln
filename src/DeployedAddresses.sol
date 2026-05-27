// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

/// @notice Registry of all Kiln On-Chain V1 deployed contract addresses
/// @dev Mainnet and Testnet (Holesky) addresses for the Kiln staking ecosystem
library DeployedAddresses {
    // ========== MAINNET ==========
    address public constant MAINNET_CONSENSUS_LAYER_FEE_DISPATCHER =
        0x462Dd07A79e5DDfBe0C171449C5c01788d5d03C3;
    address public constant MAINNET_CONSENSUS_LAYER_FEE_DISPATCHER_PROXY =
        0xE8EC6F702D68ded71112031D78bBFf959c7234C7;
    address public constant MAINNET_EXECUTION_LAYER_FEE_DISPATCHER =
        0xca4DD914fA713214844c84F153A5e1627536a7fC;
    address public constant MAINNET_EXECUTION_LAYER_FEE_DISPATCHER_PROXY =
        0x72b4C52f18f52EbA3E4290a002dF7c387427b058;
    address public constant MAINNET_FEE_RECIPIENT =
        0x933fBfeb4Ed1F111D12A39c2aB48657e6fc875C6;
    address public constant MAINNET_STAKING_CONTRACT =
        0x0A7272e8573aea8359FEC143ac02AED90F822bD0;
    address public constant MAINNET_STAKING_CONTRACT_PROXY =
        0x1e68238cE926DEC62b3FBC99AB06eB1D85CE0270;

    // ========== TESTNET (Holesky) ==========
    address public constant TESTNET_CONSENSUS_LAYER_FEE_DISPATCHER =
        0xD36B422a7EE65219732724d849B8b6BceD6155Fe;
    address public constant TESTNET_CONSENSUS_LAYER_FEE_DISPATCHER_PROXY =
        0x50Dba42662FD69f5Fd9236540aaD9f99f7F6b3b2;
    address public constant TESTNET_EXECUTION_LAYER_FEE_DISPATCHER =
        0xa69dDEBd0B6893A6F3d34A5df610d0E2ED433D18;
    address public constant TESTNET_EXECUTION_LAYER_FEE_DISPATCHER_PROXY =
        0x639d818639B85a1892Bfbb40Bd724b4Ddea43C0C;
    address public constant TESTNET_FEE_RECIPIENT =
        0x1AcD717aDF8A3A1e4c23C6510cfbE76834E3f1bf;
    address public constant TESTNET_STAKING_CONTRACT =
        0xcd01846F1b37aCE16916969989C136e3c52ef7d2;
    address public constant TESTNET_STAKING_CONTRACT_PROXY =
        0xe8Ff2a04837aac535199eEcB5ecE52b2735b3543;
}
