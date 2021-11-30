//SPDX-license-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProfitBank is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;
    
    address payable public marketingAddress = payable(0x06825B26a92Cd4A13b0f91e10d67f8bA34253820); // Marketing Address
    address payable public devAddress = payable(0x7Ab5016e4Abb0bcA73Da724E1901609B3FcBf991); // Dev Address

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public excludeFromTaxes;
   
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 100000000000  * 10**6;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "Profit Bank";
    string private _symbol = "PBK";
    uint8 private _decimals = 6;


    uint256[2] public _taxFee = [0,0]; // [Before, after] [30,50]
    uint256[2] private _previousTaxFee = _taxFee;
    
    uint256[2] public _liquidityFee = [0,0]; // [Before, after] [70,50]
    uint256[2] private _previousLiquidityFee = _liquidityFee;
    
    uint256[2] public marketingDivisor = [0,0]; // [Before, after] [25,15]
    uint256[2] public devDivisor = [0,0] ; // [Before, after] [25,15]
    
    uint256 public _maxTxAmount = 30000000000 * 10**6;
    uint256 private minimumTokensBeforeSwap = 20000 * 10**6; 
    
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = false;
    bool public buyBackEnabled = true;

    
    event RewardLiquidityProviders(uint256 tokenAmount);
    event BuyBackEnabledUpdated(bool enabled);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    
    event SwapETHForTokens(
        uint256 amountIn,
        address[] path
    );
    
    event SwapTokensForETH(
        uint256 amountIn,
        address[] path
    );
    
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    constructor (IUniswapV2Router02 _router) {
        _rOwned[_msgSender()] = _rTotal;
        
       // IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        uniswapV2Pair = IUniswapV2Factory(_router.factory())
            .createPair(address(this), _router.WETH());

        uniswapV2Router = _router;
        
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }
    
    function minimumTokensBeforeSwapAmount() public view returns (uint256) {
        return minimumTokensBeforeSwap;
    }
    
    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        // require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,) = _getValues(tAmount,0);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,) = _getValues(tAmount,0);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,) = _getValues(tAmount,0);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner()) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool overMinimumTokenBalance = contractTokenBalance >= minimumTokensBeforeSwap;
        
        if (!inSwapAndLiquify && swapAndLiquifyEnabled && to == uniswapV2Pair) {
            if (overMinimumTokenBalance) {
                contractTokenBalance = minimumTokensBeforeSwap;
                swapTokens(contractTokenBalance);    
            }
        }
        
        _tokenTransfer(from,to,amount);
    }

    function swapTokens(uint256 contractTokenBalance) private lockTheSwap {
        uint256 initialBalance = address(this).balance;
        swapTokensForEth(contractTokenBalance.div(2));
        uint256 leftToken = contractTokenBalance.sub(contractTokenBalance.div(2));
        uint256 transferredBalance = address(this).balance.sub(initialBalance);
        addLiquidity(leftToken, transferredBalance);
    }
    
    
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();   

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this), // The contract
            block.timestamp
        );
        
        emit SwapTokensForETH(tokenAmount, path);
    }
    
    
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    function _tokenTransfer(address sender, address recipient, uint256 amount) private {


        if(sender == uniswapV2Pair && ( !excludeFromTaxes[recipient]) && _liquidityFee[0]!=0 ) {
            _transferStandard(sender, recipient, amount, 0);
        } else if (recipient == uniswapV2Pair && ( !excludeFromTaxes[sender]) && _liquidityFee[1]!=0 ) {
            _transferStandard(sender, recipient, amount, 1);
        } else {
            _transferExcluded(sender, recipient, amount);
        }

    }

    function _transferStandard(address sender, address recipient, uint256 tAmount, uint256 index) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount, index);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity,index);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _transferExcluded(address sender, address recipient, uint256 tAmount) private {
        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount.mul(currentRate);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);        
        emit Transfer(sender, recipient, tAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount, uint256 index) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount, index);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
    }

    function _getTValues(uint256 tAmount, uint256 index) private view returns (uint256, uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount, index);
        uint256 tLiquidity = calculateLiquidityFee(tAmount, index);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function _takeLiquidity(uint256 tLiquidity, uint256 index) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 forMarketing = rLiquidity.mul(marketingDivisor[index]).div(_liquidityFee[index]);
        uint256 forDev = rLiquidity.mul(devDivisor[index]).div(_liquidityFee[index]);
        _rOwned[marketingAddress] = _rOwned[marketingAddress].add(forMarketing);
        _rOwned[devAddress] = _rOwned[devAddress].add(forDev);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity.sub(forMarketing.add(forDev)));

    }
    
    function calculateTaxFee(uint256 _amount, uint256 index) private view returns (uint256) {
        return _amount.mul(_taxFee[index]).div(
            10**3
        );
    }
    
    function calculateLiquidityFee(uint256 _amount, uint256 index) private view returns (uint256) {
        return _amount.mul(_liquidityFee[index]).div(
            10**3
        );
    }
    
    function removeAllFee() private {
        if(_taxFee[0] == 0 && _liquidityFee[0] == 0) return;
        
        _previousTaxFee[0] = _taxFee[0];
        _previousTaxFee[1] = _taxFee[1];
        _previousLiquidityFee[0] = _liquidityFee[0];
        _previousLiquidityFee[1] = _liquidityFee[1];
        
        _taxFee[0] = 0;
        _liquidityFee[0] = 0;
        _taxFee[1] = 0;
        _liquidityFee[1] = 0;
    }
    
    function restoreAllFee() private {
        _taxFee[0] = _previousTaxFee[0];
        _taxFee[1] = _previousTaxFee[1];
        _liquidityFee[0] = _previousLiquidityFee[0];
        _liquidityFee[1] = _previousLiquidityFee[1];
    }

    
    function setTaxFeePercent(uint256[2] memory taxFee) external onlyOwner() {
        _taxFee = taxFee;
    }
    
    function setLiquidityFeePercent(uint256[2] memory liquidityFee) external onlyOwner() {
        _liquidityFee = liquidityFee;
    }
    
    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner() {
        _maxTxAmount = maxTxAmount;
    }
    
    function setMarketingDivisor(uint256[2] memory divisor) external onlyOwner() {
        marketingDivisor = divisor;
    }
     
    function setDevDivisor(uint256[2] memory divisor) external onlyOwner() {
        devDivisor = divisor;
    }

    function setMarketingAddress(address _marketingAddress) external onlyOwner() {
        marketingAddress = payable(_marketingAddress);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }
    
    function setBuyBackEnabled(bool _enabled) public onlyOwner {
        buyBackEnabled = _enabled;
        emit BuyBackEnabledUpdated(_enabled);
    }
    
    function setExclusions(address _account, bool _status) public onlyOwner {
        excludeFromTaxes[_account] = _status;
    }
    
    function transferToAddressETH(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }
    
     //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}
}