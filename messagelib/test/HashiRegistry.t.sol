// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import "../contracts/uln/dvn/adapters/Hashi/HashiRegistry.sol";

contract HashiRegistryTest is Test {
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

    HashiRegistry hashiRegistry;
    address owner;
    uint32 srcEid = 77;
    uint32 dstEid = 88;
    address[] sourceAdpaters_ = [address(0x11), address(0x22)];
    address[] destAdapters_ = [address(0x33), address(0x44)];

    function setUp() public {
        hashiRegistry = new HashiRegistry();
        console.log(hashiRegistry.owner());
        console.log(address(hashiRegistry));
        owner = hashiRegistry.owner();
    }

    function test_setDestFee() public {
        vm.expectEmit(true, true, false, false, address(hashiRegistry));
        emit NewFeeSet(dstEid, 10);

        hashiRegistry.setDestFee(dstEid, 10);
    }

    function test_getDestFee() public {
        hashiRegistry.setDestFee(dstEid, 10);
        uint256 fee = hashiRegistry.getDestFee(dstEid);
        assertEq(fee, 10);
    }

    function test_setSourceAdaptersPair() public {
        for (uint256 i = 0; i < sourceAdpaters_.length; i++) {
            vm.expectEmit(true, true, true, true, address(hashiRegistry));
            emit NewSourceAdaptersPairSet(
                srcEid,
                dstEid,
                sourceAdpaters_[i],
                destAdapters_[i]
            );
        }
        hashiRegistry.setSourceAdaptersPair(
            srcEid,
            dstEid,
            sourceAdpaters_,
            destAdapters_
        );
    }

    function test_getSourceAdaptersPair() public {
        hashiRegistry.setSourceAdaptersPair(
            srcEid,
            dstEid,
            sourceAdpaters_,
            destAdapters_
        );

        HashiRegistry.AdapterPair[] memory adaptersPair = hashiRegistry
            .getSourceAdaptersPair(srcEid, dstEid);

        assertEq(adaptersPair[0].sourceAdapter, sourceAdpaters_[0]);
        assertEq(adaptersPair[1].sourceAdapter, sourceAdpaters_[1]);
        assertEq(adaptersPair[0].destAdapter, destAdapters_[0]);
        assertEq(adaptersPair[1].destAdapter, destAdapters_[1]);
    }

    function test_setDestAdapters() public {
        for (uint256 i = 0; i < destAdapters_.length; i++) {
            vm.expectEmit(true, true, true, false, address(hashiRegistry));
            emit NewDestAdaptersPairSet(srcEid, dstEid, destAdapters_[i]);
        }
        hashiRegistry.setDestAdapters(srcEid, dstEid, destAdapters_);
    }

    function test_getDestAdapters() public {
        hashiRegistry.setDestAdapters(srcEid, dstEid, destAdapters_);
        address[] memory destAdapter = hashiRegistry.getDestAdapters(
            srcEid,
            dstEid
        );
        assertEq(destAdapter[0], destAdapters_[0]);
        assertEq(destAdapter[1], destAdapters_[1]);
    }
}
