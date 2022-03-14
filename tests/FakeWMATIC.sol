pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// FakeWMATIC
contract FakeWMATIC is ERC20('FakeWMATIC', 'FakeWMATIC') {
    constructor() {
        _mint(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266), uint256(90000000));
    }

	function decimals() public view override returns (uint8) {
		return 18;
	}
}