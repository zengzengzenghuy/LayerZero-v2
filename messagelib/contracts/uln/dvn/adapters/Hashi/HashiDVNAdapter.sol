// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import {DVNAdapterBase} from "../DVNAdapterBase.sol";
import {HashiRegistry, AdapterPair} from "./HashiRegistry.sol";
import "https://github.com/gnosis/hashi/blob/main/packages/evm/contracts/Yaho.sol";
import "https://github.com/gnosis/hashi/blob/main/packages/evm/contracts/Hashi.sol";
import {IOracleAdapter} from "https://github.com/gnosis/hashi/blob/main/packages/evm/contracts/interfaces/IOracleAdapter.sol";

abstract contract HashiDVNAdapter is DVNAdapterBase {
    Yaho yaho;
    Hashi hashi;
    HashiRegistry hashiRegistry;
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
        address _hashi,
        address _hashiRegistry
    ) DVNAdapterBase(_sendLib, _receiveLib, _admins) {
        yaho = Yaho(_yaho);
        hashi = Hashi(_hashi);
        hashiRegistry = HashiRegistry(_hashiRegistry);
    }

    // Called by SendLib from source chain
    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata _options
    ) external payable override onlySendLib returns (uint256 fee) {
        DstConfig memory config = dstConfig[_param.dstEid];

        // in packetHeader, there is no message field
        // Hashi's message = DVN's payload
        bytes memory message = _encodePayload(
            _param.packetHeader,
            _param.payloadHash
        );

        (uint32 _srcEid, uint32 _dstEid, bytes _receiver) = _decodePacketHeader(
            _param.packetHeader
        );

        // construct Hashi Message type
        Message memory HashiMessage = Message({
            to: address(receiver),
            toChainId: eidToChainId[_param.dstEid],
            data: message
        });

        Message[] memory messageArray = new Message[](1);
        messageArray[0] = HashiMessage;

        // Get an array of Hashi adapters
        AdapterPair[] memory sourceAdaptersPair = hashiRegistry
            .getSourceAdaptersPair(_srcEid, _param.dstEid);

        // pass the message to adapters
        yaho.dispatchMessagesToAdapters(
            messageArray,
            sourceAdaptersPair.sourceAdapter,
            sourceAdaptersPair.destAdapter
        );

        // TODO: get Fee from Hashi adapters
        fee = 10000;
        _assertBalanceAndWithdrawFee(fee);

        return fee;
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
        (bytes memory packetHeader, bytes32 payloadHash) = _decodePayload(
            _payload
        );

        (uint32 _srcEid, uint32 _dstEid, bytes _receiver) = _decodePacketHeader(
            _param.packetHeader
        );

        address[] memory destAdapters = hashiRegistry.getDestAdapters(
            _srcEid,
            _dstEid
        );
        bytes32 reportedHash = 0x0;
        IOracleAdapter[] memory oracleAdapters = new IOracleAdapter[](
            destAdapters.length
        );
        for (uint56 i = 0; i < destAdapters.length; i++) {
            oracleAdapters[i] = IOracleAdapter(destAdapters[i]);
        }

        uint256 sourceChainId = uint256(srcEid);
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

    function _decodePacket(
        bytes memory packetHeader
    ) internal returns (uint32 srcEid, uint32 dstEid, bytes32 receiver) {
        // bytes packetHeader = abi.encodePacked(
        //     PACKET_VERSION, //uint8
        //     _packet.nonce, //uint64
        //     _packet.srcEid, //uint32
        //     _packet.sender.toBytes32(),  //bytes32
        //     _packet.dstEid, //uint32
        //     _packet.receiver //bytes32
        // );
        assembly {
            srcEid := mload(add(packetHeader, 72)) // 8 + 64
            dstEid := mload(add(packetHeader, 360)) // 8 + 64 + 32 +256
            receiver := mload(add(packetHeader, 392)) // 8 + 64 + 32 +256 +
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
