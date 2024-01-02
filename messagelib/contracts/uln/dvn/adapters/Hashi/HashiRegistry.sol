// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

struct AdapterPair {
    address sourceAdapter;
    address destAdapter;
}

contract HashiRegistry is Ownable {
    mapping(uint32 sourceEid => mapping(uint32 destEid => AdapterPair[] adapters)) sourceAdaptersPair;
    mapping(uint32 destEid => mapping(uint32 sourceEid => address[] adapters)) destAdapters;

    constructor() Ownable(msg.sender) {}

    function getSourceAdaptersPair(
        uint32 sourceEid,
        uint32 destEid
    ) external view returns (AdapterPair[] memory) {
        return sourceAdaptersPair[sourceEid][destEid];
    }

    function setSourceAdaptersPair(
        uint32 sourceEid,
        uint32 destEid,
        address[] calldata _sourceAdapters,
        address[] calldata _destAdapters
    ) external onlyOwner {
        uint256 len = _sourceAdapters.length;
        for (uint256 i = 0; i < len; i++) {
            sourceAdapters[sourceEid][destEid].push(
                AdapterPair(_sourceAdapters[i], _destAdapters[i])
            );
        }
    }

    function getDestAdapters(
        uint32 sourceEid,
        uint32 destEid
    ) external view returns (address[] memory) {
        return destAdapters[sourceEid][destEid];
    }

    function setDestAdapters(
        uint32 sourceEid,
        uint32 destEid,
        address[] calldata _destAdapters
    ) external onlyOwner {
        uint256 len = _destAdapters.length;
        for (uint256 i = 0; i < len; i++) {
            destAdapters[sourceEid][destEid].push(_destAdapters[i]);
        }
    }
}
