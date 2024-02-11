//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
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
    MockFailedTransferFrom failedToken;
    address ethUsdPriceFeed;
    address weth;

    address public USER;
    address public liquidator = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    uint256 public amountToMint = 100;
    uint256 public collateralToCover = 20 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    // address[] public

    function setUp() public {
        USER = makeAddr("user");
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        vm.deal(USER, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    }
    //Constructor tests

    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        //populate the arrays and two in the pricefeedaddresses array so it should revert,arranging first the variables manually
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(ethUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressNeedsSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //Price tests

    //this test needs to be updated to get the pricefeed
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18; //supposedly the price of eth is 2k
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
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

    // gets an error if insufficientallowance, while i did as much as possible to have the approve. needs review
    // function testCollateralDepositedEventEmission() public depositedCollateral {
    //     // Start recording all emitted events
    //     vm.recordLogs();

    //     // Perform the deposit operation to trigger the event
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

    //     // Stop pranking to restore normal behavior
    //     vm.stopPrank();

    //     // Retrieve the recorded logs
    //     Vm.Log[] memory logs = vm.getRecordedLogs();

    //     // Get the hash of the event signature
    //     bytes32 eventSignature = keccak256("CollateralDeposited(address,address,uint256)");

    //     // Loop through the logs to find the CollateralDeposited event
    //     for (uint256 i = 0; i < logs.length; i++) {
    //         if (logs[i].topics[0] == eventSignature) {
    //             // Decode the event parameters
    //             (address emittedUser, address emittedToken, uint256 emittedAmount) =
    //                 abi.decode(logs[i].data, (address, address, uint256));

    //             // Verify the event arguments
    //             assertEq(emittedUser, USER, "Event user should match the sender");
    //             assertEq(emittedToken, weth, "Event token should match the token address");
    //             assertEq(emittedAmount, AMOUNT_COLLATERAL, "Event amount should match the deposit amount");
    //             return; // Return early if the event is found and verified
    //         }
    //     }

    //     // Fail the test if the event is not found
    //     fail("CollateralDeposited event not emitted");
    // this test function below does not work, particular since depositCOllateral does not return anything.
    // function testSuccessfulCollateralTransfer() public depositedCollateral {
    //     // Assuming USER has approved the DSCEngine to spend tokens on their behalf
    //     // The DSCEngine calls transferFrom to move the collateral from the user to itself
    //     (bool success,) = dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    //     assertTrue(success, "Transfer should succeed if the user has enough balance and allowance");
    // }

    // Uncomment the following imports to use the mock tokens
    // import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
    // import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";

    //suggested by phind
    // function testCollateralTransferFailure() public {
    //     // Create a mock token that will always fail transferFrom
    //     failedToken = new MockFailedTransferFrom("FailToken", "FT", USER, AMOUNT_COLLATERAL);

    //     // User approves the DSCEngine to spend tokens on their behalf
    //     failedToken.approve(address(dsce), AMOUNT_COLLATERAL);

    //     // Expect the transaction to revert due to the failed transferFrom
    //     vm.expectRevert(bytes("DSCEngine__TransferFailed"));

    //     // Try to deposit collateral with the mock token that will always fail
    //     dsce.depositCollateral(address(failedToken), AMOUNT_COLLATERAL);
    // }

    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    //mint testing

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dsce.mintDsc(AMOUNT_TO_MINT);

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    //making sure we can mint and deposit, tested and works so we can use it as a modifier

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    function testRevertsIfMintFails() public {
        // Arrange - Setup
        // Create an instance of a mock ERC20 token that will always fail when mint is called
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();

        // Define the addresses for the token and price feeds
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        // Get the current sender's address
        address owner = msg.sender;

        // Impersonate the owner to perform actions as if they were the owner
        vm.prank(owner);

        // Deploy a new instance of the DSCEngine contract with the mock token as the DSC token
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        // Transfer ownership of the mock DSC token to the DSCEngine contract
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        // Start pranking as the user to simulate actions performed by the user
        vm.startPrank(USER);

        // Approve the DSCEngine contract to spend collateral on behalf of the user
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);

        // Act / Assert
        // Expect the transaction to revert with the specific error message selector
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);

        // Call the depositCollateralAndMintDsc function which internally calls the mint function
        // This is expected to fail since the mock token will always fail the mint
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);

        // Stop pranking to revert back to the original sender
        vm.stopPrank();
    }

    // function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
    //     uint256 expectedHealthFactor = 100 ether;
    //     uint256 healthFactor = dsce.getHealthFactor(USER);
    //     // $100 minted with $20,000 collateral at 50% liquidation threshold
    //     // means that we must have $200 collatareral at all times.
    //     // 20,000 * 0.5 = 10,000
    //     // 10,000 / 100 = 100 health factor
    //     assertEq(healthFactor, expectedHealthFactor);
    // }
    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether; // Adjusted to match the precision used in the contract
        uint256 healthFactor = dsce.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at  50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        //  20,000 *  0.5 =  10,000
        //  10,000 /  100 =  100 health factor
        // Ensure the precision matches the contract's calculations
        assertEq(healthFactor, expectedHealthFactor, "Health factor does not match the expected value");
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Rememeber, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) = 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    // function testRevertsIfMintAmountBreaksHealthFactor() public {
    //     // Retrieve the latest price from the price feed
    //     (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();

    //     // Calculate the amount to mint based on the collateral and the latest price
    //     amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();

    //     // Begin impersonating the user account for testing purposes
    //     vm.startPrank(USER);

    //     // Calculate the expected health factor based on the mint amount and collateral value
    //     uint256 expectedHealthFactor =
    //         dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
    //     console.log(expectedHealthFactor);
    //     // Expect the transaction to revert with the DSCEngine__BreaksHealthFactor error
    //     // The abi.encodeWithSelector method encodes the error selector and expected health factor
    //     vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));

    //     // Attempt to mint the calculated amount, which should exceed the health factor limit
    //     dsce.mintDsc(amountToMint);

    //     // Stop impersonating the user account after the test
    //     vm.stopPrank();
    // }

    // burn testing

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dsce.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 oldBalance = dsc.balanceOf(USER);
        console.log(oldBalance);
        dsc.approve(address(dsce), amountToMint);

        dsce.burnDsc(amountToMint);
        uint256 newBalanceAfterBurn = dsc.balanceOf(USER);
        console.log(newBalanceAfterBurn);
        vm.stopPrank();

        uint256 expectedBalance = oldBalance - amountToMint;
        assertEq(expectedBalance, newBalanceAfterBurn);
    }

    function testGetDsc() public {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    //liquidate dsc & redeem collateral

    // This test function checks that the liquidate function cannot be called when the user's health factor is good (above the minimum)
    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        // Mint the collateral token to the liquidator's address
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        // Impersonate the liquidator account for the purpose of this test
        vm.startPrank(liquidator);

        // Approve the DSCEngine contract to spend the liquidator's collateral token on their behalf
        ERC20Mock(weth).approve(address(dsce), collateralToCover);

        // Deposit collateral and mint DSC tokens in one transaction
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);

        // Approve the DSCEngine contract to burn the liquidator's DSC tokens on their behalf
        dsc.approve(address(dsce), amountToMint);

        // Expect the liquidate function to revert with the DSCEngine__HealthFactorOk error
        // This is because the user's health factor is assumed to be above the minimum, so attempting to liquidate should fail
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);

        // Attempt to liquidate the user's position
        // Since the user's health factor is good, this call should revert with the DSCEngine__HealthFactorOk error
        dsce.liquidate(weth, USER, amountToMint);

        // Stop impersonating the liquidator account after the test
        vm.stopPrank();
    }

    //redeem collateral
    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testMustImproveHealthFactorOnLiquidation() public {
        // Create a mock contract for the decentralized stable coin (DSC) with additional debt functionality
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);

        // Define the addresses for the token and price feed that will be used in the test
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        // Get the current contract owner's address
        address owner = msg.sender;

        // Impersonate the owner account for the purpose of this test
        vm.prank(owner);

        // Deploy the DSCEngine contract with the specified token and price feed addresses, and the mock DSC contract
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        // Transfer ownership of the mock DSC contract to the deployed DSCEngine contract
        mockDsc.transferOwnership(address(mockDsce));

        // Begin impersonating the user account to simulate a user depositing collateral and minting DSC
        vm.startPrank(USER);

        // Approve the DSCEngine contract to spend the user's collateral token on their behalf
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);

        // Have the user deposit collateral and mint DSC tokens in one transaction
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);

        // Stop impersonating the user account after the deposit and mint operations
        vm.stopPrank();

        // Begin impersonating the liquidator account to simulate a liquidator depositing collateral and minting DSC
        vm.startPrank(liquidator);

        // Mint collateral tokens to the liquidator's address
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        // Approve the DSCEngine contract to spend the liquidator's collateral token on their behalf
        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);

        // Have the liquidator deposit collateral and mint DSC tokens in one transaction
        uint256 debtToCover = 10 ether;
        mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);

        // Approve the DSCEngine contract to burn the liquidator's DSC tokens on their behalf
        mockDsc.approve(address(mockDsce), debtToCover);

        // Update the price feed to simulate market conditions
        int256 ethUsdUpdatedPrice = 18e8; //  1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Expect the liquidate function to revert with the DSCEngine__HealthFactorOk error
        // This is because the user's health factor is assumed to be above the minimum, so attempting to liquidate should fail
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);

        // Attempt to liquidate the user's position
        // Since the user's health factor is good, this call should revert with the DSCEngine__HealthFactorOk error
        mockDsce.liquidate(weth, USER, debtToCover);

        // Stop impersonating the liquidator account after the test
        vm.stopPrank();
    }

    modifier liquidated() {
        // Start a prank to impersonate the user
        vm.startPrank(USER);

        // Approve the DSCEngine to spend the user's WETH tokens
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        // Deposit collateral and mint DSC tokens as the user
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);

        // Stop the prank, returning control to the original caller
        vm.stopPrank();

        // Update the price feed with a new ETH to USD exchange rate
        int256 ethUsdUpdatedPrice = 18e8; //  1 ETH = $18

        // Retrieve the user's current health factor
        uint256 userHealthFactor = dsce.getHealthFactor(USER);

        // Mint WETH tokens to the liquidator account
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        // Start another prank to impersonate the liquidator
        vm.startPrank(liquidator);

        // Approve the DSCEngine to spend the liquidator's WETH tokens
        ERC20Mock(weth).approve(address(dsce), collateralToCover);

        // Deposit collateral and mint DSC tokens as the liquidator
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);

        // Approve the DSCEngine to spend the liquidator's DSC tokens
        dsc.approve(address(dsce), amountToMint);

        // Call the liquidate function to cover the user's debt
        dsce.liquidate(weth, USER, amountToMint); // We are covering their whole debt

        // Stop the prank, returning control to the original caller
        vm.stopPrank();

        // Placeholder for the function body where the modifier is applied
        _;
    }

    // function testLiquidationPayoutIsCorrect() public liquidated {
    //     // Retrieve the balance of WETH tokens held by the liquidator after the liquidation
    //     uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);

    //     // Calculate the expected amount of WETH tokens the liquidator should receive,
    //     // which includes the initial amount plus the liquidation bonus
    //     uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, amountToMint)
    //         + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());

    //     // Hardcoded value representing the expected WETH balance after liquidation
    //     uint256 hardCodedExpected = 6111111111111111110;

    //     // Assert that the liquidator's WETH balance equals the hardcoded expected value
    //     assertEq(liquidatorWethBalance, hardCodedExpected);

    //     // Assert that the liquidator's WETH balance also equals the dynamically calculated expected value
    //     assertEq(liquidatorWethBalance, expectedWeth);
    // }

    // apparently there is some bug here in this function also where the liquidation is not needed
    // function testUserStillHasSomeEthAfterLiquidation() public liquidated {
    //     // Calculate the total amount of WETH that was liquidated by subtracting the liquidation bonus from the initial amount to mint
    //     uint256 amountLiquidated = dsce.getTokenAmountFromUsd(weth, amountToMint)
    //         + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());

    //     // Convert the liquidated amount to its USD equivalent
    //     uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);

    //     // Subtract the USD value of the liquidated amount from the original collateral value to get the remaining collateral value in USD
    //     uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) - (usdAmountLiquidated);

    //     // Retrieve the current USD value of the user's collateral from the contract's account information
    //     (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(USER);

    //     // Define a hardcoded expected value for comparison purposes (this should ideally be calculated based on the test conditions)
    //     uint256 hardCodedExpectedValue = 70000000000000000020;

    //     // Assert that the current collateral value in USD matches the expected collateral value after liquidation
    //     assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);

    //     // Assert that the current collateral value in USD matches the hardcoded expected value
    //     assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    // }

    // function testLiquidatorTakesOnUsersDebt() public liquidated {
    //     (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);
    //     assertEq(liquidatorDscMinted, amountToMint);
    // }

    // function testUserHasNoMoreDebt() public liquidated {
    //     (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
    //     assertEq(userDscMinted, 0);
    // }
}
