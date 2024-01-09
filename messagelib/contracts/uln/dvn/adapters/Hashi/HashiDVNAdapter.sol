// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import {DVNAdapterBase} from "../DVNAdapterBase.sol";
import {HashiRegistry, AdapterPair} from "./HashiRegistry.sol";
import {Yaho} from "@hashi/packages/evm/contracts/Yaho.sol";
import {Hashi} from "@hashi/packages/evm/contracts/Hashi.sol";
import {Message} from "@hashi/packages/evm/contracts/interfaces/IMessageDispatcher.sol";
import {IOracleAdapter} from "@hashi/packages/evm/contracts/interfaces/IOracleAdapter.sol";

contract HashiDVNAdapter is DVNAdapterBase {
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

    /// @notice sets configuration (`dstEid`, `multiplierBps`, `gasLimit` and `peer`) for destination chains
    /// @param _params array of chain configurations
    function setDstConfig(
        DstConfigParam[] calldata _params
    ) external onlyAdmin {
        for (uint256 i = 0; i < _params.length; i++) {
            DstConfigParam calldata param = _params[i];

            dstConfig[param.dstEid] = DstConfig({
                multiplierBps: param.multiplierBps,
                gasLimit: param.gasLimit,
                peer: param.peer
            });
        }

        emit DstConfigSet(_params);
    }

    /// @notice sets mapping for LayerZero's EID to ChainID
    /// @param eid eid of LayerZero
    /// @param chainID chainID of EIP155
    function setEidToChainID(uint32 eid, uint256 chainID) external onlyOwner {
        eidToChainId[eid] = chainID;
    }

    /// @notice function called by SendLib from source chain when a new job is assigned by user
    /// @param _param param for AssignJob
    /// @param _options options includes Security and Executor
    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata _options
    ) external payable override onlySendLib returns (uint256 fee) {
        DstConfig memory config = dstConfig[_param.dstEid];

        // In _param.packetHeader, there is no message field. In order to construct the message for Hashi, we need to encode payload with packet header
        // Hashi's message = DVN's payload
        bytes memory message = _encodePayload(
            _param.packetHeader,
            _param.payloadHash
        );

        (
            uint32 _srcEid,
            uint32 _dstEid,
            bytes32 _receiver
        ) = _decodePacketHeader(_param.packetHeader);

        // Construct Hashi Message type

        Message memory HashiMessage = Message({
            to: address(uint160(uint(_receiver))),
            toChainId: eidToChainId[_param.dstEid],
            data: message
        });

        Message[] memory messageArray = new Message[](1);
        messageArray[0] = HashiMessage;

        // Get an array of available Hashi adapters for source -> dest chain
        AdapterPair[] memory sourceAdaptersPair = hashiRegistry
            .getSourceAdaptersPair(_srcEid, _param.dstEid);

        // Pass the message to Hashi adapters by calling Yaho contract
        address[] memory sourceAdapters;
        address[] memory destAdapters;

        for (uint256 i = 0; i < sourceAdaptersPair.length; i++) {
            sourceAdapters[i] = (sourceAdaptersPair[i].sourceAdapter);
            destAdapters[i] = (sourceAdaptersPair[i].destAdapter);
        }

        yaho.dispatchMessagesToAdapters(
            messageArray,
            sourceAdapters,
            destAdapters
        );

        // TODO: get Fee from Hashi adapters
        // Currently it is hardcoded in HashiRegistry contract
        fee = hashiRegistry.getDestFee(_param.dstEid);

        return fee;
    }

    // TODO: define Fee lib logic
    // Currently it is hardcoded in HashiRegistry contract
    /// @notice Function called by LayerZero contract
    function getFee(
        uint32 _dstEid,
        uint64 _confirmations,
        address _sender,
        bytes calldata _options
    ) external view override returns (uint256 fee) {
        DstConfig storage config = dstConfig[_dstEid];
        fee = hashiRegistry.getDestFee(_dstEid);
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

    /// @notice Function called by Hashi DVN on destination chain
    ///         1. Check if message hash from Hashi adapters are the same
    ///         2. If same, call receiveLib to verify the payload
    /// @param messageId messageId from Hashi `MessageRelayed` event from source chain
    /// @param _payload payload from Endpoint
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

        (
            uint32 _srcEid,
            uint32 _dstEid,
            bytes32 _receiver
        ) = _decodePacketHeader(packetHeader);

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

        uint256 sourceChainId = uint256(_srcEid);
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

    /// @notice decode data from packetHeader
    // bytes packetHeader = abi.encodePacked(
    //     PACKET_VERSION, //uint8
    //     _packet.nonce, //uint64
    //     _packet.srcEid, //uint32
    //     _packet.sender.toBytes32(),  //bytes32
    //     _packet.dstEid, //uint32
    //     _packet.receiver //bytes32
    // );
    /// @param packetHeader packet header from endpoint
    function _decodePacketHeader(
        bytes memory packetHeader
    ) internal returns (uint32 srcEid, uint32 dstEid, bytes32 receiver) {
        assembly {
            srcEid := mload(add(packetHeader, 72)) // 8 + 64
            dstEid := mload(add(packetHeader, 360)) // 8 + 64 + 32 +256
            receiver := mload(add(packetHeader, 392)) // 8 + 64 + 32 +256 +
        }
    }
}
