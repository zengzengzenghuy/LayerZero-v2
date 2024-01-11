// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {DVNAdapterBase} from "../contracts/uln/dvn/adapters/DVNAdapterBase.sol";
import {DVNAdapterFeeLibBase} from "../contracts/uln/dvn/adapters/DVNAdapterFeeLibBase.sol";
import {SendLibMock} from "./mocks/SendLibMock.sol";
import {ReceiveLibMock} from "./mocks/ReceiveLibMock.sol";
import {HashiRegistry} from "../contracts/uln/dvn/adapters/Hashi/HashiRegistry.sol";
import {HashiDVNAdapter} from "../contracts/uln/dvn/adapters/Hashi/HashiDVNAdapter.sol";
import {Constant} from "./util/Constant.sol";
import {ILayerZeroDVN} from "../contracts/uln/interfaces/ILayerZeroDVN.sol";
import {Packet} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import {MessageRelayMock} from "./mocks/MessageRelayMock.sol";
import {MessageRelayAdapterMock} from "./mocks/MessageRelayAdapterMock.sol";
import {Yaho} from "@hashi/packages/evm/contracts/Yaho.sol";
import {Hashi} from "@hashi/packages/evm/contracts/Hashi.sol";
import {Message} from "@hashi/packages/evm/contracts/interfaces/IMessageDispatcher.sol";
import {IOracleAdapter} from "@hashi/packages/evm/contracts/interfaces/IOracleAdapter.sol";
import {IMessageRelay} from "@hashi/packages/evm/contracts/interfaces/IMessageRelay.sol";

contract HashiDVNAdapterTest is Test {
    // export decode packetheader

    Yaho yaho;
    Hashi hashi;
    HashiRegistry hashiRegistry;
    SendLibMock sendLibMock;
    ReceiveLibMock receiveLibMock;
    HashiDVNAdapter hashiDVNAdapter;
    MessageRelayMock messageRelayA;
    MessageRelayMock messageRelayB;
    MessageRelayAdapterMock messageRelayAdapterA;
    MessageRelayAdapterMock messageRelayAdapterB;
    address[] admin = new address[](1);

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address[] sourceAdapters_ = new address[](2);
    address[] destAdapters_ = new address[](2);
    uint32 srcEid = 40161; // Sepolia
    uint256 srcChainId = 11155111;
    uint32 dstEid = 40109; // Mumbai
    uint256 dstChainId = 80001;

    function setUp() public {
        yaho = new Yaho();
        hashi = new Hashi();
        hashiRegistry = new HashiRegistry();
        messageRelayA = new MessageRelayMock();
        messageRelayB = new MessageRelayMock();
        messageRelayAdapterA = new MessageRelayAdapterMock();
        messageRelayAdapterB = new MessageRelayAdapterMock();

        sourceAdapters_[0] = address(messageRelayA);
        sourceAdapters_[1] = address(messageRelayB);

        destAdapters_[0] = address(messageRelayAdapterA);
        destAdapters_[1] = address(messageRelayAdapterB);

        sendLibMock = new SendLibMock();
        receiveLibMock = new ReceiveLibMock();

        admin[0] = address(0x1);
        hashiDVNAdapter = new HashiDVNAdapter(
            address(sendLibMock),
            address(receiveLibMock),
            admin,
            address(yaho),
            address(hashi),
            address(hashiRegistry)
        );

        hashiRegistry.setSourceAdaptersPair(
            srcEid,
            dstEid,
            sourceAdapters_,
            destAdapters_
        );
        hashiRegistry.setDestAdapters(srcEid, dstEid, destAdapters_);
        hashiRegistry.setDestFee(dstEid, 1_000);

        hashiDVNAdapter.setEidToChainID(srcEid, srcChainId);
        hashiDVNAdapter.setEidToChainID(dstEid, dstChainId);

        console.log("Alice", address(alice));
        console.log("BOB", address(bob));
        // deploy sendlib, receivelib, hashi registry, yaho, hashi
    }

    function test_Revert_assignJob_NotMessageLib() public {
        ILayerZeroDVN.AssignJobParam memory param = ILayerZeroDVN
            .AssignJobParam(dstEid, "", "", 0, address(0));
        bytes memory options = "";

        vm.expectRevert(DVNAdapterBase.OnlySendLib.selector);
        vm.prank(alice);
        hashiDVNAdapter.assignJob(param, options);
    }

    function test_assignJob() public {
        bytes memory message = "";
        bytes32 guid = bytes32("0x100");
        Packet memory packet = Packet(
            0,
            srcEid,
            alice,
            dstEid,
            bytes32(uint256(uint160(bob))),
            guid,
            message
        );
        bytes memory packetHeader = PacketV1Codec.encodePacketHeader(packet);
        //bytes memory payload = PacketV1Codec.encodePayload(packet);

        ILayerZeroDVN.AssignJobParam memory param = ILayerZeroDVN
            .AssignJobParam(dstEid, packetHeader, "", 0, alice);
        bytes memory options = "";

        vm.startPrank(address(sendLibMock));
        for (uint256 i = 0; i < sourceAdapters_.length; i++) {
            vm.expectEmit(
                true,
                true,
                false,
                false,
                address(sourceAdapters_[i])
            );
            emit MessageRelayMock.MessageRelayed(
                address(sourceAdapters_[i]),
                0 // messageId
            );
        }

        hashiDVNAdapter.assignJob(param, options);
        vm.stopPrank();
    }

    function test_verifyMessageHash() public {
        bytes memory message = "";
        bytes32 guid = bytes32("0x100");
        Packet memory packet = Packet(
            0,
            srcEid,
            alice,
            dstEid,
            bytes32(uint256(uint160(bob))),
            guid,
            message
        );
        bytes memory packetHeader = PacketV1Codec.encodePacketHeader(packet);
        bytes32 payloadHash = keccak256(PacketV1Codec.encodePayload(packet));
        bytes memory payload = hashiDVNAdapter.encodePayload(
            packetHeader,
            payloadHash
        );
        bytes32 messageId = 0;
        messageRelayAdapterA.storeHash(
            srcChainId,
            uint256(messageId),
            keccak256(payload)
        );
        messageRelayAdapterB.storeHash(
            srcChainId,
            uint256(messageId),
            keccak256(payload)
        );

        hashiDVNAdapter.verifyMessageHash(messageId, payload);

        // storeHash(uint256 domain, uint256 id, bytes32 hash)
    }
    // set dst config test
    // test assignjob return real value from hashi registry
    // test verifymessageHash
}
