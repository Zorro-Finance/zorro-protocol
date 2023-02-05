// TODO: Run these without Mock tokens

// const MockPriceFeed = artifacts.require('MockPriceFeed');
// const MockAggregatorV3 = artifacts.require('MockAggregatorV3');

// contract('MockPriceFeed', async accounts => {
//     it('gets the exchange rate for a given price feed', async () => {
//         const price = 4015905000000;
//         const dec = 8;

//         const lib = await MockPriceFeed.deployed();
//         const priceFeed = await MockAggregatorV3.deployed(); 
//         await priceFeed.setDecimals(dec);
//         await priceFeed.setAnswer(price);

//         const ans = await lib.getExchangeRate.call(priceFeed.address);

//         assert.equal(ans, price * (1e12) / (10**dec));
//     });
// })