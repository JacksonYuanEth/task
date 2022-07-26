// SPDX-License-Identifier: MIT


pragma solidity ^0.8.0;


contract test {

    //用一个uint256数组代表nonces是否被使用
    //比如nonce = 255 ,则令 used[_user][0] 的第256位为true
    //比如nonce = 256 ,则令 used[_user][1] 的第1位为true
    mapping(address => uint256[]) public used;

    //修改指定nonce的签名对应的uint256
    function writeNonces(address _user,uint256 _nonce,bool _setToTrue) public{
        uint256[] storage used = used[_user];

        (uint size,uint index) = preOpNonce(_nonce);
        uint arrlength = used.length;
        //如果数组没有初始化，则需要分配空间,否则无法通过索引操作
        if(arrlength<=size){
            for(uint i = arrlength;i<=size;i++){
                used.push(0);
            }
        }
        else{
            //修改对应uint256数组
            uint beforeNum = used[size];
            used[size] = writeBybit(beforeNum,index,_setToTrue);
        }
    }
    function readNonces(address _user,uint256 _nonce)public view returns(bool){
        (uint size,uint index) = preOpNonce(_nonce);
    
        //得到指定nonce的uint值
        uint temp = used[_user][size];

        //
        temp = temp & (1 << index);

        return temp > 0;    
    }

    function writeBybit(uint256 _num,uint256 _index,bool _setToTrue) internal returns(uint256){
        if(_setToTrue == true)
            _num += 2**(_index);
        else 
            _num -= 2**(_index);
        return _num;
    }

    function preOpNonce(uint _nonce) public view returns(uint256 _size,uint256 _index){
        if(_nonce == 0){
            _size = 0;
            _index = 0;
        }
        else{
            _size = _nonce /256;
            _index = _nonce % 256;
        }
    }
    function getArr() public view returns (uint[] memory) {
        return used[msg.sender];
    }
}
