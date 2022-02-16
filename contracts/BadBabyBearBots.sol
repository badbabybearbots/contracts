// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "erc721b/contracts/extensions/ERC721BURIBase.sol";

error SaleNotStarted();
error InvalidRecipient();

contract BadBabyBearBots is
  Ownable,
  ReentrancyGuard,
  ERC721BURIBase
{
  using Strings for uint256;
  using SafeMath for uint256;

  // ============ Constants ============
  
  //max amount that can be minted in this collection
  uint16 public constant MAX_SUPPLY = 10000;
  //maximum amount that can be purchased per wallet
  uint8 public constant MAX_PURCHASE = 5;
  //start date of the token sale
  //April 1, 2022 12AM GTM
  uint64 public constant SALE_DATE = 1648771200;
  //the sale price per token
  uint256 public constant SALE_PRICE = 0.08 ether;
  //the amount of tokens to reserve
  uint16 public constant RESERVED = 30;
  //the provenance hash (the CID)
  string public PROVENANCE;
  //the contract address of the DAO
  address public immutable DAO;
  //the contract address of the BBBB multisig wallet
  address public immutable BBBB;

  // ============ Storage ============

  //the offset to be used to determine what token id should get which 
  //CID in some sort of random fashion. This is kind of immutable as 
  //it's only set in `widthdraw()`
  uint16 public indexOffset;

  //mapping of address to amount minted
  mapping(address => uint256) public minted;

  // ============ Deploy ============

  /**
   * @dev Grants `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` to the
   * account that deploys the contract. Sets the contract's URI. 
   */
  constructor(
    string memory uri_,
    string memory cid_,
    address dao, 
    address bbbb
  ) ERC721B("Bad Baby Bear Bots", "BBBB") {
    _setBaseURI(uri_);
    //set provenance data
    PROVENANCE = cid_;
    //save DAO address. now it's immutable
    DAO = dao;
    //save BBBB address. now it's immutable
    BBBB = bbbb;

    //reserve bears
    _safeMint(_msgSender(), 30);
  }

  // ============ Read Methods ============

  /**
   * @dev The URI for contract data ex. https://creatures-api.opensea.io/contract/opensea-creatures
   * Example Format:
   * {
   *   "name": "OpenSea Creatures",
   *   "description": "OpenSea Creatures are adorable aquatic beings primarily for demonstrating what can be done using the OpenSea platform. Adopt one today to try out all the OpenSea buying, selling, and bidding feature set.",
   *   "image": "https://openseacreatures.io/image.png",
   *   "external_link": "https://openseacreatures.io",
   *   "seller_fee_basis_points": 100, # Indicates a 1% seller fee.
   *   "fee_recipient": "0xA97F337c39cccE66adfeCB2BF99C1DdC54C2D721" # Where seller fees will be paid to.
   * }
   */
  function contractURI() public view returns (string memory) {
    //ex. https://ipfs.io/ipfs/ + Qm123abc + /contract.json
    return string(
      abi.encodePacked(baseTokenURI(), PROVENANCE, "/contract.json")
    );
  }

  /**
   * @dev Combines the base token URI and the token CID to form a full 
   * token URI
   */
  function tokenURI(uint256 tokenId) 
    public view virtual override returns(string memory) 
  {
    if (!_exists(tokenId)) revert NonExistentToken();

    //if no offset
    if (indexOffset == 0) {
      //use the placeholder
      return string(
        abi.encodePacked(baseTokenURI(), PROVENANCE, "/placeholder.json")
      );
    }

    //for example, given offset is 2 and size is 8:
    // - token 5 = ((5 + 2) % 8) + 1 = 8
    // - token 6 = ((6 + 2) % 8) + 1 = 1
    // - token 7 = ((7 + 2) % 8) + 1 = 2
    // - token 8 = ((8 + 2) % 8) + 1 = 3
    uint256 index = tokenId.add(indexOffset).mod(MAX_SUPPLY).add(1);
    //ex. https://ipfs.io/ + Qm123abc + / + 1000 + .json
    return string(
      abi.encodePacked(baseTokenURI(), PROVENANCE, "/", index.toString(), ".json")
    );
  }
  
  /**
   * @dev Shows the overall amount of tokens generated in the contract
   */
  function totalSupply() public virtual view returns (uint256) {
    return lastTokenId();
  }

  // ============ Write Methods ===========

  /**
   * @dev Creates a new token for the `recipient`. Its token ID will be 
   * automatically assigned (and available on the emitted 
   * {IERC721-Transfer} event), and the token URI autogenerated based 
   * on the base URI passed at construction.
   */
  function mint(uint256 quantity) external payable {
    address recipient = _msgSender();
    //make sure recipient is a valid address
    if (recipient == address(0)) revert InvalidRecipient();
    //has the sale started?
    if(uint64(block.timestamp) < SALE_DATE) 
      revert SaleNotStarted();
  
    if (quantity == 0 
      //the quantity here plus the current amount already minted 
      //should be less than the max purchase amount
      || quantity.add(minted[recipient]) > MAX_PURCHASE
      //the value sent should be the price times quantity
      || quantity.mul(SALE_PRICE) > msg.value
      //the quantity being minted should not exceed the max supply
      || (lastTokenId() + quantity) > MAX_SUPPLY
    ) revert InvalidAmount();

    minted[recipient] += uint8(quantity);
    _safeMint(recipient, quantity);
  }

  /**
   * @dev Since we are using IPFS CID for the token URI, we can allow 
   * the changing of the base URI to toggle between services for faster 
   * speeds while keeping the metadata provably fair
   */
  function setBaseURI(string memory uri) 
    public virtual onlyOwner
  {
    _setBaseURI(uri);
  }

  /**
   * @dev Allows the proceeds to be withdrawn. This also releases the  
   * collection at the same time to discourage rug pulls 
   */
  function withdraw() external virtual onlyOwner nonReentrant {
    //set the offset
    if (indexOffset == 0) {
      indexOffset = uint16(block.number - 1) % MAX_SUPPLY;
      if (indexOffset == 0) {
        indexOffset = 1;
      }
    }

    //DAO gets 50%
    payable(DAO).transfer(address(this).balance.div(2));
    //rest goes to BBBB
    payable(BBBB).transfer(address(this).balance);
  }
}