//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
// import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
// import {MockToken} from "../mocks/MockToken.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
// import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
// import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
// import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
// import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {Test, console} from "forge-std/Test.sol";
// import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); // if redeemFrom != redeemedTo, then it was liquidated

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    // MockToken mockToken;
    address ethUSDPriceFeed;
    address weth;

    address public USER;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    // address[] public

    function setUp() public {
        USER = makeAddr("user");
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUSDPriceFeed,, weth,,) = config.activeNetworkConfig();
        vm.deal(USER, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    }
    //Constructor tests

    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        //populate the arrays and two in the pricefeedaddresses array so it should revert,arranging first the variables manually
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(ethUSDPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressNeedsSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //Price tests

    //this test needs to be updated to get the pricefeed
    function testGetUSDValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUSD = 30000e18; //supposedly the price of eth is 2k
        uint256 actualUSD = dsce.getUSDValue(weth, ethAmount);
        assertEq(expectedUSD, actualUSD);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    // Deposit Collateral tests
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank;
    }

    modifier depositedCollateral() {
        vm.deal(USER, STARTING_USER_BALANCE);
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectTotalDscMinted, totalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    // the eror comes !record logs are different
    //function testCollateralDepositedEventEmission() public depositedCollateral {
    ////     // Define the expected event to compare against
    //     vm.prank(USER);
    //     emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

    //     // Check that the topics  1,  2, and  3 match exactly and that the rest of the data matches
    //     vm.expectEmit(true, true, true, true);

    //     // Call the depositCollateral function which should emit the CollateralDeposited event
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    // }

    function testCollateralDepositedEventEmission() public depositedCollateral {
        // Start recording all emitted events
        vm.recordLogs();

        // Perform the deposit operation to trigger the event
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Stop pranking to restore normal behavior
        vm.stopPrank();

        // Retrieve the recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Get the hash of the event signature
        bytes32 eventSignature = keccak256("CollateralDeposited(address,address,uint256)");

        // Loop through the logs to find the CollateralDeposited event
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                // Decode the event parameters
                (address emittedUser, address emittedToken, uint256 emittedAmount) =
                    abi.decode(logs[i].data, (address, address, uint256));

                // Verify the event arguments
                assertEq(emittedUser, USER, "Event user should match the sender");
                assertEq(emittedToken, weth, "Event token should match the token address");
                assertEq(emittedAmount, AMOUNT_COLLATERAL, "Event amount should match the deposit amount");
                return; // Return early if the event is found and verified
            }
        }

        // Fail the test if the event is not found
        fail("CollateralDeposited event not emitted");
    }
}
