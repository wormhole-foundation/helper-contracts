// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct Jobv1 {
    SourceChainActions[] sourceChainActions;
    SendRequest[] sendRequests;
}

struct SourceChainActions {
    bytes4 selector;
    bytes data;
    bool shouldCaptureVaa;
}

struct SendRequest {
    bytes32 targetAddress;
    bytes4 selector;
    bytes data;
}

struct TargetChainActions {
    bytes4 selector;
    bytes data;
}

//TODO consider converting to pure library
contract Serde {



}