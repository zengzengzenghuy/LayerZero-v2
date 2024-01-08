// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

struct AdapterPair {
    address sourceAdapter;
    address destAdapter;
}

contract HashiRegistry is Ownable {
    event NewFeeSet(uint32 indexed destEid, uint256 indexed fee);
    event NewSourceAdaptersPairSet(
        uint32 indexed sourceEid,
        uint32 indexed destEid,
        address indexed sourceAdapters,
        address destAdapters
    );
    event NewDestAdaptersPairSet(
        uint32 indexed sourceEid,
        uint32 indexed destEid,
        address indexed destAdapters
    );
    mapping(uint32 sourceEid => mapping(uint32 destEid => AdapterPair[] adapters)) sourceAdaptersPair;
    mapping(uint32 destEid => mapping(uint32 sourceEid => address[] adapters)) destAdapters;
    mapping(uint32 destEid => uint256 fee) hashiFee;

    constructor() Ownable(msg.sender) {}

    function getSourceAdaptersPair(
        uint32 sourceEid,
        uint32 destEid
    ) external view returns (AdapterPair[] memory) {
        return sourceAdaptersPair[sourceEid][destEid];
    }

    /// @notice set source adapters pair, called by source Hashi DVN owner
    function setSourceAdaptersPair(
        uint32 sourceEid,
        uint32 destEid,
        address[] calldata _sourceAdapters,
        address[] calldata _destAdapters
    ) external onlyOwner {
        uint256 len = _sourceAdapters.length;
        for (uint256 i = 0; i < len; i++) {
            sourceAdaptersPair[sourceEid][destEid].push(
                AdapterPair(_sourceAdapters[i], _destAdapters[i])
            );
            emit NewSourceAdaptersPairSet(
                sourceEid,
                destEid,
                _sourceAdapters[i],
                _destAdapters[i]
            );
        }
    }

    function getDestAdapters(
        uint32 sourceEid,
        uint32 destEid
    ) external view returns (address[] memory) {
        return destAdapters[sourceEid][destEid];
    }

    /// @notice set dest adapters pair, called by destination Hashi DVN owner
    function setDestAdapters(
        uint32 sourceEid,
        uint32 destEid,
        address[] calldata _destAdapters
    ) external onlyOwner {
        uint256 len = _destAdapters.length;
        for (uint256 i = 0; i < len; i++) {
            destAdapters[sourceEid][destEid].push(_destAdapters[i]);
            emit NewDestAdaptersPairSet(sourceEid, destEid, _destAdapters[i]);
        }
    }

    function getDestFee(uint32 destEid) external view returns (uint256 fee) {
        return hashiFee[destEid];
    }

    /// @notice set fee for destination adapters, called by source Hashi DVN owner
    function setDestFee(uint32 destEid, uint256 _fee) external onlyOwner {
        hashiFee[destEid] = _fee;
    }
}
