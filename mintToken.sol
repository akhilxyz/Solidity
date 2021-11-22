// SPDX-License-Identifier: MIT
    pragma solidity >=0.8.0;
    
    import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
    import "@openzeppelin/contracts/access/Ownable.sol";
    
    contract Test_token1 is ERC20, Ownable {
    
        constructor(
            string memory _name,
            string memory _symbol
        ) ERC20(_name, _symbol) {
            _mint(msg.sender, 100000000000*10**decimals());
        }
        
        function decimals() public pure override returns (uint8) {
            return 18;
        }
    }
