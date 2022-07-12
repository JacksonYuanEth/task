pragma solidity >=0.7.0 <0.9.0;
import "./SafeMath.sol";
interface IUniswapV2ERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

contract test{

    using SafeMath for uint;
                                    ///元操作标识符///
    //bytes32("SWAP")
    bytes32 constant private SWAP_OPERATION = 0x5357415000000000000000000000000000000000000000000000000000000000;
    //bytes32("BORROW")
    bytes32 constant private BORROW_OPERATION = 0x424f52524f570000000000000000000000000000000000000000000000000000;
    //bytes32("LIQUIDITY")
    bytes32 constant private LIQUIDITY_OPERATION = 0x4c49515549444954595f4f5045524154494f4e00000000000000000000000000;

    struct Task{
        address signer;
        address tokenA;
        address tokenB;
        bytes32 opType;
        //为了防止front-run导致的交易失败，tokenA和tokenB的数量应该为一个范围
        // amountAdown<=amountA<=amountAup
        // amountBdown<=amountB<=amountBup
        uint amountA;
        uint amountB;
        //以tokenA计价的执行者奖励
        uint amountReward;
        //防止签名重放
        uint expiredTime;
    }
    struct Record{
        uint amountA;
        uint amountB;
    }
    struct EIP712Domain {
        string  name;
        string  version;
        uint256 chainId;
        address verifyingContract;
    }
                                   ///EIP-712相关///
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant TYPE_HASH = keccak256("Task(address signer,address tokenA,address tokenB,bytes32 opType,uint amountA,uint amountB,uint amountReward,uint expiredTime)");
    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256("sign"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function verify(Task memory task,uint8 v, bytes32 r, bytes32 s) internal view returns (bool) {

        bytes32 digest = keccak256(abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        hashStruct(task)
        ));

        return ecrecover(digest, v, r, s) == task.signer;

    }

    function hashStruct(Task memory task) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TYPE_HASH,
                task.signer,
                task.tokenA,
                task.tokenB,
                task.opType,
                task.amountA,
                task.amountB,
                task.amountReward,
                task.expiredTime
            )
        );
    }
                                    ///逻辑函数///              
    function multiCall(bytes32[] memory userData,bytes[] calldata data,uint8 v, bytes32 r, bytes32 s) public payable {
        //验证签名是否由用户发出
        Task memory task = splitUserData(userData);
        require(verify(task,v,r,s)==true,"Error singer!");

        //根据不同的opType记录用户数据
        Record memory record = diffRecord(task);
    
        //根据不同的opType授权给执行者
        require(true == auth(task,record),"Error when auth!");

        //执行者输入任意的bytes[]，执行任意函数
        _multiCall(data);

        //验证执行者_multiCall之后的结果是否和用户task中一样，如果错误则回滚
        require(verifyResult(record,task)==true,"error result");
    }
    //来源于https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/Multicall.sol
    function _multiCall(bytes[] calldata data) internal  returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
    function auth(Task memory task,Record memory record) internal returns(bool success){
    
        if(task.opType == SWAP_OPERATION){
            //将tokenA从signer转移给执行者进行multiCall
            require(true == IUniswapV2ERC20(task.tokenA).transferFrom(task.signer,msg.sender,task.amountA),"error when transferFrom!");
            success = true;
        }
        return success;
    }
    function diffRecord(Task memory task)internal returns(Record memory){
        if(task.opType == SWAP_OPERATION){
            //记录执行者调用_multiCall之前的用户数据
            Record memory record;
            record.amountA = IUniswapV2ERC20(task.tokenA).balanceOf(task.signer);
            record.amountB = IUniswapV2ERC20(task.tokenB).balanceOf(task.signer);
        }
    }
    function verifyResult(Record memory record,Task memory task)public returns(bool success){
        if(task.opType == SWAP_OPERATION){
            uint amountAnow = IUniswapV2ERC20(task.tokenA).balanceOf(task.signer);
            uint amountBnow = IUniswapV2ERC20(task.tokenB).balanceOf(task.signer);
            require(record.amountA.sub(amountAnow)==task.amountA);
            require(record.amountB.sub(amountBnow)==task.amountB);
            success == true;
        }
        return success;
    }
    function splitUserData(bytes32[] memory userData) internal pure returns(Task memory task){
        //bytes32类型不能直接转化为address类型，需要移位后转换
        bytes32 tempSinger = userData[0];
        bytes32 temptokenA = userData[1];
        bytes32 temptokenB = userData[2];
        assembly{
            tempSinger := shl(96,tempSinger)
            temptokenA := shl(96,temptokenA)
            temptokenB := shl(96,temptokenB)
        }
        task.signer = address(bytes20(tempSinger));
        task.tokenA = address(bytes20(temptokenA));
        task.tokenB = address(bytes20(temptokenB));
        task.opType = userData[3];
        task.amountA = uint(userData[4]);
        task.amountB = uint(userData[5]);
        task.amountReward = uint(userData[6]);
        task.expiredTime = uint(userData[7]);
        return task;          
    }
}
