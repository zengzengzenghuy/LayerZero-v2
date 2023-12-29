// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import {DVNAdapterBase} from "../DVNAdapterBase.sol";
import "https://github.com/gnosis/hashi/blob/main/packages/evm/contracts/Yaho.sol";
import "https://github.com/gnosis/hashi/blob/main/packages/evm/contracts/Hashi.sol";
import {IOracleAdapter} from "https://github.com/gnosis/hashi/blob/main/packages/evm/contracts/interfaces/IOracleAdapter.sol";

abstract contract HashiDVNAdapter is DVNAdapterBase {
    Yaho yaho;
    Hashi hashi;
    struct DstConfigParam {
        uint32 dstEid;
        uint16 multiplierBps;
        uint256 gasLimit;
        bytes peer;
    }

    struct DstConfig {
        uint16 multiplierBps;
        uint256 gasLimit;
        bytes peer;
    }

    address private constant NATIVE_GAS_TOKEN_ADDRESS = address(0);

    event DstConfigSet(DstConfigParam[] params);
    event LogError(string error);

    mapping(uint32 dstEid => DstConfig config) public dstConfig;

    mapping(uint32 dstEid => uint256 chainId) public eidToChainId;
    mapping(uint256 chainId => uint32 eid) public chainIdToEid;

    mapping(uint256 chainId => address[] destAdapter)
        public chainIdToDestAdapters;
    address[] sourceAdapters;

    constructor(
        address _sendLib,
        address _receiveLib,
        address[] memory _admins,
        address _yaho,
        address _hashi
    ) DVNAdapterBase(_sendLib, _receiveLib, _admins) {
        yaho = Yaho(_yaho);
        hashi = Hashi(_hashi);
    }

    // Called by SendLib from source chain
    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata _options
    ) external payable override onlySendLib returns (uint256 fee) {
        DstConfig memory config = dstConfig[_param.dstEid];

        // in packetHeader, there is no message field
        // pHashi's message = DVN's payload
        bytes memory message = _encodePayload(
            _param.packetHeader,
            _param.payloadHash
        );

        // decode receiver field from AssignJobParam _param
        address receiver;
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 36, 81)
            receiver := mload(add(ptr, 49))
        }

        // construct Hashi Message type
        Message memory HashiMessage = Message({
            to: address(receiver),
            toChainId: eidToChainId[_param.dstEid],
            data: message
        });

        Message[] memory messageArray = new Message[](1);
        messageArray[0] = HashiMessage;

        // Get an array of Hashi adapters
        address[] memory destAdapters = chainIdToDestAdapters[
            eidToChainId[_param.dstEid]
        ];

        // pass the message to adapters
        yaho.dispatchMessagesToAdapters(
            messageArray,
            sourceAdapters,
            destAdapters
        );

        // TODO: get Fee from Hashi adapters
        fee = 10000;
        _assertBalanceAndWithdrawFee(fee);

        return fee;
    }

    function setSourceAdapters(address[] memory _adapters) external onlyAdmin {
        sourceAdapters = _adapters;
    }

    function setDestAdapters(
        uint256 chainId,
        address[] memory _adapters
    ) external onlyAdmin {
        chainIdToDestAdapters[chainId] = _adapters;
    }

    // TODO: define Fee lib logic
    // combining fee request from different adapters?
    function getFee(
        uint32 _dstEid,
        uint64 _confirmations,
        address _sender,
        bytes calldata _options
    ) external view override returns (uint256 fee) {
        DstConfig storage config = dstConfig[_dstEid];

        if (address(feeLib) != address(0)) {
            fee = feeLib.getFee(
                _dstEid,
                _sender,
                defaultMultiplierBps,
                config.multiplierBps,
                fee
            );
        }
    }

    // called by Hashi DVN on destination chain
    // 1. Check if message hash from Hashi adapters are the same
    // 2. If same, call receiveLib to verify the payload
    function verifyMessageHash(
        bytes32 messageId,
        bytes memory _payload
    ) external {
        // check hash from different adapters
        // It's not possible to know the source chain based on messageId and messageHash from adapters
        // Here we assume source chain is Ethereum
        uint256 sourceChainId = 1;
        address[] memory destAdapters = chainIdToDestAdapters[block.chainid];
        bytes32 reportedHash = 0x0;
        IOracleAdapter[] memory oracleAdapters = new IOracleAdapter[](
            destAdapters.length
        );
        for (uint56 i = 0; i < destAdapters.length; i++) {
            oracleAdapters[i] = IOracleAdapter(destAdapters[i]);
        }
        try
            hashi.getHash(sourceChainId, uint256(messageId), oracleAdapters)
        returns (bytes32 hash) {
            reportedHash = hash;
        } catch Error(string memory error) {
            emit LogError(error);
        }

        if (reportedHash != 0x0) {
            _verify(_payload);
        }
    }

    // TODO: since there is no way to get sourceChainID from messageId, we need to make sure this function is called by DVN peer from source chain
    function _assertPeer(
        uint256 _sourceChainId,
        bytes memory _sourceDVNAddress
    ) private view {
        uint32 sourceEid = chainIdToEid[_sourceChainId];
        bytes memory sourcePeer = dstConfig[sourceEid].peer;

        if (keccak256(_sourceDVNAddress) != keccak256(sourcePeer))
            revert Unauthorized();
    }
}
